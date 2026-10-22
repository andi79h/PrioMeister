-- PrioMeister – Main.lua
-- Hauptfenster mit den Reitern Raid, Vergaben, Plündern (Rollen, Listen je
-- Instanz) und Optionen sowie der Minimap-Knopf.

local ADDON, ns = ...
local L, PM, UI = ns.Logic, ns.PM, ns.UI
local T = ns.T or function(s) return s end
local Popup = ns.Popup or function(name, def) StaticPopupDialogs[name] = def return def end
local format = string.format

-- Logo und Symbole liegen in Media (TGA, Kantenlänge eine Zweierpotenz).
-- Neue Bilddateien findet WoW erst nach einem Neustart des Spiels.
local MEDIA = "Interface\\AddOns\\" .. (ADDON or "PrioMeister") .. "\\Media\\"
UI.LOGO = MEDIA .. "Logo.tga"
UI.LOGO_ROUND = MEDIA .. "Round.tga"

local MAIN_W, MAIN_H = 620, 570
local DE_DROPDOWN_W = 110
local CONTENT_W = MAIN_W - 32
-- Reiter enden bei -58, darunter je 10 Abstand bis zur Trennlinie und bis zum Inhalt
local DIVIDER_Y, PAGE_TOP = -68, -78
local ROLE_X = 60 -- Rollen im Reiter Raid: Abstand der Knöpfe vom linken Rand
local FIELD_X = 110 -- Reiter Plündern: Knopf und Auswahl hinter „Plündermeister:“ und „Plündergrenze:“

local TABS = {
	{ key = "raid", label = "Raid" },
	{ key = "awards", label = "Vergaben" },
	{ key = "loot", label = "Plündern" },
	{ key = "options", label = "Optionen", gear = true }, -- kein Reiter, Knopf „?“ oben rechts
}

local NEW_RAID_HELP = "Startet einen neuen Raid: Vergaben, Würfelstufen und Prioliste beginnen leer. Der bisherige Raid kommt ins Archiv, im Reiter „Vergaben“ siehst und exportierst du ihn weiter und kannst ihn fortsetzen."

Popup("PRIOMEISTER_NEWRAID", {
	text = "Neuen Raid starten?\nVergaben, Würfelstufen und Prioliste beginnen leer. Der bisherige Raid kommt ins Archiv und lässt sich im Reiter „Vergaben“ wieder fortsetzen.",
	button1 = YES, button2 = NO,
	OnAccept = function() PM:NewRaid() end,
	timeout = 0, whileDead = true, hideOnEscape = true,
})

Popup("PRIOMEISTER_REOPEN", {
	text = "%s",
	button1 = YES, button2 = NO,
	OnAccept = function(_, data)
		if data and PM:ReopenRaid(data.entry) and UI.main then
			UI.main.pages.awards.view = 0
			UI:RefreshAll()
		end
	end,
	timeout = 0, whileDead = true, hideOnEscape = true,
})

Popup("PRIOMEISTER_HANDOVER", {
	text = "%s",
	button1 = "Eintragen", button2 = CANCEL,
	OnAccept = function(_, data) if data then PM:HandOver(data) end end,
	timeout = 0, whileDead = true, hideOnEscape = true,
})

Popup("PRIOMEISTER_HANDOVER_UNDO", {
	text = "Weitergabe zurücknehmen?\n%s",
	button1 = YES, button2 = NO,
	OnAccept = function(_, data)
		if data and PM:ViewRaid(data.view).awards[data.index] == data.aw then PM:RemoveHandover(data.view, data.index) end
	end,
	timeout = 0, whileDead = true, hideOnEscape = true,
})

Popup("PRIOMEISTER_RELOAD", {
	text = "Die Sprache wechselt nach dem Neuladen der Oberfläche. Jetzt neu laden?",
	button1 = "Neu laden", button2 = "Später",
	OnAccept = function() if ReloadUI then ReloadUI() end end,
	timeout = 0, whileDead = true, hideOnEscape = true,
})

Popup("PRIOMEISTER_UNDO", {
	text = "Letzte Vergabe zurücknehmen?\n%s",
	button1 = YES, button2 = NO,
	OnAccept = function() PM:UndoLast() end,
	timeout = 0, whileDead = true, hideOnEscape = true,
})

local function Heading(parent, text)
	local fs = UI.Label(parent, "GameFontNormal")
	fs:SetText(T(text))
	return fs
end

-------------------------------------------------------------------------------
-- Rahmen und Reiter
-------------------------------------------------------------------------------

function UI:GetMain()
	if self.main then return self.main end
	local f = self.Box("PrioMeisterMainFrame", UIParent, "DIALOG", true)
	f:SetSize(MAIN_W, MAIN_H)
	f:SetPoint("CENTER")
	self.Movable(f)
	f:SetToplevel(true)
	table.insert(UISpecialFrames, "PrioMeisterMainFrame")

	-- Logo links oben, mittig auf der Höhe von „?“ und Kreuz rechts; der Titel steht daneben
	f.logo = f:CreateTexture(nil, "ARTWORK")
	f.logo:SetSize(26, 26)
	f.logo:SetPoint("TOPLEFT", 12, -5)
	f.logo:SetTexture(UI.LOGO)
	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.title:SetPoint("LEFT", f.logo, "RIGHT", 6, 0)
	f.title:SetText("PrioMeister " .. PM.version)
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)
	f.close = close
	-- Optionen: roter Knopf „?“ oben rechts wie die anderen Knöpfe (ein Zahnrad auf rotem Knopf hat
	-- Classic nicht), ein zweiter Klick führt zurück; der Changelog steht in den Optionen
	-- quadratisch wie das Kreuz daneben, mittig auf seiner Höhe
	f.gear = self.Button(f, "?", 24, 24)
	f.gear:SetPoint("RIGHT", close, "LEFT", 0, 0)
	f.gear:SetScript("OnClick", function()
		UI:SelectTab(f.current == "options" and (f.lastTab or "raid") or "options")
	end)
	self.Tooltip(f.gear, "Optionen", "Einstellungen, angeheftete Spieler und der Changelog. Ein zweiter Klick führt zurück.")

	f.tabs, f.pages = {}, {}
	local x = 14
	for _, t in ipairs(TABS) do
		if not t.gear then
			local b = self.Button(f, t.label, 110, 22)
			b:SetPoint("TOPLEFT", f, "TOPLEFT", x, -36)
			b:SetScript("OnClick", function() UI:SelectTab(t.key) end)
			f.tabs[t.key] = b
			x = x + 114
		end
		local page = CreateFrame("Frame", nil, f)
		page:SetPoint("TOPLEFT", 16, PAGE_TOP)
		page:SetPoint("BOTTOMRIGHT", -16, 14)
		page:Hide()
		f.pages[t.key] = page
	end
	-- Trennlinie zwischen den Reitern und dem Inhalt
	f.divider = f:CreateTexture(nil, "ARTWORK")
	f.divider:SetColorTexture(0.55, 0.55, 0.6, 0.35)
	f.divider:SetHeight(1)
	f.divider:SetPoint("TOPLEFT", f, "TOPLEFT", 14, DIVIDER_Y)
	f.divider:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, DIVIDER_Y)
	f.current = "raid"
	self.main = f
	self:BuildRaidPage(f.pages.raid)
	self:BuildAwardsPage(f.pages.awards)
	self:BuildLootPage(f.pages.loot)
	self:BuildOptionsPage(f.pages.options)
	f:Hide()
	return f
end

function UI:SelectTab(key)
	local f = self:GetMain()
	f.current = key
	if key ~= "options" then f.lastTab = key end
	for k, page in pairs(f.pages) do page:SetShown(k == key) end
	for k, b in pairs(f.tabs) do
		if k == key then b:LockHighlight() else b:UnlockHighlight() end
	end
	if key == "options" then f.gear:LockHighlight() else f.gear:UnlockHighlight() end
	self:RefreshMain()
end

function UI:ShowMain(tab)
	local f = self:GetMain()
	f:Show()
	self:SelectTab(tab or f.current or "raid")
end

function UI:ToggleMain()
	local f = self:GetMain()
	if f:IsShown() then f:Hide() else self:ShowMain() end
end

function UI:RefreshMain()
	local f = self.main
	if not f or not f:IsShown() or not PM.db then return end
	local page = f.pages[f.current or "raid"]
	if page and page.refresh then page.refresh() end
end

-------------------------------------------------------------------------------
-- Reiter "Raid"
-------------------------------------------------------------------------------

-- Würfelstufen: zwei Spalten mit Name, Stufe, Minus und Plus
local TIER_CELL_W, TIER_ROW_H = math.floor((CONTENT_W - 30) / 2), 21

local function CreateTierRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(TIER_CELL_W, 20)
	row.text = UI.Label(row, "GameFontHighlightSmall", TIER_CELL_W - 60)
	row.text:SetPoint("LEFT", 4, 0)
	row.text:SetWordWrap(false)
	row.minus = UI.Button(row, "-", 22, 18, true)
	row.minus:SetPoint("LEFT", row, "LEFT", TIER_CELL_W - 52, 0)
	row.plus = UI.Button(row, "+", 22, 18, true)
	row.plus:SetPoint("LEFT", row.minus, "RIGHT", 2, 0)
	row.minus:SetScript("OnClick", function() if row.key then PM:AdjustWins(row.key, -1) end end)
	row.plus:SetScript("OnClick", function() if row.key then PM:AdjustWins(row.key, 1) end end)
	UI.Tooltip(row.minus, "Ein freier Gewinn weniger", "Würfelt eine Stufe höher, höchstens mit 100. Steht mit Uhrzeit in der Vergabeliste.")
	UI.Tooltip(row.plus, "Ein freier Gewinn mehr",
		"Würfelt eine Stufe tiefer, etwa nach einer Vergabe aus Kulanz ohne Wurf im Addon. Steht mit Uhrzeit in der Vergabeliste.")
	return row
end

