-- PrioMeister – Loot.lua
-- Plünderfenster: relevante Items erfassen, automatisch an Plünderhelfer und
-- Schatzmeister geben, Zuweisungen über GiveMasterLoot und per Handel erkennen
-- und bestätigen, Plündermeister-Liste sortieren und markieren.

local ADDON, ns = ...
local L, PM = ns.Logic, ns.PM
local T = ns.T or function(s) return s end
local Popup = ns.Popup or function(name, def) StaticPopupDialogs[name] = def return def end

local PENDING_SECONDS = 60
local LOOT_ERRORS = {
	"ERR_LOOT_MASTER_INV_FULL", "ERR_LOOT_MASTER_UNIQUE_ITEM", "ERR_LOOT_MASTER_OTHER",
	"ERR_LOOT_PLAYER_NOT_FOUND", "ERR_LOOT_TOO_FAR", "ERR_ITEM_MAX_COUNT", "ERR_LOOT_DIDNT_KILL",
}

-------------------------------------------------------------------------------
-- Hooks
-------------------------------------------------------------------------------

function PM:InstallHooks()
	if not self.hookedGive and type(GiveMasterLoot) == "function" then
		hooksecurefunc("GiveMasterLoot", function(slot, index) PM:OnGiveMasterLoot(slot, index) end)
		self.hookedGive = true
	end
	if not self.hookedML and type(MasterLooterFrame_UpdatePlayers) == "function" then
		hooksecurefunc("MasterLooterFrame_UpdatePlayers", function() PM:DecorateMasterLooterFrame() end)
		self.hookedML = true
	end
end

-------------------------------------------------------------------------------
-- Loot erfassen
-------------------------------------------------------------------------------

function PM:IsMasterLooter()
	return IsMasterLooter and IsMasterLooter() and true or false
end

-- GUID der Leiche oder Truhe, aus der ein Loot-Platz stammt.
function PM:LootSource(slot)
	if not slot or not GetLootSourceInfo then return nil end
	return (GetLootSourceInfo(slot))
end

-- Herkunft eines Items im offenen Plünderfenster.
function PM:ContextForItem(itemID)
	local slot = self:SlotOfItem(itemID)
	if not slot then return nil end
	return { source = self:LootSource(slot) }
end

-- Link und Item-ID eines Loot-Platzes, nil bei Geld und bei leeren Plätzen.
-- Vergebene Plätze behalten ihre Nummer, GetLootSlotLink liefert dort manchmal
-- noch einen leeren Link ohne Item-ID. Im Panel stand dann „Item 60“.
function PM:LootSlotItem(slot)
	if not slot then return nil end
	if GetLootSlotType and GetLootSlotType(slot) ~= (LOOT_SLOT_ITEM or 1) then return nil end
	local link = GetLootSlotLink(slot)
	local itemID = L.ItemID(link)
	if not itemID then return nil end
	return link, itemID
end

-- Relevant sind Items ab der Plündergrenze, Items zum Verwürfeln und Items mit Prio.
-- below: liegt unter der Plündergrenze, geht also nur per Handel.
-- loading: WoW hat die Itemdaten noch nicht, sie kommen mit GET_ITEM_INFO_RECEIVED.
function PM:ScanLoot()
	local items, links = {}, {}
	local threshold = GetLootThreshold and GetLootThreshold() or 2
	local roll = self:ActiveItemList("roll")
	for slot = 1, GetNumLootItems() do
		local link, itemID = self:LootSlotItem(slot)
		if link then
			links[slot] = link
			local texture, name, quantity, _, quality = GetLootSlotInfo(slot)
			local loading = (name == nil or name == "" or link:find("|h[]|h", 1, true) ~= nil)
			if loading then self:RequestItems({ itemID }) end
			local below = quality ~= nil and quality < threshold
			local relevant = not below or roll[itemID]
			if not relevant then
				relevant = L.HasHolders(self:ResolveForItem(itemID))
			end
			if relevant and not (self.autoGiving and self.autoGiving[slot]) then
				items[#items + 1] = {
					slot = slot, link = link, itemID = itemID, texture = texture,
					name = name, quality = quality or 1, quantity = quantity,
					source = self:LootSource(slot), below = below, loading = loading,
				}
			end
		end
	end
	self.lootItems = items
	self.slotLinks = links
end

-- Liegt ein Loot-Platz unter der Plündergrenze (nur selbst plündern, dann handeln)?
function PM:BelowThreshold(slot)
	local quality = slot and select(5, GetLootSlotInfo(slot))
	local threshold = GetLootThreshold and GetLootThreshold() or 2
	return quality ~= nil and quality < threshold
end

