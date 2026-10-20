-- Nachbildung der WoW-Umgebung (Classic Era 1.15.9) für Tests außerhalb des Spiels.
-- Widget-Methoden werden gegen Blizzards API-Dokumentation geprüft:
-- Ein Aufruf einer nicht existierenden Methode löst einen Fehler aus.

local TESTDIR = TESTDIR or "."
local API = dofile(TESTDIR .. "/widget_api.lua")

local mock = {
	chat = {},        -- Zeilen im eigenen Chatfenster
	sent = {},        -- gesendete Chatnachrichten {msg, channel}
	given = {},       -- GiveMasterLoot-Aufrufe
	events = {},      -- registrierte Frames je Ereignis
	now = 1000,       -- GetTime()
	clock = 1791800000, -- time()
	focus = nil,
	timers = {},
	widgets = {},     -- alle erzeugten Widgets, für Prüfungen der Texte
}
_G.MOCK = mock

-------------------------------------------------------------------------------
-- Widgets
-------------------------------------------------------------------------------

local function set(groups)
	local s = {}
	for _, g in ipairs(groups) do
		assert(API[g], "API-Gruppe fehlt: " .. g)
		for _, m in ipairs(API[g]) do s[m] = true end
	end
	return s
end

local BASE = { "SimpleObjectAPI", "SimpleFrameScriptObjectAPI", "SimpleScriptRegionAPI", "SimpleScriptRegionResizingAPI" }
local function with(extra)
	local t = {}
	for _, g in ipairs(BASE) do t[#t + 1] = g end
	for _, g in ipairs(extra) do t[#t + 1] = g end
	return set(t)
end

local ALLOWED = {
	Frame = with({ "SimpleFrameAPI" }),
	Button = with({ "SimpleFrameAPI", "SimpleButtonAPI" }),
	CheckButton = with({ "SimpleFrameAPI", "SimpleButtonAPI", "SimpleCheckboxAPI" }),
	EditBox = with({ "SimpleFrameAPI", "SimpleEditBoxAPI" }),
	ScrollFrame = with({ "SimpleFrameAPI", "SimpleScrollFrameAPI" }),
	Slider = with({ "SimpleFrameAPI", "SimpleSliderAPI" }),
	FontString = with({ "SimpleRegionAPI", "SimpleFontStringAPI", "SimpleFontAPI" }),
	Texture = with({ "SimpleRegionAPI", "SimpleTextureBaseAPI", "SimpleTextureAPI" }),
}
-- Blizzards neues Dropdown (DropdownButton mit WowStyle1DropdownTemplate): Button plus Mixin-Methoden
ALLOWED.DropdownButton = with({ "SimpleFrameAPI", "SimpleButtonAPI" })
for _, m in ipairs({ "SetupMenu", "GenerateMenu", "SetSelectionTranslator", "SetDefaultText", "OverrideText" }) do
	ALLOWED.DropdownButton[m] = true
end
ALLOWED.GameTooltip = with({ "SimpleFrameAPI" })
for _, m in ipairs({ "SetOwner", "SetText", "AddLine", "AddDoubleLine", "SetLootItem", "SetHyperlink", "IsOwned", "ClearLines", "NumLines" }) do
	ALLOWED.GameTooltip[m] = true
end

local Impl = {}
local Widget = {}
local WidgetMT = {
	__index = function(t, k)
		local kind = rawget(t, "_kind")
		local first = type(k) == "string" and k:sub(1, 1) or ""
		if first:match("%u") then
			if not ALLOWED[kind][k] then
				error(("Unbekannte Methode %s für %s %s"):format(k, kind, tostring(rawget(t, "_name"))), 2)
			end
			return Impl[k] or function() return nil end
		end
		return nil
	end,
}

local function CreateWidget(kind, name, parent)
	local o = setmetatable({
		_kind = kind, _name = name, _parent = parent, _shown = true, _scripts = {},
		_w = 0, _h = 0, _points = {},
	}, WidgetMT)
	if name then _G[name] = o end
	mock.widgets[#mock.widgets + 1] = o
	return o
end
mock.CreateWidget = CreateWidget

function Impl:SetScript(name, fn) self._scripts[name] = fn end
function Impl:GetScript(name) return self._scripts[name] end
function Impl:HookScript(name, fn)
	local old = self._scripts[name]
	self._scripts[name] = function(...)
		if old then old(...) end
		return fn(...)
	end
end
function Impl:Show()
	local was = self._shown
	self._shown = true
	if not was and self._scripts.OnShow then self._scripts.OnShow(self) end
end
function Impl:Hide()
	local was = self._shown
	self._shown = false
	if was and self._scripts.OnHide then self._scripts.OnHide(self) end
end
function Impl:IsShown() return self._shown end
function Impl:IsVisible()
	local o = self
	while o do
		if not o._shown then return false end
		o = o._parent
	end
	return true
end
function Impl:SetShown(v) if v then self:Show() else self:Hide() end end
function Impl:RegisterEvent(ev)
	mock.events[ev] = mock.events[ev] or {}
	mock.events[ev][self] = true
end
function Impl:UnregisterEvent(ev) if mock.events[ev] then mock.events[ev][self] = nil end end
function Impl:CreateFontString(name, layer, template)
	local fs = CreateWidget("FontString", name, self)
	fs._template = template
	return fs
end
function Impl:CreateTexture(name, layer, template, sub) return CreateWidget("Texture", name, self) end
function Impl:GetName() return self._name end
function Impl:GetParent() return self._parent end
function Impl:SetText(t)
	self._text = t
	if self._kind == "EditBox" and self._scripts.OnTextChanged then self._scripts.OnTextChanged(self, false) end
end
function Impl:GetText() return self._text end
function Impl:SetWidth(w) self._w = w end
function Impl:SetHeight(h) self._h = h end
function Impl:SetSize(w, h) self._w, self._h = w, h end
function Impl:GetWidth() return self._w end
function Impl:GetHeight() return self._h end
function Impl:SetPoint(...) self._points[#self._points + 1] = { ... } end
function Impl:ClearAllPoints() self._points = {} end
function Impl:GetStringHeight()
	local t = self._text or ""
	local n = 1
	for _ in t:gmatch("\n") do n = n + 1 end
	return n * 12
end
function Impl:IsTruncated() return false end
function Impl:SetChecked(v) self._checked = v and true or false end
function Impl:GetChecked() return self._checked end
function Impl:SetFocus() mock.focus = self end
function Impl:ClearFocus() if mock.focus == self then mock.focus = nil end end
function Impl:HasFocus() return mock.focus == self end
function Impl:SetTextColor(r, g, b) self._color = { r, g, b } end
function Impl:SetColorTexture(r, g, b, a) self._colorTex = { r, g, b, a } end
function Impl:SetTexture(t) self._texture = t end
function Impl:Insert(t) self._text = (self._text or "") .. t end
function Impl:SetMinMaxValues(lo, hi) self._min, self._max = lo, hi end
function Impl:SetValue(v)
	if self._min then v = math.max(self._min, math.min(self._max, v)) end
	self._value = v
	if self._scripts.OnValueChanged then self._scripts.OnValueChanged(self, v, false) end
end
function Impl:GetValue() return self._value end
function Impl:GetCenter() return 100, 100 end
function Impl:GetEffectiveScale() return 1 end
function Impl:LockHighlight() self._locked = true end
function Impl:SetEnabled(v) self._disabled = not v end
function Impl:IsEnabled() return not self._disabled end
function Impl:UnlockHighlight() self._locked = false end
-- Dropdown: Menü erzeugen, angezeigter Text ist der ausgewählte Eintrag
function Impl:SetupMenu(generator)
	self._menuGen = generator
	self:GenerateMenu()
end
function Impl:GenerateMenu()
	local entries, root = {}, {}
	function root:CreateRadio(text, isSelected, setSelected, data)
		entries[#entries + 1] = { text = text, isSelected = isSelected, setSelected = setSelected, data = data }
		return { SetTooltip = function() end }
	end
	function root:SetTag() end
	if self._menuGen then self._menuGen(self, root) end
	self._entries = entries
	self._selected = nil
	for _, e in ipairs(entries) do
		if e.isSelected(e.data) then self._selected = e.text end
	end
end
function mock.PickDropdown(dropdown, index)
	local e = assert(dropdown._entries[index], "Dropdown-Eintrag fehlt: " .. tostring(index))
	e.setSelected(e.data)
	dropdown:GenerateMenu()
end
function Impl:SetHyperlinksEnabled(v) self._hyperlinks = v and true or false end
-- GameTooltip
function Impl:SetOwner(owner) self._owner = owner; self._lines = {} end
function Impl:IsOwned(owner) return self._owner == owner end
function Impl:AddLine(t) self._lines = self._lines or {}; self._lines[#self._lines + 1] = t end
function Impl:SetLootItem(slot) self._lines = { "LootItem " .. tostring(slot) } end
function Impl:SetHyperlink(link)
	assert(type(link) == "string" and link:match("^item:%d+"), "SetHyperlink erwartet item:..., bekam " .. tostring(link))
	self._lines = { link }
end

local TEMPLATES = {}
function TEMPLATES.BackdropTemplate(o)
	o.SetBackdrop = function(self, b) self._backdrop = b end
	o.SetBackdropColor = function(self, r, g, b, a) self._bgColor = { r, g, b, a } end
	o.SetBackdropBorderColor = function() end
end
function TEMPLATES.UIPanelButtonTemplate(o)
	o.Left = CreateWidget("Texture", nil, o)
	o.Middle = CreateWidget("Texture", nil, o)
	o.Right = CreateWidget("Texture", nil, o)
	o.Text = CreateWidget("FontString", o._name and (o._name .. "Text"), o)
end
function TEMPLATES.UIPanelCloseButton(o) end
function TEMPLATES.WowStyle1DropdownTemplate(o)
	o.Text = CreateWidget("FontString", nil, o)
	o.Arrow = CreateWidget("Texture", nil, o)
end
function TEMPLATES.UIPanelScrollFrameTemplate(o)
	o.ScrollBar = CreateWidget("Slider", o._name and (o._name .. "ScrollBar"), o)
end
function TEMPLATES.UICheckButtonTemplate(o)
	o.Text = CreateWidget("FontString", o._name and (o._name .. "Text"), o)
	o.text = o.Text
end
function TEMPLATES.InputBoxTemplate(o)
	assert(o._name, "InputBoxTemplate braucht einen Namen")
	o.Left = CreateWidget("Texture", nil, o)
	o.Middle = CreateWidget("Texture", nil, o)
	o.Right = CreateWidget("Texture", nil, o)
end
function TEMPLATES.UISliderTemplateWithLabels(o)
	assert(o._name, "UISliderTemplateWithLabels braucht einen Namen")
	o.Text = CreateWidget("FontString", o._name .. "Text", o)
	o.Low = CreateWidget("FontString", o._name .. "Low", o)
	o.High = CreateWidget("FontString", o._name .. "High", o)
	o.Thumb = CreateWidget("Texture", o._name .. "Thumb", o)
end
function TEMPLATES.MasterLooterPlayerTemplate(o)
	o.Bg = CreateWidget("Texture", nil, o)
	o.Highlight = CreateWidget("Texture", nil, o)
	o.Name = CreateWidget("FontString", nil, o)
	o:SetScript("OnEnter", function(self)
		self.Highlight:Show()
		if self.tooltip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.tooltip, 1, 1, 1)
		end
	end)
	o:SetScript("OnClick", function(self) MasterLooterPlayerFrame_OnClick(self) end)
end

local KINDS = { FRAME = "Frame", BUTTON = "Button", CHECKBUTTON = "CheckButton", EDITBOX = "EditBox", SCROLLFRAME = "ScrollFrame", SLIDER = "Slider", DROPDOWNBUTTON = "DropdownButton", GAMETOOLTIP = "GameTooltip" }

function CreateFrame(kind, name, parent, template)
	local k = KINDS[kind:upper()]
	assert(k, "CreateFrame: unbekannter Typ " .. tostring(kind))
	local o = CreateWidget(k, name, parent)
	if template then
		for t in template:gmatch("[^,%s]+") do
			assert(TEMPLATES[t], "CreateFrame: unbekanntes Template " .. t)
			TEMPLATES[t](o)
		end
	end
	return o
end

-------------------------------------------------------------------------------
-- Globale Objekte und Konstanten
-------------------------------------------------------------------------------

UIParent = CreateWidget("Frame", "UIParent")
WorldFrame = CreateWidget("Frame", "WorldFrame")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) mock.chat[#mock.chat + 1] = msg end }
GameTooltip = CreateWidget("GameTooltip", "GameTooltip", UIParent)
UISpecialFrames = {}
ChatFontNormal, GameFontHighlight, GameFontNormal = {}, {}, {}
GameFontNormalSmall, GameFontHighlightSmall, GameFontDisableSmall, GameFontNormalLarge = {}, {}, {}, {}
YES, NO = "Ja", "Nein"
function GetLocale() return mock.locale or "deDE" end
StaticPopupDialogs = {}
function StaticPopup_Show(name, arg1, arg2, data)
	local d = StaticPopupDialogs[name]
	assert(d, "StaticPopup fehlt: " .. name)
	mock.popup = { name = name, arg = arg1, arg2 = arg2, data = data, text = d.text:format(arg1 or "", arg2 or "") }
end
-- Klick auf einen Link wie im Chat (ItemRef.lua)
mock.itemRefs = {}
function SetItemRef(link, text, button, frame)
	mock.itemRefs[#mock.itemRefs + 1] = { link = link, text = text, button = button, frame = frame }
end
-- Wie Blizzards StaticPopup: OnAccept(self, data)
function mock.AcceptPopup()
	local p = mock.popup
	mock.popup = nil
	StaticPopupDialogs[p.name].OnAccept({ data = p.data }, p.data)
end
mock.shift = false
function IsShiftKeyDown() return mock.shift end
function InCombatLockdown() return false end
Minimap = CreateWidget("Frame", "Minimap", UIParent)
mock.cursor = { 150, 120 }
function GetCursorPosition() return mock.cursor[1], mock.cursor[2] end
mock.cursorItem = nil
function GetCursorInfo() if mock.cursorItem then return "item", mock.cursorItem end end
function ClearCursor() mock.cursorItem = nil end
ITEM_QUALITY_COLORS = {
	[0] = { hex = "|cff9d9d9d" }, [1] = { hex = "|cffffffff" }, [2] = { hex = "|cff1eff00" },
	[3] = { hex = "|cff0070dd" }, [4] = { hex = "|cffa335ee" },
}
ChatFrameUtil = { InsertLink = function(text) return false end }

-- Plündermethode und -grenze
mock.lootMethod, mock.mlRaid, mock.threshold = 2, 1, 2
mock.lootCalls = {}
C_PartyInfo = {
	GetLootMethod = function() return mock.lootMethod, nil, mock.mlRaid end,
	SetLootMethod = function(method, name)
		mock.lootCalls[#mock.lootCalls + 1] = { "method", method, name }
		mock.lootMethod = method
		for i, r in ipairs(mock.raid) do
			if r[1] == name then mock.mlRaid = i end
		end
		return true
	end,
}
function SetLootThreshold(q)
	mock.lootCalls[#mock.lootCalls + 1] = { "threshold", q }
	if not mock.thresholdStuck then mock.threshold = q end
end
MAX_RAID_MEMBERS = 40
SlashCmdList = {}
RAID_CLASS_COLORS = {
	MAGE = { r = 0.25, g = 0.78, b = 0.92 }, PRIEST = { r = 1, g = 1, b = 1 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
	PALADIN = { r = 0.96, g = 0.55, b = 0.73 }, DRUID = { r = 1, g = 0.49, b = 0.04 }, WARLOCK = { r = 0.53, g = 0.53, b = 0.93 },
	HUNTER = { r = 0.67, g = 0.83, b = 0.45 }, ROGUE = { r = 1, g = 0.96, b = 0.41 }, SHAMAN = { r = 0, g = 0.44, b = 0.87 },
}

-- deutsche Client-Texte (Annahme für die Tests; im Spiel liefert WoW die echten)
RANDOM_ROLL_RESULT = "%s würfelt. Ergebnis: %d (%d-%d)"
LOOT_ITEM = "%s bekommt Beute: %s."
LOOT_ITEM_MULTIPLE = "%s bekommt Beute: %sx%d."
LOOT_ITEM_SELF = "Ihr bekommt Beute: %s."
LOOT_ITEM_SELF_MULTIPLE = "Ihr bekommt Beute: %sx%d."
ERR_LOOT_MASTER_INV_FULL = "Das Inventar dieses Spielers ist voll."
ERR_LOOT_MASTER_UNIQUE_ITEM = "Dieser Spieler hat bereits genug davon."
ERR_LOOT_MASTER_OTHER = "Dieser Spieler kann diese Beute nicht erhalten."
ERR_LOOT_PLAYER_NOT_FOUND = "Spieler nicht gefunden."

ceil, floor, max, min, mod = math.ceil, math.floor, math.max, math.min, math.fmod
tinsert, tremove, wipe = table.insert, table.remove, function(t) for k in pairs(t) do t[k] = nil end return t end
time = function() return mock.clock end
date = function(fmt, t) return os.date(fmt, t) end
GetTime = function() return mock.now end

C_Timer = { After = function(sec, fn) mock.timers[#mock.timers + 1] = fn end }
function mock.RunTimers()
	local t = mock.timers
	mock.timers = {}
	for _, fn in ipairs(t) do fn() end
end

-------------------------------------------------------------------------------
-- Gruppe
-------------------------------------------------------------------------------

mock.player = "Arcanaa"
mock.raid = {} -- { name, classFile, online }
mock.inRaid = true

function IsInRaid() return mock.inRaid and #mock.raid > 0 end
function IsInGroup() return #mock.raid > 0 end
function GetNumGroupMembers() return #mock.raid end
function GetNumSubgroupMembers() return math.max(#mock.raid - 1, 0) end
function GetRaidRosterInfo(i)
	local r = mock.raid[i]
	if not r then return nil end
	return r[1], 0, r.group or 1, 60, r[2], r[2], "Onyxias Hort", r[3] ~= false, false, nil, false
end
function UnitName(unit)
	if unit == "player" then return mock.player end
	if unit == "NPC" then return mock.trade and mock.trade.partner end
	local i = tonumber(unit:match("party(%d)"))
	return i and mock.raid[i + 1] and mock.raid[i + 1][1] or nil
end
function UnitClass(unit) return "Magier", "MAGE" end
function UnitIsConnected() return true end
function UnitIsGroupLeader() return true end
function UnitIsGroupAssistant() return false end
function Ambiguate(name) return (name:gsub("%-.*$", "")) end

-- /roll des eigenen Charakters: Ergebnis kommt als Systemmeldung zurück
mock.randomCalls = {}
function RandomRoll(low, high)
	mock.randomCalls[#mock.randomCalls + 1] = { low, high }
	local value = mock.nextRandom or low
	mock.Fire("CHAT_MSG_SYSTEM", RANDOM_ROLL_RESULT:format(mock.player, value, low, high))
end

function SendChatMessage(msg, channel, language, target)
	assert(#msg <= 255, "Chatnachricht zu lang (" .. #msg .. "): " .. msg)
	assert(not msg:find("|", 1, true) or msg:find("|Hitem:", 1, true), "Ungültige |-Sequenz: " .. msg)
	assert(channel ~= "WHISPER" or (target and target ~= ""), "Flüstern ohne Ziel")
	mock.sent[#mock.sent + 1] = { msg = msg, channel = channel, target = target }
end
mock.inGuild = true
function IsInGuild() return mock.inGuild end

-------------------------------------------------------------------------------
-- Items
-------------------------------------------------------------------------------

local ITEMS = {
	[16914] = { "Krone des Netherwinds", 4, 4, 1, "Stoff", "INVTYPE_HEAD" },
	[16929] = { "Schädelkappe der Nemesis", 4, 4, 1, "Stoff", "INVTYPE_HEAD" },
	[18422] = { "Kopf von Onyxia", 4 }, [18423] = { "Kopf von Onyxia", 4 },
	[17075] = { "Vis'kag der Blutvergießer", 4, 2, 7, "Einhandschwerter", "INVTYPE_WEAPON" },
	[17965] = { "Gelber Sack voller Edelsteine", 3 }, [17962] = { "Blauer Sack voller Edelsteine", 3 },
	[16955] = { "Krone des Richturteils", 4, 4, 4, "Platte", "INVTYPE_HEAD", { "PALADIN" } },
	[17966] = { "Rucksack aus Onyxias Haut", 4 },
	[16921] = { "Heiligenschein der Erhabenheit", 4 }, [16900] = { "Bedeckung des Stormrage", 4 },
	[18813] = { "Ring der Bindung", 4, 4, 0, "Verschiedenes", "INVTYPE_FINGER" },
	[18205] = { "Eskhandars Halsband", 4, 4, 0, "Verschiedenes", "INVTYPE_NECK" }, [17011] = { "Lavakern", 4 },
	-- nur für die Tests der Tragbarkeit
	[99001] = { "Testplattenhandschuhe", 4, 4, 4, "Platte", "INVTYPE_HAND" },
	[99002] = { "Testdolch der Schildhand", 4, 2, 15, "Dolche", "INVTYPE_WEAPONOFFHAND" },
	[99003] = { "Testzauberstab", 4, 2, 19, "Zauberstäbe", "INVTYPE_RANGEDRIGHT" },
	[99004] = { "Testrobe der Priester", 4, 4, 1, "Stoff", "INVTYPE_ROBE", { "PRIEST" } },
	-- nur für die Tests von „An Entzauberer“ ohne Würfelrunde, niemand hat Prio darauf
	[99005] = { "Testumhang", 3, 4, 1, "Stoff", "INVTYPE_CLOAK" },
	[99006] = { "Testschwert", 2, 2, 7, "Einhandschwerter", "INVTYPE_WEAPON" },
	[99007] = { "Testkette", 4, 4, 0, "Verschiedenes", "INVTYPE_NECK" },
	[2589] = { "Leinenstoff", 0 },
	[18259] = { "Formel: Waffe - Zauberkraft", 4, 9, 8, "Verzauberkunst" },
	[20861] = { "Bronzeskarabäus", 2, 12, 0, "Quest" }, [20863] = { "Tonskarabäus", 2, 12, 0, "Quest" },
	[4000] = { "Graues Zeug", 0 }, [15000] = { "Grünes Teil", 2 }, [19229] = { "Sechs der Bestien", 4 },
	[4500] = { "Weißes Zeug", 1 },
	[21761] = { "Schlüssel für einen Skarabäuskasten", 1, 13, 0, "Schlüssel" },
	[21762] = { "Schlüssel für einen großen Skarabäuskasten", 1, 13, 0, "Schlüssel" },
	[19872] = { "Schneller Razzashiraptor", 4, 15, 5, "Reittier" },
	[21218] = { "Blauer Qirajiresonanzkristall", 3, 15, 0, "Plunder" },
	[19726] = { "Blutrebe", 2, 7, 0, "Handwerkswaren" }, [19698] = { "Zulianische Münze", 2, 15, 0, "Plunder" },
	[19939] = { "Gri'leks Blut", 2, 15, 0, "Plunder" }, [19940] = { "Renatakis Zahn", 2, 15, 0, "Plunder" },
	[19941] = { "Wushoolays Mähne", 2, 15, 0, "Plunder" }, [19942] = { "Hazza'rahs Traumfaden", 2, 15, 0, "Plunder" },
	[21214] = { "Foliant des Frostblitzes XI", 3, 9, 0, "Buch" },
	[19802] = { "Herz von Hakkar", 4, 12, 0, "Quest" },
	[19707] = { "Rotes Schmuckstück der Hakkari", 3, 12, 0, "Quest" },
}
-- Items, deren Daten der Client noch nicht geladen hat: leerer Link „[]“, kein Symbol
mock.uncached = {}
local QCOLOR = { [0] = "ff9d9d9d", [1] = "ffffffff", [2] = "ff1eff00", [3] = "ff0070dd", [4] = "ffa335ee" }
function mock.Link(id)
	local it = ITEMS[id]
	return ("|c%s|Hitem:%d::::::::60:::::::|h[%s]|h|r"):format(QCOLOR[it[2]], id, it[1])
end
-- Itemdaten: Name, Qualität, Klasse, Unterklasse, Unterklassen-Name, Platz, Klassen laut Tooltip.
-- Ohne Angabe: Rüstung „Verschiedenes“, das alle tragen können.
local TYPE_NAMES = { [2] = "Waffe", [4] = "Rüstung", [9] = "Rezept" }
function GetItemInfo(id)
	id = tonumber(id)
	local it = ITEMS[id]
	if not it or mock.uncached[id] then return nil end
	return it[1], mock.Link(id), it[2], 60, 60, TYPE_NAMES[it[3] or 4] or "Verschiedenes", it[5] or "Verschiedenes", 1,
		it[6] or "", "Interface\\Icons\\Item" .. id
end
function GetItemInfoInstant(id)
	id = tonumber(id)
	local it = ITEMS[id]
	if not it then return nil end
	return id, TYPE_NAMES[it[3] or 4] or "Verschiedenes", it[5] or "Verschiedenes", it[6] or "", "Interface\\Icons\\Item" .. id,
		it[3] or 4, it[4] or 0
end

-- Unsichtbarer Tooltip zum Auslesen: Zeilen als <Name>TextLeftN, mit „Klassen: …“
-- für Items mit Klassenbeschränkung. Ohne geladene Daten nur „wird abgerufen“.
ITEM_CLASSES_ALLOWED = "Klassen: %s"
RETRIEVING_ITEM_INFO = "Gegenstandsinformationen werden abgerufen"
LOCALIZED_CLASS_NAMES_MALE = {
	WARRIOR = "Krieger", PALADIN = "Paladin", HUNTER = "Jäger", ROGUE = "Schurke", PRIEST = "Priester",
	SHAMAN = "Schamane", MAGE = "Magier", WARLOCK = "Hexenmeister", DRUID = "Druide",
}
LOCALIZED_CLASS_NAMES_FEMALE = {
	WARRIOR = "Kriegerin", PALADIN = "Paladin", HUNTER = "Jägerin", ROGUE = "Schurkin", PRIEST = "Priesterin",
	SHAMAN = "Schamanin", MAGE = "Magierin", WARLOCK = "Hexenmeisterin", DRUID = "Druidin",
}
mock.tooltipScans = 0
function TEMPLATES.GameTooltipTemplate(o)
	o._scanLines = {}
	o.ClearLines = function(self) self._scanLines = {} end
	o.NumLines = function(self) return #self._scanLines end
	o.SetHyperlink = function(self, link)
		mock.tooltipScans = mock.tooltipScans + 1
		local id = tonumber(tostring(link):match("item:(%d+)"))
		local it = id and ITEMS[id]
		local lines = {}
		if it and not mock.uncached[id] then
			lines[1] = it[1]
			if it[7] then
				local names = {}
				for _, token in ipairs(it[7]) do names[#names + 1] = LOCALIZED_CLASS_NAMES_MALE[token] end
				lines[#lines + 1] = ITEM_CLASSES_ALLOWED:format(table.concat(names, ", "))
			end
		else
			lines[1] = RETRIEVING_ITEM_INFO
		end
		self._scanLines = lines
		for i, text in ipairs(lines) do
			local fs = _G[self._name .. "TextLeft" .. i] or CreateWidget("FontString", self._name .. "TextLeft" .. i, self)
			fs:SetText(text)
		end
	end
end
C_Item = { GetItemInfo = GetItemInfo, GetItemInfoInstant = GetItemInfoInstant, RequestLoadItemDataByID = function() end }

-- Handel: mock.trade = { partner = Name, items = { {itemID, Anzahl}, ... } } bei offenem Fenster
mock.trade = nil
function GetTradePlayerItemLink(i)
	local it = mock.trade and mock.trade.items[i]
	return it and mock.Link(it[1]) or nil
end
function GetTradePlayerItemInfo(i)
	local it = mock.trade and mock.trade.items[i]
	if not it then return nil end
	local info = ITEMS[it[1]]
	return info[1], "Interface\\Icons\\Item" .. it[1], it[2] or 1, info[2], nil, false, false, it[1]
end
ERR_TRADE_COMPLETE = "Handel abgeschlossen."
-- Abgeschlossener Handel; das Fenster schließt, bevor die Meldung kommt.
function mock.Trade(partner, items)
	mock.trade = { partner = partner, items = items }
	mock.Fire("TRADE_SHOW")
	mock.Fire("TRADE_PLAYER_ITEM_CHANGED", 1)
	mock.Fire("TRADE_ACCEPT_UPDATE", 1, 1)
	mock.trade = nil
	mock.Fire("TRADE_CLOSED")
	mock.Fire("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
	mock.RunTimers()
end
function HandleModifiedItemClick(link) mock.modifiedClick = link end

-------------------------------------------------------------------------------
-- Plündern
-------------------------------------------------------------------------------

mock.loot = {}       -- Slots: { id = itemID, qty = 1 } oder false (geleert)
mock.candidates = {} -- Namen in Server-Reihenfolge
mock.isML = true

function IsMasterLooter() return mock.isML end

-- Instanz: { Name, Typ, ID } oder nil außerhalb von Instanzen
mock.instance = nil
function GetInstanceInfo()
	local i = mock.instance
	if not i then return "Östliche Königreiche", "none", 0, "", 0, 0, false, 0, 0, nil end
	return i[1], i[2], 3, "40 Spieler", 40, 0, false, i[3], 40, nil
end
function GetLootThreshold() return mock.threshold end
LOOT_SLOT_NONE, LOOT_SLOT_ITEM, LOOT_SLOT_MONEY = 0, 1, 2
function GetNumLootItems() return #mock.loot end
-- Wie im Spiel: Vergebene Plätze bleiben stehen, Typ 0, mit leerem Link ohne Item-ID.
function GetLootSlotType(slot)
	local s = mock.loot[slot]
	if not s then return LOOT_SLOT_NONE end
	return s.money and LOOT_SLOT_MONEY or LOOT_SLOT_ITEM
end
function GetLootSourceInfo(slot)
	if mock.loot[slot] then return mock.lootSource, 1 end
end
function GetLootSlotLink(slot)
	local s = mock.loot[slot]
	if s == false then return "|cffffffff|Hitem:::::::::60::::::::::|h[]|h|r" end
	if not s or s.money then return nil end
	if mock.uncached[s.id] then return ("|cffffffff|Hitem:%d::::::::60:::::::|h[]|h|r"):format(s.id) end
	return mock.Link(s.id)
end
function GetLootSlotInfo(slot)
	local s = mock.loot[slot]
	if not s then return nil end
	if s.money then return "Interface\\Icons\\INV_Misc_Coin_01", "12 Gold", 0, nil, 0, false end
	if mock.uncached[s.id] then return nil, "", s.qty or 1, nil, nil, false end
	local it = ITEMS[s.id]
	return "Interface\\Icons\\Item" .. s.id, it[1], s.qty or 1, nil, it[2], false
end
local CLASSES = { Magier = "MAGE", Priester = "PRIEST", Krieger = "WARRIOR", Paladin = "PALADIN", Druide = "DRUID", Hexenmeister = "WARLOCK", ["Jäger"] = "HUNTER", Schurke = "ROGUE" }
function GetMasterLootCandidate(slot, i)
	local name = mock.candidates[i]
	if not name then return nil end
	local cls = "Magier"
	for _, r in ipairs(mock.raid) do
		if r[1] == name then
			for de, tok in pairs(CLASSES) do if tok == r[2] then cls = de end end
		end
	end
	return name, cls, CLASSES[cls]
end
function GiveMasterLoot(slot, index)
	mock.given[#mock.given + 1] = { slot = slot, index = index }
end

function hooksecurefunc(tbl, name, func)
	if type(tbl) == "string" then tbl, name, func = _G, tbl, name end
	local orig = tbl[name]
	assert(type(orig) == "function", "hooksecurefunc: " .. tostring(name) .. " ist keine Funktion")
	tbl[name] = function(...)
		local r = { orig(...) }
		func(...)
		return unpack(r)
	end
end

-- Blizzards Plündermeister-Liste (Classic Era, LootFrame.lua), unverändert nachgebaut
LootFrame = CreateWidget("Frame", "LootFrame", UIParent)
LootFrame._shown = false
MasterLooterFrame = CreateWidget("Frame", "MasterLooterFrame", UIParent)
MasterLooterFrame._shown = false
MasterLooterFrame.player1 = CreateFrame("Button", nil, MasterLooterFrame, "MasterLooterPlayerTemplate")

local buttonsToHide = {}
local function MasterLooterPlayerSort(pInfo1, pInfo2)
	if pInfo1.class == pInfo2.class then
		return pInfo1.name < pInfo2.name
	else
		return pInfo1.class < pInfo2.class
	end
end

function MasterLooterFrame_UpdatePlayers()
	local playerInfo = {}
	for i = 1, MAX_RAID_MEMBERS do
		local name, class, className = GetMasterLootCandidate(LootFrame.selectedSlot, i)
		if name then
			local pInfo = {}
			pInfo["index"] = i
			pInfo["name"] = name
			pInfo["class"] = class
			pInfo["className"] = className
			tinsert(playerInfo, pInfo)
		end
	end
	table.sort(playerInfo, MasterLooterPlayerSort)

	local numColumns = ceil(#playerInfo / 10)
	numColumns = max(numColumns, 2)
	local numRows = ceil(#playerInfo / numColumns)
	local row = 0
	local column = 0
	local shownButtons = {}
	for i = 1, MAX_RAID_MEMBERS do
		if playerInfo[i] then
			row = row + 1
			if row > numRows then
				row = 1
				column = column + 1
			end
			local buttonIndex = column * 10 + row
			local playerFrame = MasterLooterFrame["player" .. buttonIndex]
			if not playerFrame then
				playerFrame = CreateFrame("BUTTON", nil, MasterLooterFrame, "MasterLooterPlayerTemplate")
				MasterLooterFrame["player" .. buttonIndex] = playerFrame
				if mod(row, 2) == 0 then
					playerFrame.Bg:SetColorTexture(0, 0, 0, 0)
				end
			end
			playerFrame.id = playerInfo[i].index
			playerFrame.Name:SetText(playerInfo[i].name)
			local color = RAID_CLASS_COLORS[playerInfo[i].className]
			playerFrame.Name:SetTextColor(color.r, color.g, color.b)
			playerFrame:Show()
			if buttonsToHide[playerFrame] then buttonsToHide[playerFrame] = nil end
			shownButtons[playerFrame] = 1
			if playerFrame.Name:IsTruncated() then
				playerFrame.tooltip = playerInfo[i].name
			else
				playerFrame.tooltip = nil
			end
		else
			break
		end
	end
	for playerFrame in pairs(buttonsToHide) do playerFrame:Hide() end
	buttonsToHide = shownButtons
end

mock.originals = { GiveMasterLoot = GiveMasterLoot, MasterLooterFrame_UpdatePlayers = MasterLooterFrame_UpdatePlayers }

-- /reload nachstellen: Ereignisse und Hooks zurücksetzen.
function mock.ResetUI()
	mock.events = {}
	GiveMasterLoot = mock.originals.GiveMasterLoot
	MasterLooterFrame_UpdatePlayers = mock.originals.MasterLooterFrame_UpdatePlayers
end

-- SavedVariables wie WoW schreiben: jede Tabelle als eigene Kopie.
function mock.Serialize(v, indent)
	indent = indent or ""
	local t = type(v)
	if t == "string" then return string.format("%q", v) end
	if t == "number" or t == "boolean" or t == "nil" then return tostring(v) end
	assert(t == "table", "nicht speicherbar: " .. t)
	local parts = {}
	for k, x in pairs(v) do
		local key = type(k) == "string" and string.format("[%q]", k) or ("[" .. tostring(k) .. "]")
		parts[#parts + 1] = indent .. "  " .. key .. " = " .. mock.Serialize(x, indent .. "  ")
	end
	return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

function MasterLooterFrame_Show()
	MasterLooterFrame:Show()
	MasterLooterFrame_UpdatePlayers()
end

function MasterLooterPlayerFrame_OnClick(self)
	MasterLooterFrame.slot = LootFrame.selectedSlot
	MasterLooterFrame.candidateId = self.id
	GiveMasterLoot(MasterLooterFrame.slot, MasterLooterFrame.candidateId)
	MasterLooterFrame:Hide()
end

function ScrollingEdit_OnCursorChanged(self, x, y, w, h) self.cursorOffset, self.cursorHeight = y, h end
function ScrollingEdit_OnUpdate() end

-------------------------------------------------------------------------------
-- Ereignisse und Helfer
-------------------------------------------------------------------------------

function mock.Fire(event, ...)
	for frame in pairs(mock.events[event] or {}) do
		local fn = frame._scripts.OnEvent
		if fn then fn(frame, event, ...) end
	end
end

function mock.Roll(name, value, low, high)
	mock.Fire("CHAT_MSG_SYSTEM", RANDOM_ROLL_RESULT:format(name, value, low or 1, high or 100))
end

-- source: GUID der Leiche; ohne Angabe ist jedes Öffnen eine neue Leiche.
mock.corpse = 0
function mock.OpenLoot(slots, source)
	mock.corpse = mock.corpse + 1
	mock.lootSource = source or ("Creature-0-0-0-0-" .. mock.corpse)
	mock.loot = slots
	LootFrame._shown = true
	mock.Fire("LOOT_OPENED", false)
end

function mock.CloseLoot()
	LootFrame._shown = false
	MasterLooterFrame._shown = false
	mock.Fire("LOOT_CLOSED")
end

-- Plündermeister klickt Item an und wählt einen Spieler in der Liste.
function mock.AssignViaList(slot, playerName, confirm)
	LootFrame.selectedSlot = slot
	MasterLooterFrame_Show()
	local btn
	for i = 1, 40 do
		local b = MasterLooterFrame["player" .. i]
		if b and b._shown and b.Name:GetText() == playerName then btn = b end
	end
	assert(btn, "Spieler nicht in der Plündermeister-Liste: " .. playerName)
	btn._scripts.OnClick(btn, "LeftButton")
	if confirm ~= false then
		mock.loot[slot] = false
		mock.Fire("LOOT_SLOT_CLEARED", slot)
	end
	return btn
end

-- Sichtbare Namen der Plündermeister-Liste in Anzeige-Reihenfolge (spaltenweise).
function mock.ListOrder()
	local out = {}
	for col = 0, 3 do
		for row = 1, 10 do
			local b = MasterLooterFrame["player" .. (col * 10 + row)]
			if b and b._shown then out[#out + 1] = b.Name:GetText() end
		end
	end
	return out
end

function mock.LastChat(n)
	return mock.chat[#mock.chat - (n or 0)]
end

function mock.ChatContains(text)
	for _, l in ipairs(mock.chat) do
		if l:find(text, 1, true) then return l end
	end
	return nil
end

function mock.SentContains(text)
	for _, s in ipairs(mock.sent) do
		if s.msg:find(text, 1, true) then return s end
	end
	return nil
end

return mock
