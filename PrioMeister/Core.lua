-- PrioMeister – Core.lua
-- Datenbank, Ereignisse, Gruppenliste, Chat-Ausgabe, Rollen, Plündermethode
-- und Slash-Befehle.

local ADDON, ns = ...
local L = ns.Logic
local T = ns.T or function(s) return s end
local Popup = ns.Popup or function(name, def) StaticPopupDialogs[name] = def return def end

local PM = CreateFrame("Frame", "PrioMeisterEventFrame")
ns.PM = PM
PM.version = "1.24.0"
PM.roster = {}
PM.lootItems = {}
PM.pending = {}
PM.noPrioSeen = {}
PM.roleBatch = {}

local format = string.format

local DEFAULTS = {
	enabled = true,           -- Addon aktiv
	language = "auto",        -- Sprache: auto (nach der Spielsprache), de oder en
	awardsToRaid = true,      -- Vergaben im Raidchat (für das Protokoll eines anderen Spielers)
	tierHints = true,         -- Würfelstufen (99, 98 ...) im Chat nennen
	reportWrongRolls = true,  -- falsche Würfelbereiche im Raidchat melden
	tierChangesToRaid = true, -- Änderungen der Würfelstufe von Hand im Raidchat melden
	secondaryRolls = true,    -- 50er-Würfe für Zweitchar oder Zweitskillung
	recipeRolls = true,       -- Rezepte ohne Würfelstufen verwürfeln
	recipePrio = false,       -- Rezepte dürfen auf Prio stehen
	mountPrio = false,        -- Reittiere dürfen auf Prio stehen
	raidWarning = false,      -- Würfelaufrufe als Schlachtzugswarnung
	prio0Mode = 3,            -- 3: Prio 1+2+3 gleich, 2: Prio 1+2 gleich
	alwaysShow = false,       -- Panel auch ohne Plündermeister-Rolle
	sortMasterLoot = true,    -- Plündermeister-Liste umsortieren
	panelEnabled = true,
	showMinimap = true,
	minimapAngle = 200,
	announceLoot = true,      -- Beute beim Öffnen im Raidchat ansagen (mit Prios)
	announceDelay = 90,       -- dieselbe Beute frühestens nach so vielen Sekunden erneut ansagen (0–600)
	showTableAfterImport = true, -- Prio-Tabelle nach dem Import kurz anzeigen
	shareChannel = "GUILD",   -- Vergaben teilen: GUILD, OFFICER, RAID, PARTY oder WHISPER
	shareTarget = "",         -- Vergaben teilen: Name beim Flüstern
	autoLootQualities = {},   -- Plünderhelfer: diese Qualitäten automatisch, z. B. {[0]=true, [1]=true}
	helperLowChat = false,    -- graue und weiße Items an den Plünderhelfer im Chat melden
	treasurerChat = false,    -- Vergaben an den Schatzmeister im Raidchat melden
	confirmEpicWinner = true, -- „An Name“: bei epischen Items vorher nachfragen
	deButtonQuality = 2,      -- „An Entzauberer“ an jedem Item im Panel ab dieser Qualität, false: nie
	usableRolls = true,       -- Würfe auf Items, die die Klasse nicht tragen kann, zählen nicht
	lootLists = L.DefaultLootLists(), -- Schatzmeister: Item-IDs je Instanz, 0 = alle Instanzen
	rollLists = L.DefaultRollLists(), -- immer verwürfeln: Item-IDs je Instanz, 0 = alle Instanzen
}

local LOOT_METHOD_MASTER = 2 -- Enum.LootMethod.Masterlooter
PM.LOOT_METHOD_MASTER = LOOT_METHOD_MASTER
-- Feste Texte nach Schlüssel, beim Zugriff in der eingestellten Sprache. english: eigene
-- englische Texte, wenn ein deutsches Wort anderswo anders übersetzt wird („Gruppe“).
local function Translated(texts, english)
	return setmetatable({}, { __index = function(_, k)
		if english and ns.lang == "en" and english[k] then return english[k] end
		local v = texts[k]
		return v and T(v)
	end })
end
PM.METHOD_TEXT = Translated({
	[0] = "Jeder gegen jeden", [1] = "Reihum", [2] = "Plündermeister",
	[3] = "Gruppe", [4] = "Bedarf vor Gier", [5] = "Persönlich",
}, { [0] = "Free for All", [1] = "Round Robin", [2] = "Master Looter", [3] = "Group Loot", [4] = "Need before Greed", [5] = "Personal Loot" })
PM.QUALITY_TEXT = Translated({ [0] = "Grau", [1] = "Weiß", [2] = "Grün", [3] = "Blau", [4] = "Episch" })
PM.ROLES = { "lootHelper", "treasurer", "disenchanter" }
PM.ROLE_TEXT = Translated({ lootHelper = "Plünderhelfer", treasurer = "Schatzmeister", disenchanter = "Entzauberer" })
PM.ROLE_SHORT = Translated({ lootHelper = "PH", treasurer = "SM", disenchanter = "DE" })

local function deepcopy(v)
	if type(v) ~= "table" then return v end
	local t = {}
	for k, x in pairs(v) do t[k] = deepcopy(x) end
	return t
end
ns.deepcopy = deepcopy

local function refreshUI()
	if ns.UI and ns.UI.RefreshAll then ns.UI:RefreshAll() end
end

-------------------------------------------------------------------------------
-- Ausgabe
-------------------------------------------------------------------------------

local PREFIX = "|cff33ff99PrioMeister|r: "

function PM:Print(msg, ...)
	msg = T(msg)
	if select("#", ...) > 0 then msg = format(msg, ...) end
	DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
end

function PM:GroupChannel()
	if IsInRaid() then return "RAID" end
	if IsInGroup() then return "PARTY" end
	return nil
end

function PM:RollCallChannel()
	if IsInRaid() then
		if self.db.settings.raidWarning and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
			return "RAID_WARNING"
		end
		return "RAID"
	end
	return self:GroupChannel()
end

-- Sendet in den Gruppenchat oder den angegebenen Kanal (target beim Flüstern);
-- allein oder im Testmodus nur lokal.
function PM:Send(msg, channel, target)
	channel = channel or self:GroupChannel()
	if self.testMode or not channel then
		self:Print("|cff999999[%s]|r %s", channel and self:ShareLabel(channel, target) or T("nur lokal"), msg)
		return
	end
	local send = SendChatMessage or (C_ChatInfo and C_ChatInfo.SendChatMessage)
	if send then send(msg, channel, nil, target) end
end

-- Kanäle zum Teilen. SAY, YELL und öffentliche Kanäle verlangen in Classic einen
-- Tastendruck und gehen nicht zeilenweise per Timer.
PM.SHARE_CHANNELS = {
	{ "GUILD", "Gilde" }, { "OFFICER", "Offiziere" }, { "RAID", "Schlachtzug" },
	{ "PARTY", "Gruppe" }, { "WHISPER", "Flüstern" },
}

function PM:ShareLabel(channel, target)
	for _, c in ipairs(self.SHARE_CHANNELS) do
		if c[1] == channel then
			if channel == "WHISPER" and target then return format(T("Flüstern an %s"), target) end
			return T(c[2])
		end
	end
	return channel
end

-- Entzaubern lassen sich nur Rüstung (Klasse 4) und Waffen (Klasse 2). Die Klasse kennt der
-- Client auch ohne geladene Itemdaten.
function PM:Disenchantable(itemID)
	local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	local classID = instant and itemID and select(6, instant(itemID))
	return classID == 2 or classID == 4
end

function PM:QualityLabel(q)
	local text = self.QUALITY_TEXT[q] or tostring(q)
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
	if c and c.hex then return c.hex .. text .. "|r" end
	return text
end

-------------------------------------------------------------------------------
-- Datenbank
-------------------------------------------------------------------------------

function PM:InitDB()
	if type(PrioMeisterDB) ~= "table" then PrioMeisterDB = {} end
	local db = PrioMeisterDB
	db.settings = db.settings or {}
	for k, v in pairs(DEFAULTS) do
		if db.settings[k] == nil then db.settings[k] = deepcopy(v) end
	end
	if (db.dbVersion or 1) < 2 then
		-- seit 1.1: Vergaben gehen standardmäßig in den Raidchat
		db.settings.awardsToRaid = true
	end
	local oldVersion = db.dbVersion or 1
	db.dbVersion = 8
	db.pins = db.pins or {}
	db.history = db.history or {}
	db.instanceNames = db.instanceNames or {}
	if oldVersion < 4 then
		-- seit 1.3: Die Item-Liste gehört dem Schatzmeister und gilt je Instanz.
		-- Bisherige Einträge gelten in allen Instanzen, Skarabäen stehen schon bei AQ.
		local old, lists = db.settings.autoLootItems, db.settings.lootLists
		if type(old) == "table" then
			lists[L.ALL_INSTANCES] = lists[L.ALL_INSTANCES] or {}
			for id in pairs(old) do
				if not ((lists[509] and lists[509][id]) or (lists[531] and lists[531][id])) then
					lists[L.ALL_INSTANCES][id] = true
				end
			end
		end
		db.settings.autoLootItems = nil
	end
	if oldVersion < 5 then
		-- seit 1.5: Qualitäten des Plünderhelfers einzeln statt „bis …“
		local below = db.settings.autoLootBelow
		if type(below) == "number" then
			for q = 0, 3 do
				if q < below then db.settings.autoLootQualities[q] = true end
			end
		end
		db.settings.autoLootBelow = nil
		-- Blutrebe und die Klassenbücher aus AQ20 gehen an den Schatzmeister.
		local roll, loot = db.settings.rollLists, db.settings.lootLists
		if roll[309] then roll[309][L.BLOODVINE] = nil end
		loot[309] = loot[309] or {}
		loot[309][L.BLOODVINE] = true
		loot[509] = loot[509] or {}
		for _, id in ipairs(L.AQ20_BOOKS) do loot[509][id] = true end
	end
	if oldVersion < 6 then
		-- seit 1.9.4: Schmuckstücke der Hakkari gehen an den Schatzmeister.
		local loot = db.settings.lootLists
		loot[309] = loot[309] or {}
		for _, id in ipairs(L.HAKKARI_BIJOUS) do loot[309][id] = true end
	end
	if type(db.raid) ~= "table" then db.raid = L.NewRaid(time()) end
	local r = db.raid
	r.players = r.players or {}
	r.awards = r.awards or {}
	r.adjust = r.adjust or {}
	r.sessions = r.sessions or {}
	if oldVersion < 3 then
		-- Runden aus älteren Versionen kennen ihre Beute nicht: abschließen,
		-- damit ihre Würfe nicht an spätere Exemplare geraten.
		for _, s in ipairs(r.sessions) do
			s.closed, s.done = true, true
		end
	end
	if oldVersion < 7 and not r.rollLog then
		-- seit 1.17: Wurf-Protokoll für den Export. Die Würfe der noch gespeicherten
		-- Runden des laufenden Raids kommen hinein, ältere Runden kennt das Addon nicht mehr.
		for _, s in ipairs(r.sessions) do
			for _, roll in ipairs(s.rolls or {}) do L.LogRoll(r, s, roll, L.GUIDMapID(s.source)) end
		end
	end
	if oldVersion < 8 then
		-- seit 1.17.1: Würfe, die ein Verzicht zurückgezogen hat, stehen auch im Protokoll so.
		L.RepairRollLog(r)
		for _, h in ipairs(db.history) do L.RepairRollLog(h) end
	end
	self.db = db
end

function PM:IsEnabled()
	return self.db ~= nil and self.db.settings.enabled
end

-- Im Testmodus wird eine Kopie bearbeitet, die echten Daten bleiben unberührt.
function PM:Raid()
	return self.testRaid or self.db.raid
end

function PM:SetOption(key, value)
	self.db.settings[key] = value
	if key == "enabled" and not value and ns.UI then ns.UI:HidePanel() end
	if key == "showMinimap" and ns.UI and ns.UI.UpdateMinimapButton then ns.UI:UpdateMinimapButton() end
	refreshUI()
end

-- Laufenden Raid ins Archiv legen, wenn er Vergaben hat.
function PM:ArchiveCurrentRaid()
	local db = self.db
	local r = db.raid
	if r and r.awards and #r.awards > 0 then
		table.insert(db.history, 1, L.ArchiveEntry(r, time()))
		while #db.history > 30 do table.remove(db.history) end
		-- Wurf-Protokolle sind groß: nur die letzten zehn Raids im Archiv behalten sie.
		for i = 11, #db.history do db.history[i].rollLog = nil end
		return true
	end
	return false
end