-- Stückzahl eines Items in derselben Beute, mindestens 1.
function PM:CopiesInLoot(itemID, source)
	if not self.lootOpen then return 1 end
	local canon, n = L.Canon(itemID), 0
	for slot = 1, GetNumLootItems() do
		local _, id = self:LootSlotItem(slot)
		if id and L.Canon(id) == canon and (not source or self:LootSource(slot) == source) then
			local _, _, quantity = GetLootSlotInfo(slot)
			n = n + (quantity or 1)
		end
	end
	return math.max(n, 1)
end

-- Berechtigte Spieler für einen Loot-Platz (nur als Plündermeister bekannt).
function PM:GetCandidates(slot)
	if not slot or not self:IsMasterLooter() then return nil end
	local set, any = {}, false
	for i = 1, (MAX_RAID_MEMBERS or 40) do
		local key = L.NameKey(GetMasterLootCandidate(slot, i))
		if key then
			set[key] = i
			any = true
		end
	end
	return any and set or nil
end

function PM:CandidateIndex(slot, name)
	local key = L.NameKey(name)
	if not key or not slot then return nil end
	for i = 1, (MAX_RAID_MEMBERS or 40) do
		if L.NameKey(GetMasterLootCandidate(slot, i)) == key then return i end
	end
	return nil
end

-- Liegt noch ein weiteres Exemplar im Loot? exceptSlot: gerade vergebener Platz.
function PM:LootHasItem(itemID, exceptSlot)
	return self:SlotOfItem(itemID, exceptSlot) ~= nil
end

function PM:SlotOfItem(itemID, exceptSlot)
	if not self.lootOpen then return nil end
	local canon = L.Canon(itemID)
	for slot = 1, GetNumLootItems() do
		if slot ~= exceptSlot then
			local _, id = self:LootSlotItem(slot)
			if id and L.Canon(id) == canon then return slot end
		end
	end
	return nil
end

-- Gibt einen Loot-Platz an einen Spieler. reason: "helper", "treasurer", "de", "random" oder nil.
-- extra: Zusatzangaben für das Protokoll (Platz und Anzahl beim Zufall).
function PM:GiveSlot(slot, name, reason, extra)
	local index = self:CandidateIndex(slot, name)
	if not index then return false end
	self.nextGiveReason, self.nextGiveExtra = reason, extra
	GiveMasterLoot(slot, index)
	self.nextGiveReason, self.nextGiveExtra = nil, nil
	return true
end

-- Daten für das Panel: Items samt Prio-Auflösung.
function PM:PanelItems()
	if self.testMode then
		for _, it in ipairs(self.testItems or {}) do it.res = self:ResolveForItem(it.itemID) end
		return self.testItems or {}
	end
	if not self.lootOpen then return {} end
	for _, it in ipairs(self.lootItems) do
		it.res = self:ResolveForItem(it.itemID, self:GetCandidates(it.slot), it.source)
	end
	return self.lootItems
end

-- Loot-Platz mit dem Item einer Würfelrunde, aus derselben Leiche oder Truhe.
function PM:SlotForSession(s)
	if not s or not self.lootOpen then return nil end
	local canon = L.Canon(s.itemID)
	for slot = 1, GetNumLootItems() do
		local _, id = self:LootSlotItem(slot)
		if id and L.Canon(id) == canon and (not s.source or self:LootSource(slot) == s.source) then return slot end
	end
	return nil
end

-- Würfelrunde für das Panel: laufende Runden immer. Ist das Item vergeben,
-- verschwindet die Runde, die Vergabe steht im Chat. Eine beendete Runde ohne
-- Vergabe bleibt nur, solange ihr Item noch in derselben offenen Beute liegt.
function PM:PanelSession()
	local s = L.ActiveSession(self:Raid())
	if not s or not s.closed then return s end
	if s.done then return nil end
	if self.testMode then return s end
	return self:SlotForSession(s) and s or nil
end

function PM:ShouldShowPanel()
	if not self:IsEnabled() or not self.db.settings.panelEnabled then return false end
	if self.testMode then return true end
	if #self.lootItems == 0 then return false end
	return self:IsMasterLooter() or self.db.settings.alwaysShow
end

-------------------------------------------------------------------------------
-- Plünderhelfer und Schatzmeister: Items automatisch verteilen
-------------------------------------------------------------------------------

function PM:AutoLootRules()
	local s = self.db.settings
	return {
		items = self:ActiveItemList("treasurer"), roll = self:ActiveItemList("roll"),
		qualities = s.autoLootQualities, recipeRolls = s.recipeRolls,
		helper = s.lootHelper, treasurer = s.treasurer,
	}
end

local ROLE_OF_TARGET = { helper = "lootHelper", treasurer = "treasurer" }

