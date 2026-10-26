-- PrioMeister – UI.lua
-- Gemeinsame Bausteine, Panel neben dem Plünderfenster, Namensauswahl,
-- Import- und Exportfenster.

local ADDON, ns = ...
local L, PM = ns.Logic, ns.PM
local T = ns.T or function(s) return s end
local UI = {}
ns.UI = UI

local format = string.format
local PANEL_WIDTH = 370
local ROW_WIDTH = PANEL_WIDTH - 20
local MAX_ROLL_LINES = 14
local ROLL_BUTTONS = { "rollWin", "rollTie", "rollDE", "rollPost", "rollEnd" }

-------------------------------------------------------------------------------
-- Bausteine
-------------------------------------------------------------------------------

UI.BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

-- Fenster mit deckendem Hintergrund: einfarbige Fläche statt der Tooltip-Textur,
-- die WoW leicht durchscheinend zeichnet. Nur das Hauptfenster bleibt durchscheinend.
UI.WINDOW_BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8X8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = false, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

-- translucent: leicht durchscheinend wie die WoW-Tooltips (Hauptfenster)
function UI.Box(name, parent, strata, translucent)
	local f = CreateFrame("Frame", name, parent or UIParent, "BackdropTemplate")
	if translucent then
		f:SetBackdrop(UI.BACKDROP)
		f:SetBackdropColor(0.04, 0.04, 0.06, 0.94)
	else
		f:SetBackdrop(UI.WINDOW_BACKDROP)
		f:SetBackdropColor(0.06, 0.06, 0.08, 1)
	end
	f:SetBackdropBorderColor(0.55, 0.55, 0.6, 1)
	if strata then f:SetFrameStrata(strata) end
	f:SetClampedToScreen(true)
	return f
end

function UI.Movable(f)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
end

function UI.Button(parent, text, width, height, small)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or 90, height or 22)
	if small then
		b:SetNormalFontObject(GameFontNormalSmall)
		b:SetHighlightFontObject(GameFontHighlightSmall)
		b:SetDisabledFontObject(GameFontDisableSmall)
	end
	b:SetText(T(text))
	return b
end

function UI.Label(parent, font, width)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
	fs:SetJustifyH("LEFT")
	if width then fs:SetWidth(width) end
	return fs
end

-- text darf eine Funktion sein, dann entsteht er erst beim Zeigen
function UI.Tooltip(widget, title, text)
	widget:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(T(title))
		local body = type(text) == "function" and text() or T(text)
		if body then GameTooltip:AddLine(body, 1, 1, 1, true) end
		GameTooltip:Show()
	end)
	widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Itemlinks in den Texten eines Frames wie im Chat: Maus darüber zeigt das Item,
-- Klick öffnet es, Shift-Klick verlinkt es im Chat. onRightClick(frame): eigener
-- Rechtsklick, auch auf dem Link.
function UI.EnableLinks(frame, onRightClick)
	frame:SetHyperlinksEnabled(true)
	frame:SetScript("OnHyperlinkEnter", function(f, link)
		if type(link) ~= "string" or not link:find("^item:") then return end
		GameTooltip:SetOwner(f, "ANCHOR_CURSOR")
		GameTooltip:SetHyperlink(link)
		GameTooltip:Show()
	end)
	frame:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
	frame:SetScript("OnHyperlinkClick", function(f, link, text, button)
		if onRightClick and button == "RightButton" then return onRightClick(f) end
		SetItemRef(link, text, button, f)
	end)
	return frame
end

local function ItemString(link)
	return type(link) == "string" and link:match("|H(item:[^|]+)|h") or nil
end

function UI:RefreshAll()
	self:RefreshPanel()
	if self.RefreshMain then self:RefreshMain() end
	if self.prioTable and self.prioTable:IsShown() then self:FillPrioTable() end
end

-------------------------------------------------------------------------------
-- Rollen-Knöpfe (Plünderhelfer, Schatzmeister, Entzauberer)
-------------------------------------------------------------------------------

-- short: Kürzel (PH, SM, DE) statt des Rollennamens, für das schmale Panel
function UI:RoleText(role, short)
	local name = PM.db.settings[role]
	local who = name and PM:ColoredName(L.NameKey(name), name) or T("|cff808080niemand|r")
	return format("%s: %s", short and PM.ROLE_SHORT[role] or PM.ROLE_TEXT[role], who)
end

local ROLE_HELP = {
	lootHelper = T("Bekommt automatisch alles bis zur eingestellten Qualität, was nicht auf der Liste des Schatzmeisters steht (Reiter „Plünderoptionen“ im Hauptfenster)."),
	treasurer = T("Bekommt automatisch nur die Items der Liste, z. B. Skarabäen und Schlüssel in AQ. Jede Instanz hat ihre eigene Liste (Reiter „Plünderoptionen“ im Hauptfenster)."),
	disenchanter = T("Bekommt Items, auf die niemand würfelt: „An Entzauberer“ am Item im Panel oder in der Würfelrunde. Ändert seine Würfelstufe nicht."),
}

function UI:CreateRoleButton(parent, role, width)
	local b = self.Button(parent, "", width, 20, true)
	b.role = role
	b:SetScript("OnClick", function(btn)
		UI:ShowPicker(btn, PM.ROLE_TEXT[role] .. T(" wählen"), {
			current = L.NameKey(PM.db.settings[role]),
			onPick = function(name) PM:SetRole(role, name) end,
		})
	end)
	self.Tooltip(b, PM.ROLE_TEXT[role], function() return T(ROLE_HELP[role]) .. T(" Klick: Spieler wählen.") end)
	return b
end

-------------------------------------------------------------------------------
-- Texte für Prio und Würfe
-------------------------------------------------------------------------------

local function HolderText(h, isTop)
	local txt
	if h.passed then
		txt = format(T("|cff808080%s (verzichtet)|r"), h.name)
	elseif h.unusable then
		txt = format(T("|cff808080%s (nicht tragbar)|r"), h.name)
	elseif not h.present then
		txt = format(T("|cff808080%s (fehlt)|r"), h.name)
	elseif isTop then
		txt = PM:ColoredName(h.key, h.name)
	else
		txt = format("|cffb0b0b0%s|r", h.name)
	end
	if h.received and h.received > 0 then
		txt = txt .. format(" |cffff8000+%d|r", h.received)
	end
	return txt
end