-- Früheren Raid fortsetzen: Er wird wieder der laufende Raid mit seinen Vergaben,
-- Würfelstufen und seiner Prioliste, der bisherige laufende Raid kommt ins Archiv.
-- Raids vor 1.14 haben ihre Liste nicht gespeichert, sie starten ohne Liste: Eine
-- fremde Liste fiele nicht auf, eine fehlende schon.
function PM:ReopenRaid(entry)
	local db = self.db
	local index
	for i, h in ipairs(db.history) do
		if h == entry then index = i end
	end
	if not index then
		self:Print("Diesen Raid gibt es nicht mehr im Archiv.")
		return false
	end
	table.remove(db.history, index)
	local archived = self:ArchiveCurrentRaid()
	local r = L.ReopenRaid(entry)
	db.raid = r
	self.noPrioSeen = {}
	self:Print("Raid vom %s fortgesetzt: %d Vergaben, die Würfelstufen gelten weiter.%s", date("%d.%m. %H:%M", r.started or 0),
		L.AwardCount(r), archived and T(" Der bisherige Raid liegt im Archiv.") or "")
	if not next(r.players) then
		self:Print("|cffff4040Für diesen Raid ist keine Prioliste gespeichert|r, er kam vor Version 1.14 ins Archiv. Bitte die Liste importieren, mit „Nur Liste ersetzen“ bleiben Vergaben und Würfelstufen.")
	elseif r.imported then
		self:Print("Es gilt die Prioliste vom %s. Eine neuere Liste importierst du mit „Nur Liste ersetzen“.", date("%d.%m. %H:%M", r.imported))
	end
	self:BindListNames()
	refreshUI()
	return true
end

function PM:NewRaid(silent)
	local db = self.db
	self:ArchiveCurrentRaid()
	db.raid = L.NewRaid(time())
	self.noPrioSeen = {}
	if not silent then
		self:Print("Neuer Raid gestartet: Vergaben und Würfelstufen sind zurückgesetzt.")
	end
	refreshUI()
end