-- Der Schatzmeister bekommt nur Items seiner Liste, der Plünderhelfer alles andere
-- bis zur eingestellten Qualität. Items mit Prio und Items zum Verwürfeln werden
-- nie automatisch verteilt.
function PM:AutoLoot()
	local s = self.db.settings
	if not (s.lootHelper or s.treasurer) or not self:IsMasterLooter() then return end
	if self.lootShift then return end -- Shift beim Öffnen: nichts automatisch
	local rules = self:AutoLootRules()
	if not next(rules.qualities) and not next(rules.items) then return end
	local threshold = GetLootThreshold and GetLootThreshold() or 2
	local blocked, failed, waiting = 0, {}, {}
	for slot = GetNumLootItems(), 1, -1 do
		local link, itemID
		if not self.autoGiving[slot] then link, itemID = self:LootSlotItem(slot) end
		if link then
			local _, _, _, _, quality, locked = GetLootSlotInfo(slot)
			local target, listed = L.AutoLootTarget(itemID, quality, self:IsRecipe(itemID), rules)
			if (target or listed) and not locked and not L.HasHolders(self:ResolveForItem(itemID)) then
				if quality and quality < threshold then
					blocked = blocked + 1
				elseif not target then
					table.insert(waiting, 1, link)
				elseif self:GiveSlot(slot, rules[target], target) then
					self.autoGiving[slot] = true
				else
					failed[target] = true
				end
			end
		end
	end
	for _, target in ipairs({ "helper", "treasurer" }) do
		if failed[target] then
			self:Print("%s %s kann diese Beute nicht erhalten (nicht in der Nähe?).",
				self.ROLE_TEXT[ROLE_OF_TARGET[target]], rules[target])
		end
	end
	if #waiting > 0 and not self.treasurerHintShown then
		self.treasurerHintShown = true
		self:Print("Kein Schatzmeister bestimmt, diese Items der Liste bleiben liegen: %s. Bestimmen im Panel oder unter „Plündern“.",
			table.concat(waiting, ", "))
	end
	if blocked > 0 and not self.thresholdHintShown then
		self.thresholdHintShown = true
		self:Print("%d Item(s) für Plünderhelfer oder Schatzmeister liegen unter der Plündergrenze und lassen sich nicht automatisch verteilen. Die Grenze kannst du im Fenster unter „Plündern“ senken.", blocked)
	end
end