function UI:BuildRaidPage(page)
	page.listInfo = self.Label(page, "GameFontNormal", 260)
	page.listInfo:SetPoint("TOPLEFT", 0, 0)
	page.listInfo:SetWordWrap(false)
	page.listSub = self.Label(page, "GameFontHighlightSmall", 260)
	page.listSub:SetPoint("TOPLEFT", page.listInfo, "BOTTOMLEFT", 0, -2)
	page.listSub:SetWordWrap(false)
	-- Maus über „Prioliste“: Stand der Liste wie /pm stand
	page.listHover = CreateFrame("Frame", nil, page)
	page.listHover:SetPoint("TOPLEFT", page.listInfo, "TOPLEFT", 0, 0)
	page.listHover:SetSize(260, 30)
	page.listHover:EnableMouse(true)
	self.Tooltip(page.listHover, "Prioliste", function() return table.concat(PM:ListInfo(), "\n") end)

	local newRaid = self.Button(page, "Neuer Raid", 100, 22)
	newRaid:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 2)
	newRaid:SetScript("OnClick", function() StaticPopup_Show("PRIOMEISTER_NEWRAID") end)
	self.Tooltip(newRaid, "Neuer Raid", NEW_RAID_HELP)
	page.newRaid = newRaid
	local import = self.Button(page, "Importieren …", 110, 22)
	import:SetPoint("RIGHT", newRaid, "LEFT", -6, 0)
	import:SetScript("OnClick", function() UI:ShowImport() end)
	self.Tooltip(import, "Importieren", "Zeigt die geladene Liste als CSV. Eine neue Liste von priomeister.de einfügen ersetzt sie.")
	page.table = self.Button(page, "Anzeigen", 100, 22)
	page.table:SetPoint("RIGHT", import, "LEFT", -6, 0)
	page.table:SetScript("OnClick", function() UI:ShowPrioTable() end)
	self.Tooltip(page.table, "Prioliste anzeigen", "Alle Spieler mit ihren Prios 1 bis 3 als Tabelle, wie bei Prio3. Erhaltene Prios sind grün markiert.")

	-- Rollen: drei gleich breite Knöpfe bis zum rechten Rand
	local roles = Heading(page, "Rollen:")
	roles:SetPoint("TOPLEFT", 0, -46)
	local roleW = math.floor((CONTENT_W - ROLE_X - 12) / 3)
	page.helper = self:CreateRoleButton(page, "lootHelper", roleW)
	page.helper:SetPoint("LEFT", roles, "LEFT", ROLE_X, 0)
	page.treasurer = self:CreateRoleButton(page, "treasurer", roleW)
	page.treasurer:SetPoint("LEFT", page.helper, "RIGHT", 6, 0)
	page.de = self:CreateRoleButton(page, "disenchanter", CONTENT_W - ROLE_X - 12 - 2 * roleW)
	page.de:SetPoint("LEFT", page.treasurer, "RIGHT", 6, 0)

	local noPrioTitle = Heading(page, "Im Raid ohne Prio:")
	noPrioTitle:SetPoint("TOPLEFT", 0, -82)
	local remind = self.Button(page, "Im Raid erinnern", 130, 20, true)
	remind:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -78)
	remind:SetScript("OnClick", function() PM:RemindNoPrio() end)
	self.Tooltip(remind, "Im Raid erinnern", "Postet die Namen im Raidchat mit der Bitte, Prios einzutragen. Mit einer Liste von priomeister.de steht der Link zum Prio-Run samt PIN dabei.")
	page.noPrio = self.Label(page, "GameFontHighlightSmall", CONTENT_W)
	page.noPrio:SetPoint("TOPLEFT", noPrioTitle, "BOTTOMLEFT", 0, -6)
	page.noPrio:SetMaxLines(2)
	page.noPrio:SetJustifyV("TOP")
	page.noPrio:SetHeight(26)
	-- Priocheck von priomeister.de: Zusammenfassung, Details im Tooltip (seit 1.20)
	page.checkLine = self.Label(page, "GameFontDisableSmall", CONTENT_W)
	page.checkLine:SetPoint("TOPLEFT", page.noPrio, "BOTTOMLEFT", 0, -2)
	page.checkLine:SetWordWrap(false)
	page.checkHover = CreateFrame("Frame", nil, page)
	page.checkHover:SetPoint("TOPLEFT", page.noPrio, "TOPLEFT", 0, 0)
	page.checkHover:SetPoint("BOTTOMRIGHT", page.checkLine, "BOTTOMRIGHT", 0, 0)
	page.checkHover:EnableMouse(true)
	self.Tooltip(page.checkHover, "Priocheck", function() return table.concat(PM:CheckLines(), "\n") end)

	local recipeTitle = Heading(page, "Rezepte und Reittiere auf Prio (werden ignoriert):")
	recipeTitle:SetPoint("TOPLEFT", 0, -148)
	local recipeAnnounce = self.Button(page, "Im Raid ansagen", 130, 20, true)
	recipeAnnounce:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -144)
	recipeAnnounce:SetScript("OnClick", function() PM:AnnounceIgnoredPrios() end)
	self.Tooltip(recipeAnnounce, "Im Raid ansagen", "Bittet die Spieler im Raidchat, ihre Prio auf ein anderes Item zu ändern.")
	page.recipeBox = self.EnableLinks(CreateFrame("Frame", nil, page))
	page.recipeBox:SetPoint("TOPLEFT", recipeTitle, "BOTTOMLEFT", 0, -6)
	page.recipeBox:SetSize(CONTENT_W, 38)
	page.recipes = self.Label(page.recipeBox, "GameFontHighlightSmall", CONTENT_W)
	page.recipes:SetPoint("TOPLEFT", 0, 0)
	page.recipes:SetMaxLines(3)
	page.recipes:SetJustifyV("TOP")
	page.recipes:SetHeight(38)

	-- Würfelstufen aller, die gewürfelt haben, in zwei Spalten zum Scrollen
	local tiersTitle = Heading(page, "Würfelstufen aller, die in diesem Raid gewürfelt haben:")
	tiersTitle:SetPoint("TOPLEFT", 0, -214)
	local tierScroll = CreateFrame("ScrollFrame", "PrioMeisterTierScroll", page, "UIPanelScrollFrameTemplate")
	tierScroll:SetPoint("TOPLEFT", 0, -234)
	tierScroll:SetPoint("BOTTOMRIGHT", -26, 0)
	page.tierContent = CreateFrame("Frame", nil, tierScroll)
	page.tierContent:SetSize(2 * TIER_CELL_W, 10)
	tierScroll:SetScrollChild(page.tierContent)
	page.tierRows = {}
	page.tierEmpty = self.Label(page, "GameFontDisableSmall", CONTENT_W)
	page.tierEmpty:SetPoint("TOPLEFT", 4, -238)

	page.refresh = function()
		local raid = PM:Raid()
		local count = 0
		for _ in pairs(raid.players) do count = count + 1 end
		if count == 0 then
			page.listInfo:SetText(T("Prioliste: |cffff8000noch nicht importiert|r"))
		else
			local stand = raid.meta and L.FormatStand(raid.meta.stand, date("%Y-%m-%d"))
			page.listInfo:SetText(format(T("Prioliste: %d Spieler%s"), count, stand and (T(" · Stand ") .. stand) or ""))
		end
		page.listSub:SetText(format(T("Raid seit %s · %d Vergaben%s"), date("%d.%m. %H:%M", raid.started or time()),
			L.AwardCount(raid), PM.testMode and T(" · |cffff8000Testmodus|r") or ""))
		page.helper:SetText(UI:RoleText("lootHelper"))
		page.treasurer:SetText(UI:RoleText("treasurer"))
		page.de:SetText(UI:RoleText("disenchanter"))

		local noPrio = PM:NoPrioMembers()
		local check = PM:CheckResult()
		if check then
			page.checkLine:SetText(format(T("Priocheck von %s: %d unvollständig, %d vollständig. Maus darüber zeigt Details."),
				date("%H:%M", PM:CurrentCheck().t), #check.partial, check.complete))
		else
			page.checkLine:SetText(T("Prüfen ohne Schließen: „Priocheck kopieren“ unter „Alle Prios“ auf der Spielerseite, hier einfügen."))
		end
		if count == 0 and not check then
			page.noPrio:SetText(T("|cff808080Erst nach dem Import der Prioliste.|r"))
		elseif #noPrio == 0 then
			page.noPrio:SetText(T("|cff40ff40Alle im Raid haben Prios eingetragen.|r"))
		else
			local names = {}
			for _, n in ipairs(noPrio) do names[#names + 1] = PM:ColoredName(L.NameKey(n), n) end
			page.noPrio:SetText(table.concat(names, ", "))
		end

		local ignored = PM:IgnoredPrioEntries()
		if PM.db.settings.recipePrio and PM.db.settings.mountPrio then
			page.recipes:SetText(T("|cff808080Rezepte und Reittiere auf Prio sind erlaubt (Optionen).|r"))
		elseif #ignored == 0 then
			page.recipes:SetText(T("|cff808080Keine.|r"))
		else
			local parts = {}
			for _, e in ipairs(ignored) do parts[#parts + 1] = format(T("%s %s (Prio %d)"), e.name, e.label, e.level) end
			page.recipes:SetText(table.concat(parts, ", "))
		end

		local tiers = PM:TierList()
		for i, e in ipairs(tiers) do
			local row = page.tierRows[i]
			if not row then
				row = CreateTierRow(page.tierContent)
				page.tierRows[i] = row
			end
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", page.tierContent, "TOPLEFT", ((i - 1) % 2) * TIER_CELL_W, -math.floor((i - 1) / 2) * TIER_ROW_H)
			row.key = e.key
			local won = (e.wins > 0) and format(T("%d gewonnen, "), e.wins) or ""
			local roll = (e.max < 100) and format(T("|cffffd100/roll %d|r"), e.max) or T("/roll 100")
			row.text:SetText(format("%s: %s%s", PM:ColoredName(e.key, e.name), won, roll))
			row.minus:SetEnabled(e.wins > 0)
			row:Show()
		end
		for i = #tiers + 1, #page.tierRows do
			page.tierRows[i].key = nil
			page.tierRows[i]:Hide()
		end
		page.tierContent:SetHeight(math.max(10, math.ceil(#tiers / 2) * TIER_ROW_H))
		page.tierEmpty:SetText(#tiers == 0 and T("Noch hat niemand gewürfelt. Alle würfeln mit /roll 100.") or "")
	end
end

-------------------------------------------------------------------------------
-- Reiter "Vergaben"
-------------------------------------------------------------------------------

-- Instanzen eines Raids als Text, z. B. " · Onyxias Hort, Zul'Gurub". Leer, wenn
-- das Addon sie nicht kennt (Raids vor Version 1.11).
function UI:RaidInstanceText(raid)
	local names = {}
	for _, id in ipairs(L.RaidInstances(raid)) do names[#names + 1] = PM:InstanceName(id) end
	return #names > 0 and (" · " .. table.concat(names, ", ")) or ""
end

-- Rückfrage vor dem Fortsetzen eines früheren Raids (Nummer im Archiv).
function UI:RequestReopen(index)
	local h = PM.db.history[index]
	if not h then return end
	local current = PM:Raid()
	local tail = (#current.awards > 0) and T("Der laufende Raid kommt ins Archiv und lässt sich genauso fortsetzen.")
		or T("Der laufende Raid hat keine Vergaben und wird verworfen.")
	-- Kommt die Prioliste mit? Raids vor 1.14 haben sie nicht gespeichert.
	local players = 0
	for _ in pairs(h.players or {}) do players = players + 1 end
	local list = (players > 0)
		and format(T("Die Prioliste mit %d Spielern%s wird mitgeladen."), players, h.imported and (T(" vom ") .. date("%d.%m. %H:%M", h.imported)) or "")
		or T("|cffff4040Für diesen Raid ist keine Prioliste gespeichert.|r Du importierst sie danach mit „Nur Liste ersetzen“.")
	StaticPopup_Show("PRIOMEISTER_REOPEN", format(T("Raid vom %s%s fortsetzen?\n\n%d Vergaben und die Würfelstufen gelten weiter. %s\n\n%s"),
		date("%d.%m. %H:%M", h.started or h.ended or 0), self:RaidInstanceText(h), L.AwardCount(h), list, tail), nil, { entry = h })
end

-- Beschriftung eines Raids in der Auswahl: 0 = aktueller Raid, sonst ein früherer.
function UI:RaidLabel(index)
	if index == 0 then
		local raid = PM:Raid()
		return format(T("Aktueller Raid%s (%d)"), self:RaidInstanceText(raid), L.AwardCount(raid))
	end
	local h = PM.db.history[index]
	return format(T("Raid vom %s%s (%d)"), date("%d.%m. %H:%M", h.started or h.ended or 0), self:RaidInstanceText(h), L.AwardCount(h))
end

-- Zeile der Vergabenliste: Text mit Links wie bisher, Rechtsklick für die Weitergabe.
-- Ein Frame, kein Knopf: Links in Frames gehen sicher (Maus darüber, Klick, Shift-Klick).
function UI:AwardRow(page, content)
	local row = CreateFrame("Frame", nil, content)
	row:SetSize(CONTENT_W - 34, 16)
	row:EnableMouse(true)
	local hl = row:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(row)
	hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	hl:SetBlendMode("ADD")
	row.text = self.Label(row, "GameFontHighlightSmall", CONTENT_W - 34)
	row.text:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.text:SetWordWrap(false)
	local function menu(r) UI:AwardMenu(page, r.index, r) end
	self.EnableLinks(row, menu)
	row:SetScript("OnMouseUp", function(r, button) if button == "RightButton" then menu(r) end end)
	return row
end

-- Rechtsklick auf eine Vergabe: Namen zur Auswahl, bei einer Weitergabe auch Zurücknehmen.
-- Geht auch in früheren Raids, etwa wenn die Weitergabe erst nach dem Raid auffällt.
function UI:AwardMenu(page, index, anchor)
	local view = page.view
	local raid = PM:ViewRaid(view)
	local aw = index and raid.awards[index]
	if not aw then return end
	if not L.CanHandOver(aw) then
		if aw.givenTo then
			PM:Print("%s hat %s schon an %s weitergegeben.", aw.name, aw.link or "das Item", aw.givenTo)
		else
			PM:Print("Weitergeben lassen sich nur vergebene Items.")
		end
		return
	end
	local action
	if aw.kind == "given" then
		action = { text = T("Weitergabe zurücknehmen"), onClick = function()
			StaticPopup_Show("PRIOMEISTER_HANDOVER_UNDO", L.AwardLine(aw), nil, { view = view, index = index, aw = aw })
		end }
	end
	self:ShowPicker(anchor, format(T("%s hat es weitergegeben an:"), aw.name), {
		names = PM:HandoverNames(raid, aw.key), noNone = true, action = action,
		onPick = function(name) if name then PM:RequestHandover(view, index, name) end end,
	})
end

function UI:BuildAwardsPage(page)
	page.view = 0
	page.header = Heading(page, "")
	page.header:SetPoint("TOPLEFT", 0, 0)
	page.header:SetWidth(CONTENT_W - 300)
	page.header:SetWordWrap(false)

	-- aktueller oder früherer Raid
	local raidSelect = CreateFrame("DropdownButton", "PrioMeisterAwardsRaid", page, "WowStyle1DropdownTemplate")
	raidSelect:SetWidth(280)
	raidSelect:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 4)
	raidSelect:SetupMenu(function(_, root)
		local function isSelected(index) return index == page.view end
		local function select(index)
			page.view = index
			page.refresh()
		end
		root:CreateRadio(UI:RaidLabel(0), isSelected, select, 0)
		for i in ipairs(PM.db.history) do root:CreateRadio(UI:RaidLabel(i), isSelected, select, i) end
		if root.SetScrollMode and #PM.db.history > 15 then root:SetScrollMode(400) end
	end)
	page.raidSelect = raidSelect

	local scroll = CreateFrame("ScrollFrame", "PrioMeisterAwardsScroll", page, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, -26)
	scroll:SetPoint("BOTTOMRIGHT", -26, 80)
	page.hint = self.Label(page, "GameFontDisableSmall", CONTENT_W - 30)
	page.hint:SetPoint("BOTTOMLEFT", 0, 64)
	page.hint:SetText(T("Rechtsklick auf eine Vergabe: Weitergabe an einen anderen Spieler eintragen."))
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(CONTENT_W - 30, 10)
	scroll:SetScrollChild(content)
	page.content = content
	page.lines = {}  -- Texte der Zeilen
	page.rows = {}   -- Zeilen als Knöpfe, für den Rechtsklick
	self.EnableLinks(content)

	-- Teilen: Kanal wählen, beim Flüstern den Namen
	local shareLabel = self.Label(page, "GameFontHighlight")
	shareLabel:SetText(T("Teilen in:"))
	shareLabel:SetPoint("BOTTOMLEFT", 0, 40)
	local channel = CreateFrame("DropdownButton", "PrioMeisterShareChannel", page, "WowStyle1DropdownTemplate")
	channel:SetWidth(130)
	channel:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 72, 34)
	channel:SetupMenu(function(_, root)
		for _, c in ipairs(PM.SHARE_CHANNELS) do
			root:CreateRadio(T(c[2]), function(value) return value == PM.db.settings.shareChannel end,
				function(value)
					PM.db.settings.shareChannel = value
					page.refresh()
				end, c[1])
		end
	end)
	page.channel = channel
	local target = CreateFrame("EditBox", "PrioMeisterShareTarget", page, "InputBoxTemplate")
	target:SetSize(130, 20)
	target:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 218, 36)
	target:SetAutoFocus(false)
	local function saveTarget(e) PM.db.settings.shareTarget = L.Trim(e:GetText()) end
	target:SetScript("OnEditFocusLost", saveTarget)
	target:SetScript("OnEnterPressed", function(e)
		saveTarget(e)
		e:ClearFocus()
	end)
	target:SetScript("OnEscapePressed", function(e) e:ClearFocus() end)
	page.target = target
	local share = self.Button(page, "Teilen", 100, 22)
	share:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 356, 34)
	share:SetScript("OnClick", function()
		saveTarget(target)
		PM:ShareAwards(PM:ViewRaid(page.view))
	end)
	self.Tooltip(share, "Vergaben teilen",
		"Postet die Vergaben des gewählten Raids im gewählten Kanal, eine Zeile pro halbe Sekunde. Eigene Gewinne stehen einzeln da, Vergaben an Plünderhelfer, Schatzmeister und Entzauberer gebündelt.")
	page.share = share

	-- untere Reihe: vier Knöpfe vom linken bis zum rechten Rand
	local undo = self.Button(page, "Letzte zurücknehmen", 150, 22)
	undo:SetPoint("BOTTOMLEFT", 0, 0)
	undo:SetScript("OnClick", function()
		local raid = PM:Raid()
		local last = raid.awards[#raid.awards]
		if last then StaticPopup_Show("PRIOMEISTER_UNDO", L.AwardLine(last)) end
	end)
	page.undo = undo
	local resume = self.Button(page, "Raid fortsetzen", 150, 22)
	resume:SetPoint("BOTTOMLEFT", 0, 0)
	resume:SetScript("OnClick", function() UI:RequestReopen(page.view) end)
	self.Tooltip(resume, "Raid fortsetzen",
		"Macht den gewählten Raid wieder zum laufenden Raid, etwa nach einem versehentlichen „Neuer Raid“ oder am zweiten Abend. Vergaben und Würfelstufen gelten weiter, der laufende Raid kommt ins Archiv.")
	page.resume = resume
	local chat = self.Button(page, "Im Chat ausgeben", 138, 22)
	chat:SetPoint("LEFT", undo, "RIGHT", 6, 0)
	chat:SetScript("OnClick", function() PM:PrintAwards(PM:ViewRaid(page.view)) end)
	self.Tooltip(chat, "Im Chat ausgeben", "Zeigt die Vergaben nur in deinem eigenen Chatfenster.")
	local export = self.Button(page, "Export (CSV)", 134, 22)
	export:SetPoint("LEFT", chat, "RIGHT", 6, 0)
	export:SetScript("OnClick", function()
		UI:ShowText("PrioMeister – Export", PM:ExportCSV({ PM:ViewRaid(page.view) }))
	end)
	self.Tooltip(export, "Export (CSV)",
		"Alle Vergaben und Würfe des gewählten Raids als CSV, zum Einfügen auf priomeister.de im Reiter „Vergaben“ des Prio-Runs oder für eine Tabelle. Einfügen dürfen Raidleitung und Plündermeister. Würfe stehen als Art „Wurf“ mit Runde und Status darin.")
	local exportAll = self.Button(page, "Export alle Raids", CONTENT_W - 150 - 138 - 134 - 18, 22)
	exportAll:SetPoint("LEFT", export, "RIGHT", 6, 0)
	exportAll:SetScript("OnClick", function() UI:ShowText(T("PrioMeister – Export aller Raids"), PM:ExportText(true)) end)

	page.refresh = function()
		if page.view > 0 and not PM.db.history[page.view] then page.view = 0 end
		local raid = PM:ViewRaid(page.view)
		local n = #raid.awards
		if page.view == 0 then
			page.header:SetText(format(T("Vergaben seit %s: %d"), date("%d.%m. %H:%M", raid.started or time()), L.AwardCount(raid)))
		else
			page.header:SetText(format(T("Raid vom %s bis %s: %d Vergaben"), date("%d.%m. %H:%M", raid.started or 0),
				date("%H:%M", raid.ended or raid.started or 0), L.AwardCount(raid)))
		end
		if raidSelect.GenerateMenu then raidSelect:GenerateMenu() end
		undo:SetEnabled(page.view == 0)
		undo:SetShown(page.view == 0)
		resume:SetShown(page.view > 0)
		page.hint:SetShown(n > 0)
		for i = 1, math.max(n, 1) do
			local row = page.rows[i]
			if not row then
				row = UI:AwardRow(page, content)
				page.rows[i] = row
				page.lines[i] = row.text
			end
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -(i - 1) * 16)
			row.index = i
			local aw = raid.awards[i]
			if aw then
				local line = L.AwardLine(aw)
				if aw.kind == "tier" then line = "|cffffd100" .. line .. "|r" end
				if aw.kind == "pass" then line = "|cffb0b0b0" .. line .. "|r" end
				if aw.kind == "given" then line = "|cffa0c8ff" .. line .. "|r" end
				row.text:SetText(format("|cff909090%s|r  %s", date("%H:%M", aw.t or 0), line))
			else
				row.text:SetText(T("|cff808080Noch keine Vergaben in diesem Raid.|r"))
			end
			row:Show()
		end
		for i = math.max(n, 1) + 1, #page.rows do page.rows[i]:Hide() end
		content:SetHeight(math.max(10, n * 16))

		local s = PM.db.settings
		if channel.GenerateMenu then channel:GenerateMenu() end
		target:SetShown(s.shareChannel == "WHISPER")
		if not target:HasFocus() then target:SetText(s.shareTarget or "") end
		share:SetEnabled(PM.sharing == nil and n > 0)
		share:SetText(PM.sharing and T("Teilt …") or T("Teilen"))
	end
end

-------------------------------------------------------------------------------
-- Reiter "Plündern"
-------------------------------------------------------------------------------

local HELPER_QUALITIES = { 0, 1, 2, 3 } -- Grau bis Blau, einzeln an- und abwählbar

local INST_W, LIST_TOP, LIST_H, LIST_ROW = 200, -246, 140, 16

Popup("PRIOMEISTER_CLEARLIST", {
	text = "%s leeren?",
	button1 = YES, button2 = NO,
	OnAccept = function(_, data)
		if data then PM:ClearList(data.kind, data.id) end
	end,
	timeout = 0, whileDead = true, hideOnEscape = true,
})

-- Einträge der Instanz-Spalte: alle Instanzen, die Raids, dann die aktuelle
-- Instanz und weitere Instanzen mit eigener Liste.
local function InstanceEntries(current)
	local list, seen = { L.ALL_INSTANCES }, { [L.ALL_INSTANCES] = true }
	for _, r in ipairs(L.RAIDS) do
		list[#list + 1] = r.id
		seen[r.id] = true
	end
	local extra = {}
	if current and not seen[current] then
		seen[current] = true
		extra[#extra + 1] = current
	end
	for _, setting in pairs(PM.LIST_SETTING) do
		for id, items in pairs(PM.db.settings[setting]) do
			if not seen[id] and next(items) then
				seen[id] = true
				extra[#extra + 1] = id
			end
		end
	end
	table.sort(extra, function(a, b) return L.Lower(PM:InstanceName(a)) < L.Lower(PM:InstanceName(b)) end)
	for _, id in ipairs(extra) do list[#list + 1] = id end
	return list
end

-- Überschrift einer Liste; plain ohne Farbcodes (für die Rückfrage).
function UI:ListTitle(kind, id, plain)
	local name = plain and ("„" .. PM:InstanceName(id) .. "“") or ("|cffffffff" .. PM:InstanceName(id) .. "|r")
	if kind == "roll" then return format(T("Immer verwürfeln in %s"), name) end
	return format(T("Liste des Schatzmeisters für %s"), name)
end

local function CountItems(t)
	local n = 0
	for _ in pairs(t or {}) do n = n + 1 end
	return n
end

local function ListBox(page, name, x, width)
	local box = CreateFrame("Frame", nil, page, "BackdropTemplate")
	box:SetBackdrop(UI.BACKDROP)
	box:SetBackdropColor(0, 0, 0, 0.5)
	box:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
	box:SetPoint("TOPLEFT", x, LIST_TOP)
	box:SetSize(width, LIST_H)
	local scroll = CreateFrame("ScrollFrame", name, box, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", -28, 6)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(width - 40, 10)
	scroll:SetScrollChild(content)
	return content
end

local function CreateInstanceRow(page)
	local b = CreateFrame("Button", nil, page.instContent)
	b:SetSize(INST_W - 40, LIST_ROW)
	b.sel = b:CreateTexture(nil, "BACKGROUND")
	b.sel:SetAllPoints(b)
	b.sel:SetColorTexture(1, 0.82, 0, 0.2)
	b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	b.text = UI.Label(b, "GameFontHighlightSmall", INST_W - 44)
	b.text:SetPoint("LEFT", 2, 0)
	b.text:SetWordWrap(false)
	b:SetScript("OnClick", function(btn)
		page.selected = btn.instanceID
		page.refresh()
	end)
	return b
end

local function CreateItemRow(page)
	local width = CONTENT_W - INST_W - 6 - 44
	local row = UI.EnableLinks(CreateFrame("Frame", nil, page.itemContent))
	row:SetSize(width, 18)
	row.text = UI.Label(row, "GameFontHighlightSmall", width - 30)
	row.text:SetPoint("LEFT", 2, 0)
	row.text:SetWordWrap(false)
	row.remove = UI.Button(row, "x", 22, 16, true)
	row.remove:SetPoint("RIGHT", 0, 0)
	row.remove:SetScript("OnClick", function()
		if row.id then PM:RemoveListItem(page.kind, page.selected, row.id) end
	end)
	return row
end

function UI:BuildLootPage(page)
	page.state = Heading(page, "")
	page.state:SetPoint("TOPLEFT", 0, 0)

	local mlLabel = self.Label(page, "GameFontHighlight")
	mlLabel:SetText(T("Plündermeister:"))
	mlLabel:SetPoint("TOPLEFT", 0, -28)
	page.ml = self.Button(page, "", 170, 20, true)
	page.ml:SetPoint("LEFT", mlLabel, "LEFT", FIELD_X, 0)
	page.ml:SetScript("OnClick", function(btn)
		UI:ShowPicker(btn, "Plündermeister wählen", {
			current = L.NameKey(PM.db.settings.masterLooterName),
			onPick = function(name)
				PM.db.settings.masterLooterName = name
				UI:RefreshAll()
			end,
		})
	end)
	self.Tooltip(page.ml, "Plündermeister", "Wer Plündermeister werden soll. „niemand“ heißt: du selbst.")

	local thLabel = self.Label(page, "GameFontHighlight")
	thLabel:SetText(T("Plündergrenze:"))
	thLabel:SetPoint("TOPLEFT", 0, -58)
	local threshold = CreateFrame("DropdownButton", "PrioMeisterThresholdDropdown", page, "WowStyle1DropdownTemplate")
	threshold:SetWidth(170)
	threshold:SetPoint("LEFT", thLabel, "LEFT", FIELD_X, 0)
	threshold:SetupMenu(function(_, root)
		for q = 0, 4 do
			root:CreateRadio(PM:QualityLabel(q),
				function(value) return value == select(3, PM:CurrentLootMethod()) end,
				function(value) PM:ApplyLootSettings(value) end, q)
		end
	end)
	page.threshold = threshold
	local thHint = self.Label(page, "GameFontDisableSmall", CONTENT_W)
	thHint:SetPoint("TOPLEFT", 0, -84)
	thHint:SetText(T("Setzt bei Bedarf zuerst den Plündermeister und danach die Grenze. Grau und Weiß gehen nur hier, nicht über Blizzards Menü. Nur als Gruppen- bzw. Schlachtzugsleitung."))

	-- Rollen: Plünderhelfer mit Qualität, Schatzmeister mit Liste, Entzauberer
	page.helper = self:CreateRoleButton(page, "lootHelper", 200)
	page.helper:SetPoint("TOPLEFT", 0, -122)
	-- Qualitäten bis zum rechten Rand, „bekommt:“ davor
	page.qualityButtons = {}
	local prev
	for i, q in ipairs(HELPER_QUALITIES) do
		local b = self.Button(page, "", 78, 20, true)
		if i == 1 then
			b:SetPoint("LEFT", page.helper, "LEFT", CONTENT_W - #HELPER_QUALITIES * 80 + 2, 0)
		else
			b:SetPoint("LEFT", prev, "RIGHT", 2, 0)
		end
		b:SetScript("OnClick", function()
			local qualities = PM.db.settings.autoLootQualities
			qualities[q] = (not qualities[q]) or nil
			UI:RefreshAll()
		end)
		self.Tooltip(b, PM.QUALITY_TEXT[q], "Klick schaltet um. Ja: Items dieser Qualität gehen automatisch an den Plünderhelfer, wenn sie auf keiner Liste stehen und niemand Prio hat.")
		page.qualityButtons[q] = b
		prev = b
	end
	local qLabel = self.Label(page, "GameFontHighlightSmall")
	qLabel:SetText(T("bekommt:"))
	qLabel:SetPoint("RIGHT", page.qualityButtons[HELPER_QUALITIES[1]], "LEFT", -6, 0)
	local helperHint = self.Label(page, "GameFontDisableSmall", CONTENT_W - 210)
	helperHint:SetPoint("TOPLEFT", 210, -146)
	helperHint:SetText(T("alles in den Qualitäten mit „ja“, was auf keiner der Listen unten steht"))

	page.treasurer = self:CreateRoleButton(page, "treasurer", 200)
	page.treasurer:SetPoint("TOPLEFT", 0, -166)
	local tHint = self.Label(page, "GameFontHighlightSmall", CONTENT_W - 210)
	tHint:SetPoint("LEFT", page.treasurer, "RIGHT", 10, 0)
	tHint:SetText(T("bekommt nur die Items der Liste unten"))

	page.de = self:CreateRoleButton(page, "disenchanter", 200)
	page.de:SetPoint("TOPLEFT", 0, -192)
	-- Knopf „An Entzauberer“ an jedem Item im Panel ab dieser Qualität: wie die Plündergrenze oben,
	-- Beschriftung davor und die Qualitäten in ihren Farben, bündig mit dem rechten Rand
	local deQuality = CreateFrame("DropdownButton", "PrioMeisterDisenchantDropdown", page, "WowStyle1DropdownTemplate")
	deQuality:SetWidth(DE_DROPDOWN_W)
	deQuality:SetPoint("LEFT", page.de, "LEFT", CONTENT_W - DE_DROPDOWN_W, 0)
	deQuality:SetupMenu(function(_, root)
		local function isSelected(value) return value == (PM.db.settings.deButtonQuality or "nie") end
		local function pick(value)
			PM.db.settings.deButtonQuality = (value ~= "nie") and value or false
			UI:RefreshAll()
		end
		root:CreateRadio(T("nie"), isSelected, pick, "nie")
		for q = 2, 4 do root:CreateRadio(PM:QualityLabel(q), isSelected, pick, q) end
	end)
	self.Tooltip(deQuality, "Knopf „An Entzauberer“",
		"Ab welcher Qualität im Panel an jedem Item der Knopf „An Entzauberer“ steht, auch ohne Würfelrunde. Gilt für Rüstung und Waffen, solange kein anwesender Spieler Prio hat.")
	page.deQuality = deQuality
	local deLabel = self.Label(page, "GameFontHighlightSmall")
	deLabel:SetText(T("Knopf ab:"))
	deLabel:SetPoint("RIGHT", deQuality, "LEFT", -6, 0)
	page.deLabel = deLabel
	local deHint = self.Label(page, "GameFontHighlightSmall", CONTENT_W - 210 - DE_DROPDOWN_W - 80)
	deHint:SetPoint("LEFT", page.de, "RIGHT", 10, 0)
	deHint:SetText(T("bekommt, worauf niemand würfelt"))

	-- Listen je Instanz: links die Instanz, oben rechts die Art der Liste
	page.kind = "treasurer"
	page.listTitle = Heading(page, "")
	page.listTitle:SetPoint("TOPLEFT", 0, -226)
	page.listTitle:SetWidth(CONTENT_W - 222)
	page.listTitle:SetWordWrap(false)
	page.kindButtons = {}
	local kindPrev
	for _, k in ipairs({ { "treasurer", "Schatzmeister" }, { "roll", "Immer verwürfeln" } }) do
		local b = self.Button(page, k[2], 108, 20, true)
		if kindPrev then
			b:SetPoint("LEFT", kindPrev, "RIGHT", 4, 0)
		else
			b:SetPoint("TOPRIGHT", page, "TOPRIGHT", -112, -222)
		end
		b:SetScript("OnClick", function()
			page.kind = k[1]
			page.refresh()
		end)
		page.kindButtons[k[1]] = b
		kindPrev = b
	end
	self.Tooltip(page.kindButtons.treasurer, "Schatzmeister",
		"Diese Items bekommt der Schatzmeister automatisch, z. B. Skarabäen und Schlüssel in AQ.")
	self.Tooltip(page.kindButtons.roll, "Immer verwürfeln",
		"Diese Items gehen nie automatisch an Plünderhelfer oder Schatzmeister. Sie stehen immer im Panel und in der Beute-Ansage, auch unter der Plündergrenze. Mit Prio gehen sie an den Prio-Halter, sonst wird gewürfelt.")
	page.instContent = ListBox(page, "PrioMeisterInstanceScroll", 0, INST_W)
	page.instRows = {}
	page.itemContent = ListBox(page, "PrioMeisterLootListScroll", INST_W + 6, CONTENT_W - INST_W - 6)
	page.itemRows = {}
	page.itemEmpty = self.Label(page.itemContent, "GameFontDisableSmall", CONTENT_W - INST_W - 50)
	page.itemEmpty:SetPoint("TOPLEFT", 2, -2)
	page.itemEmpty:SetText(T("Noch leer. Items per Shift-Klick ins Feld unten verlinken, hineinziehen oder die Item-ID eintippen."))

	-- Zeile unter den Listen, bündig mit ihren Rändern: Feld über die ganze Breite, Hinzufügen, Liste leeren
	local rowY = LIST_TOP - LIST_H - 16 -- Mitte der Zeile
	page.clear = self.Button(page, "Liste leeren", 96, 20, true)
	page.clear:SetPoint("RIGHT", page, "TOPRIGHT", 0, rowY)
	local add = self.Button(page, "Hinzufügen", 96, 20, true)
	add:SetPoint("RIGHT", page.clear, "LEFT", -4, 0)
	local edit = CreateFrame("EditBox", "PrioMeisterLootListEdit", page, "InputBoxTemplate")
	edit:SetHeight(20)
	edit:SetPoint("LEFT", page, "TOPLEFT", 6, rowY) -- der Rahmen der Vorlage ragt links 5 px hinaus
	edit:SetPoint("RIGHT", add, "LEFT", -8, 0)
	edit:SetAutoFocus(false)
	-- Hinweis im leeren Feld, was hineingehört
	edit.hint = edit:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	edit.hint:SetPoint("LEFT", edit, "LEFT", 2, 0)
	edit.hint:SetPoint("RIGHT", edit, "RIGHT", -2, 0)
	edit.hint:SetJustifyH("LEFT")
	edit.hint:SetWordWrap(false)
	edit.hint:SetText(T("Item für die gewählte Instanz: Shift-Klick, hineinziehen oder Item-ID"))
	local function updateHint() edit.hint:SetShown(edit:GetText() == "" and not edit:HasFocus()) end
	edit:SetScript("OnTextChanged", updateHint)
	edit:SetScript("OnEditFocusGained", updateHint)
	edit:SetScript("OnEditFocusLost", updateHint)
	edit.updateHint = updateHint
	self.Tooltip(edit, "Item für die Liste", "Item per Shift-Klick ins Feld verlinken, hineinziehen oder die Item-ID eintippen, dann Enter oder „Hinzufügen“. Es kommt in die Liste der links gewählten Instanz.")
	local function addItem(id)
		PM:AddListItem(page.kind, page.selected or L.ALL_INSTANCES, id)
	end
	local function addFromEdit()
		local id = L.ItemID(edit:GetText())
		edit:SetText("")
		edit:ClearFocus()
		addItem(id)
	end
	local function addFromCursor()
		local kind, id = GetCursorInfo()
		if kind == "item" then
			ClearCursor()
			addItem(id)
		end
	end
	edit:SetScript("OnEnterPressed", addFromEdit)
	edit:SetScript("OnEscapePressed", function(e) e:ClearFocus() end)
	edit:SetScript("OnReceiveDrag", addFromCursor)
	edit:SetScript("OnMouseDown", addFromCursor)
	page.listEdit = edit
	self.listEdit = edit
	add:SetScript("OnClick", addFromEdit)
	self.Tooltip(add, "Item hinzufügen", "Item per Shift-Klick ins Feld verlinken, hineinziehen oder die Item-ID eintippen. Es kommt in die Liste der links gewählten Instanz.")
	page.add = add
	page.clear:SetScript("OnClick", function()
		local id = page.selected or L.ALL_INSTANCES
		if next(PM:ItemList(page.kind, id)) then
			StaticPopup_Show("PRIOMEISTER_CLEARLIST", UI:ListTitle(page.kind, id, true), nil, { kind = page.kind, id = id })
		end
	end)

	local note = self.Label(page, "GameFontDisableSmall", CONTENT_W)
	note:SetPoint("TOPLEFT", 0, LIST_TOP - LIST_H - 34)
	note:SetText(T("Es gilt jeweils „Alle Instanzen“ plus die Liste der Instanz, in der du gerade bist. Items mit Prio werden nie automatisch verteilt, Shift beim Öffnen der Beute verteilt nichts automatisch. Items unter der Plündergrenze plünderst du selbst und handelst sie an den Gewinner, das Addon trägt den Handel ein."))

	page.refresh = function()
		local s = PM.db.settings
		local method, mlName, threshold = PM:CurrentLootMethod()
		local current, currentName = PM:CurrentInstance()
		local where = current and (" · " .. (currentName or PM:InstanceName(current))) or ""
		if not IsInGroup() then
			page.state:SetText(T("Aktuell: keine Gruppe") .. where)
		else
			page.state:SetText(format(T("Aktuell: %s%s, Grenze: %s%s"), PM.METHOD_TEXT[method] or "?",
				mlName and (" (" .. mlName .. ")") or "", threshold and PM:QualityLabel(threshold) or "?", where))
		end
		page.ml:SetText(s.masterLooterName or format(T("ich (%s)"), UnitName("player") or "?"))
		if page.threshold.GenerateMenu then page.threshold:GenerateMenu() end
		if page.deQuality.GenerateMenu then page.deQuality:GenerateMenu() end
		for q, b in pairs(page.qualityButtons) do
			if s.autoLootQualities[q] then
				b:SetText(format(T("%s: ja"), PM:QualityLabel(q)))
				b:LockHighlight()
			else
				b:SetText(format(T("|cff808080%s: nein|r"), PM.QUALITY_TEXT[q]))
				b:UnlockHighlight()
			end
		end
		page.helper:SetText(UI:RoleText("lootHelper"))
		page.treasurer:SetText(UI:RoleText("treasurer"))
		page.de:SetText(UI:RoleText("disenchanter"))

		-- In eine andere Instanz gewechselt: deren Liste zeigen.
		if current ~= page.lastInstance then
			page.lastInstance = current
			if current then page.selected = current end
		end
		page.selected = page.selected or L.ALL_INSTANCES

		local entries = InstanceEntries(current)
		for i, id in ipairs(entries) do
			local row = page.instRows[i]
			if not row then
				row = CreateInstanceRow(page)
				page.instRows[i] = row
			end
			row.instanceID = id
			local label = PM:InstanceName(id)
			local n = CountItems(s[PM.LIST_SETTING[page.kind]][id])
			if n > 0 then label = label .. format(" |cff808080(%d)|r", n) end
			if id == current then label = "|cff40ff40>|r " .. label end
			row.text:SetText(label)
			row.sel:SetShown(id == page.selected)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", page.instContent, "TOPLEFT", 0, -(i - 1) * LIST_ROW)
			row:Show()
		end
		for i = #entries + 1, #page.instRows do page.instRows[i]:Hide() end
		page.instContent:SetHeight(math.max(10, #entries * LIST_ROW))

		page.listTitle:SetText(UI:ListTitle(page.kind, page.selected))
		for k, b in pairs(page.kindButtons) do
			if k == page.kind then b:LockHighlight() else b:UnlockHighlight() end
		end
		local ids = {}
		for id in pairs(PM:ItemList(page.kind, page.selected)) do ids[#ids + 1] = id end
		table.sort(ids)
		for i, id in ipairs(ids) do
			local row = page.itemRows[i]
			if not row then
				row = CreateItemRow(page)
				page.itemRows[i] = row
			end
			row.id = id
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", page.itemContent, "TOPLEFT", 0, -(i - 1) * 18)
			row.text:SetText(format("%s |cff808080(%d)|r", PM:ItemLabel(id), id))
			row:Show()
		end
		for i = #ids + 1, #page.itemRows do page.itemRows[i]:Hide() end
		page.itemEmpty:SetShown(#ids == 0)
		page.itemContent:SetHeight(math.max(10, #ids * 18))
	end
end

-- Shift-Klick auf ein Item fügt den Link in das Eingabefeld der Liste ein.
local function hookLinkInsert()
	local function insert(text)
		local edit = UI.listEdit
		if edit and edit:HasFocus() and type(text) == "string" then edit:Insert(text) end
	end
	if ChatFrameUtil and ChatFrameUtil.InsertLink then
		hooksecurefunc(ChatFrameUtil, "InsertLink", insert)
	elseif ChatEdit_InsertLink then
		hooksecurefunc("ChatEdit_InsertLink", insert)
	end
end
hookLinkInsert()

-------------------------------------------------------------------------------
-- Reiter "Optionen"
-------------------------------------------------------------------------------

-- Häkchen nach Themen: links alles, was im Chat erscheint, rechts Würfeln und
-- Prio sowie die Anzeige. tip: Erklärung im Tooltip, delay: Schieberegler darunter.
local OPTION_TOP = { key = "enabled", label = "Addon aktiv",
	tip = "Aus: Das Addon sagt nichts an, verteilt nichts automatisch und trägt nichts ein." }
local OPTION_COLUMNS = {
	{
		{ title = "Im Chat posten" },
		{ key = "announceLoot", label = "Beute beim Öffnen ansagen, mit Prios", delay = true,
			tip = "Beim Öffnen der Beute steht im Raidchat, was drin liegt und wer Prio darauf hat." },
		{ key = "awardsToRaid", label = "Vergaben für das Protokoll",
			tip = "Jede Vergabe geht in den Raidchat, damit ein anderer Spieler mitschreiben kann. Aus: nur im eigenen Chatfenster." },
		{ key = "treasurerChat", label = "Vergaben an den Schatzmeister",
			tip = "Was der Schatzmeister bekommt, geht gesammelt in den Raidchat. Aus: nur im eigenen Chatfenster." },
		{ key = "helperLowChat", label = "Grau und Weiß an den Plünderhelfer",
			tip = "Graue und weiße Items, die der Plünderhelfer bekommt, stehen als Anzahl in seiner Sammelmeldung." },
		{ key = "tierHints", label = "Hinweise zu Würfelstufen (99, 98 …)",
			tip = "Der Würfelaufruf nennt, wer mit /roll 99 oder weniger würfelt. Nach einem freien Gewinn steht in der Vergabe die neue Stufe." },
		{ key = "reportWrongRolls", label = "Hinweise bei falschem Wurf",
			tip = "Wer mit falscher Stufe würfelt oder auf ein Item, das er nicht tragen kann, wird im Raidchat darauf hingewiesen." },
		{ key = "tierChangesToRaid", label = "Würfelstufe von Hand geändert",
			tip = "Plus und Minus im Reiter Raid oder /pm stufen: die Änderung und ihr Zurücknehmen gehen in den Raidchat. In der Vergabeliste stehen sie immer." },
		{ key = "raidWarning", label = "Würfelaufrufe als Schlachtzugswarnung",
			tip = "Die erste Zeile des Würfelaufrufs kommt als Schlachtzugswarnung, wenn du Leiter oder Assistent bist." },
	},
	{
		{ title = "Würfeln und Prio" },
		{ key = "secondaryRolls", label = "50er-Würfe (Zweitchar, Zweitskillung)",
			tip = "/roll 50 läuft parallel, liegt hinter allen normalen Würfen und ändert keine Stufe." },
		{ key = "usableRolls", label = "Nur Spieler, die das Item tragen können",
			tip = "Kann jemand ein Item mit seiner Klasse nicht tragen, zählt sein Wurf nicht und eine Prio darauf gilt nicht, dann ist die nächste Prio dran. Das betrifft Rüstung, etwa einen Magier auf Platte, Waffen, die die Klasse nicht führen kann, und Items, die laut Tooltip nur für andere Klassen sind. 50er-Würfe ohne Prio zählen trotzdem, sie können für einen Zweitchar sein." },
		{ key = "recipeRolls", label = "Rezept-Würfe ohne Würfelstufen",
			tip = "Rezepte werden mit /roll 100 ohne Stufen verwürfelt, nur Spieler mit passendem Beruf sollen würfeln." },
		{ key = "recipePrio", label = "Rezepte auf Prio erlaubt",
			tip = "Aus: Prios auf Rezepte zählen nicht. Das Addon meldet sie beim Import und im Reiter Raid." },
		{ key = "mountPrio", label = "Reittiere auf Prio erlaubt",
			tip = "Aus: Prios auf Reittiere zählen nicht. Das Addon meldet sie beim Import und im Reiter Raid." },
		{ key = "prio0two", label = "Prio 0 schon bei Prio 1 und 2",
			tip = "Prio 0 heißt: dasselbe Item auf mehreren Prios. Standard ist Prio 1, 2 und 3, mit Häkchen reichen Prio 1 und 2." },
		{ key = "confirmEpicWinner", label = "Epics an den Gewinner nur mit Rückfrage",
			tip = "Die Knöpfe „An Name“ im Panel, für den Gewinner der Würfelrunde und für den einzigen Prio-Halter, fragen bei epischen Items vorher nach, wie Blizzards Plündermeister-Liste." },
		{ title = "Anzeige" },
		{ key = "sortMasterLoot", label = "Plündermeister-Liste sortieren",
			tip = "Plünderhelfer, Schatzmeister, Entzauberer und angeheftete Spieler stehen oben, danach alle anderen von A bis Z." },
		{ key = "alwaysShow", label = "Panel auch ohne Plündermeister-Rolle",
			tip = "Zeigt das Panel beim Plündern auch, wenn jemand anderes Plündermeister ist." },
		{ key = "showTableAfterImport", label = "Prio-Tabelle nach dem Import zeigen",
			tip = "Die Tabelle bleibt 20 Sekunden offen, mit der Maus darüber länger." },
		{ key = "showMinimap", label = "Minimap-Knopf",
			tip = "Linksklick öffnet das Hauptfenster, Rechtsklick blendet das Panel ein und aus." },
	},
}
local OPTION_COL_W = math.floor((CONTENT_W - 12) / 2)

local function GetOption(key)
	if key == "prio0two" then return PM.db.settings.prio0Mode == 2 end
	return PM.db.settings[key] and true or false
end

local function SetOption(key, value)
	if key == "prio0two" then
		PM:SetOption("prio0Mode", value and 2 or 3)
	else
		PM:SetOption(key, value)
	end
end

function UI:BuildOptionsPage(page)
	page.checks, page.titles = {}, {}
	local function addCheck(opt, x, y, group)
		local i = #page.checks + 1
		local cb = CreateFrame("CheckButton", "PrioMeisterOption" .. i, page, "UICheckButtonTemplate")
		cb:SetSize(24, 24)
		cb:SetPoint("TOPLEFT", x, y)
		local text = cb.Text or cb.text or _G["PrioMeisterOption" .. i .. "Text"]
		if text then
			text:SetFontObject(GameFontHighlight)
			text:SetText(T(opt.label))
			text:SetWidth(OPTION_COL_W - 30)
			text:SetJustifyH("LEFT")
			text:SetWordWrap(false)
		end
		cb.optKey, cb.group = opt.key, group
		cb:SetScript("OnClick", function(self) SetOption(opt.key, self:GetChecked() and true or false) end)
		UI.Tooltip(cb, opt.label, opt.tip)
		page.checks[i] = cb
	end

	-- Schieberegler: dieselbe Beute frühestens nach so vielen Sekunden erneut ansagen
	local function addDelay(x, y)
		local label = UI.Label(page, "GameFontHighlightSmall")
		label:SetPoint("TOPLEFT", x, y)
		local slider = CreateFrame("Slider", "PrioMeisterAnnounceDelay", page, "UISliderTemplateWithLabels")
		slider:SetSize(180, 17)
		slider:SetPoint("TOPLEFT", x + 2, y - 14)
		slider:SetMinMaxValues(0, 600)
		slider:SetValueStep(5)
		slider:SetObeyStepOnDrag(true)
		if slider.Low then slider.Low:SetText("0 s") end
		if slider.High then slider.High:SetText("600 s") end
		if slider.Text then slider.Text:SetText("") end
		local function delayText(v)
			label:SetText(format(T("Dieselbe Beute erneut frühestens nach |cffffd100%d s|r"), v))
		end
		slider:SetScript("OnValueChanged", function(self, value)
			value = math.floor(value + 0.5)
			PM.db.settings.announceDelay = value
			delayText(value)
		end)
		page.delay = slider
		page.delayText = delayText
	end

	addCheck(OPTION_TOP, 0, 4, nil)
	page.changelog = self.Button(page, "Changelog", 100, 22)
	page.changelog:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 4)
	-- Sprache (seit 1.21): automatisch nach der Spielsprache, Deutsch oder Englisch; gilt nach /reload
	local language = CreateFrame("DropdownButton", "PrioMeisterLanguageDropdown", page, "WowStyle1DropdownTemplate")
	language:SetWidth(170)
	language:SetPoint("RIGHT", page.changelog, "LEFT", -6, 0)
	language:SetupMenu(function(_, root)
		local function isSelected(value) return (PM.db.settings.language or "auto") == value end
		local function select(value)
			PM.db.settings.language = value
			if ns.ResolveLanguage and ns.ResolveLanguage(value, GetLocale and GetLocale() or "deDE") ~= ns.lang then
				StaticPopup_Show("PRIOMEISTER_RELOAD")
			end
		end
		root:CreateRadio(T("Sprache: automatisch"), isSelected, select, "auto")
		root:CreateRadio("Sprache: Deutsch", isSelected, select, "de")
		root:CreateRadio("Language: English", isSelected, select, "en")
	end)
	self.Tooltip(language, "Sprache", "Automatisch nach der Spielsprache: deutscher Client Deutsch, sonst Englisch. Gilt nach dem Neuladen der Oberfläche (/reload).")
	page.language = language
	page.changelog:SetScript("OnClick", function() UI:ShowChangelog() end)
	self.Tooltip(page.changelog, "Changelog", "Alle Versionen von PrioMeister und was sich jeweils geändert hat.")
	local bottom = 0
	for c, column in ipairs(OPTION_COLUMNS) do
		local x, y, group = (c - 1) * (OPTION_COL_W + 12), -34, nil
		for _, opt in ipairs(column) do
			if opt.title then
				if group then y = y - 10 end
				group = opt.title
				local h = Heading(page, opt.title)
				h:SetPoint("TOPLEFT", x, y)
				page.titles[#page.titles + 1] = h
				y = y - 20
			else
				addCheck(opt, x, y, group)
				y = y - 23
				if opt.delay then
					addDelay(x + 30, y + 2)
					y = y - 44
				end
			end
		end
		bottom = math.min(bottom, y)
	end

	local y = bottom - 12
	local pinLabel = Heading(page, "Angeheftete Spieler (stehen in der Plündermeister-Liste oben):")
	pinLabel:SetPoint("TOPLEFT", 0, y)
	local pick = self.Button(page, "Auswählen …", 110, 22)
	pick:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, y - 20)
	local pins = CreateFrame("EditBox", "PrioMeisterPinsEdit", page, "InputBoxTemplate")
	pins:SetHeight(22)
	pins:SetPoint("LEFT", page, "TOPLEFT", 6, y - 31)
	pins:SetPoint("RIGHT", pick, "LEFT", -10, 0)
	pins:SetAutoFocus(false)
	local function savePins(self)
		PM:SetPinsFromText(self:GetText())
		self:SetText(PM:PinsText())
	end
	pins:SetScript("OnEnterPressed", function(self)
		savePins(self)
		self:ClearFocus()
	end)
	pins:SetScript("OnEditFocusLost", savePins)
	pins:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	page.pins = pins
	pick:SetScript("OnClick", function(btn)
		UI:ShowPicker(btn, "Spieler anheften", {
			multi = true,
			isSelected = function(name) return PM:IsPinned(name) end,
			onToggle = function(name) PM:TogglePin(name) end,
		})
	end)

	page.refresh = function()
		if page.language.GenerateMenu then page.language:GenerateMenu() end
		for _, cb in ipairs(page.checks) do cb:SetChecked(GetOption(cb.optKey)) end
		local delay = PM.db.settings.announceDelay or 90
		page.delay:SetValue(delay)
		page.delayText(delay)
		if not page.pins:HasFocus() then page.pins:SetText(PM:PinsText()) end
	end
end

-------------------------------------------------------------------------------
-- Changelog
-------------------------------------------------------------------------------

local CHANGELOG = {
	{ "1.24.0", "22.10.2026", {
		"Wartelisten von priomeister.de: Für einzelne Items wie die Reittiere aus Zul'Gurub oder die Bindungen des Windsuchers aus dem Geschmolzenen Kern führt die Raidleitung geordnete Wartelisten. Sie kommen mit der Prioliste ins Addon. Der erste Anwesende der Liste ist dran und schlägt jede Prio, auch Prio 0. Ist niemand von der Liste da, gelten die üblichen Regeln.",
		"Die Ansage nennt den Namen, etwa „[Item] – Warteliste: Mike“. Das Panel zeigt die ganze Reihenfolge, „An Mike“ gibt das Item direkt. Wer mit /roll 1 verzichtet, macht Platz für den Nächsten. Wer das Item bekommt, fällt für den Rest des Raids von der Liste. Bei Sets mit „Set vervollständigen“ rückt nach vorn, wer im Raid schon ein anderes Teil bekommen hat.",
		"Im Export stehen diese Vergaben mit der Art „Warteliste“. /pm stand nennt die Wartelisten. Gilt eine Warteliste auf der Seite als Prio 0, stehen ihre Spieler nicht unter „Im Raid ohne Prio“.",
	} },
	{ "1.23.0", "21.10.2026", {
		"Namen ohne Akzente: Steht auf priomeister.de „Leryssia“ und heißt der Charakter im Spiel „Leryssiá“, gilt der Eintrag auf der Prioliste trotzdem. Das Addon meldet die Zuordnung einmal im Chat. Das gilt auch für den Priocheck und für Namen in Befehlen wie /pm vergabe oder /pm stufen.",
		"Passen zwei Spieler im Raid zum selben Namen ohne Akzente, zählt der exakte Name. Ist keiner exakt, ordnet das Addon niemanden zu. Vergaben, Würfelstufen und Würfe bleiben, wie sie gespeichert sind.",
	} },
	{ "1.22.1", "20.10.2026", {
		"Beute aus einem Behälter in der eigenen Tasche, etwa dem Immergrünkrautgehäuse, sagt das Addon nicht mehr an und verteilt sie nicht an Plünderhelfer oder Schatzmeister. Dasselbe gilt beim Angeln und für Kräuter und Erzadern. Diese Beute läuft nicht über den Plündermeister, das Zuweisen schlug fehl.",
	} },
	{ "1.22.0", "20.10.2026", {
		"„An Entzauberer“ steht jetzt auch ohne Würfelrunde an jedem Item im Panel: bei Rüstung und Waffen, solange kein anwesender Spieler Prio hat. Ab welcher Qualität, stellst du im Reiter Plündern neben dem Entzauberer ein, voreingestellt ab Grün. Bei epischen Items und wenn schon jemand gewürfelt hat, fragt das Addon vorher nach.",
	} },
	{ "1.21.1", "20.10.2026", {
		"PrioMeister hat ein Logo: im Fensterkopf, auf dem Minimap-Knopf und als Symbol in der Addon-Liste. Wer im laufenden Spiel aktualisiert, muss WoW einmal neu starten, damit die Bilder erscheinen.",
	} },
	{ "1.21.0", "20.10.2026", {
		"PrioMeister gibt es jetzt auch auf Englisch: Oberfläche, Chat-Nachrichten, Hilfe und Changelog. Die Sprache folgt der Spielsprache, unter Optionen lässt sie sich fest auf Deutsch oder Englisch stellen. Ein Wechsel gilt nach dem Neuladen der Oberfläche.",
		"Alle Befehle gibt es auch auf Englisch, etwa /pm remind, /pm status, /pm tiers, /pm award und /pm share guild. Die deutschen Befehle gehen weiter.",
		"Der Export für priomeister.de bleibt in beiden Sprachen gleich, mit deutschen Spalten und Werten.",
	} },
	{ "1.20.2", "19.10.2026", {
		"Den Priocheck gibt es auf priomeister.de jetzt für alle auf der Spielerseite des Prio-Runs unter „Alle Prios“. Die Hinweise im Addon sagen das.",
	} },
	{ "1.20.1", "19.10.2026", {
		"Die Hinweise nennen die Knöpfe auf priomeister.de: „Kopieren für PrioMeister“ für die Prioliste, „Priocheck kopieren“ für den Priocheck.",
	} },
	{ "1.20.0", "19.10.2026", {
		"Priocheck: priomeister.de bietet eine Kurzform des Prio-Runs an, wer welche Prios gesetzt hat, ohne Items. Unter „Importieren …“ eingefügt und mit „Prüfen“ verglichen, zeigt das Addon, wer im Raid noch keine Prios hat und bei wem welche fehlen. Die Eintragung muss dafür nicht geschlossen werden, die Prioliste bleibt, wie sie ist.",
		"Im Reiter Raid steht das unter „Im Raid ohne Prio“, die Maus darüber zeigt die Details. „Im Raid erinnern“ und /pm erinnern nennen die Spieler ohne Prios mit Link und PIN. /pm check zeigt das Ergebnis im Chat.",
		"Der Priocheck gilt, bis eine neuere Prioliste importiert wird.",
	} },
	{ "1.19.6", "18.10.2026", {
		"Der Knopf „?“ ist jetzt quadratisch wie das Kreuz zum Schließen und sitzt genau auf dessen Höhe.",
	} },
	{ "1.19.5", "18.10.2026", {
		"Die Trennlinie unter den Reitern ist blasser.",
	} },
	{ "1.19.4", "18.10.2026", {
		"Mehr Abstand über und unter der Trennlinie, das Hauptfenster ist dafür etwas höher.",
		"Im Reiter Plündern reicht das Feld unter den Listen jetzt vom linken Rand bis „Hinzufügen“, der Hinweis darin passt hinein.",
	} },
	{ "1.19.3", "18.10.2026", {
		"Eine Trennlinie trennt die Reiter Raid, Vergaben und Plündern vom Inhalt darunter.",
	} },
	{ "1.19.2", "18.10.2026", {
		"Die Optionen öffnet jetzt ein roter Knopf mit Fragezeichen oben rechts, wie die anderen Knöpfe, statt des Zahnrads.",
	} },
	{ "1.19.1", "18.10.2026", {
		"Aufgeräumt: Die Optionen öffnet jetzt das Zahnrad oben rechts statt eines eigenen Reiters, ein zweiter Klick führt zurück. Der Knopf „Changelog“ steht jetzt in den Optionen.",
		"Im Reiter Raid heißt der Knopf für die Prio-Tabelle jetzt „Anzeigen“. „Neuer Raid“ erklärt im Tooltip, was er tut, die Rückfrage sagt jetzt auch, dass die Prioliste leer beginnt.",
		"Im Reiter Plündern zeigt das leere Feld unter der Item-Liste, was hineingehört. Feld und Knöpfe schließen bündig mit der Liste ab, Plündermeister und Plündergrenze stehen genau untereinander.",
		"Knopfreihen schließen jetzt bündig mit dem rechten Rand ab: Rollen im Reiter Raid, Qualitäten im Reiter Plündern, die untere Reihe unter Vergaben und die angehefteten Spieler in den Optionen.",
	} },
	{ "1.19.0", "18.10.2026", {
		"Ausnahmen von priomeister.de: Darf ein Rezept oder Reittier laut Prio-Run trotz „werden gewürfelt“ auf Prio, zählen Prios darauf. Die Liste bringt diese Items in ihrer letzten Zeile mit, beim Import stehen sie in der Meldung zu den Regeln und unter /pm stand.",
	} },
	{ "1.18.0", "18.10.2026", {
		"Weitergaben: Hat ein Spieler ein Item im Spiel an einen anderen gegeben, trägst du das per Rechtsklick auf die Vergabe im Reiter „Vergaben“ ein. Du wählst den neuen Besitzer, eine Rückfrage nennt die Folgen. Das geht auch in früheren Raids, ohne sie fortzusetzen, dann ohne Meldung im Raidchat.",
		"Eine Weitergabe zählt wie eine neue Vergabe. Hat der Empfänger Prio auf das Item, ist sie erfüllt, sonst sinkt seine Würfelstufe wie nach einem freien Wurf. Die Vergabe des Gebers zählt nicht mehr: Seine Prio ist wieder offen, ein freier Wurfsieg gibt ihm die Stufe zurück. Items aus 50er-Würfen, Rezept-Würfen und Würfen ohne Stufen ändern keine Stufe.",
		"Auch Items von Entzauberer, Plünderhelfer und Schatzmeister lassen sich so an einen Spieler weitergeben.",
		"„Letzte zurücknehmen“ hebt eine gerade eingetragene Weitergabe auf, eine ältere nimmst du per Rechtsklick auf die Weitergabe zurück.",
		"Der Export bringt Weitergaben mit. Der Geber steht mit dem Status „weitergegeben“ darin, der Empfänger mit der Art „Weitergabe“. priomeister.de übernimmt beides beim Einfügen.",
	} },
	{ "1.17.1", "17.10.2026", {
		"Wurf-Protokoll: Zieht ein Spieler seinen Wurf mit /roll 1 zurück, steht der Wurf im Protokoll und im Export jetzt als „zurückgezogen“ statt „zählt“. Nimmst du den Verzicht mit „Letzte zurücknehmen“ zurück, zählt er dort wieder.",
		"Schon gespeicherte Protokolle bringt das Addon beim ersten Start auf denselben Stand.",
		"Ein fortgesetzter Raid nummeriert seine Würfelrunden nach der letzten Runde im Protokoll weiter. So bekommt keine neue Runde die Nummer einer alten.",
	} },
	{ "1.17.0", "17.10.2026", {
		"Wurf-Protokoll: Das Addon merkt sich jeden Wurf in einer Würfelrunde, auch ungültige, mit Item, Runde, Rundenart, Status und Grund. Es bleibt beim Archivieren erhalten, für die letzten zehn Raids im Archiv.",
		"Der Export (CSV) enthält jetzt das komplette Protokoll: alle Vergaben, auch an Schatzmeister, Plünderhelfer und Entzauberer, und alle Würfe als Art „Wurf“. Neue Spalten: Runde, Rundenart, Status, Grund, Instanz, Raid und Zeitstempel. Die ersten zehn Spalten sind wie bisher.",
		"Für den laufenden Raid stehen die Würfe der zuletzt gespeicherten 25 Runden schon im Protokoll, frühere Würfe kennt das Addon nicht mehr.",
	} },
	{ "1.16.1", "17.10.2026", {
		"Auch Prios zählen nur, wenn der Spieler das Item tragen kann. Hat etwa ein Magier Prio auf Platte, ist die nächste Prio dran, im Panel steht er als „nicht tragbar“. Das gilt auch für „An Name“ und die Beute-Ansage.",
		"In Prio-Runden zählen Würfe auf untragbare Items ebenfalls nicht. Das Häkchen dazu heißt jetzt „Nur Spieler, die das Item tragen können“.",
	} },
	{ "1.16.0", "16.10.2026", {
		"Würfe auf Items, die der Spieler nicht tragen kann, zählen nicht: Rüstung, die seine Klasse nicht tragen kann, etwa ein Magier auf Platte, Waffen, die sie nicht führen kann, und Items, die laut Tooltip nur für andere Klassen sind. Im Panel steht der Grund, im Raidchat ein Hinweis wie bei falscher Stufe.",
		"50er-Würfe zählen weiter, sie können für einen Zweitchar einer anderen Klasse sein. Prio-Runden prüft das Addon nicht. Abschaltbar unter Optionen mit „Würfe auf untragbare Items ignorieren“.",
	} },
	{ "1.15.0", "16.10.2026", {
		"Hat nur ein anwesender Spieler Prio auf ein Item, steht in seiner Zeile im Panel der Knopf „An Name“: Er gibt ihm das Item direkt. Bei epischen Items fragt das Addon vorher nach, wie bei „An Name (Wurf)“.",
		"Verzicht mit /roll 1: Wer Prio hat und das Item nicht will, würfelt /roll 1. Das gilt nur für dieses Exemplar, die Prio bleibt für ein späteres. Im Raidchat steht, wer verzichtet und wer jetzt Prio hat. Das Panel zeigt ihn als „verzichtet“, danach ist die nächste Prio dran oder es gibt einen Wurf ohne Prio.",
		"Der Verzicht geht auch direkt nach der Beute-Ansage, ohne Würfelrunde. Hat jemand auf mehrere Items der Beute Prio, gilt /roll 1 dem Item, das gerade angesagt oder verwürfelt wird.",
		"In einer Würfelrunde ohne Prio zieht /roll 1 den eigenen Wurf zurück. Ein Wurf von 1 (1-1) zählt nie als normaler Wurf.",
		"Verzichte stehen in der Vergabeliste, im Export und beim Teilen, zählen aber nicht als Vergabe. „Letzte zurücknehmen“ hebt einen versehentlichen Verzicht wieder auf.",
		"Würfelstufen im Reiter Raid: Dort stehen jetzt alle, die in diesem Raid gewürfelt haben, auch mit 100 und auch, wenn ihr Wurf erst nach dem Ende der Runde kam. Plus senkt die Stufe, etwa nach einer Vergabe aus Kulanz. Die Liste hat zwei Spalten und lässt sich scrollen.",
	} },
	{ "1.14.3", "15.10.2026", {
		"Die Rückfrage vor „Raid fortsetzen“ sagt, ob die Prioliste mitkommt: mit wie vielen Spielern und von wann. Bei einem alten Raid ohne gespeicherte Liste steht das rot da.",
	} },
	{ "1.14.2", "15.10.2026", {
		"Ein Raid aus der Zeit vor 1.14 hat keine Prioliste gespeichert. Beim Fortsetzen startet er jetzt ohne Liste, mit deutlichem Hinweis im Chat, statt die gerade geladene Liste zu übernehmen. Eine fremde Liste fällt nicht auf, eine fehlende schon.",
	} },
	{ "1.14.1", "15.10.2026", {
		"Ein fortgesetzter Raid bekommt immer seine eigene Prioliste. Nur wenn er keine gespeichert hat, bleibt die aktuelle. Vorher gewann die neuere Liste, das konnte eine Testliste sein.",
	} },
	{ "1.14.0", "15.10.2026", {
		"Frühere Raids lassen sich fortsetzen, etwa nach einem versehentlichen „Neuer Raid“ oder am zweiten Abend: im Reiter „Vergaben“ den Raid wählen und „Raid fortsetzen“ klicken, oder /pm fortsetzen. Vergaben und Würfelstufen gelten weiter, der laufende Raid kommt ins Archiv.",
		"Das Archiv speichert jetzt auch Prioliste und Korrekturen der Würfelstufe. Bei älteren Raids gilt beim Fortsetzen die aktuelle Prioliste, die Korrekturen holt das Addon aus dem Protokoll.",
	} },
	{ "1.13.0", "15.10.2026", {
		"Die Prios kommen jetzt von priomeister.de, der Seite der Gilde passend zum Addon. Import-Hinweis, Tooltips und /pm-Hilfe nennen priomeister.de statt sahne-team.de. Listen von sahne-team.de lassen sich weiter importieren.",
		"Die letzte Zeile der Liste von priomeister.de bringt die Regeln des Prio-Runs mit: Ob Rezepte und Reittiere auf Prio dürfen oder gewürfelt werden, übernimmt das Addon beim Import in die Optionen.",
		"Neu: /pm stand und der Tooltip über „Prioliste“ im Reiter Raid zeigen Spieler, Prios, die letzte Änderung auf der Seite und den Link zum Prio-Run. Im Reiter steht der Stand auch direkt hinter der Spielerzahl.",
		"„Im Raid erinnern“ nennt den Link zum Prio-Run samt PIN, zum Beispiel priomeister.de/r/746312.",
	} },
	{ "1.12.0", "15.10.2026", {
		"Optionen neu geordnet, in zwei Spalten: links alles, was im Chat erscheint, rechts „Würfeln und Prio“ und „Anzeige“. Die Häkchen haben kürzere Namen und erklären sich im Tooltip.",
		"Der Schieberegler für die erneute Beute-Ansage steht direkt unter „Beute beim Öffnen ansagen“.",
		"Das Hauptfenster hat wieder seine alte Höhe.",
	} },
	{ "1.11.2", "15.10.2026", {
		"Items sind überall klickbar, wo sie farbig stehen: bei Rezepten und Reittieren auf Prio im Raid-Reiter, in den Listen von Schatzmeister und „Immer verwürfeln“ und in der Überschrift der Würfe im Panel.",
	} },
	{ "1.11.1", "15.10.2026", {
		"Neues Häkchen unter Optionen: „Vor der Vergabe an den Gewinner bei epischen Items nachfragen“, Standard an.",
		"Das Hauptfenster ist etwas höher, damit alle Optionen hineinpassen.",
	} },
	{ "1.11.0", "15.10.2026", {
		"Neuer Knopf im Panel „An Name (Wurf)“: gibt das Item dem Gewinner der Würfelrunde, bei mehreren Exemplaren dem nächsten. Bei epischen Items fragt das Addon vorher nach, wie Blizzards Plündermeister-Liste.",
		"„An Entzauberer“ bleibt auch nach „Beenden“ stehen. „Beenden“ erklärt im Tooltip, was passiert.",
		"Die Knöpfe unter den Würfen stehen in zwei Reihen: oben, wer das Item bekommt, unten „Ergebnis posten“ und „Beenden“.",
		"Items in der Vergabenliste sind klickbar wie im Chat: Maus darüber zeigt das Item, Klick öffnet es, Shift-Klick verlinkt es.",
		"Die Raid-Auswahl unter „Vergaben“ nennt die Instanz. Das Addon merkt sie sich ab jetzt bei jeder Vergabe, für den laufenden Raid liest es sie aus den Würfelrunden.",
	} },
	{ "1.10.2", "14.10.2026", {
		"Eine Würfelrunde verschwindet aus dem Panel, sobald ihr Item vergeben ist. Beim Plündern der nächsten Leiche stehen keine alten Würfe mehr unten im Panel.",
		"Eine beendete Runde ohne Vergabe bleibt nur stehen, solange ihr Item noch in der offenen Beute liegt.",
	} },
	{ "1.10.1", "14.10.2026", {
		"Im Panel bleiben keine Reste schon vergebener Items mehr stehen. WoW liefert für einen vergebenen Platz manchmal noch einen leeren Link, daraus wurde die Zeile „Item 60, Daten werden geladen …“.",
	} },
	{ "1.10.0", "14.10.2026", {
		"„An Entzauberer“ fragt nach, wenn in der Würfelrunde schon jemand gewürfelt hat oder es eine Prio-Runde ist. Die Rückfrage nennt die Würfe.",
		"„Zufällig vergeben“ fragt auch nach, wenn für das Item schon gewürfelt wurde, nicht nur bei Prio.",
		"Neues Häkchen „Vergaben an den Schatzmeister im Raidchat melden“, Standard aus. Im eigenen Chatfenster stehen diese Vergaben weiterhin.",
		"Das Hauptfenster ist etwas höher, damit alle Optionen hineinpassen.",
	} },
	{ "1.9.4", "14.10.2026", {
		"Die neun Schmuckstücke der Hakkari stehen auf der Zul'Gurub-Liste des Schatzmeisters.",
	} },
	{ "1.9.3", "14.10.2026", {
		"Items, deren Daten WoW beim Öffnen der Beute noch nicht geladen hat, stehen nicht mehr als leere Zeile „[]“ im Panel. Sobald die Daten da sind, erscheinen sie richtig, in der Beute-Ansage und beim Plünderhelfer.",
	} },
	{ "1.9.2", "14.10.2026", {
		"Das Hauptfenster ist wieder leicht durchscheinend, alle anderen Fenster bleiben deckend.",
	} },
	{ "1.9.1", "14.10.2026", {
		"Alle Fenster haben einen deckenden Hintergrund und sind besser lesbar.",
	} },
	{ "1.9.0", "14.10.2026", {
		"Änderungen der Würfelstufe von Hand gehen in den Raidchat, auch wenn du eine zurücknimmst. Abschaltbar unter Optionen.",
		"Knopf „Changelog“ mit allen Versionen.",
	} },
	{ "1.8.0", "13.10.2026", {
		"Änderungen der Würfelstufe von Hand stehen mit Uhrzeit in der Vergabeliste, im Export und beim Teilen.",
		"„Letzte zurücknehmen“ macht auch solche Änderungen rückgängig.",
	} },
	{ "1.7.0", "13.10.2026", {
		"Vergaben teilen in Gilde, Offiziere, Schlachtzug, Gruppe oder per Flüstern, auch mit /pm teilen.",
		"Frühere Raids im Reiter Vergaben ansehen, ausgeben, exportieren und teilen.",
	} },
	{ "1.6.0", "13.10.2026", {
		"Prio-Tabelle wie bei Prio3, nach dem Import 20 Sekunden lang, mit Knopf im Reiter Raid und /pm tabelle.",
		"Das Importfenster zeigt die geladene Liste als CSV.",
	} },
	{ "1.5.1", "13.10.2026", {
		"Würfelaufrufe nennen /roll 50 nicht mehr.",
	} },
	{ "1.5.0", "13.10.2026", {
		"Immer verwürfeln: alle würfeln mit /roll 100, ein Gewinn senkt keine Stufe.",
		"Mehrere gleiche Items: die höchsten Würfe gewinnen, ein Stichwurf nur an der Grenze.",
		"Blutrebe und die 27 Klassenbücher aus AQ20 gehen an den Schatzmeister.",
		"Klassenbücher zählen nicht mehr als Rezept, Prio darauf gilt.",
		"Plündergrenze als Dropdown, Qualitäten des Plünderhelfers einzeln mit ja oder nein.",
	} },
	{ "1.4.0", "13.10.2026", {
		"Liste „Immer verwürfeln“ je Instanz, Zul'Gurub mit den Items vom Rand des Wahnsinns vorbelegt.",
		"Items unter der Plündergrenze: selbst plündern und handeln, der Handel wird als Vergabe eingetragen.",
	} },
	{ "1.3.0", "13.10.2026", {
		"Neue Rolle Schatzmeister: bekommt nur die Items seiner Liste, der Plünderhelfer alles andere.",
		"Listen je Instanz, AQ20 und AQ40 mit Skarabäen und Kastenschlüsseln vorbelegt.",
		"Häkchen „Reittiere auf Prio erlaubt“, Standard aus.",
		"Häkchen für graue und weiße Items an den Plünderhelfer im Chat, Standard aus.",
		"„Zufällig vergeben“ fragt bei Items mit Prio nach.",
	} },
	{ "1.2.0", "13.10.2026", {
		"Beute-Ansage beim Öffnen samt Prios, wie bei Prio3, mit Wartezeit von 0 bis 600 Sekunden.",
		"„Zufällig vergeben“: Wurf über alle Spieler im Raid, gezählt durch die Gruppen 1 bis 8.",
	} },
	{ "1.1.2", "13.10.2026", {
		"Stichwurf bei Gleichstand, mit derselben Stufe wie beim ersten Wurf.",
	} },
	{ "1.1.1", "13.10.2026", {
		"Würfe gehören zu ihrer Beute: Alte Würfe tauchen nicht mehr bei späteren Exemplaren auf.",
	} },
	{ "1.1", "12.10.2026", {
		"Doppelte Spieler in der Liste: Es gilt der letzte Stand mit den meisten Items.",
		"Hinweis auf Spieler im Raid ohne Prio, mit „Im Raid erinnern“.",
		"Das Würfelergebnis nennt nur die ersten drei Plätze.",
		"50er-Würfe für Zweitchar und Zweitskillung, ohne Stufenänderung.",
		"Rezept-Würfe ohne Stufen, Rezepte auf Prio werden ignoriert und beim Import gemeldet.",
		"Rollen Plünderhelfer und Entzauberer mit Namensauswahl.",
		"Vergaben im Raidchat für den Mitschreiber.",
		"Hauptfenster mit den Reitern Raid, Vergaben, Plündern und Optionen.",
		"Plündermeister und Plündergrenze setzen, auch Grau und Weiß.",
	} },
	{ "1.0", "12.10.2026", {
		"Prioliste von sahne-team.de importieren, Prio 0 bis 3.",
		"Freier Wurf mit Würfelstufen 100, 99, 98 und Hinweis bei falschem Wurf.",
		"Panel neben dem Plünderfenster mit Prio-Haltern und Würfen.",
		"Plündermeister-Liste alphabetisch, angeheftete Spieler oben.",
		"Jede Vergabe mit Wurf im Chat und im Protokoll.",
	} },
}
UI.CHANGELOG = CHANGELOG

local function ChangelogText()
	local parts = {}
	for i, entry in ipairs(CHANGELOG) do
		if i > 1 then parts[#parts + 1] = "" end
		parts[#parts + 1] = format("|cffffd100Version %s|r  |cff909090%s|r", entry[1], entry[2])
		for _, change in ipairs(entry[3]) do parts[#parts + 1] = "- " .. T(change) end
	end
	return table.concat(parts, "\n")
end

function UI:ShowChangelog()
	if not self.changelog then
		local f = self.Box("PrioMeisterChangelog", UIParent, "DIALOG")
		f:SetSize(580, 460)
		f:SetPoint("CENTER")
		self.Movable(f)
		f:SetToplevel(true)
		table.insert(UISpecialFrames, "PrioMeisterChangelog")
		f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		f.title:SetPoint("TOPLEFT", 14, -12)
		f.title:SetText("PrioMeister – Changelog")
		local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -2, -2)
		local scroll = CreateFrame("ScrollFrame", "PrioMeisterChangelogScroll", f, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 16, -42)
		scroll:SetPoint("BOTTOMRIGHT", -34, 14)
		local content = CreateFrame("Frame", nil, scroll)
		content:SetSize(520, 10)
		scroll:SetScrollChild(content)
		f.text = self.Label(content, "GameFontHighlight", 520)
		f.text:SetPoint("TOPLEFT", 0, 0)
		f.text:SetJustifyV("TOP")
		f.content = content
		self.changelog = f
	end
	local f = self.changelog
	f.text:SetText(ChangelogText())
	f.content:SetHeight(f.text:GetStringHeight() + 10)
	f:Show()
	f:Raise()
end

-------------------------------------------------------------------------------
-- Minimap-Knopf
-------------------------------------------------------------------------------

local function PositionMinimapButton(b)
	local angle = math.rad(PM.db.settings.minimapAngle or 200)
	b:ClearAllPoints()
	b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * 80, math.sin(angle) * 80)
end

local function DragMinimapButton(b)
	local mx, my = Minimap:GetCenter()
	local px, py = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	px, py = px / scale, py / scale
	PM.db.settings.minimapAngle = math.deg(math.atan2(py - my, px - mx)) % 360
	PositionMinimapButton(b)
end

function UI:GetMinimapButton()
	if self.minimapButton then return self.minimapButton end
	if not Minimap then return nil end
	local b = CreateFrame("Button", "PrioMeisterMinimapButton", Minimap)
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(20, 20)
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetPoint("TOPLEFT", 7, -5)
	-- rundes Logo genau über dem runden Hintergrund
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetSize(20, 20)
	icon:SetTexture(UI.LOGO_ROUND)
	icon:SetPoint("TOPLEFT", 7, -5)
	b.icon = icon
	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT")
	b:SetScript("OnClick", function(_, mouseButton)
		if mouseButton == "RightButton" then UI:TogglePanel() else UI:ToggleMain() end
	end)
	b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", DragMinimapButton) end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	self.Tooltip(b, "PrioMeister", "Linksklick: Hauptfenster\nRechtsklick: Panel\nZiehen: verschieben")
	self.minimapButton = b
	return b
end

function UI:UpdateMinimapButton()
	if not PM.db then return end
	if PM.db.settings.showMinimap then
		local b = self:GetMinimapButton()
		if b then
			PositionMinimapButton(b)
			b:Show()
		end
	elseif self.minimapButton then
		self.minimapButton:Hide()
	end
end