-- Ergebnis: true bei Erfolg; ein Priocheck von priomeister.de ändert die Prioliste nicht
-- und liefert als zweiten Wert "check".
function PM:ImportText(text, newRaid)
	if L.IsPrioCheck(text) then return self:ApplyPrioCheck(text) ~= nil, "check" end
	local players, info = L.ParsePrioList(text)
	if info.players == 0 then
		self:Print("|cffff4040Keine Spieler erkannt.|r Bitte die Liste von priomeister.de vollständig einfügen.")
		return false
	end
	if newRaid then self:NewRaid(true) end
	local r = self.db.raid
	r.players = players
	r.imported = time()
	r.importCount = info.players
	r.meta = info.meta
	self.noPrioSeen = {}

	local prio0 = 0
	for _, p in pairs(players) do
		for _, e in ipairs(L.GetEntries(p, self.db.settings.prio0Mode)) do
			if e.level == 0 then prio0 = prio0 + 1 end
		end
		self:RequestItems(p.p)
	end
	self:Print("%d Spieler importiert (Format %s, %d mit Prio 0)%s.", info.players, T(info.format), prio0,
		newRaid and T(", neuer Raid gestartet") or T(", bisherige Vergaben bleiben"))
	if info.meta then
		local stand = L.FormatStand(info.meta.stand)
		self:Print("Prio-Run %s: %s Spieler, %s Prios%s.", info.meta.run or "?", info.meta.spieler or "?",
			info.meta.prios or "?", stand and (T(", letzte Änderung ") .. stand) or "")
		self:ApplyListRules(info.meta)
	end
	if #info.duplicates > 0 then
		local parts = {}
		for _, d in ipairs(info.duplicates) do
			parts[#parts + 1] = format(T("%s (Stand mit %d Items)"), d.name, d.count)
		end
		self:Print("Doppelt eingetragen, es gilt der letzte Stand mit den meisten Items: %s", table.concat(parts, ", "))
	end
	if #info.skipped > 0 then
		self:Print("|cffffd100%d Zeile(n) nicht erkannt:|r %s", #info.skipped, info.skipped[1])
	end
	self:BindListNames()
	for _, line in ipairs(self:WaitlistLines()) do self:Print(line) end
	self:ReportIgnoredPrios()
	self:CheckPresence()
	refreshUI()
	if self.db.settings.showTableAfterImport and ns.UI.ShowPrioTable then
		ns.UI:ShowPrioTable(PM.TABLE_AUTO_CLOSE)
	end
	return true
end

PM.TABLE_AUTO_CLOSE = 20 -- Sekunden, die die Prio-Tabelle nach dem Import offen bleibt

-- Geladene Prioliste als CSV; Itemnamen aus der CSV, sonst aus dem Spiel.
function PM:PrioListCSV()
	return L.PrioListCSV(self:Raid().players, function(id, csvName)
		if csvName and csvName ~= "" then return csvName end
		return (self:ItemInfo(id)) or ""
	end)
end

-------------------------------------------------------------------------------
-- Gruppe
-------------------------------------------------------------------------------

function PM:UpdateRoster()
	local roster, order = {}, {}
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local name, _, subgroup, _, _, classFile, _, online = GetRaidRosterInfo(i)
			if name then
				local short = Ambiguate and Ambiguate(name, "short") or name
				local key = L.NameKey(short)
				if key then
					roster[key] = { name = short, class = classFile, online = online and true or false }
					order[#order + 1] = { name = short, group = subgroup or 1, index = i }
				end
			end
		end
	else
		local units = { "player" }
		if IsInGroup() then
			for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
		end
		for _, unit in ipairs(units) do
			local name = UnitName(unit)
			local key = L.NameKey(name)
			if key then
				local _, classFile = UnitClass(unit)
				roster[key] = { name = name, class = classFile, online = UnitIsConnected(unit) and true or false }
				order[#order + 1] = { name = name, group = 1, index = #order + 1 }
			end
		end
	end
	-- Reihenfolge wie im Raidfenster: Gruppe 1 bis 8, innerhalb der Gruppe nach Raid-Index
	table.sort(order, function(a, b)
		if a.group ~= b.group then return a.group < b.group end
		return a.index < b.index
	end)
	self.roster = roster
	self.rosterOrder = order
end

-- Prioliste an die Namen im Raid binden (seit 1.23): Steht jemand auf priomeister.de ohne
-- Akzent und heißt im Spiel mit Akzent oder umgekehrt, gilt sein Eintrag unter dem Namen im
-- Spiel. Gespeicherte Vergaben, Würfelstufen und Würfe bleiben unverändert.
function PM:BindListNames()
	if not self.db or not self.db.raid then return end
	for _, m in ipairs(L.BindPlayers(self.db.raid.players, self.roster or {})) do
		self:Print("Prioliste: %s ist %s im Raid.", m.from, m.to)
	end
end

-- Eingegebener Name als Schlüssel: exakt wie im Raid, auf der Prioliste oder unter den
-- Würflern, sonst ohne Akzente, wenn genau einer passt („leryssia“ findet Leryssiá).
function PM:ResolveKey(name)
	local key = L.NameKey(name)
	if not key then return nil end
	local raid, known = self:Raid(), {}
	for _, set in ipairs({ self.roster or {}, raid.players or {}, raid.rolled or {} }) do
		for k in pairs(set) do known[k] = true end
	end
	for _, aw in ipairs(raid.awards or {}) do
		if aw.key then known[aw.key] = true end
	end
	if known[key] then return key end
	return L.MatchFolded({ [key] = true }, known)[key] or key
end

-- Wartelisten aus der Kommentarzeile der Prioliste (seit 1.24), zwischengespeichert:
-- lists[kanonische Item-ID] = { { name, star } }, sets[kanonische Item-ID] = Items des Sets
function PM:Waitlists(raid)
	local meta = (raid or self:Raid()).meta
	local text = meta and meta.wartelisten
	if not text or text == "" then return nil end
	local c = self.waitCache
	if not c or c.text ~= text or c.sets ~= meta.sets then
		c = { text = text, sets = meta.sets, lists = L.ParseWaitlists(text), groups = L.ParseSets(meta.sets) }
		self.waitCache = c
	end
	if not next(c.lists) then return nil end
	return c.lists, c.groups
end

-- Warteliste eines Items im laufenden Raid: { key, name } in Reihenfolge, ohne wer das Item
-- schon hat; Namen wie im Raid. nil ohne Warteliste.
function PM:WaitlistFor(itemID)
	local raid = self:Raid()
	local lists, groups = self:Waitlists(raid)
	if not lists or not itemID then return nil end
	local list = L.WaitlistOrder(raid, L.Canon(itemID), lists, groups, function(name)
		local key = self:ResolveKey(name)
		return key, self:DisplayName(key, name)
	end)
	return #list > 0 and list or nil
end

-- Zeilen für Import und /pm stand: je Item mit Warteliste die Reihenfolge
function PM:WaitlistLines()
	local lists = self:Waitlists()
	if not lists then return {} end
	local ids, lines = {}, {}
	for canon in pairs(lists) do ids[#ids + 1] = canon end
	table.sort(ids)
	for _, canon in ipairs(ids) do
		local names = {}
		for _, w in ipairs(self:WaitlistFor(canon) or {}) do names[#names + 1] = w.name end
		lines[#lines + 1] = format(T("Warteliste %s: %s"), self:ItemLabel(canon),
			#names > 0 and table.concat(names, ", ") or T("alle haben es schon"))
	end
	return lines
end

function PM:RosterList()
	local list = {}
	for key, r in pairs(self.roster) do list[#list + 1] = { key = key, name = r.name } end
	table.sort(list, function(a, b) return L.SortKey(a.name) < L.SortKey(b.name) end)
	return list
end

-- Anwesend = berechtigt für dieses Loot (falls bekannt), sonst online im Raid.
function PM:IsPresent(key, candidates)
	if self.testMode then return true end
	if candidates then return candidates[key] ~= nil end
	local r = self.roster[key]
	return r ~= nil and r.online
end

function PM:IsMember(key)
	if self.testMode then return true end
	return self.roster[key] ~= nil
end

function PM:DisplayName(key, fallback)
	local r = key and self.roster[key]
	if r then return r.name end
	local p = key and self:Raid().players[key]
	if p then return p.name end
	return fallback or key
end

function PM:ClassToken(key)
	local token = self.roster[key] and self.roster[key].class
	if not token then
		local p = self:Raid().players[key]
		token = p and p.token
	end
	return token
end

function PM:ColoredName(key, name)
	name = name or self:DisplayName(key)
	local token = self:ClassToken(key)
	local c = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
	if not c then return name end
	return format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, name)
end

-- Spieler im Raid ohne Eintrag auf der Prioliste.
function PM:NoPrioMembers()
	local res = self:CheckResult()
	if res then return res.none end
	local raid = self:Raid()
	if not next(raid.players) then return {} end
	local list = {}
	for key, r in pairs(self.roster) do
		if not raid.players[key] then list[#list + 1] = r.name end
	end
	return L.SortNames(list)
end

function PM:CheckPresence()
	if not IsInGroup() then return end
	local raid = self:Raid()
	local missing = {}
	for key, p in pairs(raid.players) do
		if not self.roster[key] then missing[#missing + 1] = p.name end
	end
	L.SortNames(missing)
	if #missing > 0 then self:Print("Auf der Prioliste, aber nicht im Raid: %s", table.concat(missing, ", ")) end
	local noPrio = self:NoPrioMembers()
	for _, name in ipairs(noPrio) do self.noPrioSeen[L.NameKey(name)] = true end
	if #noPrio > 0 then
		self:Print("|cffffd100Im Raid ohne Prios:|r %s", table.concat(noPrio, ", "))
	end
end

-- Hinweis, wenn neue Spieler ohne Prio in den Raid kommen.
function PM:ScheduleNoPrioCheck()
	if self.noPrioQueued then return end
	self.noPrioQueued = true
	C_Timer.After(3, function()
		PM.noPrioQueued = false
		PM:CheckNewWithoutPrio()
	end)
end

function PM:CheckNewWithoutPrio()
	if not self:IsEnabled() or not IsInGroup() then return end
	local fresh = {}
	for _, name in ipairs(self:NoPrioMembers()) do
		local key = L.NameKey(name)
		if not self.noPrioSeen[key] then
			self.noPrioSeen[key] = true
			fresh[#fresh + 1] = name
		end
	end
	if #fresh > 0 then
		self:Print("|cffffd100Im Raid ohne Prio:|r %s. Erinnern mit /pm erinnern oder im Fenster unter „Raid“.",
			table.concat(fresh, ", "))
	end
end

function PM:RemindNoPrio()
	local list = self:NoPrioMembers()
	if #list == 0 then
		self:Print("Alle im Raid haben Prios eingetragen.")
		return
	end
	-- Mit Liste oder Priocheck von priomeister.de: Link zum Prio-Run samt PIN
	local check = self:CurrentCheck()
	local meta = check and check.meta or self:Raid().meta
	local link = meta and L.ShortLink(meta.link) or "priomeister.de"
	for _, m in ipairs(L.AppendChunks({}, T("Noch ohne Prio: "), list, format(T(" – bitte Prios auf %s eintragen!"), link))) do
		self:Send(m)
	end
end

-------------------------------------------------------------------------------
-- Priocheck (seit 1.20): Kurzform des Prio-Runs von priomeister.de, wer welche
-- Prios gesetzt hat. Er gilt, bis eine neuere Prioliste importiert wird, und
-- ersetzt solange die Liste beim Blick auf „Im Raid ohne Prio“.
-------------------------------------------------------------------------------

function PM:CurrentCheck()
	local raid = self:Raid()
	local check = raid.check
	if check and (check.t or 0) >= (raid.imported or 0) then return check end
	return nil
end

function PM:CheckResult()
	local check = self:CurrentCheck()
	return check and L.CheckRaid(check, self:RosterList()) or nil
end

function PM:ApplyPrioCheck(text)
	local check = L.ParsePrioCheck(text)
	if not check then return nil end
	check.t = time()
	self:Raid().check = check
	self:PrintCheck()
	refreshUI()
	return check
end

-- Zeilen fürs eigene Chatfenster und den Tooltip im Reiter Raid
function PM:CheckLines()
	local check = self:CurrentCheck()
	if not check then
		return { T("Kein Priocheck geladen. Auf priomeister.de auf der Spielerseite des Prio-Runs unter „Alle Prios“ „Priocheck kopieren“ klicken, hier unter „Importieren …“ einfügen und „Prüfen“ wählen. Die Eintragung kann dabei offen bleiben.") }
	end
	local res = L.CheckRaid(check, self:RosterList())
	local lines = { format(T("Priocheck %s, Stand %s: %d mit Eintrag auf der Seite"), check.meta.run or "", date("%d.%m. %H:%M", check.t), check.count) }
	if #self:RosterList() == 0 then
		lines[#lines + 1] = T("Nicht im Raid: Der Priocheck vergleicht mit den Mitgliedern des Raids.")
		return lines
	end
	lines[#lines + 1] = (#res.none > 0) and (T("|cffffd100Ohne Prios:|r ") .. table.concat(res.none, ", ")) or T("|cff40ff40Alle im Raid haben Prios eingetragen.|r")
	if #res.partial > 0 then
		lines[#lines + 1] = T("|cffffd100Unvollständig:|r")
		for _, p in ipairs(res.partial) do lines[#lines + 1] = format("   %s: %s", p.name, p.detail) end
	end
	lines[#lines + 1] = format(T("Vollständig: %d"), res.complete)
	if res.away > 0 then lines[#lines + 1] = format(T("Mit Eintrag, aber nicht im Raid: %d"), res.away) end
	return lines
end

function PM:PrintCheck()
	for i, line in ipairs(self:CheckLines()) do
		if i == 1 then self:Print(line) else DEFAULT_CHAT_FRAME:AddMessage("  " .. line) end
	end
end

-- Regeln aus der Kommentarzeile von priomeister.de: Dürfen Rezepte und Reittiere auf Prio?
local LIST_RULES = {
	{ key = "rezepte", option = "recipePrio", label = "Rezepte" },
	{ key = "reittiere", option = "mountPrio", label = "Reittiere" },
}

function PM:ApplyListRules(meta)
	local parts = {}
	for _, rule in ipairs(LIST_RULES) do
		local value = meta[rule.key] and meta[rule.key]:lower()
		if value == "prio" or value == "wuerfeln" or value == "würfeln" then
			self.db.settings[rule.option] = value == "prio"
			parts[#parts + 1] = T(rule.label) .. (value == "prio" and T(" auf Prio") or T(" werden gewürfelt"))
		end
	end
	local exceptions = self:ExceptionLabels(meta)
	if #exceptions > 0 then parts[#parts + 1] = T("trotzdem auf Prio: ") .. table.concat(exceptions, ", ") end
	if #parts > 0 then self:Print("Regeln vom Prio-Run übernommen: %s.", table.concat(parts, ", ")) end
end

-- Items, die laut Prio-Run trotz der Regel für Rezepte oder Reittiere auf Prio dürfen:
-- Positivliste von priomeister.de, in der Kommentarzeile „ausnahmen=18259,18260“ (seit 1.19).
function PM:PrioException(itemID)
	local meta = self:Raid().meta
	local text = meta and meta.ausnahmen
	if not text or text == "" then return false end
	local cache = self.exceptionCache
	if not cache or cache.text ~= text then
		cache = { text = text, set = L.ParseIDSet(text) }
		self.exceptionCache = cache
	end
	return cache.set[L.Canon(itemID)] == true
end

-- Ausnahmen als Itemlinks, sonst mit dem Namen aus der Liste
function PM:ExceptionLabels(meta)
	local ids = {}
	for id in pairs(L.ParseIDSet(meta and meta.ausnahmen)) do ids[#ids + 1] = id end
	table.sort(ids)
	local labels = {}
	for i, id in ipairs(ids) do
		local name
		for _, p in pairs(self:Raid().players) do
			for idx = 1, 3 do
				if L.Canon(p.p[idx]) == id and p.pn and p.pn[idx] and p.pn[idx] ~= "" then name = p.pn[idx] end
			end
		end
		labels[i] = self:ItemLabel(id, name)
	end
	return labels
end

-- Stand der geladenen Prioliste, für /pm stand und den Tooltip im Reiter Raid
function PM:ListInfo()
	local r = self:Raid()
	local players, prios = 0, 0
	for _, p in pairs(r.players) do
		players = players + 1
		prios = prios + #L.GetEntries(p, self.db.settings.prio0Mode)
	end
	if players == 0 then return { T("Noch keine Prioliste importiert.") } end
	local lines = { format(T("Prioliste: %d Spieler, %d Prios, importiert %s"), players, prios,
		date("%d.%m. %H:%M", r.imported or time())) }
	local meta = r.meta
	if meta then
		local stand = L.FormatStand(meta.stand)
		lines[#lines + 1] = format(T("Prio-Run %s%s"), meta.run or "", stand and (T(", letzte Änderung auf der Seite ") .. stand) or "")
		local link = L.ShortLink(meta.link)
		if link then lines[#lines + 1] = T("Aktueller Stand und Eintragen: ") .. link end
		local exceptions = self:ExceptionLabels(meta)
		if #exceptions > 0 then lines[#lines + 1] = T("Trotzdem auf Prio: ") .. table.concat(exceptions, ", ") end
		for _, line in ipairs(self:WaitlistLines()) do lines[#lines + 1] = line end
	else
		lines[#lines + 1] = T("Ohne Angaben zum Prio-Run: Die Liste kommt nicht von priomeister.de.")
	end
	return lines
end

-------------------------------------------------------------------------------
-- Items
-------------------------------------------------------------------------------

local GetItemInfoCompat = GetItemInfo or (C_Item and C_Item.GetItemInfo)
local GetItemInfoInstantCompat = GetItemInfoInstant or (C_Item and C_Item.GetItemInfoInstant)

function PM:ItemInfo(itemID)
	if not itemID or itemID == 0 or not GetItemInfoCompat then return nil end
	local name, link, quality, _, _, _, _, _, _, texture = GetItemInfoCompat(itemID)
	return name, link, quality, texture
end

-- Klasse und Unterklasse ohne Server-Anfrage.
function PM:ItemInstant(itemID)
	if not itemID or itemID == 0 or not GetItemInfoInstantCompat then return nil end
	local _, _, subType, _, icon, classID, subClassID = GetItemInfoInstantCompat(itemID)
	return classID, subClassID, subType, icon
end

-- Berufsrezept? Klassenbücher sind Rezepte der Unterklasse „Buch“ und zählen nicht.
function PM:IsRecipe(itemID)
	local classID, subClassID = self:ItemInstant(itemID)
	return classID == L.RECIPE_CLASS and subClassID ~= L.BOOK_SUBCLASS
end

function PM:IsMount(itemID)
	if not itemID then return false end
	if L.MOUNTS[itemID] then return true end
	local classID, subClassID = self:ItemInstant(itemID)
	return classID == L.MISC_CLASS and subClassID == L.MOUNT_SUBCLASS
end

-- Klassen aus einer Tooltip-Zeile wie „Klassen: Magier, Priester“ als Tokens (MAGE …).
function PM:ClassTokensFromText(text)
	local byName = {}
	for token, name in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do byName[name] = token end
	for token, name in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do byName[name] = token end
	local set, any = {}, false
	for part in text:gmatch("[^,]+") do
		local token = byName[L.Trim(part)]
		if token then set[token], any = true, true end
	end
	return any and set or nil
end

-- Klassenbeschränkung aus dem Tooltip des Items, gelesen mit einem unsichtbaren
-- Tooltip. Rückgabe: Klassen und der Text der Zeile, nil ohne Beschränkung.
local scanTooltip
function PM:TooltipClasses(itemID)
	if not scanTooltip then
		scanTooltip = CreateFrame("GameTooltip", "PrioMeisterScanTooltip", nil, "GameTooltipTemplate")
	end
	scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
	scanTooltip:ClearLines()
	scanTooltip:SetHyperlink("item:" .. itemID)
	if not self.classesMatcher then self.classesMatcher = L.FormatToMatcher(ITEM_CLASSES_ALLOWED or "Klassen: %s") end
	for i = 1, scanTooltip:NumLines() do
		local line = _G["PrioMeisterScanTooltipTextLeft" .. i]
		local m = line and L.MatchFormat(self.classesMatcher, line:GetText())
		if m and m[1] then
			local set = self:ClassTokensFromText(m[1])
			if set then return set, m[1] end
		end
	end
	return nil
end

-- Wer ein Item tragen kann, samt Angaben für den Hinweis; nil heißt alle oder
-- unbekannt. Gemerkt wird erst, wenn WoW das Item vollständig geladen hat.
function PM:ItemUsability(itemID)
	if not itemID or not GetItemInfoInstantCompat then return nil end
	self.usability = self.usability or {}
	local known = self.usability[itemID]
	if known ~= nil then return known or nil end
	local _, _, subType, equipLoc, _, classID, subclassID = GetItemInfoInstantCompat(itemID)
	if not classID then return nil end
	local restricted, restrictedText = self:TooltipClasses(itemID)
	local users = L.ItemUsers(classID, subclassID, equipLoc, restricted)
	local info = users and { users = users, restricted = restricted, restrictedText = restrictedText,
		subType = subType, offhand = equipLoc == "INVTYPE_WEAPONOFFHAND" } or false
	if GetItemInfoCompat and GetItemInfoCompat(itemID) then self.usability[itemID] = info end
	return info or nil
end

-- Prüfung für L.AddRoll: Grund, wenn der Spieler das Item mit seiner Klasse nicht tragen kann.
function PM:UnusableCheck(itemID)
	if not self.db.settings.usableRolls then return nil end
	local info = self:ItemUsability(itemID)
	if not info then return nil end
	return function(key)
		local class = self.roster and self.roster[key] and self.roster[key].class
		if not class then return nil end
		return L.UnusableReason(info, class, LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class])
	end
end

-- Beruf eines Rezepts (z. B. "Schmiedekunst"), sonst nil.
function PM:Profession(itemID)
	local classID, subClassID, subType = self:ItemInstant(itemID)
	if classID == L.RECIPE_CLASS and subClassID ~= 0 then return subType end
	return nil
end

function PM:RequestItems(ids)
	if not (C_Item and C_Item.RequestLoadItemDataByID) then return end
	for _, id in ipairs(ids or {}) do
		if id and id > 0 and not self:ItemInfo(id) then C_Item.RequestLoadItemDataByID(id) end
	end
end

-- Anzeigename eines Items: Itemlink, sonst Name aus der CSV.
function PM:ItemLabel(itemID, fallbackName)
	local _, link = self:ItemInfo(itemID)
	if link then return link end
	if fallbackName and fallbackName ~= "" then return "[" .. fallbackName .. "]" end
	return "Item " .. tostring(itemID)
end

-- Art einer Prio, die wegen der Optionen nicht zählt: "recipe", "mount" oder nil.
function PM:IgnoredKind(itemID)
	local s = self.db.settings
	if self:PrioException(itemID) then return nil end
	if self:IsRecipe(itemID) then return (not s.recipePrio) and "recipe" or nil end
	if self:IsMount(itemID) then return (not s.mountPrio) and "mount" or nil end
	return nil
end

-- Prios auf Rezepte und Reittiere, die ignoriert werden. kind: "recipe", "mount" oder nil für beide.
function PM:IgnoredPrioEntries(kind)
	local out = {}
	for _, p in pairs(self:Raid().players) do
		local seen = {}
		for idx = 1, 3 do
			local id = p.p[idx]
			if id and id ~= 0 and not seen[id] then
				seen[id] = true
				local k = self:IgnoredKind(id)
				if k and (kind == nil or kind == k) then
					out[#out + 1] = { name = p.name, itemID = id, level = idx, kind = k, label = self:ItemLabel(id, p.pn[idx]) }
				end
			end
		end
	end
	table.sort(out, function(a, b) return L.SortKey(a.name) < L.SortKey(b.name) end)
	return out
end

function PM:RecipePrioEntries()
	return self:IgnoredPrioEntries("recipe")
end

local IGNORED_TEXT = { recipe = "Rezepte", mount = "Reittiere" }

function PM:ReportIgnoredPrios()
	for _, kind in ipairs({ "recipe", "mount" }) do
		local list = self:IgnoredPrioEntries(kind)
		if #list > 0 then
			local parts = {}
			for _, e in ipairs(list) do parts[#parts + 1] = format("%s %s (Prio %d)", e.name, e.label, e.level) end
			self:Print("|cffffd100%s sind nicht auf Prio möglich, diese Prios werden ignoriert:|r %s",
				T(IGNORED_TEXT[kind]), table.concat(parts, ", "))
		end
	end
end

function PM:AnnounceIgnoredPrios()
	local any = false
	for _, kind in ipairs({ "recipe", "mount" }) do
		local list = self:IgnoredPrioEntries(kind)
		if #list > 0 then
			any = true
			local parts = {}
			for _, e in ipairs(list) do parts[#parts + 1] = format("%s (%s)", e.name, e.label) end
			for _, m in ipairs(L.AppendChunks({}, format(T("%s gehen nicht auf Prio: "), T(IGNORED_TEXT[kind])), parts, T(" – bitte Prio ändern!"))) do
				self:Send(m)
			end
		end
	end
	if not any then self:Print("Niemand hat ein Rezept oder Reittier auf Prio.") end
end

-------------------------------------------------------------------------------
-- Instanzen und Listen des Schatzmeisters
-------------------------------------------------------------------------------

local RAID_NAMES = {}
for _, r in ipairs(L.RAIDS) do RAID_NAMES[r.id] = r.name end

-- Aktuelle Instanz als ID und Name, außerhalb von Instanzen nil.
function PM:CurrentInstance()
	if not GetInstanceInfo then return nil end
	local name, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
	if not instanceID or not instanceType or instanceType == "none" then return nil end
	if name and name ~= "" and self.db then self.db.instanceNames[instanceID] = name end
	return instanceID, name
end

function PM:InstanceName(id)
	if id == L.ALL_INSTANCES then return T("Alle Instanzen") end
	return (self.db.instanceNames and self.db.instanceNames[id]) or (RAID_NAMES[id] and T(RAID_NAMES[id])) or (T("Instanz ") .. tostring(id))
end

-- Listenarten: "treasurer" (bekommt der Schatzmeister) und "roll" (immer verwürfeln)
PM.LIST_SETTING = { treasurer = "lootLists", roll = "rollLists" }

-- Liste einer Art für eine Instanz; create legt eine leere Liste an.
function PM:ItemList(kind, id, create)
	local lists = self.db.settings[self.LIST_SETTING[kind]]
	if not lists[id] and create then lists[id] = {} end
	return lists[id] or {}
end

-- Was hier gilt: Liste aller Instanzen plus Liste der aktuellen Instanz.
function PM:ActiveItemList(kind)
	local out = {}
	for id in pairs(self:ItemList(kind, L.ALL_INSTANCES)) do out[id] = true end
	local current = self:CurrentInstance()
	if current then
		for id in pairs(self:ItemList(kind, current)) do out[id] = true end
	end
	return out
end

function PM:AddListItem(kind, instanceID, itemID)
	itemID = tonumber(itemID)
	if not itemID or itemID <= 0 then return false end
	self:ItemList(kind, instanceID, true)[itemID] = true
	self:RequestItems({ itemID })
	refreshUI()
	return true
end

function PM:RemoveListItem(kind, instanceID, itemID)
	self:ItemList(kind, instanceID)[itemID] = nil
	refreshUI()
end

function PM:ClearList(kind, instanceID)
	self.db.settings[self.LIST_SETTING[kind]][instanceID] = {}
	refreshUI()
end

-------------------------------------------------------------------------------
-- Prio-Auflösung
-------------------------------------------------------------------------------

function PM:ResolveOpts(itemID)
	local s = self.db.settings
	local isRecipe = self:IsRecipe(itemID)
	local isMount = not isRecipe and self:IsMount(itemID)
	return {
		prio0Mode = s.prio0Mode or 3,
		recipe = isRecipe,
		recipeRolls = s.recipeRolls,
		plain = itemID ~= nil and self:ActiveItemList("roll")[itemID] == true,
		mount = isMount,
		ignorePrio = not self:PrioException(itemID) and ((isRecipe and not s.recipePrio) or (isMount and not s.mountPrio)),
		profession = isRecipe and self:Profession(itemID) or nil,
	}
end

-- source: Herkunft des Exemplars (Leiche oder Truhe), damit Verzichte darauf zählen.
function PM:ResolveForItem(itemID, candidates, source)
	local raid = self:Raid()
	local opts = self:ResolveOpts(itemID)
	opts.passed = L.PassesFor(raid, itemID, source)
	opts.unusable = self:UnusableCheck(itemID)
	opts.waitlist = self:WaitlistFor(itemID)
	return L.ResolveItem(raid, itemID, function(key) return self:IsPresent(key, candidates) end, opts)
end

function PM:AwardOpts(itemID, reason, ctx)
	local o = self:ResolveOpts(itemID)
	local s = self.db.settings
	o.reason = reason
	o.ctx = ctx
	o.helper = L.NameKey(s.lootHelper)
	o.treasurer = L.NameKey(s.treasurer)
	o.disenchanter = L.NameKey(s.disenchanter)
	o.listed = itemID and self:ActiveItemList("treasurer")[itemID] or false
	o.waitlist = self:WaitlistFor(itemID)
	return o
end

-------------------------------------------------------------------------------
-- Ereignisse
-------------------------------------------------------------------------------

PM:SetScript("OnEvent", function(self, event, ...)
	local handler = self[event]
	if handler then handler(self, ...) end
end)
PM:RegisterEvent("ADDON_LOADED")
PM:RegisterEvent("PLAYER_LOGIN")

function PM:ADDON_LOADED(name)
	if name == ADDON then
		self:InitDB()
	end
	if self.db then self:ApplyLanguage() end
	if self.db and self.InstallHooks then self:InstallHooks() end
end

-- Sprache nach der Option „Sprache“ und der Spielsprache; Wechsel gilt nach /reload
function PM:ApplyLanguage()
	if ns.SetLanguage then
		ns.SetLanguage(ns.ResolveLanguage(self.db.settings.language, GetLocale and GetLocale() or "deDE"))
	end
end

function PM:PLAYER_LOGIN()
	if not self.db then self:InitDB() end
	self:ApplyLanguage()
	self:InstallHooks()
	self:UpdateRoster()
	self:BindListNames()
	for _, ev in ipairs({
		"GROUP_ROSTER_UPDATE", "LOOT_OPENED", "LOOT_CLOSED", "LOOT_SLOT_CLEARED", "LOOT_SLOT_CHANGED",
		"CHAT_MSG_SYSTEM", "CHAT_MSG_LOOT", "UI_ERROR_MESSAGE", "GET_ITEM_INFO_RECEIVED", "PARTY_LOOT_METHOD_CHANGED",
		"UI_INFO_MESSAGE", "TRADE_SHOW", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_ACCEPT_UPDATE",
	}) do
		self:RegisterEvent(ev)
	end
	if ns.UI and ns.UI.UpdateMinimapButton then ns.UI:UpdateMinimapButton() end
end

function PM:GROUP_ROSTER_UPDATE()
	self:UpdateRoster()
	self:BindListNames()
	refreshUI()
	self:ScheduleNoPrioCheck()
end

function PM:PARTY_LOOT_METHOD_CHANGED()
	refreshUI()
end

function PM:GET_ITEM_INFO_RECEIVED()
	if not self.itemRefreshQueued then
		self.itemRefreshQueued = true
		C_Timer.After(0.3, function()
			PM.itemRefreshQueued = false
			if PM.testMode then PM.testItems = PM:BuildTestItems() end
			-- Daten für ein Item im offenen Plünderfenster nachgeladen: neu einlesen
			if PM.lootOpen and not PM.testMode and PM:IsEnabled() then
				PM:AutoLoot()
				PM:ScanLoot()
				PM:AnnounceLoot()
			end
			refreshUI()
		end)
	end
end

-------------------------------------------------------------------------------
-- Würfe
-------------------------------------------------------------------------------

function PM:CHAT_MSG_SYSTEM(msg)
	if not self:IsEnabled() then return end
	if not self.rollMatcher then self.rollMatcher = L.FormatToMatcher(RANDOM_ROLL_RESULT) end
	local m = L.MatchFormat(self.rollMatcher, msg)
	if not m then return end
	local name, value, low, high = m[1], tonumber(m[2]), tonumber(m[3]), tonumber(m[4])
	if not (name and value and low and high) then return end
	-- eigener Wurf für "Zufällig vergeben"
	local rr = self.randomRoll
	if rr and L.NameKey(name) == L.NameKey(UnitName("player")) and low == 1 and high == rr.n then
		self.randomRoll = nil
		self:FinishRandomAssign(rr, value)
		return
	end
	self:HandleRoll(name, value, low, high)
end

-------------------------------------------------------------------------------
-- Zufällig vergeben: Wurf 1 bis Anzahl der Spieler, gezählt durch die Gruppen
-------------------------------------------------------------------------------

function PM:RandomOrder()
	if self.testMode then
		local names = {}
		for _, p in pairs(self:Raid().players) do names[#names + 1] = p.name end
		return L.SortNames(names)
	end
	local names = {}
	for _, e in ipairs(self.rosterOrder or {}) do names[#names + 1] = e.name end
	return names
end

Popup("PRIOMEISTER_RANDOM", {
	text = "%s\n\nSicher zufällig vergeben?",
	button1 = YES, button2 = NO,
	OnAccept = function(_, data)
		if data then PM:StartRandomAssign(data.itemID, data.link, data.slot) end
	end,
	timeout = 0, whileDead = true, hideOnEscape = true,
})

-- Zufällig vergeben; haben anwesende Spieler Prio darauf oder für dieses
-- Exemplar schon gewürfelt, erst nach Rückfrage.
function PM:RequestRandomAssign(itemID, link, slot)
	if not self:IsEnabled() then
		self:Print("PrioMeister ist ausgeschaltet (Optionen).")
		return
	end
	link = link or self:ItemLabel(itemID)
	local ctx = slot and { source = self:LootSource(slot) } or nil
	local res = self:ResolveForItem(itemID, slot and self:GetCandidates(slot) or nil, ctx and ctx.source)
	local prioText
	if res.top ~= nil then
		local names = {}
		for _, h in ipairs(res.topHolders) do names[#names + 1] = h.name end
		prioText = L.LevelText(res.top) .. ": " .. table.concat(names, ", ")
	end
	local rolls = L.OpenRolls(L.FindSession(self:Raid(), itemID, ctx))
	if prioText or #rolls > 0 then
		StaticPopup_Show("PRIOMEISTER_RANDOM", L.ConfirmText(link, prioText, rolls), nil,
			{ itemID = itemID, link = link, slot = slot })
		return
	end
	self:StartRandomAssign(itemID, link, slot)
end

function PM:StartRandomAssign(itemID, link, slot)
	if not self:IsEnabled() then
		self:Print("PrioMeister ist ausgeschaltet (Optionen).")
		return
	end
	local names = self:RandomOrder()
	if #names == 0 then
		self:Print("Niemand in der Gruppe.")
		return
	end
	link = link or self:ItemLabel(itemID)
	self.randomRoll = { itemID = itemID, link = link, slot = slot, names = names, n = #names }
	self:Send(L.RandomAnnouncement(link, #names), self:RollCallChannel())
	RandomRoll(1, #names)
end

function PM:FinishRandomAssign(rr, value)
	local name = rr.names[value]
	if not name then return end
	local key = L.NameKey(name)
	self.lastRandom = { item = L.Canon(rr.itemID), key = key, place = value, of = rr.n, t = GetTime() }
	local result = string.format(T("%s zufällig vergeben: Platz %d von %d ist %s"), rr.link, value, rr.n, name)
	if self.testMode or not rr.slot then
		self:ConfirmAward({ key = key, name = name, itemID = rr.itemID, link = rr.link, reason = "random", place = value, of = rr.n })
		return
	end
	local _, slotID = self:LootSlotItem(rr.slot)
	local stillThere = self.lootOpen and slotID ~= nil and L.Canon(slotID) == L.Canon(rr.itemID)
	if stillThere and self:BelowThreshold(rr.slot) then
		-- unter der Plündergrenze: selbst plündern und handeln, der Handel wird eingetragen
		self:Send(result)
		self:Print("%s liegt unter der Plündergrenze. Selbst plündern und an %s handeln, das Addon trägt den Handel ein.", rr.link, name)
		return
	end
	if stillThere and self:GiveSlot(rr.slot, name, "random", { place = value, of = rr.n }) then
		if not self.db.settings.awardsToRaid then self:Send(result) end
		return
	end
	self:Send(result .. T(" – kann die Beute gerade nicht erhalten"))
	self:Print("%s kann %s nicht automatisch bekommen. Von Hand geben oder erneut „Zufällig vergeben“.", name, rr.link)
end

function PM:HandleRoll(name, value, low, high)
	local raid = self:Raid()
	-- Wer gewürfelt hat, steht im Reiter Raid mit seiner Würfelstufe, auch mit 100
	-- und auch, wenn der Wurf erst nach dem Ende der Runde kam.
	local key = L.NameKey(name)
	if key and self:IsMember(key) then
		raid.rolled = raid.rolled or {}
		raid.rolled[key] = name
	end
	local s = L.ActiveSession(raid)
	if s and s.closed then s = nil end
	if L.IsPass(low, high) and self:HandlePass(name, s) then return end
	if not s then return end
	local r = L.AddRoll(raid, s, name, value, low, high, time(), function(key) return self:IsMember(key) end,
		self:UnusableCheck(s.itemID))
	L.LogRoll(raid, s, r, self:CurrentInstance())
	if (r.status == "range" or r.unusable) and self.db.settings.reportWrongRolls then
		self:Send(L.WrongRollMessage(r))
	end
	refreshUI()
end

-------------------------------------------------------------------------------
-- Verzicht mit /roll 1: Wer Prio hat und das Item nicht will, würfelt /roll 1.
-- Das gilt nur für dieses Exemplar, danach ist die nächste Prio dran oder es
-- gibt einen Wurf ohne Prio.
-------------------------------------------------------------------------------

-- Ein Verzicht bezieht sich auf das offene Plünderfenster oder, für ein paar
-- Minuten, auf das zuletzt geschlossene. So auch die zuletzt angesagte Beute.
local RECENT_SECONDS = 300

function PM:PassableLoot()
	if self.testMode then return self.testItems or {}, false end
	if self.lootOpen then return self.lootItems, true end
	local rl = self.recentLoot
	if rl and GetTime() - rl.t <= RECENT_SECONDS then return rl.items, false end
	return {}, false
end

-- Exemplare in der Beute, auf die ein Spieler Prio hat und noch nicht verzichtet
-- hat, je Item und Herkunft einmal: { itemID, link, source, slot, level, name }
function PM:PassCandidates(key)
	local items, open = self:PassableLoot()
	local out, seen = {}, {}
	for _, it in ipairs(items) do
		local id = tostring(it.source) .. ":" .. tostring(L.Canon(it.itemID))
		if not seen[id] then
			seen[id] = true
			local slot = open and it.slot or nil
			local res = self:ResolveForItem(it.itemID, slot and self:GetCandidates(slot) or nil, it.source)
			-- je Exemplar einmal, die Warteliste vor der Prio
			local hit
			for _, h in ipairs(res.waitlist or {}) do
				if not hit and h.key == key and not h.passed and not h.unusable then hit = h end
			end
			for lvl = 0, 3 do
				for _, h in ipairs(res.levels[lvl]) do
					if not hit and h.key == key and not h.passed and not h.unusable then hit = h end
				end
			end
			if hit then
				out[#out + 1] = { itemID = it.itemID, link = it.loading and self:ItemLabel(it.itemID) or it.link,
					source = it.source, slot = slot, level = hit.level, name = hit.name }
			end
		end
	end
	return out
end

-- /roll 1. Gilt der laufenden Prio-Runde, wenn der Spieler darin würfeln darf.
-- Hat er in der laufenden Runde ohne Prio gewürfelt, zieht er dort seinen Wurf
-- zurück, das erledigt L.AddRoll. Sonst gilt der Verzicht dem Exemplar der Beute,
-- auf das er Prio hat, bei mehreren dem der laufenden Runde oder dem zuletzt
-- angesagten. Rückgabe true: erledigt, die Würfelrunde bekommt den Wurf nicht.
function PM:HandlePass(name, s)
	local key = L.NameKey(name)
	if not key then return false end
	if s and s.mode == "prio" and s.eligible[key] then
		if s.winners[key] or (s.passed and s.passed[key]) then return false end
		self:RegisterPass({ itemID = s.itemID, link = s.link, source = s.source, level = s.level,
			slot = self:SlotForSession(s) }, key, s.eligible[key])
		return true
	end
	if s and s.mode ~= "prio" then
		for _, r in ipairs(s.rolls) do
			if r.key == key and (r.status == "ok" or r.status == "range") then return false end
		end
	end
	local cands = self:PassCandidates(key)
	local pick = (#cands == 1) and cands[1] or nil
	if #cands > 1 then
		local function find(item, source)
			for _, c in ipairs(cands) do
				if L.Canon(c.itemID) == item and c.source == source then return c end
			end
		end
		if s then pick = find(s.item, s.source) end
		local call = self.lastCall
		if not pick and call and GetTime() - call.t <= RECENT_SECONDS then pick = find(call.item, call.source) end
		if not pick then
			local links = {}
			for _, c in ipairs(cands) do links[#links + 1] = c.link end
			self:Print("%s hat /roll 1 gewürfelt, hat aber auf mehrere Items Prio: %s. Erst das gemeinte Item mit „Ansagen“ oder „Würfeln“ aufrufen, dann noch einmal /roll 1.",
				name, table.concat(links, ", "))
			return true
		end
	end
	if not pick then return false end
	self:RegisterPass(pick, key, pick.name)
	return true
end

-- Verzicht eintragen: im Protokoll, in der laufenden Runde dieses Exemplars und im
-- Chat. Bleibt in einer Prio-Runde niemand übrig, schließt sie.
-- t: itemID, link, source, level, slot (Loot-Platz bei offenem Plünderfenster)
function PM:RegisterPass(t, key, name)
	local raid = self:Raid()
	name = self:DisplayName(key, name)
	local now = time()
	local s = L.ActiveSession(raid)
	local inSession = s ~= nil and not s.closed and s.item == L.Canon(t.itemID) and s.source == t.source
	local aw = L.RecordPass(raid, { key = key, name = name, itemID = t.itemID, link = t.link or self:ItemLabel(t.itemID),
		level = t.level, source = t.source, session = inSession and s.id or nil }, now)
	if inSession and (s.mode ~= "prio" or s.eligible[key]) then
		L.PassInSession(s, key, name, now, raid)
		if s.mode == "prio" and L.RemainingEligible(s) == 0 then s.closed, s.closedByPass = true, true end
	end
	local res = self:ResolveForItem(t.itemID, t.slot and self:GetCandidates(t.slot) or nil, t.source)
	for i, m in ipairs(L.PassMessages(aw, res)) do
		if i == 1 then self:Print(m) else DEFAULT_CHAT_FRAME:AddMessage("  " .. m) end
		if self.db.settings.awardsToRaid then self:Send(m) end
	end
	refreshUI()
	return aw
end

-- Startet eine Würfelrunde und sagt sie an. forceFree: freier Wurf trotz Prio.
-- ctx.source: Herkunft der Beute, damit Würfe beim richtigen Exemplar landen.
function PM:StartRoll(itemID, link, res, forceFree, ctx)
	if not self:IsEnabled() then
		self:Print("PrioMeister ist ausgeschaltet (Optionen).")
		return
	end
	local raid = self:Raid()
	local opts = self:ResolveOpts(itemID)
	if not res then res = self:ResolveForItem(itemID, nil, ctx and ctx.source) end
	self:RememberCall(itemID, ctx)
	if forceFree then
		res = {
			top = nil, topHolders = {}, levels = res.levels, ignored = res.ignored,
			recipe = opts.recipe, profession = opts.profession,
			mode = L.NoPrioMode(opts),
		}
	end
	link = link or self:ItemLabel(itemID)
	-- Läuft für dieses Exemplar schon eine offene Runde gleicher Art, nur erneut ansagen.
	-- Nach einem Verzicht kann eine andere Prio-Stufe dran sein, die bekommt eine neue Runde.
	local s = L.ActiveSession(raid)
	local mode = (res.top ~= nil) and "prio" or res.mode
	local same = s and not s.closed and s.item == L.Canon(itemID) and s.mode == mode and L.SessionMatches(s, ctx)
		and (mode ~= "prio" or s.level == res.top)
	if not same then
		s = L.NewSession(raid, itemID, link, res, time(), {
			secondary = self.db.settings.secondaryRolls,
			source = ctx and ctx.source,
			copies = self:CopiesInLoot(itemID, ctx and ctx.source),
		})
	elseif s.tiebreak then
		-- Während eines Stichwurfs wird der Stichwurf erneut angesagt.
		self:AnnounceTiebreak(s)
		return s
	end
	local msgs = L.BuildRollCall(raid, res, link, self:PresentMembers(), {
		tierHints = self.db.settings.tierHints, copies = s.copies,
	})
	for i, m in ipairs(msgs) do
		self:Send(m, (i == 1) and self:RollCallChannel() or self:GroupChannel())
	end
	refreshUI()
	return s
end

-- Zuletzt angesagtes oder verwürfeltes Exemplar: Hat jemand auf mehrere Items
-- der Beute Prio, gilt sein /roll 1 diesem.
function PM:RememberCall(itemID, ctx)
	self.lastCall = { item = L.Canon(itemID), source = ctx and ctx.source, t = GetTime() }
end

-- Einzigen Prio-Halter ansagen. ctx.source: Herkunft der Beute.
function PM:Announce(itemID, link, res, ctx)
	if not self:IsEnabled() then return end
	res = res or self:ResolveForItem(itemID, nil, ctx and ctx.source)
	link = link or self:ItemLabel(itemID)
	self:RememberCall(itemID, ctx)
	local msgs = L.BuildRollCall(self:Raid(), res, link, self:PresentMembers(), {
		tierHints = self.db.settings.tierHints,
	})
	for i, m in ipairs(msgs) do
		self:Send(m, (i == 1) and self:RollCallChannel() or self:GroupChannel())
	end
end

function PM:PresentMembers()
	local list = {}
	for _, m in ipairs(self:RosterList()) do
		if self:IsPresent(m.key) then list[#list + 1] = m end
	end
	return list
end

-- Gleichstand an der Spitze: Stichwurf mit derselben Stufe wie beim ersten Wurf.
function PM:StartTiebreak()
	local s = L.ActiveSession(self:Raid())
	if not s or s.closed then
		self:Print("Keine Würfelrunde aktiv.")
		return
	end
	if not L.StartTiebreak(s) then
		self:Print("Kein Gleichstand an der Spitze.")
		return
	end
	self:AnnounceTiebreak(s)
	refreshUI()
end

function PM:AnnounceTiebreak(s)
	for i, m in ipairs(L.TiebreakMessages(s, s.link or "?")) do
		self:Send(m, (i == 1) and self:RollCallChannel() or self:GroupChannel())
	end
end

function PM:EndSession()
	local s = L.ActiveSession(self:Raid())
	if s then s.closed = true end
	refreshUI()
end

-------------------------------------------------------------------------------
-- Vergaben bestätigen und protokollieren
-------------------------------------------------------------------------------

-- p = { key, name, itemID, link, slot, quality, reason, source }
-- Per Handel zusätzlich: viaTrade, count (Stückzahl), session (Würfelrunde des Empfängers)
function PM:ConfirmAward(p)
	if not self:IsEnabled() then return end
	local raid = self:Raid()
	local name = self:DisplayName(p.key, p.name)
	local ctx = (p.session and { session = p.session }) or (p.source and { source = p.source }) or nil
	-- von Hand oder per Handel nachgereichte Zufallsvergabe (z. B. nach vollem Inventar) erkennen
	local lr = self.lastRandom
	local window = p.viaTrade and 7200 or 600
	if not p.reason and lr and lr.key == p.key and lr.item == L.Canon(p.itemID) and GetTime() - lr.t < window then
		p.reason, p.place, p.of = "random", lr.place, lr.of
	end
	if p.reason == "random" then self.lastRandom = nil end
	local opts = self:AwardOpts(p.itemID, p.reason, ctx)
	opts.place, opts.of = p.place, p.of
	local aw = L.BuildAward(raid, p.key, name, p.itemID, p.link, opts, time())
	aw.quality = p.quality
	aw.instance = self:CurrentInstance()
	if p.count and p.count > 1 then aw.count = p.count end
	L.RecordAward(raid, aw)

	if aw.kind == "helper" or aw.kind == "treasurer" then
		self:QueueRoleAward(aw)
	else
		local line = L.AwardLine(aw)
		local tierNote = ""
		if aw.kind == "free" then
			tierNote = format(T(" – würfelt ab jetzt mit /roll %d"), L.AllowedMax(raid, p.key))
		end
		self:Print(line .. tierNote)
		if self.db.settings.awardsToRaid then
			self:Send(line .. (self.db.settings.tierHints and tierNote or ""))
		end
	end

	-- Würfelrunde abschließen, wenn kein weiteres Exemplar dieser Beute mehr daliegt.
	-- Per Handel: wenn so viele Stück vergeben sind, wie in der Beute lagen.
	local s = L.SessionById(raid, aw.session)
	if s and p.viaTrade then
		s.given = (s.given or 0) + (p.count or 1)
		if s.given >= (s.copies or 1) then s.closed, s.done = true, true end
	elseif s and not self:LootHasItem(p.itemID, p.slot) then
		s.closed, s.done = true, true
	end
	refreshUI()
	return aw
end

-- Vergaben an Plünderhelfer und Schatzmeister werden gesammelt gemeldet.
function PM:QueueRoleAward(aw)
	self.roleBatch[#self.roleBatch + 1] = aw
	if not self.roleFlushQueued then
		self.roleFlushQueued = true
		C_Timer.After(1.5, function() PM:FlushRoleAwards() end)
	end
end

local ROLE_OF_KIND = { helper = "lootHelper", treasurer = "treasurer" }

-- Graue und weiße Items an den Plünderhelfer nur mit Häkchen „im Chat melden“.
-- Vergaben an den Schatzmeister stehen immer im eigenen Chatfenster, im
-- Raidchat nur mit Häkchen.
function PM:FlushRoleAwards()
	self.roleFlushQueued = false
	local batch = self.roleBatch
	self.roleBatch = {}
	local s = self.db.settings
	local groups, order = {}, {}
	for _, aw in ipairs(batch) do
		local gkey = aw.kind .. ":" .. aw.name
		local g = groups[gkey]
		if not g then
			g = { kind = aw.kind, name = aw.name, items = {}, counts = {}, low = 0 }
			groups[gkey] = g
			order[#order + 1] = g
		end
		if aw.kind == "helper" and aw.quality and aw.quality < 2 then
			g.low = g.low + 1
		else
			local id = aw.itemID or 0
			if not g.counts[id] then
				g.counts[id] = 0
				g.items[#g.items + 1] = { id = id, link = aw.link or self:ItemLabel(id) }
			end
			g.counts[id] = g.counts[id] + (aw.count or 1)
		end
	end
	for _, g in ipairs(order) do
		local parts = {}
		for _, it in ipairs(g.items) do
			local n = g.counts[it.id]
			parts[#parts + 1] = it.link .. ((n > 1) and (" x" .. n) or "")
		end
		if g.low > 0 and s.helperLowChat then parts[#parts + 1] = format(T("%d graue/weiße Items"), g.low) end
		if #parts > 0 then
			local prefix = format(T("%s %s erhält: "), self.ROLE_TEXT[ROLE_OF_KIND[g.kind]], g.name)
			local toRaid = s.awardsToRaid and (g.kind ~= "treasurer" or s.treasurerChat)
			for _, m in ipairs(L.AppendChunks({}, prefix, parts, "")) do
				self:Print(m)
				if toRaid then self:Send(m) end
			end
		end
	end
end

-- Änderungen der Würfelstufe in den Gruppenchat, damit der Mitschreiber den Stand kennt.
function PM:PostTierChanges()
	return self.db.settings.tierChangesToRaid and (IsInGroup() or self.testMode) and true or false
end

function PM:UndoLast()
	local aw = L.UndoLast(self:Raid())
	if aw then
		self:Print("Rückgängig gemacht: %s", L.AwardLine(aw))
		if aw.kind == "tier" and self:PostTierChanges() then
			self:Send(format(T("%s: Änderung der Würfelstufe zurückgenommen, wieder %d"), aw.name, aw.from or 100))
		elseif aw.kind == "pass" and self.db.settings.awardsToRaid then
			if aw.level == L.WAITLIST then
				self:Send(format(T("%s: Verzicht auf %s zurückgenommen, wieder auf dem Warteplatz"), aw.name, aw.link or T("das Item")))
			else
				self:Send(format(T("%s: Verzicht auf %s zurückgenommen, wieder Prio %s"), aw.name, aw.link or T("das Item"), tostring(aw.level)))
			end
		elseif aw.kind == "given" and self.db.settings.awardsToRaid then
			self:Send(L.HandoverUndoLine(aw))
		end
	else
		self:Print("Keine Vergabe zum Rückgängigmachen.")
	end
	refreshUI()
end

-------------------------------------------------------------------------------
-- Weitergaben (seit 1.18): Rechtsklick auf eine Vergabe im Reiter „Vergaben“, im
-- laufenden Raid oder in einem früheren (view: 0 laufender Raid, sonst Archiv).
-- Nur im laufenden Raid geht eine Meldung in den Raidchat.
-------------------------------------------------------------------------------

-- Namen zur Auswahl: wer im Raid ist, gewürfelt hat, auf der Prioliste steht oder
-- etwas bekommen hat, ohne den Geber.
function PM:HandoverNames(raid, except)
	local seen, list = {}, {}
	local function add(key, name)
		if key and key ~= except and not seen[key] then
			seen[key] = true
			list[#list + 1] = { key = key, name = self:DisplayName(key, name) }
		end
	end
	for _, m in ipairs(self:RosterList()) do add(m.key, m.name) end
	for key, name in pairs(raid.rolled or {}) do add(key, name) end
	for key, p in pairs(raid.players or {}) do add(key, p.name) end
	for _, aw in ipairs(raid.awards) do
		if L.PERSONAL[aw.kind] then add(aw.key, aw.name) end
	end
	table.sort(list, function(a, b) return L.SortKey(a.name) < L.SortKey(b.name) end)
	return list
end

-- Name wie im Raid oder auf der Prioliste, sonst mit großem Anfangsbuchstaben.
function PM:HandoverName(text)
	local key = self:ResolveKey(text)
	if not key then return nil end
	local known = self:DisplayName(key, nil)
	if known and known ~= key then return key, known end
	for _, raid in ipairs({ self:Raid(), self.db.history[1] }) do
		if raid and raid.rolled and raid.rolled[key] then return key, raid.rolled[key] end
	end
	local name = L.Trim(text):gsub("%-.*$", "")
	local first = name:match("^[%z\1-\127\194-\244][\128-\191]*") or ""
	return key, (first:upper() .. name:sub(#first + 1))
end

-- Rückfrage vor der Weitergabe, mit den Folgen für Prio und Würfelstufe.
function PM:RequestHandover(view, index, text)
	local raid = self:ViewRaid(view)
	local src = raid.awards[index]
	local key, name = self:HandoverName(text or "")
	local effects, err = L.HandoverEffects(raid, index, key, name, self.db.settings.prio0Mode)
	if not effects then
		self:Print(err)
		return false
	end
	local head = format(T("%s hat %s an %s weitergegeben?"), src.name, src.link or (T("Item ") .. tostring(src.itemID)), name)
	StaticPopup_Show("PRIOMEISTER_HANDOVER", head .. "\n\n" .. table.concat(effects, "\n"), nil,
		{ view = view, index = index, key = key, name = name, t = src.t, srcKey = src.key })
	return true
end

-- Weitergabe eintragen; data aus der Rückfrage, die Liste darf sich inzwischen nicht verschoben haben.
function PM:HandOver(data)
	local raid = self:ViewRaid(data.view)
	local src = raid.awards[data.index]
	if not src or src.t ~= data.t or src.key ~= data.srcKey then
		self:Print("Die Vergabeliste hat sich geändert, bitte die Weitergabe noch einmal eintragen.")
		return nil
	end
	local srcFree = L.CountsAsFreeWin(src)
	local aw, err = L.RecordHandover(raid, data.index, data.key, data.name, time(), self.db.settings.prio0Mode)
	if not aw then
		self:Print(err)
		return nil
	end
	local line = L.AwardLine(aw)
	local tierNote = L.CountsAsFreeWin(aw) and format(T(" – würfelt ab jetzt mit /roll %d"), L.AllowedMax(raid, aw.key)) or ""
	self:Print(line .. tierNote)
	if srcFree then self:Print("%s würfelt wieder mit /roll %d.", src.name, L.AllowedMax(raid, src.key)) end
	if (data.view or 0) == 0 and self.db.settings.awardsToRaid then
		self:Send(line .. (self.db.settings.tierHints and tierNote or ""))
	end
	refreshUI()
	return aw
end

function PM:RemoveHandover(view, index)
	local raid = self:ViewRaid(view)
	local aw, src = L.RemoveHandover(raid, index)
	if not aw then
		self:Print(src)
		return nil
	end
	local line = L.HandoverUndoLine(aw)
	self:Print(line)
	if (view or 0) == 0 and self.db.settings.awardsToRaid then self:Send(line) end
	refreshUI()
	return aw
end

-- /pm vergabe Name [Item]: ohne Item gilt das Item der aktiven Würfelrunde.
function PM:ManualAward(text)
	local name, itemText = L.Trim(text):match("^(%S+)%s*(.-)$")
	if not name then
		self:Print("Aufruf: /pm vergabe Name [Item] – das Item per Shift-Klick verlinken.")
		return
	end
	local id, link
	if itemText:find("item:") then
		id, link = L.ItemID(itemText), L.ExtractLink(itemText)
	elseif tonumber(itemText) then
		id = tonumber(itemText)
	end
	if not id then
		local s = L.ActiveSession(self:Raid())
		if s then id, link = s.itemID, s.link end
	end
	if not id and self.testMode and self.testItems and self.testItems[1] then
		id, link = self.testItems[1].itemID, self.testItems[1].link
	end
	if not id then
		self:Print("Kein Item angegeben und keine Würfelrunde aktiv: /pm vergabe Name [Item]")
		return
	end
	self:ConfirmAward({ key = self:ResolveKey(name), name = name, itemID = id, link = link or self:ItemLabel(id) })
end

-- Raid für die Vergaben-Ansicht: 0 = aktueller Raid, sonst ein früherer (neuester zuerst).
function PM:ViewRaid(index)
	if index and index > 0 and self.db.history[index] then return self.db.history[index] end
	return self:Raid()
end

function PM:PrintAwards(raid)
	raid = raid or self:Raid()
	if #raid.awards == 0 then
		self:Print("Noch keine Vergaben in diesem Raid.")
		return
	end
	self:Print("Vergaben seit %s:", date("%d.%m. %H:%M", raid.started or time()))
	for _, aw in ipairs(raid.awards) do
		DEFAULT_CHAT_FRAME:AddMessage(format("  %s %s", date("%H:%M", aw.t or 0), L.AwardLine(aw)))
	end
end

-- Vergaben eines Raids im gewählten Kanal teilen, eine Zeile pro halbe Sekunde.
local SHARE_INTERVAL = 0.5

function PM:ShareAwards(raid, channel, target)
	raid = raid or self:Raid()
	local s = self.db.settings
	channel = channel or s.shareChannel or "GUILD"
	if channel == "WHISPER" then
		target = L.Trim(target or s.shareTarget or "")
		if target == "" then
			self:Print("Bitte einen Namen zum Anflüstern eingeben.")
			return false
		end
	elseif (channel == "GUILD" or channel == "OFFICER") and not (IsInGuild and IsInGuild()) then
		self:Print("Du bist in keiner Gilde.")
		return false
	elseif channel == "RAID" and not IsInRaid() then
		self:Print("Du bist in keinem Schlachtzug.")
		return false
	elseif channel == "PARTY" and not IsInGroup() then
		self:Print("Du bist in keiner Gruppe.")
		return false
	end
	if self.sharing then
		self:Print("Die Vergaben werden gerade schon geteilt.")
		return false
	end
	local lines = L.ShareLines(raid, date, { lowItems = s.helperLowChat })
	if not lines then
		self:Print("Keine Vergaben zum Teilen.")
		return false
	end
	if channel ~= "WHISPER" then target = nil end
	self.sharing = { lines = lines, index = 0, channel = channel, target = target }
	self:Print("Teile %d Zeilen: %s.", #lines, self:ShareLabel(channel, target))
	self:ShareNext()
	refreshUI()
	return true
end

function PM:ShareNext()
	local sh = self.sharing
	if not sh then return end
	sh.index = sh.index + 1
	local line = sh.lines[sh.index]
	if not line then
		self.sharing = nil
		self:Print("Vergaben geteilt.")
		refreshUI()
		return
	end
	self:Send(line, sh.channel, sh.target)
	C_Timer.After(SHARE_INTERVAL, function() PM:ShareNext() end)
end

-- CSV mit allen Vergaben und Würfen der Raids, für priomeister.de oder eine Tabelle.
function PM:ExportCSV(raids)
	return L.ExportCSV(raids, date, { instanceName = function(id) return self:InstanceName(id) end })
end

function PM:ExportText(all)
	local raids = { self:Raid() }
	if all then
		for _, h in ipairs(self.db.history) do raids[#raids + 1] = h end
	end
	return self:ExportCSV(raids)
end

-------------------------------------------------------------------------------
-- Auskünfte
-------------------------------------------------------------------------------

local LEVEL_TEXT = { [0] = "Prio 0", [1] = "Prio 1", [2] = "Prio 2", [3] = "Prio 3" }
PM.LEVEL_TEXT = LEVEL_TEXT

-- Zeilen über einen Spieler: Prios, Vergaben, Würfelstufe, Rollen.
function PM:PlayerLines(key, itemID)
	local raid = self:Raid()
	local lines = {}
	local s = self.db.settings
	for _, role in ipairs(self.ROLES) do
		if L.NameKey(s[role]) == key then lines[#lines + 1] = "|cff66ccff" .. self.ROLE_TEXT[role] .. "|r" end
	end
	local p = raid.players[key]
	local canon = L.Canon(itemID)
	if p then
		local entries = L.GetEntries(p, s.prio0Mode)
		for _, e in ipairs(entries) do
			local idx = (e.level == 0) and 1 or e.level
			local label = self:ItemLabel(p.p[idx], p.pn[idx])
			local done = true
			for _, o in ipairs(L.OpenEntriesFor(raid, key, e.item, s.prio0Mode)) do
				if o.level == e.level then done = false end
			end
			local txt = format("%s %s", LEVEL_TEXT[e.level], label)
			if done then txt = txt .. T(" |cff40ff40(erhalten)|r") end
			local ignored = self:IgnoredKind(p.p[idx])
			if ignored then
				txt = txt .. ((ignored == "mount") and T(" |cffff8000(Reittier, ignoriert)|r") or T(" |cffff8000(Rezept, ignoriert)|r"))
			end
			if canon and e.item == canon then txt = "|cffffd100>|r " .. txt end
			lines[#lines + 1] = txt
		end
		if #entries == 0 then lines[#lines + 1] = T("|cff909090Keine Prios eingetragen.|r") end
	else
		lines[#lines + 1] = T("|cff909090Nicht auf der Prioliste.|r")
	end
	local lists = self:Waitlists(raid)
	if lists then
		local ids = {}
		for id in pairs(lists) do ids[#ids + 1] = id end
		table.sort(ids)
		for _, id in ipairs(ids) do
			local place = L.WaitlistPlace(self:WaitlistFor(id), key)
			if place then
				local txt = format(T("Warteliste %s: Platz %d"), self:ItemLabel(id), place)
				if canon and id == canon then txt = "|cffffd100>|r " .. txt end
				lines[#lines + 1] = txt
			end
		end
	end
	local wins = L.FreeWins(raid, key)
	if wins > 0 then
		lines[#lines + 1] = format(T("Freie Würfe gewonnen: %d – würfelt mit /roll %d"), wins, L.AllowedMax(raid, key))
	end
	for _, aw in ipairs(L.AwardsOf(raid, key)) do
		if aw.kind == "tier" then
			lines[#lines + 1] = format(T("|cffffd100Von Hand:|r %s, %s Uhr"), L.AwardDetail(aw), date("%H:%M", aw.t or 0))
		elseif aw.kind == "pass" then
			lines[#lines + 1] = format(T("|cffb0b0b0Verzichtet:|r %s (%s), %s Uhr"), aw.link or (T("Item ") .. tostring(aw.itemID)),
				L.LevelText(aw.level), date("%H:%M", aw.t or 0))
		else
			local label = (aw.givenTo and T("|cff909090Weitergegeben:|r")) or (L.PERSONAL[aw.kind] and T("|cffff8000Erhalten:|r"))
				or T("|cff909090Für die Gilde:|r")
			lines[#lines + 1] = format("%s %s (%s)", label, aw.link or (T("Item ") .. tostring(aw.itemID)), L.AwardDetail(aw))
		end
	end
	return lines
end

function PM:PrintPlayer(nameOrKey)
	local key = self:ResolveKey(nameOrKey)
	if not key then return end
	self:Print("%s:", self:ColoredName(key, self:DisplayName(key, nameOrKey)))
	for _, line in ipairs(self:PlayerLines(key)) do DEFAULT_CHAT_FRAME:AddMessage("  " .. line) end
end

function PM:PrintItem(itemID, link)
	local res = self:ResolveForItem(itemID)
	self:Print("%s:", link or self:ItemLabel(itemID))
	local any = false
	if res.waitlist then
		any = true
		local names = {}
		for _, e in ipairs(res.waitlist) do
			names[#names + 1] = (e.passed and (e.name .. T(" (verzichtet)"))) or (e.present and e.name) or (e.name .. T(" (fehlt)"))
		end
		DEFAULT_CHAT_FRAME:AddMessage(format(T("  Warteliste: %s"), table.concat(names, ", ")))
	end
	for lvl = 0, 3 do
		local names = {}
		for _, h in ipairs(res.levels[lvl]) do
			names[#names + 1] = h.present and h.name or (h.name .. T(" (fehlt)"))
		end
		if #names > 0 then
			any = true
			DEFAULT_CHAT_FRAME:AddMessage(format("  %s: %s", LEVEL_TEXT[lvl], table.concat(names, ", ")))
		end
	end
	if #res.ignored > 0 then
		local names = {}
		for _, h in ipairs(res.ignored) do names[#names + 1] = h.name end
		DEFAULT_CHAT_FRAME:AddMessage(format(T("  %s, Prio ignoriert: %s"), res.mount and T("Reittier") or T("Rezept"), table.concat(names, ", ")))
	end
	if not any then
		DEFAULT_CHAT_FRAME:AddMessage(res.mode == "recipe" and T("  Rezept-Wurf ohne Würfelstufen.") or T("  Kein Prio – freier Wurf."))
	end
end

-- Spieler mit freien Gewinnen: { key, name, wins, max }
function PM:WinsList()
	local raid = self:Raid()
	local seen = {}
	for _, aw in ipairs(raid.awards) do
		if aw.kind == "free" or aw.kind == "given" then seen[aw.key] = true end
	end
	for key in pairs(raid.adjust) do seen[key] = true end
	local list = {}
	for key in pairs(seen) do
		local wins = L.FreeWins(raid, key)
		if wins > 0 then
			list[#list + 1] = { key = key, name = self:DisplayName(key), wins = wins, max = L.AllowedMax(raid, key) }
		end
	end
	table.sort(list, function(a, b) return L.SortKey(a.name) < L.SortKey(b.name) end)
	return list
end

-- Würfelstufen für den Reiter Raid: alle, die in diesem Raid gewürfelt, frei
-- gewonnen oder eine Korrektur bekommen haben, auch mit Stufe 100.
function PM:TierList()
	local raid = self:Raid()
	local seen = {}
	for key, name in pairs(raid.rolled or {}) do seen[key] = name end
	for _, s in ipairs(raid.sessions or {}) do
		for _, r in ipairs(s.rolls) do
			if r.key and not seen[r.key] then seen[r.key] = r.name end
		end
	end
	for _, aw in ipairs(raid.awards) do
		if (aw.kind == "free" or aw.kind == "given") and not seen[aw.key] then seen[aw.key] = aw.name end
	end
	for key in pairs(raid.adjust) do
		if not seen[key] then seen[key] = key end
	end
	local list = {}
	for key, name in pairs(seen) do
		list[#list + 1] = { key = key, name = self:DisplayName(key, name), wins = L.FreeWins(raid, key), max = L.AllowedMax(raid, key) }
	end
	table.sort(list, function(a, b) return L.SortKey(a.name) < L.SortKey(b.name) end)
	return list
end

function PM:PrintWins()
	local list = self:WinsList()
	if #list == 0 then
		self:Print("Noch niemand hat einen freien Wurf gewonnen. Alle würfeln mit /roll 100.")
		return
	end
	self:Print("Würfelstufen:")
	for _, e in ipairs(list) do
		DEFAULT_CHAT_FRAME:AddMessage(format(T("  %s: %d gewonnen – /roll %d"), e.name, e.wins, e.max))
	end
end

-- Würfelstufe von Hand setzen; die Änderung steht mit Uhrzeit in der Vergabeliste.
function PM:SetWins(name, wins)
	local raid = self:Raid()
	local key = self:ResolveKey(name)
	if not key or not wins then return end
	local before, prevAdjust = L.AllowedMax(raid, key), raid.adjust[key]
	raid.adjust[key] = 0
	local derived = L.FreeWins(raid, key)
	raid.adjust[key] = wins - derived
	local after = L.AllowedMax(raid, key)
	if after ~= before then
		local index = L.RecordTierChange(raid, key, self:DisplayName(key, name), before, after, prevAdjust, time())
		if self:PostTierChanges() then self:Send(L.AwardLine(raid.awards[index])) end
	end
	self:Print("%s: %d freie Würfe gewonnen – würfelt mit /roll %d.", self:DisplayName(key, name), L.FreeWins(raid, key), L.AllowedMax(raid, key))
	refreshUI()
end

function PM:AdjustWins(key, delta)
	local wins = L.FreeWins(self:Raid(), key) + delta
	if wins < 0 then wins = 0 end
	self:SetWins(self:DisplayName(key, key), wins)
end

-------------------------------------------------------------------------------
-- Angeheftete Spieler und Rollen
-------------------------------------------------------------------------------

function PM:TogglePin(name)
	local key = self:ResolveKey(name)
	if not key then return end
	for i, n in ipairs(self.db.pins) do
		if self:ResolveKey(n) == key then
			table.remove(self.db.pins, i)
			self:Print("%s ist nicht mehr angeheftet.", n)
			refreshUI()
			return
		end
	end
	local display = self:DisplayName(key, L.Trim(name))
	table.insert(self.db.pins, display)
	self:Print("%s wird in der Plündermeister-Liste oben angezeigt.", display)
	refreshUI()
end

function PM:IsPinned(name)
	local key = L.NameKey(name)
	for _, n in ipairs(self.db.pins) do
		if L.NameKey(n) == key then return true end
	end
	return false
end

function PM:SetPinsFromText(text)
	local pins = {}
	for part in (text or ""):gmatch("[^,;%s]+") do
		pins[#pins + 1] = part
	end
	self.db.pins = pins
	refreshUI()
end

function PM:PinsText()
	return table.concat(self.db.pins, ", ")
end

-- role: "lootHelper" (Plünderhelfer), "treasurer" (Schatzmeister) oder "disenchanter" (Entzauberer)
function PM:SetRole(role, name)
	if not self.ROLE_TEXT[role] then return end
	name = name and L.Trim(name) or nil
	if name == "" or name == "-" then name = nil end
	if name then name = self:DisplayName(self:ResolveKey(name), name) end
	self.db.settings[role] = name
	if role == "treasurer" then self.treasurerHintShown = false end
	self:Print("%s: %s", self.ROLE_TEXT[role], name or T("niemand"))
	refreshUI()
end

-- Reihenfolge oben in der Plündermeister-Liste: Rollen, dann Angeheftete.
function PM:PinnedOrder()
	local list = {}
	for _, role in ipairs(self.ROLES) do
		if self.db.settings[role] then list[#list + 1] = self.db.settings[role] end
	end
	for _, n in ipairs(self.db.pins) do list[#list + 1] = n end
	return list
end

-------------------------------------------------------------------------------
-- Plündermethode und Plündergrenze (auch Grau und Weiß)
-------------------------------------------------------------------------------

function PM:CurrentLootMethod()
	local method, partyID, raidID
	if C_PartyInfo and C_PartyInfo.GetLootMethod then
		method, partyID, raidID = C_PartyInfo.GetLootMethod()
	elseif GetLootMethod then
		local m
		m, partyID, raidID = GetLootMethod()
		method = (m == "master") and LOOT_METHOD_MASTER or m
	end
	local mlName
	if method == LOOT_METHOD_MASTER then
		if raidID and IsInRaid() then
			mlName = GetRaidRosterInfo(raidID)
		elseif partyID then
			mlName = (partyID == 0) and UnitName("player") or UnitName("party" .. partyID)
		end
	end
	return method, mlName, GetLootThreshold and GetLootThreshold() or nil
end

function PM:CanChangeLoot()
	if not IsInGroup() then
		self:Print("Du bist in keiner Gruppe.")
		return false
	end
	if not UnitIsGroupLeader("player") then
		self:Print("Nur die Gruppen- bzw. Schlachtzugsleitung kann Plündermethode und Grenze ändern.")
		return false
	end
	if InCombatLockdown and InCombatLockdown() then
		self:Print("Im Kampf nicht möglich.")
		return false
	end
	return true
end

function PM:SetThreshold(q, attempt)
	local set = SetLootThreshold or (C_PartyInfo and C_PartyInfo.SetLootThreshold)
	if not set then return end
	set(q)
	C_Timer.After(0.7, function()
		local current = GetLootThreshold and GetLootThreshold()
		if current == q then
			PM:Print("Plündergrenze: %s.", PM:QualityLabel(q))
		elseif (attempt or 1) < 3 then
			PM:SetThreshold(q, (attempt or 1) + 1)
		else
			PM:Print("|cffff4040Plündergrenze konnte nicht auf %s gesetzt werden.|r", PM:QualityLabel(q))
		end
		refreshUI()
	end)
end

-- Setzt Plündermeister (gewählter Name oder du selbst) und danach die Grenze.
function PM:ApplyLootSettings(threshold)
	if not self:CanChangeLoot() then return end
	local wanted = self.db.settings.masterLooterName or UnitName("player")
	local method, mlName = self:CurrentLootMethod()
	if method ~= LOOT_METHOD_MASTER or L.NameKey(mlName) ~= L.NameKey(wanted) then
		if C_PartyInfo and C_PartyInfo.SetLootMethod then
			C_PartyInfo.SetLootMethod(LOOT_METHOD_MASTER, wanted)
		elseif SetLootMethod then
			SetLootMethod("master", wanted)
		end
		self:Print("Plündermeister: %s.", wanted)
		if threshold then
			C_Timer.After(0.5, function() PM:SetThreshold(threshold, 1) end)
		end
	elseif threshold then
		self:SetThreshold(threshold, 1)
	end
end

-------------------------------------------------------------------------------
-- Slash-Befehle
-------------------------------------------------------------------------------

local HELP = {
	"|cffffd100/pm|r – Hauptfenster (Raid, Vergaben, Plündern, Optionen), |cffffd100/pm changelog|r – Versionen und Änderungen",
	"|cffffd100/pm import|r – Prioliste von priomeister.de einfügen, |cffffd100/pm neu|r – neuer Raid",
	"|cffffd100/pm fortsetzen|r – frühere Raids, |cffffd100/pm fortsetzen 1|r setzt den letzten fort (Vergaben und Würfelstufen gelten weiter)",
	"|cffffd100/pm stand|r – Stand der Prioliste: Spieler, Prios, letzte Änderung und Link zum Prio-Run",
	"|cffffd100/pm tabelle|r – Prio-Tabelle aller Spieler",
	"|cffffd100/pm liste|r, |cffffd100/pm export|r – Vergaben im Chat bzw. als CSV",
	"|cffffd100/pm teilen|r [gilde|offiziere|raid|gruppe|Name] – Vergaben teilen, ohne Angabe im gewählten Kanal",
	"|cffffd100/pm undo|r – letzte Vergabe zurücknehmen, |cffffd100/pm vergabe Name [Item]|r – von Hand eintragen",
	"|cffffd100/pm prio Name|r oder |cffffd100/pm prio [Item]|r – Prios nachsehen",
	"|cffffd100/pm stufen|r – Würfelstufen; |cffffd100/pm stufen Name 2|r setzt 2 freie Siege",
	"|cffffd100/pm würfeln [Item]|r / |cffffd100/pm frei [Item]|r – Würfelrunde starten, |cffffd100/pm stopp|r beendet sie",
	"|cffffd100/pm stich|r – Stichwurf bei Gleichstand (gleiche Stufe wie beim ersten Wurf)",
	"|cffffd100/pm zufall [Item]|r – zufällig vergeben: Wurf über alle Spieler, gezählt durch die Gruppen 1 bis 8",
	"|cffffd100/pm erinnern|r – Spieler ohne Prio im Raid erinnern",
	"|cffffd100/pm check|r – Priocheck: wer im Raid noch Prios braucht (einfügen unter |cffffd100/pm import|r)",
	"|cffffd100/pm helfer Name|r, |cffffd100/pm schatzmeister Name|r, |cffffd100/pm entzauberer Name|r – Rollen setzen (|cffffd100-|r leert)",
	"|cffffd100/pm pin Name|r – Spieler oben anheften, |cffffd100/pm panel|r – Panel ein-/ausblenden",
	"|cffffd100/pm test|r – Testmodus ohne Raid (|cffffd100/pm testwurf Name 87 99|r, |cffffd100/pm vergabe Name|r)",
}

-- Englische Befehle (seit 1.21) mit derselben Bedeutung wie die deutschen
local COMMAND_ALIASES = {
	status = "stand", table = "tabelle", list = "liste", tiers = "stufen", award = "vergabe", free = "frei",
	random = "zufall", tiebreak = "stich", remind = "erinnern", helper = "helfer", treasurer = "schatzmeister",
	disenchanter = "entzauberer", testroll = "testwurf",
}

function PM:Slash(msg)
	msg = L.Trim(msg or "")
	local cmd, rest = msg:match("^(%S+)%s*(.-)$")
	cmd = cmd and L.Lower(cmd) or ""
	cmd = COMMAND_ALIASES[cmd] or cmd
	rest = rest or ""

	if (cmd == "" or cmd == "optionen" or cmd == "options" or cmd == "config" or cmd == "plündern"
		or cmd == "pluendern" or cmd == "loot") and not ns.UI.ShowMain then
		self:Print("Das Hauptfenster ist neu. Bitte WoW einmal komplett neu starten, damit es geladen wird.")
	elseif cmd == "" then
		ns.UI:ShowMain()
	elseif cmd == "hilfe" or cmd == "help" then
		self:Print("Version %s – Befehle:", self.version)
		for _, line in ipairs(HELP) do DEFAULT_CHAT_FRAME:AddMessage("  " .. T(line)) end
	elseif cmd == "import" then
		ns.UI:ShowImport()
	elseif cmd == "changelog" or cmd == "version" or cmd == "versionen" then
		if ns.UI.ShowChangelog then ns.UI:ShowChangelog() else self:Print("Version %s", self.version) end
	elseif cmd == "stand" then
		for _, line in ipairs(self:ListInfo()) do self:Print(line) end
	elseif cmd == "tabelle" or cmd == "prios" then
		ns.UI:ShowPrioTable()
	elseif cmd == "neu" or cmd == "new" then
		self:NewRaid()
	elseif cmd == "fortsetzen" or cmd == "resume" then
		local n = tonumber(rest)
		if n and self.db.history[n] then
			ns.UI:RequestReopen(n)
		elseif #self.db.history == 0 then
			self:Print("Kein früherer Raid im Archiv.")
		else
			self:Print("Frühere Raids, fortsetzen mit /pm fortsetzen Nummer:")
			for i = 1, math.min(#self.db.history, 10) do
				DEFAULT_CHAT_FRAME:AddMessage(format("  %d: %s", i, ns.UI:RaidLabel(i)))
			end
		end
	elseif cmd == "liste" or cmd == "log" then
		self:PrintAwards()
	elseif cmd == "teilen" or cmd == "share" then
		local arg = L.Lower(L.Trim(rest))
		local channels = { gilde = "GUILD", offiziere = "OFFICER", raid = "RAID", schlachtzug = "RAID", gruppe = "PARTY",
			guild = "GUILD", officer = "OFFICER", officers = "OFFICER", party = "PARTY" }
		if arg == "" then
			self:ShareAwards(self:Raid())
		elseif channels[arg] then
			self:ShareAwards(self:Raid(), channels[arg])
		else
			self:ShareAwards(self:Raid(), "WHISPER", L.Trim(rest))
		end
	elseif cmd == "export" then
		ns.UI:ShowText("PrioMeister – Export", self:ExportText(L.Lower(rest) == "alle" or L.Lower(rest) == "all"))
	elseif cmd == "undo" or cmd == "zurück" or cmd == "zurueck" then
		self:UndoLast()
	elseif cmd == "vergabe" or cmd == "testvergabe" then
		self:ManualAward(rest)
	elseif cmd == "prio" then
		local id = rest:find("item:") and L.ItemID(rest)
		if id then
			self:PrintItem(id, L.ExtractLink(rest) or rest)
		elseif rest ~= "" then
			self:PrintPlayer(rest)
		else
			self:PrintPlayer(UnitName("player"))
		end
	elseif cmd == "stufen" or cmd == "siege" then
		local name, n = rest:match("^(%S+)%s+(%d+)$")
		if name then self:SetWins(name, tonumber(n)) else self:PrintWins() end
	elseif cmd == "würfeln" or cmd == "wuerfeln" or cmd == "roll" or cmd == "frei" then
		local id = L.ItemID(rest)
		if not id then
			self:Print("Bitte ein Item verlinken (Shift-Klick), z. B. /pm würfeln [Item].")
			return
		end
		self:StartRoll(id, L.ExtractLink(rest), nil, cmd == "frei", self:ContextForItem(id))
	elseif cmd == "zufall" or cmd == "zufällig" then
		local id = L.ItemID(rest)
		if not id then
			self:Print("Bitte ein Item verlinken (Shift-Klick), z. B. /pm zufall [Item].")
			return
		end
		self:RequestRandomAssign(id, L.ExtractLink(rest), self:SlotOfItem(id))
	elseif cmd == "stich" or cmd == "stichwurf" then
		self:StartTiebreak()
	elseif cmd == "stopp" or cmd == "stop" then
		self:EndSession()
		self:Print("Würfelrunde beendet.")
	elseif cmd == "erinnern" then
		self:RemindNoPrio()
	elseif cmd == "check" or cmd == "priocheck" then
		self:PrintCheck()
	elseif cmd == "helfer" or cmd == "plünderhelfer" then
		self:SetRole("lootHelper", rest)
	elseif cmd == "schatzmeister" or cmd == "schatz" or cmd == "sm" then
		self:SetRole("treasurer", rest)
	elseif cmd == "entzauberer" or cmd == "de" then
		self:SetRole("disenchanter", rest)
	elseif cmd == "pin" then
		if rest == "" then self:Print("Angeheftet: %s", (#self.db.pins > 0) and self:PinsText() or T("niemand")) else self:TogglePin(rest) end
	elseif cmd == "pins" then
		if L.Lower(rest) == "leeren" then
			self.db.pins = {}
			self:Print("Keine Spieler mehr angeheftet.")
			refreshUI()
		else
			self:Print("Angeheftet: %s", (#self.db.pins > 0) and self:PinsText() or "niemand")
		end
	elseif cmd == "panel" then
		ns.UI:TogglePanel()
	elseif cmd == "optionen" or cmd == "options" or cmd == "config" then
		ns.UI:ShowMain("options")
	elseif cmd == "plündern" or cmd == "pluendern" or cmd == "loot" then
		ns.UI:ShowMain("loot")
	elseif cmd == "test" then
		self:ToggleTest()
	elseif cmd == "testwurf" then
		local name, value, high = rest:match("^(%S+)%s+(%d+)%s*(%d*)$")
		if not name or not self.testMode then
			self:Print("Nur im Testmodus: /pm testwurf Name 87 [99]")
			return
		end
		self:HandleRoll(name, tonumber(value), 1, tonumber(high) or 100)
	else
		self:Print("Unbekannter Befehl. /pm hilfe zeigt alle Befehle.")
	end
end

SLASH_PRIOMEISTER1 = "/pm"
SLASH_PRIOMEISTER2 = "/priomeister"
SlashCmdList.PRIOMEISTER = function(msg) PM:Slash(msg) end