-- Beute im Raidchat ansagen, samt Prios. Dieselbe Beute (gleiche Leiche oder
-- Truhe und gleiches Item) wird erst nach announceDelay Sekunden erneut angesagt.
-- Items ohne geladene Daten folgen, sobald die Daten da sind, nie doppelt im selben Fenster.
function PM:AnnounceLoot()
	local s = self.db.settings
	if not s.announceLoot or self.testMode or not self:IsMasterLooter() then return end
	local now, delay = time(), s.announceDelay or 90
	self.announced = self.announced or {}
	self.announcedNow = self.announcedNow or {}
	for key, t in pairs(self.announced) do
		if now - t > 600 then self.announced[key] = nil end
	end
	local order, byItem = {}, {}
	for _, it in ipairs(self.lootItems) do
		if not it.loading then
			local canon = L.Canon(it.itemID)
			local key = (it.source or "?") .. ":" .. tostring(canon)
			local entry = byItem[key]
			if entry then
				entry.copies = entry.copies + 1
			else
				entry = { item = it, key = key, copies = 1 }
				byItem[key] = entry
				order[#order + 1] = entry
			end
		end
	end
	for _, e in ipairs(order) do
		local last = self.announced[e.key]
		if not self.announcedNow[e.key] and (not last or now - last >= delay) then
			self.announced[e.key] = now
			local it = e.item
			local res = self:ResolveForItem(it.itemID, self:GetCandidates(it.slot), it.source)
			for _, m in ipairs(L.LootAnnouncement(res, it.link, e.copies)) do self:Send(m) end
		end
		self.announcedNow[e.key] = true
	end
end

-- Entzauberer: Item der aktiven Würfelrunde, wenn niemand würfeln wollte.
Popup("PRIOMEISTER_DE", {
	text = "%s\n\nSicher an Entzauberer %s geben?",
	button1 = YES, button2 = NO,
	OnAccept = function(_, data)
		if data then PM:GiveToDisenchanter(data.session) end
	end,
	timeout = 0, whileDead = true, hideOnEscape = true,
})

-- Gibt das Item der Würfelrunde an den Entzauberer. Haben schon Spieler
-- gewürfelt oder ist es eine Prio-Runde, erst nach Rückfrage.
-- confirmed: Nummer der Runde, für die die Rückfrage bestätigt wurde.
function PM:GiveToDisenchanter(confirmed)
	local de = self.db.settings.disenchanter
	if not de then
		self:Print("Kein Entzauberer bestimmt.")
		return
	end
	local s = L.ActiveSession(self:Raid())
	if not s then
		self:Print("Keine Würfelrunde aktiv.")
		return
	end
	if confirmed and confirmed ~= s.id then
		self:Print("Inzwischen läuft eine andere Würfelrunde. Bitte noch einmal auf „An Entzauberer“ klicken.")
		return
	end
	if not confirmed then
		local rolls, prioText = L.OpenRolls(s), L.SessionPrioText(s)
		if #rolls > 0 or prioText then
			StaticPopup_Show("PRIOMEISTER_DE", L.ConfirmText(s.link, prioText, rolls), de, { session = s.id })
			return
		end
	end
	if self.testMode then
		self:ConfirmAward({ key = L.NameKey(de), name = de, itemID = s.itemID, link = s.link, reason = "de" })
		return
	end
	local slot = self:SlotForSession(s)
	if slot and not self:BelowThreshold(slot) then
		if not self:GiveSlot(slot, de, "de") then
			self:Print("Entzauberer %s kann diese Beute nicht erhalten (nicht in der Nähe?).", de)
		end
		return
	end
	-- unter der Plündergrenze oder schon selbst geplündert: per Handel
	self:AddTradeIntent(s.itemID, L.NameKey(de), "de")
	self:Print("%s an Entzauberer %s: selbst plündern und handeln, das Addon trägt den Handel als Entzaubern ein.",
		s.link or T("Das Item"), de)
end

Popup("PRIOMEISTER_WINNER", {
	text = "%s\n\nAn %s geben?",
	button1 = YES, button2 = NO,
	OnAccept = function(_, data)
		if data then PM:GiveToWinner(data.session, data.key) end
	end,
	timeout = 0, whileDead = true, hideOnEscape = true,
})

-- Gibt das Item der Würfelrunde dem Gewinner. Epische Items erst nach Rückfrage,
-- wie in Blizzards Plündermeister-Liste, abschaltbar unter Optionen. confirmedSession und confirmedKey:
-- Runde und Spieler, für die die Rückfrage bestätigt wurde.
function PM:GiveToWinner(confirmedSession, confirmedKey)
	local s = L.ActiveSession(self:Raid())
	local r = L.RoundWinner(s)
	if confirmedSession and not (r and confirmedSession == s.id and confirmedKey == r.key) then
		self:Print("Die Würfelrunde hat sich inzwischen geändert. Bitte noch einmal auf den Knopf klicken.")
		return
	end
	if not r then
		self:Print("Kein eindeutiger Gewinner in der Würfelrunde.")
		return
	end
	if self.testMode then
		self:ConfirmAward({ key = r.key, name = r.name, itemID = s.itemID, link = s.link, session = s.id })
		return
	end
	local slot = self:SlotForSession(s)
	if slot and not self:BelowThreshold(slot) then
		local quality = select(5, GetLootSlotInfo(slot))
		if not confirmedSession and self.db.settings.confirmEpicWinner and quality and quality >= (MASTER_LOOT_THREHOLD or 4) then
			StaticPopup_Show("PRIOMEISTER_WINNER", s.link or "?", string.format(T("%s (Wurf %d)"), r.name, r.value),
				{ session = s.id, key = r.key })
			return
		end
		if not self:GiveSlot(slot, r.name) then
			self:Print("%s kann diese Beute nicht erhalten (nicht in der Nähe?).", r.name)
		end
		return
	end
	-- unter der Plündergrenze oder schon selbst geplündert: per Handel
	self:Print("%s an %s: selbst plündern und handeln, das Addon trägt den Handel mit dem Wurf ein.",
		s.link or T("Das Item"), r.name)
end

Popup("PRIOMEISTER_HOLDER", {
	text = "%s\n\nAn %s geben?",
	button1 = YES, button2 = NO,
	OnAccept = function(_, data)
		if data then PM:GiveToHolder(data.itemID, data.slot, data.key, true) end
	end,
	timeout = 0, whileDead = true, hideOnEscape = true,
})

-- Hat nur ein anwesender Spieler Prio, bekommt er das Item direkt („An Name“ in
-- der Zeile des Items). Vorher prüfen, ob das Item noch daliegt und er noch der
-- einzige ist, etwa nach einem Verzicht. Epische Items erst nach Rückfrage wie bei
-- „An Name (Wurf)“. confirmed: die Rückfrage wurde bestätigt.
function PM:GiveToHolder(itemID, slot, key, confirmed)
	if not self:IsEnabled() then
		self:Print("PrioMeister ist ausgeschaltet (Optionen).")
		return
	end
	local source, res
	if self.testMode then
		res = self:ResolveForItem(itemID)
	else
		local _, id = self:LootSlotItem(slot)
		if not (self.lootOpen and id and L.Canon(id) == L.Canon(itemID)) then
			self:Print("Das Item liegt nicht mehr in der Beute.")
			return
		end
		source = self:LootSource(slot)
		res = self:ResolveForItem(itemID, self:GetCandidates(slot), source)
	end
	local h = res.mode == "single" and res.topHolders[1]
	if not h or h.key ~= key then
		self:Print("Die Prio hat sich inzwischen geändert, etwa durch einen Verzicht. Bitte im Panel noch einmal klicken.")
		return
	end
	if self.testMode then
		local link = self:ItemLabel(itemID)
		for _, it in ipairs(self.testItems or {}) do
			if it.itemID == itemID then link = it.link end
		end
		self:ConfirmAward({ key = h.key, name = h.name, itemID = itemID, link = link })
		return
	end
	local link = GetLootSlotLink(slot)
	if self:BelowThreshold(slot) then
		self:Print("%s an %s: selbst plündern und handeln, das Addon trägt den Handel als Prio ein.", link, h.name)
		return
	end
	local quality = select(5, GetLootSlotInfo(slot))
	if not confirmed and self.db.settings.confirmEpicWinner and quality and quality >= (MASTER_LOOT_THREHOLD or 4) then
		StaticPopup_Show("PRIOMEISTER_HOLDER", link, string.format("%s (Prio %d)", h.name, res.top),
			{ itemID = itemID, slot = slot, key = h.key })
		return
	end
	if not self:GiveSlot(slot, h.name) then
		self:Print("%s kann diese Beute nicht erhalten (nicht in der Nähe?).", h.name)
	end
end

-------------------------------------------------------------------------------
-- Vergabe per Handel: Items unter der Plündergrenze plündert der Plündermeister
-- selbst und handelt sie danach an den Gewinner. Eingetragen wird der Handel,
-- wenn der Empfänger in einer offenen Würfelrunde gewürfelt hat, Prio auf das
-- Item hat, zufällig gezogen oder als Entzauberer gewählt wurde oder als
-- Schatzmeister ein Item seiner Liste bekommt.
-------------------------------------------------------------------------------

local TRADE_SLOTS = 6 -- Platz 7 wird nicht gehandelt

function PM:AddTradeIntent(itemID, key, reason)
	self.tradeIntents = self.tradeIntents or {}
	table.insert(self.tradeIntents, { item = L.Canon(itemID), key = key, reason = reason, t = GetTime() })
end

function PM:TakeTradeIntent(canon, key)
	for i, it in ipairs(self.tradeIntents or {}) do
		if it.item == canon and it.key == key and GetTime() - it.t < 7200 then
			table.remove(self.tradeIntents, i)
			return it
		end
	end
	return nil
end

function PM:TRADE_SHOW()
	self.trade = { partner = UnitName("NPC"), items = {} }
end

-- Angebotene Items merken: Nach dem Abschluss ist das Handelsfenster schon zu.
function PM:SnapshotTrade()
	local t = self.trade
	if not t then return end
	t.partner = UnitName("NPC") or t.partner
	t.items = {}
	for i = 1, TRADE_SLOTS do
		local link = GetTradePlayerItemLink(i)
		if link then
			local _, _, count = GetTradePlayerItemInfo(i)
			t.items[#t.items + 1] = { link = link, itemID = L.ItemID(link), count = count or 1 }
		end
	end
end

function PM:TRADE_PLAYER_ITEM_CHANGED()
	self:SnapshotTrade()
end

function PM:TRADE_ACCEPT_UPDATE()
	self:SnapshotTrade()
end

function PM:UI_INFO_MESSAGE(_, message)
	if ERR_TRADE_COMPLETE and message == ERR_TRADE_COMPLETE then
		local t = self.trade
		self.trade = nil
		if t then self:CommitTrade(t) end
	end
end

function PM:CommitTrade(t)
	if not self:IsEnabled() then return end
	local key = L.NameKey(t.partner)
	if not key then return end
	local raid = self:Raid()
	local treasurer = L.NameKey(self.db.settings.treasurer)
	local listed = self:ActiveItemList("treasurer")
	for _, it in ipairs(t.items) do
		local canon = L.Canon(it.itemID)
		if canon then
			local p = { key = key, name = t.partner, itemID = it.itemID, link = it.link, count = it.count, viaTrade = true }
			local intent = self:TakeTradeIntent(canon, key)
			local s = not intent and L.FindSessionWithRoll(raid, it.itemID, key)
			local lr = self.lastRandom
			local drawn = lr and lr.key == key and lr.item == canon and GetTime() - lr.t < 7200
			local prio = not self:IgnoredKind(it.itemID)
				and L.OpenEntriesFor(raid, key, canon, self.db.settings.prio0Mode)[1] ~= nil
			if intent then
				p.reason = intent.reason
				self:ConfirmAward(p)
			elseif s then
				p.session = s.id
				self:ConfirmAward(p)
			elseif drawn or prio then
				self:ConfirmAward(p)
			elseif key == treasurer and listed[it.itemID] then
				p.reason = "treasurer"
				self:ConfirmAward(p)
			end
		end
	end
end

-------------------------------------------------------------------------------
-- Loot-Ereignisse
-------------------------------------------------------------------------------

function PM:LOOT_OPENED()
	self.lootOpen = true
	self.pending = {} -- offene Zuweisungen eines früheren Plünderfensters verfallen
	self.autoGiving = {}
	self.announcedNow = {}
	self.lootShift = IsShiftKeyDown and IsShiftKeyDown() or false
	if not self:IsEnabled() then
		ns.UI:HidePanel()
		return
	end
	if self.testMode then
		self:ScanLoot()
		return
	end
	self:AutoLoot()
	self:ScanLoot()
	self:AnnounceLoot()
	if self:ShouldShowPanel() then
		ns.UI:ShowPanel(true)
	else
		ns.UI:HidePanel()
	end
end

function PM:LOOT_CLOSED()
	-- Für ein /roll 1 kurz nach dem Schließen (PM:PassableLoot)
	self.recentLoot = { items = self.lootItems, t = GetTime() }
	self.lootOpen = false
	self.lootItems = {}
	self.autoGiving = {}
	if not self.testMode and not self.panelPinned then ns.UI:HidePanel() end
end

function PM:LOOT_SLOT_CLEARED(slot)
	self:ConfirmPendingBySlot(slot)
	if self.lootOpen and self:IsEnabled() then
		self:ScanLoot()
		ns.UI:RefreshPanel()
	end
end

function PM:LOOT_SLOT_CHANGED()
	if self.lootOpen and self:IsEnabled() then
		self:ScanLoot()
		ns.UI:RefreshPanel()
	end
end

-------------------------------------------------------------------------------
-- Zuweisungen erkennen
-------------------------------------------------------------------------------

function PM:PrunePending()
	local now = GetTime()
	for i = #self.pending, 1, -1 do
		if now - self.pending[i].t > PENDING_SECONDS then table.remove(self.pending, i) end
	end
end

function PM:OnGiveMasterLoot(slot, index)
	if not self:IsEnabled() then return end
	local link = self:LootSlotItem(slot) or (self.slotLinks and self.slotLinks[slot])
	local name = GetMasterLootCandidate(slot, index)
	local key = L.NameKey(name)
	if not link or not key then return end
	local _, _, _, _, quality = GetLootSlotInfo(slot)
	self:PrunePending()
	for i = #self.pending, 1, -1 do
		if self.pending[i].slot == slot then table.remove(self.pending, i) end
	end
	self.pending[#self.pending + 1] = {
		slot = slot, link = link, itemID = L.ItemID(link), name = name, key = key, t = GetTime(),
		quality = quality, reason = self.nextGiveReason,
		place = self.nextGiveExtra and self.nextGiveExtra.place,
		of = self.nextGiveExtra and self.nextGiveExtra.of,
		source = self:LootSource(slot),
	}
end

-- Erfolg: der Loot-Platz wird geleert.
function PM:ConfirmPendingBySlot(slot)
	self:PrunePending()
	for i = #self.pending, 1, -1 do
		local p = self.pending[i]
		if p.slot == slot then
			table.remove(self.pending, i)
			self:ConfirmAward(p)
			return true
		end
	end
	return false
end

-- Zweiter Weg: Beutemeldung im Chat ("X bekommt Beute: [Item].").
local function lootMatchers()
	if PM.lootMatchers then return PM.lootMatchers end
	local list = {}
	for _, key in ipairs({ "LOOT_ITEM_MULTIPLE", "LOOT_ITEM", "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF" }) do
		local fmt = _G[key]
		if type(fmt) == "string" then
			list[#list + 1] = { isSelf = key:find("SELF") ~= nil, matcher = L.FormatToMatcher(fmt) }
		end
	end
	PM.lootMatchers = list
	return list
end

function PM:CHAT_MSG_LOOT(msg)
	if #self.pending == 0 then return end
	for _, m in ipairs(lootMatchers()) do
		local r = L.MatchFormat(m.matcher, msg)
		if r then
			local name, link
			if m.isSelf then
				name, link = UnitName("player"), r[1]
			else
				name, link = r[1], r[2]
			end
			local key, canon = L.NameKey(name), L.Canon(L.ItemID(link))
			for i = #self.pending, 1, -1 do
				local p = self.pending[i]
				if p.key == key and L.Canon(p.itemID) == canon then
					table.remove(self.pending, i)
					self:ConfirmAward(p)
					return
				end
			end
			return
		end
	end
end

-- Fehlschlag: Blizzard meldet z. B. "Inventar voll".
function PM:UI_ERROR_MESSAGE(_, message)
	if #self.pending == 0 or type(message) ~= "string" then return end
	for _, key in ipairs(LOOT_ERRORS) do
		if _G[key] and message == _G[key] then
			local p = table.remove(self.pending)
			if self.autoGiving then self.autoGiving[p.slot] = nil end
			self:Print("|cffff4040Zuweisung fehlgeschlagen:|r %s an %s – %s", p.link, p.name, message)
			return
		end
	end
end

-------------------------------------------------------------------------------
-- Plündermeister-Liste: sortieren und markieren
-------------------------------------------------------------------------------

function PM:DecorateMasterLooterFrame()
	if not self:IsEnabled() or not MasterLooterFrame or not LootFrame then return end
	local slot = LootFrame.selectedSlot
	if not slot then return end

	local list = {}
	for i = 1, (MAX_RAID_MEMBERS or 40) do
		local name, class, className = GetMasterLootCandidate(slot, i)
		if name then list[#list + 1] = { index = i, name = name, class = class, className = className } end
	end
	local n = #list
	if n == 0 then return end
	local order = L.MasterLootButtonOrder(n)

	if self.db.settings.sortMasterLoot then
		L.SortCandidates(list, self:PinnedOrder())
		for i, c in ipairs(list) do
			local btn = MasterLooterFrame["player" .. order[i]]
			if btn and btn.Name then
				btn.id = c.index
				btn.Name:SetText(c.name)
				local color = RAID_CLASS_COLORS and c.className and RAID_CLASS_COLORS[c.className]
				if color then btn.Name:SetTextColor(color.r, color.g, color.b) end
			end
		end
	end

	-- Prio-Halter dieses Items, Rollen und angeheftete Spieler markieren
	local link = GetLootSlotLink(slot)
	local itemID = link and L.ItemID(link)
	local cands, byIndex = {}, {}
	for _, c in ipairs(list) do
		local key = L.NameKey(c.name)
		if key then cands[key] = c.index end
		byIndex[c.index] = c
	end
	local res = itemID and self:ResolveForItem(itemID, cands, self:LootSource(slot))
	local holderLevel, holderPassed = {}, {}
	if res then
		for lvl = 0, 3 do
			for _, h in ipairs(res.levels[lvl]) do
				holderLevel[h.key] = lvl
				holderPassed[h.key] = h.passed or h.unusable ~= nil
			end
		end
	end
	local marks = {}
	for _, pinName in ipairs(self.db.pins) do
		local key = L.NameKey(pinName)
		if key then marks[key] = "pin" end
	end
	local roleTags = {}
	for _, role in ipairs(self.ROLES) do
		local key = L.NameKey(self.db.settings[role])
		if key then roleTags[key] = roleTags[key] and (roleTags[key] .. "/" .. self.ROLE_SHORT[role]) or self.ROLE_SHORT[role] end
	end
	for key, tag in pairs(roleTags) do marks[key] = tag end

	for i = 1, n do
		local btn = MasterLooterFrame["player" .. order[i]]
		if btn then self:DecorateMLButton(btn, byIndex[btn.id], holderLevel, res, marks, itemID, holderPassed) end
	end
end

-- holderPassed: Prio-Halter, die auf dieses Exemplar verzichtet haben (grau statt grün)
function PM:DecorateMLButton(btn, c, holderLevel, res, marks, itemID, holderPassed)
	if not btn.pmTag then
		btn.pmGlow = btn:CreateTexture(nil, "BACKGROUND", nil, 2)
		btn.pmGlow:SetAllPoints(btn)
		btn.pmTag = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		btn.pmTag:SetPoint("RIGHT", btn, "RIGHT", -3, 0)
		btn:HookScript("OnEnter", function(b) PM:MasterLooterTooltip(b) end)
	end
	local key = c and L.NameKey(c.name)
	btn.pmKey, btn.pmName, btn.pmItemID = key, c and c.name, itemID

	local lvl = key and holderLevel[key]
	local mark = key and marks[key]
	local passed = key and holderPassed and holderPassed[key]
	local tag
	if lvl ~= nil then
		tag = "P" .. lvl
		btn.pmTag:SetText(tag)
		if res and res.top == lvl and not passed then
			btn.pmTag:SetTextColor(0.3, 1, 0.3)
			btn.pmGlow:SetColorTexture(0.1, 0.9, 0.1, 0.22)
		else
			btn.pmTag:SetTextColor(0.65, 0.65, 0.65)
			btn.pmGlow:SetColorTexture(0, 0, 0, 0)
		end
	elseif mark and mark ~= "pin" then
		tag = mark
		btn.pmTag:SetText(tag)
		btn.pmTag:SetTextColor(0.4, 0.8, 1)
		btn.pmGlow:SetColorTexture(0.2, 0.5, 1, 0.16)
	else
		btn.pmTag:SetText("")
		btn.pmGlow:SetColorTexture(0, 0, 0, 0)
	end
	if mark == "pin" and (lvl == nil or not res or res.top ~= lvl or passed) then
		btn.pmGlow:SetColorTexture(1, 0.82, 0, 0.16)
	end

	if btn.Name then
		btn.Name:SetWidth(tag and math.max(34, 72 - 5 * #tag) or 78)
		btn.tooltip = btn.Name:IsTruncated() and (c and c.name) or nil
	end
end

function PM:MasterLooterTooltip(btn)
	if not btn.pmKey or not self:IsEnabled() then return end
	if not GameTooltip:IsOwned(btn) then
		GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
		GameTooltip:SetText(btn.pmName or "", 1, 1, 1)
	end
	for _, line in ipairs(self:PlayerLines(btn.pmKey, btn.pmItemID)) do
		GameTooltip:AddLine(line, 1, 1, 1, true)
	end
	GameTooltip:Show()
end

-------------------------------------------------------------------------------
-- Testmodus: Panel und Würfelrunden ohne Raid ausprobieren
-------------------------------------------------------------------------------

local TEST_FREE_ITEM = 18813   -- Ring der Bindung (Onyxia), meist ohne Prio
local TEST_RECIPE_ITEM = 18259 -- Formel: Waffe - Zauberkraft (Geschmolzener Kern)

function PM:BuildTestItems()
	local raid = self:Raid()
	local counts, names = {}, {}
	for _, p in pairs(raid.players) do
		for _, e in ipairs(L.GetEntries(p, self.db.settings.prio0Mode)) do
			counts[e.item] = (counts[e.item] or 0) + 1
			if not names[e.item] then
				local i = (e.level == 0) and 1 or e.level
				names[e.item] = p.pn[i] ~= "" and p.pn[i] or nil
			end
		end
	end
	local ids = {}
	for id in pairs(counts) do ids[#ids + 1] = id end
	table.sort(ids, function(a, b)
		if counts[a] ~= counts[b] then return counts[a] > counts[b] end
		return a < b
	end)
	local items = {}
	for i = 1, math.min(#ids, 5) do
		items[#items + 1] = { itemID = ids[i], fallbackName = names[ids[i]] }
	end
	if not counts[L.Canon(TEST_FREE_ITEM)] then
		items[#items + 1] = { itemID = TEST_FREE_ITEM, fallbackName = T("Ring der Bindung") }
	end
	if not counts[TEST_RECIPE_ITEM] then
		items[#items + 1] = { itemID = TEST_RECIPE_ITEM, fallbackName = T("Formel: Waffe - Zauberkraft") }
	end
	for _, it in ipairs(items) do
		local name, link, quality, texture = self:ItemInfo(it.itemID)
		self:RequestItems({ it.itemID })
		it.link = link or ("[" .. (it.fallbackName or ("Item " .. it.itemID)) .. "]")
		it.name = name or it.fallbackName
		it.quality = quality or 4
		it.texture = texture or "Interface\\Icons\\INV_Misc_QuestionMark"
	end
	return items
end

function PM:ToggleTest()
	if self.testMode then
		self.testMode = false
		self.testRaid = nil
		self.testItems = nil
		ns.UI:HidePanel()
		self:Print("Testmodus beendet, Testdaten verworfen.")
		ns.UI:RefreshAll()
		return
	end
	self.testMode = true
	self.testRaid = ns.deepcopy(self.db.raid)
	self.testRaid.activeId = nil
	self.testItems = self:BuildTestItems()
	ns.UI:ShowPanel(false)
	self:Print("Testmodus an. Alle Spieler der Prioliste gelten als anwesend, Chat geht nur an dich.")
	DEFAULT_CHAT_FRAME:AddMessage("  " .. T("Würfeln: Knopf im Panel, dann /roll oder /pm testwurf Name 87 99 (50er: /pm testwurf Name 30 50)"))
	DEFAULT_CHAT_FRAME:AddMessage("  " .. T("Vergeben: /pm vergabe Name – beenden mit /pm test"))
	ns.UI:RefreshAll()
end