function UI:TierText()
	local raid = PM:Raid()
	local tiers, maxima = {}, {}
	for _, m in ipairs(PM:PresentMembers()) do
		local allowed = L.AllowedMax(raid, m.key)
		if allowed < 100 then
			if not tiers[allowed] then
				tiers[allowed] = {}
				maxima[#maxima + 1] = allowed
			end
			table.insert(tiers[allowed], m.name)
		end
	end
	if #maxima == 0 then return nil end
	table.sort(maxima, function(a, b) return a > b end)
	local parts = {}
	for _, mx in ipairs(maxima) do
		parts[#parts + 1] = format("%d: %s", mx, table.concat(tiers[mx], ", "))
	end
	return T("|cffb0b0b0Stufen ") .. table.concat(parts, "; ") .. "|r"
end

function UI:ResolutionText(res)
	local lines = {}
	if res.waitlist then
		local first = res.top == L.WAITLIST and res.topHolders[1]
		local parts = {}
		for _, h in ipairs(res.waitlist) do parts[#parts + 1] = HolderText(h, h == first) end
		lines[#lines + 1] = format(T("|cff%sWarteliste:|r %s"), first and "40ff40" or "909090", table.concat(parts, ", "))
	end
	for lvl = 0, 3 do
		local hs = res.levels[lvl]
		if hs and #hs > 0 then
			local parts = {}
			for _, h in ipairs(hs) do parts[#parts + 1] = HolderText(h, lvl == res.top) end
			local color = (lvl == res.top) and "40ff40" or "909090"
			lines[#lines + 1] = format("|cff%sPrio %d:|r %s", color, lvl, table.concat(parts, ", "))
		end
	end
	if res.ignored and #res.ignored > 0 then
		local names = {}
		for _, h in ipairs(res.ignored) do names[#names + 1] = h.name end
		lines[#lines + 1] = format(T("|cffff8000%s, Prio ignoriert:|r %s"), res.mount and T("Reittier") or T("Rezept"), table.concat(names, ", "))
	end
	if res.mode == "recipe" then
		lines[#lines + 1] = format(T("|cffffd100Rezept-Wurf%s, ohne Würfelstufen|r"),
			res.profession and (T(" für ") .. res.profession) or "")
	elseif res.mode == "plain" then
		lines[#lines + 1] = T("|cffffd100Kein Prio – Wurf ohne Stufen, alle /roll 100|r")
	elseif res.mode == "free" then
		lines[#lines + 1] = T("|cffffd100Kein Prio – freier Wurf|r")
		if PM.db.settings.tierHints then
			local tiers = self:TierText()
			if tiers then lines[#lines + 1] = tiers end
		end
	elseif res.mode == "single" and res.top == L.WAITLIST then
		lines[#lines + 1] = format(T("|cffffd100Vergabe an %s (Warteliste)|r"), res.topHolders[1].name)
	elseif res.mode == "single" then
		lines[#lines + 1] = format(T("|cffffd100Vergabe an %s (Prio %d)|r"), res.topHolders[1].name, res.top)
	else
		lines[#lines + 1] = format(T("|cffffd100%d Spieler würfeln um Prio %d|r"), #res.topHolders, res.top)
	end
	return table.concat(lines, "\n")
end

function UI:RollLines(s)
	local ok, other, _, tied, map = L.RankRolls(s)
	local tiedSet = {}
	for _, r in ipairs(tied or {}) do tiedSet[r] = true end
	local lines = {}
	for i, r in ipairs(ok) do
		local txt = format("%d. %s |cffffffff%d|r |cff909090(%d-%d)|r", i, PM:ColoredName(r.key, r.name), r.value, r.low, r.high)
		if r.kind == "sec" then txt = txt .. T(" |cff66ccff50er|r") end
		local values = L.TiebreakValues(s, map, r.key)
		if #values > 0 then txt = txt .. T(" |cffffd100Stichwurf ") .. table.concat(values, "/") .. "|r" end
		if s.winners[r.key] then txt = txt .. T(" |cff40ff40erhalten|r") end
		if L.WaitingForTiebreak(s, r.key) then
			txt = txt .. T(" |cffff8000wartet auf Stichwurf|r")
		elseif tiedSet[r] then
			txt = txt .. T(" |cffff4040Gleichstand|r")
		end
		if r.reroll then txt = txt .. T(" |cffffd100Neuwurf|r") end
		if r.lower then txt = txt .. T(" |cff909090freiwillig niedriger|r") end
		lines[#lines + 1] = txt
	end
	for _, r in ipairs(other) do
		if r.status == "pass" then
			lines[#lines + 1] = format(T("%s |cffff8000verzichtet|r |cff909090(/roll 1)|r"), PM:ColoredName(r.key, r.name))
		else
			lines[#lines + 1] = format("|cff808080%s %d (%d-%d) – %s|r", r.name, r.value, r.low, r.high, r.reason or "")
		end
	end
	if #lines == 0 then lines[1] = T("|cff808080Noch keine Würfe.|r") end
	return lines
end

-------------------------------------------------------------------------------
-- Panel neben dem Plünderfenster
-------------------------------------------------------------------------------

local function RowAction(row, mouseButton)
	local d = row.data
	if not d then return end
	local ctx = { source = d.source }
	if mouseButton == "RightButton" then
		PM:StartRoll(d.itemID, d.link, d.res, true, ctx)
	elseif d.res.mode == "single" then
		PM:Announce(d.itemID, d.link, d.res, ctx)
	else
		PM:StartRoll(d.itemID, d.link, d.res, false, ctx)
	end
end

local function RowTooltip(row)
	local d = row.data
	if not d then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if d.slot and PM.lootOpen and not PM.testMode then
		GameTooltip:SetLootItem(d.slot)
	elseif ItemString(d.link) then
		GameTooltip:SetHyperlink(ItemString(d.link))
	else
		GameTooltip:SetText(d.link or "?")
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("PrioMeister", 0.2, 1, 0.6)
	local any = false
	for i, h in ipairs(d.res.waitlist or {}) do
		any = true
		GameTooltip:AddLine(format(T("Warteliste %d: %s%s"), i, h.name,
			(h.passed and T(" (verzichtet)")) or (h.unusable and (" (" .. h.unusable .. ")")) or (h.present and "") or T(" (fehlt)")), 1, 1, 1)
	end
	for lvl = 0, 3 do
		for _, h in ipairs(d.res.levels[lvl]) do
			any = true
			GameTooltip:AddLine(format(T("Prio %d: %s%s"), lvl, h.name,
				(h.passed and T(" (verzichtet)")) or (h.unusable and (" (" .. h.unusable .. ")")) or (h.present and "") or T(" (fehlt)")), 1, 1, 1)
			for _, aw in ipairs(L.AwardsOf(PM:Raid(), h.key)) do
				if L.Holds(aw) then
					GameTooltip:AddLine(format(T("   hat bereits %s (%s)"), aw.link or "?", L.AwardDetail(aw)), 1, 0.5, 0, true)
				end
			end
		end
	end
	if not any then
		local what = (d.res.mode == "recipe" and T("Rezept: Würfeln ohne Würfelstufen."))
			or (d.res.mode == "plain" and T("Niemand hat Prio – Wurf ohne Stufen, ein Gewinn senkt keine Stufe."))
			or T("Niemand hat Prio – freier Wurf.")
		GameTooltip:AddLine(what, 1, 0.82, 0)
	end
	GameTooltip:Show()
end

local function CreateRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:SetWidth(ROW_WIDTH)
	row:SetHeight(30)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(22, 22)
	row.icon:SetPoint("TOPLEFT", 0, -2)

	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
	row.name:SetWidth(ROW_WIDTH - 28 - 110)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)

	row.info = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.info:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
	row.info:SetWidth(ROW_WIDTH - 28 - 110)
	row.info:SetJustifyH("LEFT")
	row.info:SetJustifyV("TOP")
	row.info:SetWordWrap(true)

	row.btn = UI.Button(row, "Würfeln", 106, 18, true)
	row.btn:SetPoint("TOPRIGHT", 0, -1)
	-- nur bei genau einem Prio-Halter: direkt an ihn geben
	row.give = UI.Button(row, "", 106, 18, true)
	row.give:SetPoint("TOPRIGHT", 0, -21)
	row.give:SetScript("OnClick", function(b)
		local d = b:GetParent().data
		local h = d and d.res.mode == "single" and d.res.topHolders[1]
		if h then PM:GiveToHolder(d.itemID, d.slot, h.key) end
	end)
	UI.Tooltip(row.give, "An den Prio-Halter",
		T("Gibt das Item dem einzigen anwesenden Prio-Halter oder dem, der auf der Warteliste dran ist. Bei epischen Items fragt das Addon vorher nach, abschaltbar unter Optionen. Will er es nicht, verzichtet er mit /roll 1, dann ist der Nächste dran oder es gibt einen Wurf ohne Prio. Liegt das Item unter der Plündergrenze, plünderst du es selbst und handelst es, das Addon trägt den Handel ein."))
	row.random = UI.Button(row, "Zufällig vergeben", 106, 18, true)
	row.random:SetPoint("TOPRIGHT", 0, -21)
	row.random:SetScript("OnClick", function(b)
		local d = b:GetParent().data
		if d then PM:RequestRandomAssign(d.itemID, d.link, d.slot) end
	end)
	UI.Tooltip(row.random, "Zufällig vergeben",
		T("Würfelt 1 bis Anzahl der Spieler im Raid. Gezählt wird wie im Raidfenster durch die Gruppen 1 bis 8, der Spieler auf diesem Platz bekommt das Item. Im Chat steht „zufällig vergeben“. Hat jemand Prio auf das Item oder schon dafür gewürfelt, fragt das Addon vorher nach."))
	-- ohne Würfelrunde an den Entzauberer, ab der Qualität aus dem Reiter Plünderoptionen
	row.de = UI.Button(row, "An Entzauberer", 106, 18, true)
	row.de:SetScript("OnClick", function(b)
		local d = b:GetParent().data
		if d then PM:GiveItemToDisenchanter(d.itemID, d.slot) end
	end)
	UI.Tooltip(row.de, "An Entzauberer",
		T("Gibt das Item ohne Würfelrunde an den Entzauberer. Der Knopf steht bei Rüstung und Waffen ab der Qualität, die im Reiter Plünderoptionen beim Entzauberer eingestellt ist, und nur, solange kein anwesender Spieler Prio hat. Bei epischen Items und wenn schon jemand gewürfelt hat, fragt das Addon vorher nach."))
	row.btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.btn:SetScript("OnClick", function(b, mouseButton) RowAction(b:GetParent(), mouseButton) end)
	UI.Tooltip(row.btn, "PrioMeister",
		T("Linksklick: Prio ansagen bzw. Würfelrunde starten und im Raid ansagen.\nRechtsklick: freier Wurf bzw. Rezept-Wurf, auch wenn jemand Prio hat.\nWer Prio hat und das Item nicht will, würfelt /roll 1. Dann ist die nächste Prio dran oder es gibt einen Wurf ohne Prio."))

	row.sep = row:CreateTexture(nil, "BACKGROUND")
	row.sep:SetColorTexture(1, 1, 1, 0.07)
	row.sep:SetHeight(1)
	row.sep:SetPoint("BOTTOMLEFT", 0, -3)
	row.sep:SetPoint("BOTTOMRIGHT", 0, -3)

	row:RegisterForClicks("LeftButtonUp")
	row:SetScript("OnClick", function(r)
		if r.data and r.data.link and HandleModifiedItemClick then HandleModifiedItemClick(r.data.link) end
	end)
	row:SetScript("OnEnter", RowTooltip)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return row
end

function UI:GetPanel()
	if self.panel then return self.panel end
	local p = self.Box("PrioMeisterPanel", UIParent, "HIGH")
	p:SetWidth(PANEL_WIDTH)
	p:SetHeight(120)
	self.Movable(p)

	p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	p.title:SetPoint("TOPLEFT", 10, -9)
	p.title:SetText("PrioMeister")

	p.status = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	p.status:SetPoint("LEFT", p.title, "RIGHT", 8, 0)
	p.status:SetPoint("RIGHT", p, "RIGHT", -52, 0)
	p.status:SetJustifyH("LEFT")
	p.status:SetWordWrap(false)

	p.close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
	p.close:SetSize(26, 26)
	p.close:SetPoint("TOPRIGHT", 0, 0)
	p.close:SetScript("OnClick", function()
		p:Hide()
		PM.panelPinned = false
	end)

	p.menu = self.Button(p, "Menü", 44, 18, true)
	p.menu:SetPoint("RIGHT", p.close, "LEFT", 0, 0)
	p.menu:SetScript("OnClick", function()
		if UI.ToggleMain then UI:ToggleMain() else PM:Slash("") end
	end)
	self.Tooltip(p.menu, "PrioMeister", "Öffnet das Hauptfenster mit Raid, Beute, Plünderoptionen und Optionen.")

	local third = (ROW_WIDTH - 8) / 3
	p.helper = self:CreateRoleButton(p, "lootHelper", third)
	p.helper:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -30)
	p.treasurer = self:CreateRoleButton(p, "treasurer", third)
	p.treasurer:SetPoint("LEFT", p.helper, "RIGHT", 4, 0)
	p.de = self:CreateRoleButton(p, "disenchanter", third)
	p.de:SetPoint("LEFT", p.treasurer, "RIGHT", 4, 0)

	p.empty = self.Label(p, "GameFontDisableSmall", ROW_WIDTH)

	p.rollHeaderBox = self.EnableLinks(CreateFrame("Frame", nil, p))
	p.rollHeaderBox:SetSize(ROW_WIDTH, 14)
	p.rollHeader = self.Label(p.rollHeaderBox, "GameFontNormalSmall", ROW_WIDTH)
	p.rollHeader:SetPoint("TOPLEFT", 0, 0)
	p.rollHeader:SetWordWrap(false)

	p.rollPost = self.Button(p, "Ergebnis posten", 104, 18, true)
	p.rollPost:SetScript("OnClick", function()
		local s = L.ActiveSession(PM:Raid())
		if s then PM:Send(L.ResultMessage(s, 3)) end
	end)
	self.Tooltip(p.rollPost, "Ergebnis posten", "Postet die ersten drei Plätze der Würfelrunde im Raid.")
	p.rollTie = self.Button(p, "Stichwurf", 104, 18, true)
	p.rollTie:SetScript("OnClick", function() PM:StartTiebreak() end)
	self.Tooltip(p.rollTie, "Stichwurf",
		T("Gleichstand an der Spitze: Die Gleichplatzierten würfeln noch einmal, mit derselben Stufe wie beim ersten Wurf. Alle anderen Würfe zählen dann nicht."))
	p.rollDE = self.Button(p, "An Entzauberer", 104, 18, true)
	p.rollDE:SetScript("OnClick", function() PM:GiveToDisenchanter() end)
	self.Tooltip(p.rollDE, "An Entzauberer",
		T("Gibt das Item der Würfelrunde an den Entzauberer, z. B. wenn niemand gewürfelt hat. Seine Würfelstufe bleibt gleich. Hat schon jemand gewürfelt oder ist es eine Prio-Runde, fragt das Addon vorher nach."))
	p.rollEnd = self.Button(p, "Beenden", 80, 18, true)
	p.rollEnd:SetScript("OnClick", function() PM:EndSession() end)
	self.Tooltip(p.rollEnd, "Beenden",
		T("Schließt die Würfelrunde. Neue Würfe zählen nicht mehr, die bisherigen bleiben gültig. Das Item bleibt liegen, im Chat erscheint nichts. Danach kannst du es weiter an den Gewinner oder den Entzauberer geben. Ein neuer Klick auf „Würfeln“ startet eine neue Runde, dann zählen die alten Würfe nicht mehr."))
	p.rollWin = self.Button(p, "", 150, 18, true)
	p.rollWin:SetScript("OnClick", function() PM:GiveToWinner() end)
	self.Tooltip(p.rollWin, "An den Gewinner",
		T("Gibt das Item dem Spieler mit dem höchsten gültigen Wurf, bei mehreren Exemplaren dem nächsten. Bei epischen Items fragt das Addon vorher nach, wie Blizzards Plündermeister-Liste. Das lässt sich unter Optionen abschalten. Liegt das Item unter der Plündergrenze, plünderst du es selbst und handelst es, das Addon trägt den Handel ein."))

	p.rows = {}
	p.rollLines = {}
	p:Hide()
	self.panel = p
	return p
end

function UI:ShowPanel(anchorToLoot)
	local p = self:GetPanel()
	p:ClearAllPoints()
	if anchorToLoot and LootFrame then
		p:SetPoint("TOPLEFT", LootFrame, "TOPRIGHT", 4, 0)
	else
		p:SetPoint("CENTER", UIParent, "CENTER", 260, 80)
	end
	p:Show()
	self:RefreshPanel()
end

function UI:HidePanel()
	if self.panel then self.panel:Hide() end
end

function UI:TogglePanel()
	local p = self:GetPanel()
	if p:IsShown() then
		p:Hide()
		PM.panelPinned = false
	else
		PM.panelPinned = true
		self:ShowPanel(PM.lootOpen)
	end
end

function UI:RefreshPanel()
	local p = self.panel
	if not p or not p:IsShown() or not PM.db then return end
	local raid = PM:Raid()

	local count = 0
	for _ in pairs(raid.players) do count = count + 1 end
	local status
	if not PM:IsEnabled() then
		status = T("|cffff4040ausgeschaltet|r")
	elseif count == 0 then
		status = T("keine Prioliste")
	else
		status = format(T("%d Spieler, %d Vergaben"), count, L.AwardCount(raid))
	end
	if PM.testMode then status = "|cffff8000TEST|r " .. status end
	p.status:SetText(status)
	p.helper:SetText(self:RoleText("lootHelper", true))
	p.treasurer:SetText(self:RoleText("treasurer", true))
	p.de:SetText(self:RoleText("disenchanter", true))

	local items = PM:PanelItems()
	local y = -56
	for i, d in ipairs(items) do
		local row = p.rows[i]
		if not row then
			row = CreateRow(p)
			p.rows[i] = row
		end
		row.data = d
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", p, "TOPLEFT", 10, y)
		row.icon:SetTexture(d.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
		local label = d.link or d.name or "?"
		if d.loading then label = format(T("|cff808080Item %s, Daten werden geladen …|r"), tostring(d.itemID or "?")) end
		if d.quantity and d.quantity > 1 then label = label .. " x" .. d.quantity end
		row.name:SetText(label)
		local info = self:ResolutionText(d.res)
		if d.below then
			info = info .. T("\n|cff909090Unter der Plündergrenze: selbst plündern und an den Gewinner handeln, das Addon trägt den Handel ein.|r")
		end
		row.info:SetText(info)
		-- genau ein Prio-Halter: Ansagen, An Name, Zufällig vergeben; sonst Würfeln, Zufällig vergeben
		local single = d.res.mode == "single"
		row.btn:SetText(single and T("Ansagen") or T("Würfeln"))
		row.give:SetShown(single)
		if single then row.give:SetText(format(T("An %s"), d.res.topHolders[1].name)) end
		row.random:ClearAllPoints()
		row.random:SetPoint("TOPRIGHT", 0, single and -41 or -21)
		local showDE = PM:ShowDisenchantButton(d)
		row.de:SetShown(showDE)
		if showDE then
			row.de:ClearAllPoints()
			row.de:SetPoint("TOPRIGHT", 0, single and -61 or -41)
		end
		local h = 18 + row.info:GetStringHeight() + 6
		local minHeight = (single and 62 or 42) + (showDE and 20 or 0)
		if h < minHeight then h = minHeight end
		row:SetHeight(h)
		row:Show()
		y = y - h - 6
	end
	for i = #items + 1, #p.rows do p.rows[i]:Hide() end

	if #items == 0 then
		p.empty:ClearAllPoints()
		p.empty:SetPoint("TOPLEFT", p, "TOPLEFT", 10, y)
		p.empty:SetText(PM.lootOpen and T("Keine Items über der Plündergrenze.") or T("Kein Plünderfenster offen."))
		p.empty:Show()
		y = y - 18
	else
		p.empty:Hide()
	end

	local s = PM:PanelSession()
	if s then
		y = y - 4
		p.rollHeaderBox:ClearAllPoints()
		p.rollHeaderBox:SetPoint("TOPLEFT", p, "TOPLEFT", 10, y)
		p.rollHeaderBox:Show()
		local what = (s.mode == "prio") and L.LevelText(s.level)
			or (s.mode == "recipe" and T("Rezept-Wurf")) or (s.mode == "plain" and T("Wurf ohne Stufen")) or T("freier Wurf")
		local copies = (s.copies and s.copies > 1) and (" x" .. s.copies) or ""
		p.rollHeader:SetText(format(T("Würfe: %s%s – %s%s"), s.link or "?", copies, what, s.closed and T(" |cff909090(beendet)|r") or ""))
		p.rollHeader:Show()
		y = y - 16
		local lines = self:RollLines(s)
		for i = 1, math.min(#lines, MAX_ROLL_LINES) do
			local fs = p.rollLines[i]
			if not fs then
				fs = self.Label(p, "GameFontHighlightSmall", ROW_WIDTH)
				fs:SetWordWrap(false)
				p.rollLines[i] = fs
			end
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", p, "TOPLEFT", 14, y)
			fs:SetText(lines[i])
			fs:Show()
			y = y - 14
		end
		for i = math.min(#lines, MAX_ROLL_LINES) + 1, #p.rollLines do p.rollLines[i]:Hide() end
		y = y - 4
		-- erste Reihe: wer das Item bekommt, zweite Reihe: die Runde selbst
		local winner = L.RoundWinner(s)
		local _, _, tieFirst = L.RankRolls(s)
		local showTie = tieFirst ~= nil and not s.closed
		local showDE = not showTie and PM.db.settings.disenchanter ~= nil
		local first, second = {}, { p.rollPost }
		if winner then
			p.rollWin:SetText(format(T("An %s (%d)"), winner.name, winner.value))
			first[#first + 1] = p.rollWin
		end
		if showTie then first[#first + 1] = p.rollTie end
		if showDE then first[#first + 1] = p.rollDE end
		if not s.closed then second[#second + 1] = p.rollEnd end
		for _, b in ipairs(ROLL_BUTTONS) do p[b]:Hide() end
		for _, buttons in ipairs({ first, second }) do
			for i, b in ipairs(buttons) do
				b:ClearAllPoints()
				if i == 1 then
					b:SetPoint("TOPLEFT", p, "TOPLEFT", 10, y)
				else
					b:SetPoint("LEFT", buttons[i - 1], "RIGHT", 4, 0)
				end
				b:Show()
			end
			if #buttons > 0 then y = y - 22 end
		end
		if L.ValidRollCount(s) == 0 and not s.closed then
			p.rollDE:LockHighlight()
		else
			p.rollDE:UnlockHighlight()
		end
	else
		p.rollHeaderBox:Hide()
		p.rollHeader:Hide()
		for _, fs in ipairs(p.rollLines) do fs:Hide() end
		for _, b in ipairs(ROLL_BUTTONS) do p[b]:Hide() end
	end

	p:SetHeight(-y + 8)
end

-------------------------------------------------------------------------------
-- Namensauswahl (wie die Plündermeister-Liste)
-------------------------------------------------------------------------------

local PICK_ROWS, PICK_W, PICK_H = 10, 104, 20

function UI:PickerNames()
	local list, seen = {}, {}
	for _, m in ipairs(PM:RosterList()) do
		seen[m.key] = true
		list[#list + 1] = m
	end
	if PM.testMode then
		for key, p in pairs(PM:Raid().players) do
			if not seen[key] then
				seen[key] = true
				list[#list + 1] = { key = key, name = p.name }
			end
		end
	end
	table.sort(list, function(a, b) return L.SortKey(a.name) < L.SortKey(b.name) end)
	return list
end

local function PickerClick(btn)
	local f = UI.picker
	local opts = f.opts
	local e = btn.entry
	if not opts or not e then return end
	if opts.multi then
		if e.key then opts.onToggle(e.name) end
		UI:FillPicker()
	else
		f:Hide()
		opts.onPick(e.name)
	end
end

function UI:GetPicker()
	if self.picker then return self.picker end
	local f = self.Box("PrioMeisterPicker", UIParent, "FULLSCREEN_DIALOG")
	f:EnableMouse(true)
	table.insert(UISpecialFrames, "PrioMeisterPicker")
	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.title:SetPoint("TOPLEFT", 10, -9)
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetSize(24, 24)
	close:SetPoint("TOPRIGHT", 0, 0)

	f.buttons = {}
	f.manualLabel = self.Label(f, "GameFontHighlightSmall")
	f.manualLabel:SetText(T("Name eingeben:"))
	f.edit = CreateFrame("EditBox", "PrioMeisterPickerEdit", f, "InputBoxTemplate")
	f.edit:SetSize(110, 20)
	f.edit:SetAutoFocus(false)
	f.ok = self.Button(f, "OK", 40, 20, true)
	local function manual()
		local text = L.Trim(f.edit:GetText())
		f.edit:SetText("")
		f.edit:ClearFocus()
		if text == "" or not f.opts then return end
		if f.opts.multi then
			f.opts.onToggle(text)
			UI:FillPicker()
		else
			f:Hide()
			f.opts.onPick(text)
		end
	end
	f.edit:SetScript("OnEnterPressed", manual)
	f.edit:SetScript("OnEscapePressed", function(e) e:ClearFocus() end)
	f.ok:SetScript("OnClick", manual)
	f.done = self.Button(f, "Fertig", 60, 20, true)
	f.done:SetScript("OnClick", function() f:Hide() end)
	f.action = self.Button(f, "", 170, 20, true)
	f.action:SetScript("OnClick", function()
		local action = f.opts and f.opts.action
		f:Hide()
		if action then action.onClick() end
	end)
	f:Hide()
	self.picker = f
	return f
end

local function CreatePickerButton(f)
	local b = CreateFrame("Button", nil, f)
	b:SetSize(PICK_W, PICK_H)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints(b)
	b.bg:SetColorTexture(0.2, 0.2, 0.2, 0.5)
	b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	b.check = b:CreateTexture(nil, "OVERLAY")
	b.check:SetSize(14, 14)
	b.check:SetPoint("LEFT", 2, 0)
	b.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.text:SetPoint("LEFT", 16, 0)
	b.text:SetWidth(PICK_W - 18)
	b.text:SetJustifyH("LEFT")
	b.text:SetWordWrap(false)
	b:SetScript("OnClick", PickerClick)
	return b
end

-- opts: multi (Mehrfachauswahl), current (Schlüssel der aktuellen Wahl),
-- isSelected(name), onPick(name oder nil), onToggle(name), names (eigene Liste
-- { key, name }), noNone (ohne „niemand“), action ({ text, onClick }: Zusatzknopf)
function UI:ShowPicker(anchor, title, opts)
	local f = self:GetPicker()
	f.opts = opts
	f.title:SetText(T(title))
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	f:Show()
	self:FillPicker()
end

function UI:FillPicker()
	local f = self.picker
	local opts = f.opts
	local entries = {}
	if not opts.multi and not opts.noNone then entries[1] = { label = T("|cff909090– niemand –|r") } end
	for _, m in ipairs(opts.names or self:PickerNames()) do entries[#entries + 1] = { key = m.key, name = m.name } end

	for i, e in ipairs(entries) do
		local b = f.buttons[i]
		if not b then
			b = CreatePickerButton(f)
			f.buttons[i] = b
		end
		local col, row = math.floor((i - 1) / PICK_ROWS), (i - 1) % PICK_ROWS
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", f, "TOPLEFT", 8 + col * (PICK_W + 4), -30 - row * PICK_H)
		b.entry = e
		b.text:SetText(e.key and PM:ColoredName(e.key, e.name) or e.label)
		local selected
		if opts.multi then
			selected = e.key and opts.isSelected(e.name)
		else
			selected = (e.key ~= nil and e.key == opts.current) or (e.key == nil and opts.current == nil)
		end
		b.check:SetShown(selected and true or false)
		b:Show()
	end
	for i = #entries + 1, #f.buttons do f.buttons[i]:Hide() end

	local cols = math.max(2, math.ceil(#entries / PICK_ROWS))
	local rows = math.min(#entries, PICK_ROWS)
	local width = 16 + cols * (PICK_W + 4)
	local bottom = -30 - rows * PICK_H - 8
	f.manualLabel:ClearAllPoints()
	f.manualLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 10, bottom - 4)
	f.edit:ClearAllPoints()
	f.edit:SetPoint("LEFT", f.manualLabel, "RIGHT", 10, 0)
	f.ok:ClearAllPoints()
	f.ok:SetPoint("LEFT", f.edit, "RIGHT", 4, 0)
	f.done:ClearAllPoints()
	f.done:SetPoint("LEFT", f.ok, "RIGHT", 4, 0)
	f.done:SetShown(opts.multi and true or false)
	local extra = 0
	if opts.action then
		f.action:SetText(opts.action.text)
		f.action:ClearAllPoints()
		f.action:SetPoint("TOPLEFT", f, "TOPLEFT", 10, bottom - 30)
		f.action:Show()
		extra = 26
	else
		f.action:Hide()
	end
	f:SetSize(math.max(width, 330), -bottom + 34 + extra)
end

-------------------------------------------------------------------------------
-- Textfenster (Import und Export)
-------------------------------------------------------------------------------

local function CreateTextDialog(name, title)
	local f = UI.Box(name, UIParent, "DIALOG")
	f:SetSize(580, 440)
	f:SetPoint("CENTER")
	UI.Movable(f)
	f:SetToplevel(true)
	table.insert(UISpecialFrames, name)

	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.title:SetPoint("TOP", 0, -12)
	f.title:SetText(title)

	f.hint = UI.Label(f, "GameFontHighlightSmall", 548)
	f.hint:SetPoint("TOPLEFT", 16, -38)

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
	box:SetBackdrop(UI.BACKDROP)
	box:SetBackdropColor(0, 0, 0, 0.6)
	box:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
	box:SetPoint("TOPLEFT", 12, -70)
	box:SetPoint("BOTTOMRIGHT", -12, 76)
	box:EnableMouse(true)

	local scroll = CreateFrame("ScrollFrame", name .. "Scroll", box, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 8, -8)
	scroll:SetPoint("BOTTOMRIGHT", -28, 8)

	local edit = CreateFrame("EditBox", name .. "Edit", scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(ChatFontNormal)
	edit:SetWidth(510)
	edit:SetHeight(280)
	edit:SetMaxLetters(0)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	if ScrollingEdit_OnCursorChanged then
		edit.cursorOffset, edit.cursorHeight = 0, 0
		edit:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
		edit:SetScript("OnUpdate", function(self, elapsed) ScrollingEdit_OnUpdate(self, elapsed, scroll) end)
	end
	scroll:SetScrollChild(edit)
	box:SetScript("OnMouseDown", function() edit:SetFocus() end)

	f.status = UI.Label(f, "GameFontHighlightSmall", 548)
	f.status:SetPoint("BOTTOMLEFT", 16, 50)

	f.edit, f.scroll = edit, scroll
	f:Hide()
	return f
end

function UI:UpdateImportMode()
	local f = self.importFrame
	if not f then return end
	local isCheck = L.IsPrioCheck(f.edit:GetText())
	if isCheck == (f.isCheck or false) then return end
	f.isCheck = isCheck
	f.check:SetShown(isCheck)
	f.newRaid:SetShown(not isCheck)
	f.replace:SetShown(not isCheck)
	if isCheck then
		f.status:SetText(T("Priocheck von priomeister.de erkannt: „Prüfen“ vergleicht ihn mit dem Raid. Die Prioliste, Vergaben und Würfelstufen bleiben, wie sie sind."))
	else
		f.status:SetText(T("„Import als neuer Raid“ setzt Vergaben und Würfelstufen zurück. „Nur Liste ersetzen“ behält sie, z. B. für eine korrigierte Liste."))
	end
end

function UI:ShowImport()
	if not self.importFrame then
		local f = CreateTextDialog("PrioMeisterImportFrame", T("PrioMeister – Prioliste importieren"))
		f.hint:SetText(T("Prioliste: auf priomeister.de „Kopieren für PrioMeister“. Priocheck: auf der Spielerseite des Prio-Runs unter „Alle Prios“ „Priocheck kopieren“. Dann hier einfügen (Cmd+V am Mac, Strg+V unter Windows). Listen von sahne-team.de gehen weiterhin."))

		local newRaid = self.Button(f, "Import als neuer Raid", 170, 24)
		newRaid:SetPoint("BOTTOMLEFT", 14, 16)
		newRaid:SetScript("OnClick", function()
			if PM:ImportText(f.edit:GetText(), true) then
				f.status:SetText(T("|cff40ff40Importiert.|r Vergaben und Würfelstufen wurden zurückgesetzt."))
			else
				f.status:SetText(T("|cffff4040Keine Spieler erkannt.|r"))
			end
		end)
		f.newRaid = newRaid

		-- Priocheck statt Liste: ein Knopf „Prüfen“ an Stelle der beiden Import-Knöpfe
		f.check = self.Button(f, "Prüfen", 170, 24)
		f.check:SetPoint("BOTTOMLEFT", 14, 16)
		f.check:SetScript("OnClick", function()
			if PM:ApplyPrioCheck(f.edit:GetText()) then
				local res = PM:CheckResult()
				f.status:SetText(res and format(T("|cff40ff40Geprüft.|r Im Raid %d ohne Prios, %d unvollständig, %d vollständig. Details im Chat und im Reiter Raid, die Prioliste bleibt, wie sie ist."),
					#res.none, #res.partial, res.complete) or T("|cff40ff40Geprüft.|r Details im Chat."))
			else
				f.status:SetText(T("|cffff4040Kein Priocheck erkannt.|r"))
			end
		end)
		f.check:Hide()

		local replace = self.Button(f, "Nur Liste ersetzen", 150, 24)
		replace:SetPoint("LEFT", newRaid, "RIGHT", 8, 0)
		f.replace = replace
		replace:SetScript("OnClick", function()
			if PM:ImportText(f.edit:GetText(), false) then
				f.status:SetText(T("|cff40ff40Importiert.|r Bisherige Vergaben und Würfelstufen bleiben erhalten."))
			else
				f.status:SetText(T("|cffff4040Keine Spieler erkannt.|r"))
			end
		end)

		local clear = self.Button(f, "Leeren", 80, 24)
		clear:SetPoint("LEFT", replace, "RIGHT", 8, 0)
		clear:SetScript("OnClick", function()
			f.edit:SetText("")
			f.edit:SetFocus()
		end)

		local close = self.Button(f, "Schließen", 90, 24)
		close:SetPoint("BOTTOMRIGHT", -14, 16)
		close:SetScript("OnClick", function() f:Hide() end)

		-- Beim Einfügen erkennen, ob eine Prioliste oder ein Priocheck im Feld steht
		f.edit:SetScript("OnTextChanged", function() UI:UpdateImportMode() end)
		self.importFrame = f
	end
	-- Im Feld steht die geladene Liste als CSV, markiert: Einfügen ersetzt sie.
	local f = self.importFrame
	local count = 0
	for _ in pairs(PM:Raid().players) do count = count + 1 end
	f:Show()
	if count > 0 then
		f.edit:SetText(PM:PrioListCSV())
		f.status:SetText(format(T("Im Feld steht die geladene Liste mit %d Spielern, schon markiert: Eine neue CSV einfügen ersetzt sie. „Import als neuer Raid“ setzt Vergaben und Würfelstufen zurück, „Nur Liste ersetzen“ behält sie."), count))
	else
		f.edit:SetText("")
		f.status:SetText(T("„Import als neuer Raid“ setzt Vergaben und Würfelstufen zurück. „Nur Liste ersetzen“ behält sie, z. B. für eine korrigierte Liste."))
	end
	f.isCheck = false
	f.check:Hide()
	f.newRaid:Show()
	f.replace:Show()
	f.edit:SetFocus()
	f.edit:HighlightText()
end

function UI:ShowText(title, text)
	if not self.textFrame then
		local f = CreateTextDialog("PrioMeisterTextFrame", title)
		f.hint:SetText(T("Zum Kopieren: „Alles markieren“, dann Cmd+C bzw. Strg+C. Das Format passt für Excel und Google Tabellen."))
		f.edit:SetScript("OnTextChanged", function(self, userInput)
			if userInput and self.fixedText then self:SetText(self.fixedText) end
		end)
		local select = self.Button(f, "Alles markieren", 130, 24)
		select:SetPoint("BOTTOMLEFT", 14, 16)
		select:SetScript("OnClick", function()
			f.edit:SetFocus()
			f.edit:HighlightText()
		end)
		local close = self.Button(f, "Schließen", 90, 24)
		close:SetPoint("BOTTOMRIGHT", -14, 16)
		close:SetScript("OnClick", function() f:Hide() end)
		self.textFrame = f
	end
	local f = self.textFrame
	f.title:SetText(title)
	f.edit.fixedText = text
	f.edit:SetText(text)
	f.status:SetText("")
	f:Show()
end

-------------------------------------------------------------------------------
-- Prio-Tabelle: alle Spieler mit Prio 1 bis 3, wie bei Prio3
-------------------------------------------------------------------------------

local TABLE_W, TABLE_H = 760, 470
local NAME_W, CELL_W, TABLE_ROW = 140, 188, 20

local function TableCellEnter(cell)
	if not cell.itemString then return end
	GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink(cell.itemString)
	for _, note in ipairs(cell.notes) do GameTooltip:AddLine(note, 1, 0.82, 0, true) end
	GameTooltip:Show()
end

local function CreateTableRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(TABLE_W - 56, TABLE_ROW)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints(row)
	row.name = UI.Label(row, "GameFontHighlightSmall", NAME_W - 8)
	row.name:SetPoint("LEFT", 4, 0)
	row.name:SetWordWrap(false)
	row.cells = {}
	for i = 1, 3 do
		local cell = CreateFrame("Button", nil, row)
		cell:SetSize(CELL_W - 6, TABLE_ROW)
		cell:SetPoint("LEFT", row, "LEFT", NAME_W + (i - 1) * CELL_W, 0)
		cell.icon = cell:CreateTexture(nil, "ARTWORK")
		cell.icon:SetSize(16, 16)
		cell.icon:SetPoint("LEFT", 0, 0)
		cell.text = UI.Label(cell, "GameFontHighlightSmall", CELL_W - 30)
		cell.text:SetPoint("LEFT", cell.icon, "RIGHT", 4, 0)
		cell.text:SetWordWrap(false)
		cell.notes = {}
		cell:SetScript("OnEnter", TableCellEnter)
		cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
		cell:SetScript("OnClick", function(c)
			if c.link and HandleModifiedItemClick then HandleModifiedItemClick(c.link) end
		end)
		row.cells[i] = cell
	end
	return row
end

function UI:GetPrioTable()
	if self.prioTable then return self.prioTable end
	local f = self.Box("PrioMeisterPrioTable", UIParent, "DIALOG")
	f:SetSize(TABLE_W, TABLE_H)
	f:SetPoint("CENTER")
	self.Movable(f)
	f:SetToplevel(true)
	table.insert(UISpecialFrames, "PrioMeisterPrioTable")

	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.title:SetPoint("TOPLEFT", 14, -12)
	f.title:SetText(T("Prioliste"))
	f.info = self.Label(f, "GameFontHighlightSmall", TABLE_W - 220)
	f.info:SetPoint("LEFT", f.title, "RIGHT", 12, 0)
	f.info:SetWordWrap(false)
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	for i, text in ipairs({ T("Spieler"), T("Prio 1"), T("Prio 2"), T("Prio 3") }) do
		local head = self.Label(f, "GameFontNormalSmall")
		head:SetText(text)
		head:SetPoint("TOPLEFT", 16 + ((i == 1) and 0 or (NAME_W + (i - 2) * CELL_W)), -42)
	end

	local scroll = CreateFrame("ScrollFrame", "PrioMeisterPrioTableScroll", f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 12, -58)
	scroll:SetPoint("BOTTOMRIGHT", -32, 42)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(TABLE_W - 56, 10)
	scroll:SetScrollChild(content)
	f.content, f.rows = content, {}
	f.empty = self.Label(content, "GameFontDisableSmall", TABLE_W - 80)
	f.empty:SetPoint("TOPLEFT", 4, -4)
	f.empty:SetText(T("Noch keine Prioliste importiert."))

	f.footer = self.Label(f, "GameFontDisableSmall", TABLE_W - 260)
	f.footer:SetPoint("BOTTOMLEFT", 16, 18)
	local closeButton = self.Button(f, "Schließen", 90, 22)
	closeButton:SetPoint("BOTTOMRIGHT", -14, 12)
	closeButton:SetScript("OnClick", function() f:Hide() end)
	local csv = self.Button(f, "Als CSV …", 100, 22)
	csv:SetPoint("RIGHT", closeButton, "LEFT", -6, 0)
	csv:SetScript("OnClick", function()
		f:Hide()
		UI:ShowImport()
	end)
	self.Tooltip(csv, "Als CSV", "Öffnet das Importfenster mit der geladenen Liste als CSV, z. B. zum Kopieren oder Korrigieren.")

	-- Nach dem Import schließt die Tabelle von selbst, außer die Maus ist darüber.
	f:SetScript("OnUpdate", function(frame, elapsed)
		if not frame.autoClose then return end
		if frame:IsMouseOver() then
			frame.autoClose = nil
			frame.footer:SetText("")
			return
		end
		frame.autoClose = frame.autoClose - elapsed
		if frame.autoClose <= 0 then
			frame.autoClose = nil
			frame:Hide()
		else
			frame.footer:SetText(format(T("Schließt in %d s. Maus über die Tabelle hält sie offen."), math.ceil(frame.autoClose)))
		end
	end)
	f:Hide()
	self.prioTable = f
	return f
end

function UI:FillPrioTable()
	local f = self.prioTable
	if not f or not PM.db then return end
	local raid = PM:Raid()
	local list = {}
	for key, p in pairs(raid.players) do list[#list + 1] = { key = key, p = p } end
	table.sort(list, function(a, b) return L.SortKey(a.p.name) < L.SortKey(b.p.name) end)
	local present = 0
	for i, e in ipairs(list) do
		local row = f.rows[i]
		if not row then
			row = CreateTableRow(f.content)
			f.rows[i] = row
		end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -(i - 1) * TABLE_ROW)
		row.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.05 or 0)
		local member = PM:IsMember(e.key)
		if member then present = present + 1 end
		local name = member and PM:ColoredName(e.key, e.p.name) or format("|cff808080%s|r", e.p.name)
		row.name:SetText(format("|cff808080%d|r %s", i, name))
		-- Welche Prio-Stufe hat jeder Platz? Prio 0 belegt mehrere Plätze.
		local levelOf = {}
		for _, entry in ipairs(L.GetEntries(e.p, PM.db.settings.prio0Mode)) do
			if entry.level == 0 then
				for idx = 1, 3 do
					if L.Canon(e.p.p[idx]) == entry.item then levelOf[idx] = 0 end
				end
			else
				levelOf[entry.level] = entry.level
			end
		end
		local used = {}
		for _, aw in ipairs(raid.awards) do
			if aw.key == e.key and L.UsesPrio(aw) then used[aw.level] = L.Canon(aw.itemID) end
		end
		for idx = 1, 3 do
			local cell = row.cells[idx]
			local id = e.p.p[idx] or 0
			cell.notes = {}
			if id ~= 0 then
				local _, link, _, texture = PM:ItemInfo(id)
				local csvName = e.p.pn[idx]
				local label = link or format("[%s]", (csvName and csvName ~= "") and csvName or ("Item " .. id))
				local prefix, suffix = "", ""
				local level = levelOf[idx]
				if level == 0 then
					prefix = "|cffffd100P0|r "
					cell.notes[#cell.notes + 1] = T("Prio 0: dasselbe Item auf mehreren Prio-Plätzen.")
				end
				if level ~= nil and used[level] == L.Canon(id) then
					suffix = T(" |cff40ff40erhalten|r")
					cell.notes[#cell.notes + 1] = T("Bereits erhalten.")
				end
				local ignored = PM:IgnoredKind(id)
				if ignored then
					suffix = suffix .. T(" |cffff8000ignoriert|r")
					cell.notes[#cell.notes + 1] = (ignored == "mount" and T("Reittier") or T("Rezept")) .. T(" auf Prio wird ignoriert (Optionen).")
				end
				cell.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
				cell.icon:Show()
				cell.text:SetText(prefix .. label .. suffix)
				cell.link = link
				cell.itemString = (link and link:match("|H(item:[^|]+)|h")) or ("item:" .. id)
			else
				cell.icon:Hide()
				cell.text:SetText(format(T("|cff606060– keine Prio %d –|r"), idx))
				cell.link, cell.itemString = nil, nil
			end
		end
		row:Show()
	end
	for i = #list + 1, #f.rows do f.rows[i]:Hide() end
	f.content:SetHeight(math.max(10, #list * TABLE_ROW))
	f.empty:SetShown(#list == 0)
	local imported = raid.imported and (T(" · importiert ") .. date("%d.%m. %H:%M", raid.imported)) or ""
	f.info:SetText(format(T("%d Spieler, davon %d im Raid%s"), #list, present, imported))
end

-- autoClose: Sekunden bis zum Schließen (nach dem Import), sonst bleibt sie offen.
function UI:ShowPrioTable(autoClose)
	local f = self:GetPrioTable()
	f.autoClose = autoClose
	f.footer:SetText("")
	for _, p in pairs(PM:Raid().players) do PM:RequestItems(p.p) end
	self:FillPrioTable()
	f:Show()
	f:Raise()
end
