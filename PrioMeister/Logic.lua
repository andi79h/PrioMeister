-- PrioMeister – Logic.lua
-- Reine Logik ohne Oberfläche: Prioliste einlesen, Prio auflösen,
-- Würfe bewerten (Würfelstufen 100 > 99 > 98 ..., 50er-Würfe, Rezept-Würfe)
-- und Vergaben auswerten. Die Datei nutzt keine WoW-Funktionen und lässt
-- sich daher auch außerhalb des Spiels testen.

local _, ns = ...
ns = ns or {}
local L = {}
ns.Logic = L
local T = ns.T or function(s) return s end -- Sprache (Locale.lua)

local format, tsort, concat = string.format, table.sort, table.concat

-------------------------------------------------------------------------------
-- Text-Hilfen
-------------------------------------------------------------------------------

function L.Trim(s)
	if type(s) ~= "string" then return "" end
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Trennt ohne Muster-Sonderzeichen und behält leere Felder.
function L.Split(s, sep)
	local out, start = {}, 1
	while true do
		local i = s:find(sep, start, true)
		if not i then
			out[#out + 1] = s:sub(start)
			return out
		end
		out[#out + 1] = s:sub(start, i - 1)
		start = i + #sep
	end
end

-- Kleinschreibung inklusive Latin-1-Großbuchstaben in UTF-8 (Ä, Ö, Ü, Á ...).
local function utf8lower(s)
	s = s:lower()
	return (s:gsub("\195([\128-\158])", function(c)
		local b = c:byte()
		if b == 151 then return "\195" .. c end -- Malzeichen
		return "\195" .. string.char(b + 32)
	end))
end
L.Lower = utf8lower

-- Vergleichsschlüssel für Spielernamen: ohne Realm, klein geschrieben.
function L.NameKey(name)
	if type(name) ~= "string" then return nil end
	name = L.Trim(name)
	name = name:gsub("%-.*$", "")
	if name == "" then return nil end
	return utf8lower(name)
end

-- Akzente weg, wie auf priomeister.de (klein, NFKD ohne Akzente, ß → ss, æ → ae, œ → oe,
-- ø → o, đ und ð → d, þ → th, ł → l): Latin-1 und Lateinisch erweitert A, groß und klein.
local FOLD = {}
for base, letters in pairs({
	a = "ÀÁÂÃÄÅàáâãäåĀāĂăĄą", ae = "Ææ", c = "ÇçĆćĈĉĊċČč", d = "ÐðĎďĐđ",
	e = "ÈÉÊËèéêëĒēĔĕĖėĘęĚě", g = "ĜĝĞğĠġĢģ", h = "Ĥĥ", i = "ÌÍÎÏìíîïĨĩĪīĬĭĮįİ", ij = "Ĳĳ",
	j = "Ĵĵ", k = "Ķķ", l = "ĹĺĻļĽľŁł", n = "ÑñŃńŅņŇň", o = "ÒÓÔÕÖØòóôõöøŌōŎŏŐő", oe = "Œœ",
	r = "ŔŕŖŗŘř", s = "ŚśŜŝŞşŠšſ", ss = "ß", t = "ŢţŤť", th = "Þþ",
	u = "ÙÚÛÜùúûüŨũŪūŬŭŮůŰűŲų", w = "Ŵŵ", y = "ÝýÿŶŷŸ", z = "ŹźŻżŽž",
}) do
	for ch in letters:gmatch("[\195-\197][\128-\191]") do FOLD[ch] = base end
end

-- Vergleichsschlüssel ohne Akzente: „Leryssiá“ und „Leryssia“ ergeben beide „leryssia“.
function L.FoldKey(name)
	local k = L.NameKey(name)
	if not k then return nil end
	return (k:gsub("[\195-\197][\128-\191]", FOLD))
end

-- Sortierschlüssel: Umlaute und Akzente wie Grundbuchstaben (Ä bei A statt hinter Z).
function L.SortKey(name)
	return L.FoldKey(name) or ""
end

function L.SortNames(list)
	tsort(list, function(a, b) return L.SortKey(a) < L.SortKey(b) end)
	return list
end

-- Namen von außen (Prioliste, Priocheck, Eingabe) den Namen im Spiel zuordnen. Der exakte
-- Name gewinnt. Sonst zählt der Name ohne Akzente, aber nur, wenn er auf beiden Seiten genau
-- einmal übrig bleibt: lieber kein Treffer als ein falscher. outside, inside: Mengen von
-- Schlüsseln (NameKey). Ergebnis: [Schlüssel außen] = Schlüssel innen für die Paare, die erst
-- ohne Akzente zusammenpassen.
function L.MatchFolded(outside, inside)
	local function group(set, other)
		local g = {}
		for key in pairs(set) do
			local f = not other[key] and L.FoldKey(key)
			if f then
				g[f] = g[f] or {}
				g[f][#g[f] + 1] = key
			end
		end
		return g
	end
	local outer, inner, map = group(outside, inside), group(inside, outside), {}
	for f, keys in pairs(outer) do
		local hits = inner[f]
		if #keys == 1 and hits and #hits == 1 then map[keys[1]] = hits[1] end
	end
	return map
end

-- Item-ID aus Zahl, Itemlink, Wowhead-Link oder "Name-12345".
function L.ItemID(value)
	if value == nil then return nil end
	if type(value) == "number" then return value end
	if type(value) ~= "string" then return nil end
	-- Itemlink: nur die Item-ID zählt. WoW liefert für vergebene Loot-Plätze
	-- manchmal einen leeren Link ohne ID („|Hitem:::::::::60:…|h[]|h“), dort
	-- darf die Stufe 60 nicht als Item-ID gelten.
	if value:find("|H", 1, true) then
		local linked = tonumber(value:match("|Hitem:(%d+)"))
		return (linked and linked > 0) and linked or nil
	end
	local id = value:match("item:(%d+)") or value:match("item=(%d+)")
		or value:match("%-(%d+)%s*$") or value:match("(%d+)")
	return id and tonumber(id) or nil
end

-- Vollständiger Itemlink aus einem Text (Farbcode |cff... oder |cnIQ4:).
function L.ExtractLink(text)
	if type(text) ~= "string" then return nil end
	return text:match("|c[^|]+|Hitem:.-|h|r")
end

-- Name aus einem Itemlink ("[Krone des Netherwinds]").
function L.LinkName(link)
	if type(link) ~= "string" then return nil end
	return link:match("%[(.-)%]")
end

-------------------------------------------------------------------------------
-- Globale Formatstrings (z. B. RANDOM_ROLL_RESULT) in Lua-Muster umwandeln
-------------------------------------------------------------------------------

function L.FormatToMatcher(fmt)
	if type(fmt) ~= "string" then return nil end
	local specs, counter = {}, 0
	local p = fmt:gsub("%%%%", "\001")
	p = p:gsub("%%(%d*)%$?([sd])", function(pos, typ)
		counter = counter + 1
		specs[#specs + 1] = { idx = tonumber(pos) or counter, typ = typ }
		return "\002" .. typ
	end)
	p = p:gsub("([%^%$%(%)%.%[%]%*%+%-%?%%])", "%%%1")
	p = p:gsub("\002s", "(.-)"):gsub("\002d", "(%%d+)"):gsub("\001", "%%%%")
	return { pattern = "^" .. p .. "$", specs = specs }
end

-- Liefert die Werte in Argument-Reihenfolge oder nil.
function L.MatchFormat(matcher, msg)
	if not matcher or type(msg) ~= "string" then return nil end
	local caps = { msg:match(matcher.pattern) }
	if caps[1] == nil then return nil end
	local out = {}
	for i, spec in ipairs(matcher.specs) do
		local v = caps[i]
		if spec.typ == "d" then v = tonumber(v) end
		out[spec.idx] = v
	end
	return out
end

-------------------------------------------------------------------------------
-- Items
-------------------------------------------------------------------------------

-- Items, die als dasselbe Item zählen (Quest-Item, Belohnungen, Fraktionsvarianten)
local ITEM_GROUPS = {
	{ 18423, 18422, 18403, 18404, 18406 }, -- Kopf von Onyxia
	{ 19003, 19002, 19383, 19366, 19384 }, -- Kopf von Nefarian
	{ 19802, 19948, 19949, 19950 },        -- Herz von Hakkar
	{ 21220, 21504, 21505, 21506, 21507 }, -- Kopf von Ossirian
}
local CANON = {}
for _, group in ipairs(ITEM_GROUPS) do
	for _, id in ipairs(group) do CANON[id] = group[1] end
end

function L.Canon(id)
	id = tonumber(id)
	if not id or id <= 0 then return nil end
	return CANON[id] or id
end

-- Materialien: dreimal dasselbe Item heißt hier "drei Stück", nicht Prio 0.
L.PRIO0_EXCLUDED = {
	[19726] = true, -- Blutrebe
	[12363] = true, -- Arkankristall
	[17011] = true, -- Lavakern
	[17010] = true, -- Feuerkern
	[17012] = true, -- Kernleder
	[11382] = true, -- Blut des Berges
}

L.RECIPE_CLASS = 9 -- Enum.ItemClass.Recipe
L.BOOK_SUBCLASS = 0 -- Rezept-Unterklasse "Buch": Klassenbücher, keine Berufsrezepte
L.MISC_CLASS, L.MOUNT_SUBCLASS = 15, 5 -- Enum.ItemClass.Miscellaneous, Unterklasse Reittier

-------------------------------------------------------------------------------
-- Wer kann ein Item tragen? Rüstung und Waffen, wie sie in Classic auf Stufe 60
-- erlernbar sind, dazu die Tooltip-Zeile „Klassen: …“.
-------------------------------------------------------------------------------

local function classSet(list)
	local set = {}
	for _, c in ipairs(list) do set[c] = true end
	return set
end

L.WEAPON_CLASS, L.ARMOR_CLASS = 2, 4 -- Enum.ItemClass.Weapon und Armor
-- Rüstung nach Unterklasse; 0 Verschiedenes und 1 Stoff können alle tragen.
L.ARMOR_USERS = {
	[2] = classSet({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "SHAMAN", "DRUID" }), -- Leder
	[3] = classSet({ "WARRIOR", "PALADIN", "HUNTER", "SHAMAN" }), -- Kette
	[4] = classSet({ "WARRIOR", "PALADIN" }), -- Platte
	[6] = classSet({ "WARRIOR", "PALADIN", "SHAMAN" }), -- Schild
	[7] = classSet({ "PALADIN" }), -- Buchband
	[8] = classSet({ "DRUID" }), -- Götze
	[9] = classSet({ "SHAMAN" }), -- Totem
}
-- Waffen nach Unterklasse; Verschiedenes (14) und Angelruten (20) können alle führen.
L.WEAPON_USERS = {
	[0] = classSet({ "WARRIOR", "PALADIN", "HUNTER", "SHAMAN" }), -- Einhandäxte
	[1] = classSet({ "WARRIOR", "PALADIN", "HUNTER", "SHAMAN" }), -- Zweihandäxte
	[2] = classSet({ "WARRIOR", "HUNTER", "ROGUE" }), -- Bögen
	[3] = classSet({ "WARRIOR", "HUNTER", "ROGUE" }), -- Schusswaffen
	[4] = classSet({ "WARRIOR", "PALADIN", "ROGUE", "PRIEST", "SHAMAN", "DRUID" }), -- Einhandstreitkolben
	[5] = classSet({ "WARRIOR", "PALADIN", "SHAMAN", "DRUID" }), -- Zweihandstreitkolben
	[6] = classSet({ "WARRIOR", "PALADIN", "HUNTER" }), -- Stangenwaffen
	[7] = classSet({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "MAGE", "WARLOCK" }), -- Einhandschwerter
	[8] = classSet({ "WARRIOR", "PALADIN", "HUNTER" }), -- Zweihandschwerter
	[10] = classSet({ "WARRIOR", "HUNTER", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }), -- Stäbe
	[13] = classSet({ "WARRIOR", "HUNTER", "ROGUE", "SHAMAN", "DRUID" }), -- Faustwaffen
	[15] = classSet({ "WARRIOR", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }), -- Dolche
	[16] = classSet({ "WARRIOR", "HUNTER", "ROGUE" }), -- Wurfwaffen
	[18] = classSet({ "WARRIOR", "HUNTER", "ROGUE" }), -- Armbrüste
	[19] = classSet({ "PRIEST", "MAGE", "WARLOCK" }), -- Zauberstäbe
}
-- Waffen nur für die Schildhand brauchen beidhändigen Kampf.
L.DUAL_WIELD = classSet({ "WARRIOR", "HUNTER", "ROGUE" })

local function intersect(a, b)
	if not a then return b end
	if not b then return a end
	local out = {}
	for k in pairs(a) do
		if b[k] then out[k] = true end
	end
	return out
end

-- Klassen, die ein Item tragen können, nil heißt alle. classID, subclassID und
-- equipLoc wie von GetItemInfoInstant, restricted: Klassen aus „Klassen: …“.
function L.ItemUsers(classID, subclassID, equipLoc, restricted)
	local users
	if classID == L.ARMOR_CLASS then
		users = L.ARMOR_USERS[subclassID]
	elseif classID == L.WEAPON_CLASS then
		users = L.WEAPON_USERS[subclassID]
		if equipLoc == "INVTYPE_WEAPONOFFHAND" then users = intersect(users, L.DUAL_WIELD) end
	end
	return intersect(users, restricted)
end

-- Grund, warum eine Klasse das Item nicht tragen kann, sonst nil.
-- info = { users, restricted, restrictedText, subType, offhand }, className: Klasse auf Deutsch.
function L.UnusableReason(info, class, className)
	if not info or not info.users or not class or info.users[class] then return nil end
	className = className or class
	if info.restricted and not info.restricted[class] then
		return format(T("nur für %s"), info.restrictedText or T("andere Klassen"))
	end
	if info.offhand and not L.DUAL_WIELD[class] then
		return format(T("als %s nicht in der Schildhand führbar"), className)
	end
	return format(T("als %s nicht tragbar (%s)"), className, info.subType or "?")
end

-- Reittiere aus Raids und Dungeons, falls der Client keine Unterklasse liefert
L.MOUNTS = {
	[19872] = true, -- Schneller Razzashiraptor (Zul'Gurub)
	[19902] = true, -- Schneller zulianischer Tiger (Zul'Gurub)
	[21218] = true, -- Blauer Qirajiresonanzkristall
	[21321] = true, -- Roter Qirajiresonanzkristall
	[21323] = true, -- Grüner Qirajiresonanzkristall
	[21324] = true, -- Gelber Qirajiresonanzkristall
	[21176] = true, -- Schwarzer Qirajiresonanzkristall
	[13335] = true, -- Zügel des Todesstreitrosses (Stratholme)
}

L.SCARABS = { 20858, 20859, 20860, 20861, 20862, 20863, 20864, 20865 } -- Skarabäen (AQ, grün)
L.COFFER_KEY, L.GREATER_COFFER_KEY = 21761, 21762 -- Schlüssel für einen (großen) Skarabäuskasten (weiß)
L.BLOODVINE = 19726 -- Blutrebe (Zul'Gurub, grün)
-- Schmuckstücke der Hakkari (Zul'Gurub, blau): Rot, Blau, Gelb, Orange, Grün, Lila, Bronze, Silber, Gold
L.HAKKARI_BIJOUS = { 19707, 19708, 19709, 19710, 19711, 19712, 19713, 19714, 19715 }

-- Klassenbücher aus AQ20 (blau), je drei pro Klasse
L.AQ20_BOOKS = {
	21214, 21279, 21280, -- Magier: Frostblitz XI, Feuerball XII, Arkane Geschosse VIII
	21281, 21282, 21283, -- Hexenmeister: Schattenblitz X, Feuerbrand VIII, Verderbnis VII
	21284, 21285, 21287, -- Priester: Große Heilung V, Erneuerung X, Gebet der Heilung V
	21288, 21289, 21290, -- Paladin: Segen der Weisheit VI, Segen der Macht VII, Heiliges Licht IX
	21291, 21292, 21293, -- Schamane: Welle der Heilung X, Totem der Erdstärke V, Totem der luftgleichen Anmut III
	21294, 21295, 21296, -- Druide: Heilende Berührung XI, Sternenfeuer VII, Verjüngung XI
	21297, 21298, 21299, -- Krieger: Heldenhafter Stoß IX, Schlachtruf VII, Rache VI
	21300, 21302, 21303, -- Schurke: Meucheln IX, Tödliches Gift V, Finte V
	21304, 21306, 21307, -- Jäger: Mehrfachschuss V, Schlangenbiss IX, Aspekt des Falken VII
}

-- Raids mit eigener Liste für den Schatzmeister. Liste 0 gilt in allen Instanzen.
L.ALL_INSTANCES = 0
L.RAIDS = {
	{ id = 409, name = "Geschmolzener Kern" },
	{ id = 249, name = "Onyxias Hort" },
	{ id = 469, name = "Pechschwingenhort" },
	{ id = 309, name = "Zul'Gurub" },
	{ id = 509, name = "Ruinen von Ahn'Qiraj" },
	{ id = 531, name = "Tempel von Ahn'Qiraj" },
	{ id = 533, name = "Naxxramas" },
}

-- Vorbelegung: Skarabäen und Kastenschlüssel in AQ20 und AQ40, die Klassenbücher
-- in AQ20, Blutrebe und Schmuckstücke der Hakkari in Zul'Gurub.
function L.DefaultLootLists()
	local aq20 = { [L.COFFER_KEY] = true }
	local aq40 = { [L.COFFER_KEY] = true, [L.GREATER_COFFER_KEY] = true }
	for _, id in ipairs(L.SCARABS) do
		aq20[id], aq40[id] = true, true
	end
	for _, id in ipairs(L.AQ20_BOOKS) do aq20[id] = true end
	local zg = { [L.BLOODVINE] = true }
	for _, id in ipairs(L.HAKKARI_BIJOUS) do zg[id] = true end
	return { [L.ALL_INSTANCES] = {}, [509] = aq20, [531] = aq40, [309] = zg }
end

-- Items, die immer verwürfelt werden: alle würfeln mit /roll 100, ein Gewinn
-- senkt keine Stufe. Zul'Gurub: die Items des wechselnden Bosses am Rand des
-- Wahnsinns (grün, werden beim Aufheben gebunden).
L.ZG_ROLL_ITEMS = {
	19939, -- Gri'leks Blut
	19940, -- Renatakis Zahn
	19941, -- Wushoolays Mähne
	19942, -- Hazza'rahs Traumfaden
}
function L.DefaultRollLists()
	local zg = {}
	for _, id in ipairs(L.ZG_ROLL_ITEMS) do zg[id] = true end
	return { [L.ALL_INSTANCES] = {}, [309] = zg }
end

-- Wer bekommt ein Item automatisch? Items der Liste nur der Schatzmeister, alles
-- andere in den gewählten Qualitäten der Plünderhelfer. Items zum Verwürfeln nie.
-- rules = { items = {[id]=true} (Schatzmeister), roll = {[id]=true} (immer verwürfeln),
--           qualities = {[Qualität]=true}, recipeRolls, helper = Plünderhelfer, treasurer = Schatzmeister }
-- Rückgabe: "treasurer", "helper" oder nil, dazu true, wenn das Item auf der Liste steht.
function L.AutoLootTarget(itemID, quality, isRecipe, rules)
	if not rules or not itemID then return nil, false end
	if rules.roll and rules.roll[itemID] then return nil, false end
	if rules.items and rules.items[itemID] then
		return rules.treasurer and "treasurer" or nil, true
	end
	if rules.helper and quality and rules.qualities and rules.qualities[quality]
		and not (isRecipe and rules.recipeRolls) then
		return "helper", false
	end
	return nil, false
end

local CLASS_TOKENS = {
	druide = "DRUID", druidin = "DRUID", druid = "DRUID",
	hexenmeister = "WARLOCK", hexenmeisterin = "WARLOCK", warlock = "WARLOCK",
	["jäger"] = "HUNTER", ["jägerin"] = "HUNTER", jaeger = "HUNTER", hunter = "HUNTER",
	krieger = "WARRIOR", kriegerin = "WARRIOR", warrior = "WARRIOR",
	magier = "MAGE", magierin = "MAGE", mage = "MAGE",
	paladin = "PALADIN", paladinin = "PALADIN",
	priester = "PRIEST", priesterin = "PRIEST", priest = "PRIEST",
	schamane = "SHAMAN", schamanin = "SHAMAN", shaman = "SHAMAN",
	schurke = "ROGUE", schurkin = "ROGUE", rogue = "ROGUE",
}

function L.ClassToken(class)
	if type(class) ~= "string" then return nil end
	return CLASS_TOKENS[utf8lower(L.Trim(class))]
end

-------------------------------------------------------------------------------
-- Prioliste einlesen (sahne-team.de: CSV, CSV kurz, TXT)
-------------------------------------------------------------------------------

local function toID(v)
	return L.ItemID(v) or 0
end

local function findHeader(lines)
	for _, line in ipairs(lines) do
		local f = L.Split(line, ";")
		local first = utf8lower(L.Trim(f[1] or ""))
		if (first == "name" or first == "username") and #f >= 2 then
			local cols = {}
			for i, raw in ipairs(f) do
				local v = utf8lower(L.Trim(raw))
				if v == "name" or v == "username" then
					cols.name = i
				elseif v == "klasse" or v == "class" then
					cols.class = i
				else
					local n, kind = v:match("^prio(%d)item(%a+)$")
					n = tonumber(n)
					if n and n >= 1 and n <= 3 then
						if kind == "id" then cols["id" .. n] = i end
						if kind == "name" then cols["nm" .. n] = i end
					end
				end
			end
			if cols.id1 then return cols end
		end
	end
	return nil
end

local function parseLine(line, cols, fmt)
	local f
	if fmt == "TXT" then
		f = {}
		for part in line:gmatch("[^\t]+") do
			part = L.Trim(part)
			if part ~= "" then f[#f + 1] = part end
		end
	else
		f = L.Split(line, ";")
		for i = 1, #f do f[i] = L.Trim(f[i]) end
	end

	local name = f[1]
	if not name or name == "" then return nil, "leer" end
	local lname = utf8lower(name)
	if lname == "name" or lname == "username" or lname == "spieler" then return nil, "kopf" end
	if name:find("%d") or name:find("[%s,]") then return nil, "name" end

	local rec = { name = name, p = { 0, 0, 0 }, pn = { "", "", "" } }
	if cols then
		rec.class = cols.class and f[cols.class] or nil
		for n = 1, 3 do
			rec.p[n] = cols["id" .. n] and toID(f[cols["id" .. n]]) or 0
			rec.pn[n] = cols["nm" .. n] and f[cols["nm" .. n]] or ""
		end
	elseif fmt == "TXT" then
		rec.class = f[2]
		for n = 1, 3 do
			local v = f[n + 2]
			rec.p[n] = v and toID(v) or 0
			if v then rec.pn[n] = L.Trim((v:gsub("%-%d+%s*$", ""))) end
		end
	else
		local f2 = f[2] or ""
		if #f >= 5 and f2 ~= "" and not f2:find("%d") then
			rec.class = f2
			for n = 1, 3 do
				rec.p[n] = toID(f[n + 2])
				rec.pn[n] = f[n + 5] or ""
			end
		else
			for n = 1, 3 do rec.p[n] = toID(f[n + 1]) end
		end
	end
	if rec.class == "" then rec.class = nil end
	rec.token = L.ClassToken(rec.class)
	return rec
end

function L.PrioCount(rec)
	local n = 0
	for i = 1, 3 do
		if rec.p[i] and rec.p[i] ~= 0 then n = n + 1 end
	end
	return n
end

-- Kommentarzeile von priomeister.de am Ende der Liste, z. B.
-- "# PrioMeister: rezepte=wuerfeln; reittiere=prio; spieler=23; prios=61; stand=2026-10-15 18:42; run=ZG 15.10.; link=https://…"
-- Seit 1.19 auch "ausnahmen=18259,18260": Items, die trotz der Regel für Rezepte und Reittiere auf Prio dürfen.
function L.ParseMeta(line)
	local body = line:match("^#%s*[Pp]rio[Mm]eister:%s*(.*)$")
	if not body then return nil end
	local meta = {}
	for part in (body .. ";"):gmatch("([^;]*);") do
		local key, value = part:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
		if key then meta[key:lower()] = value end
	end
	return meta
end

-- Item-IDs aus einer Liste wie "18259, 18260" als Menge kanonischer IDs.
function L.ParseIDSet(text)
	local set = {}
	for id in tostring(text or ""):gmatch("%d+") do
		local canon = L.Canon(tonumber(id))
		if canon then set[canon] = true end
	end
	return set
end

-------------------------------------------------------------------------------
-- Priocheck von priomeister.de (seit 1.20): wer in einem Prio-Run welche Prios
-- gesetzt hat, ohne Items. So sieht die Raidleitung, wer im Raid noch fehlt, ohne
-- die Eintragung zu schließen und die Liste zu importieren.
-- "# priocheck;v=1;run=Ony+ZG 21.10.;pin=482913;link=https://…;instanzen=Onyxias Hort:1|Zul'Gurub:3"
-- "Arcanaa;Magier;1;111" – je Instanz eine Ziffer je Prio: 1 gesetzt, 0 leer.
-- Wer auf der Seite nichts eingetragen hat, steht nicht in der Liste.
-------------------------------------------------------------------------------

function L.IsPrioCheck(text)
	local first = tostring(text or ""):match("^%s*([^\r\n]*)") or ""
	return first:lower():find("^#%s*priocheck") ~= nil
end

local function SplitFields(line)
	local f = {}
	for part in (line .. ";"):gmatch("([^;]*);") do f[#f + 1] = L.Trim(part) end
	return f
end

-- Ergebnis: { meta = { run, pin, link, v … }, instances = { { name, slots } }, players = { [key] = { name, class, bits } },
-- count } oder nil, wenn der Text kein Priocheck ist.
function L.ParsePrioCheck(text)
	if not L.IsPrioCheck(text) then return nil end
	local check = { meta = {}, instances = {}, players = {}, count = 0 }
	local header = true
	for line in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
		line = L.Trim((line:gsub("\r", "")))
		if header and line ~= "" then
			header = false
			for _, part in ipairs(SplitFields(line)) do
				local key, value = part:match("^([%w_]+)%s*=%s*(.-)$")
				if key and key:lower() == "instanzen" then
					for item in (value .. "|"):gmatch("([^|]*)|") do
						local name, slots = item:match("^%s*(.-)%s*:%s*(%d+)%s*$")
						if name and name ~= "" and tonumber(slots) > 0 then
							check.instances[#check.instances + 1] = { name = name, slots = tonumber(slots) }
						end
					end
				elseif key then
					check.meta[key:lower()] = value
				end
			end
		elseif line ~= "" and not line:find("^#") then
			local f = SplitFields(line)
			local key = L.NameKey(f[1])
			if key then
				local bits = {}
				for i = 3, #f do bits[#bits + 1] = (f[i]:gsub("[^01]", "")) end
				if not check.players[key] then check.count = check.count + 1 end
				check.players[key] = { name = (f[1]:gsub("%-.*$", "")), class = f[2], bits = bits }
			end
		end
	end
	-- ohne Angabe der Instanzen: so viele, wie die Zeilen Gruppen haben
	if #check.instances == 0 then
		for _, p in pairs(check.players) do
			for i, b in ipairs(p.bits) do
				local inst = check.instances[i] or { name = T("Instanz ") .. i, slots = 0 }
				inst.slots = math.max(inst.slots, #b)
				check.instances[i] = inst
			end
		end
	end
	return check
end

-- „2 und 3“, „1, 2 und 3“
local function JoinAnd(list)
	if #list <= 1 then return list[1] or "" end
	return concat(list, ", ", 1, #list - 1) .. T(" und ") .. list[#list]
end

-- Was einem Spieler im Priocheck fehlt: "all" (gar nichts gesetzt), nil (alles gesetzt) oder ein Text
-- wie „Onyxias Hort fehlt, Zul'Gurub ohne Prio 2 und 3“. Bei nur einer Instanz ohne ihren Namen.
function L.CheckMissing(check, p)
	local parts, any = {}, false
	local several = #check.instances > 1
	for i, inst in ipairs(check.instances) do
		local bits = p.bits[i] or ""
		local holes = {}
		for slot = 1, inst.slots do
			if bits:sub(slot, slot) == "1" then any = true else holes[#holes + 1] = tostring(slot) end
		end
		if #holes == inst.slots and several then
			parts[#parts + 1] = inst.name .. T(" fehlt")
		elseif #holes > 0 then
			parts[#parts + 1] = (several and (inst.name .. " ") or "") .. T("ohne Prio ") .. JoinAnd(holes)
		end
	end
	if not any then return "all" end
	if #parts == 0 then return nil end
	return concat(parts, ", ")
end

-- Priocheck gegen den Raid: roster ist eine Liste { key, name }. Ergebnis: none (Namen ohne Prios),
-- partial ({ name, detail }), complete (Anzahl vollständig), away (auf der Liste, aber nicht im Raid).
-- Namen, die nur ohne Akzente passen, zählen wie bei der Prioliste (L.MatchFolded).
function L.CheckRaid(check, roster)
	local res = { none = {}, partial = {}, complete = 0, away = 0 }
	local inRaid, folded, matched = {}, {}, {}
	for _, m in ipairs(roster) do inRaid[m.key] = true end
	for checkKey, rosterKey in pairs(L.MatchFolded(check.players, inRaid)) do
		folded[rosterKey], matched[checkKey] = checkKey, true
	end
	for _, m in ipairs(roster) do
		local p = check.players[m.key] or check.players[folded[m.key]]
		local missing = p and L.CheckMissing(check, p)
		if not p or missing == "all" then
			res.none[#res.none + 1] = m.name
		elseif missing then
			res.partial[#res.partial + 1] = { name = m.name, detail = missing }
		else
			res.complete = res.complete + 1
		end
	end
	for key in pairs(check.players) do
		if not inRaid[key] and not matched[key] then res.away = res.away + 1 end
	end
	L.SortNames(res.none)
	tsort(res.partial, function(a, b) return L.SortKey(a.name) < L.SortKey(b.name) end)
	return res
end

-- "https://priomeister.de/r/746312" → "priomeister.de/r/746312", kurz genug für den Raidchat
function L.ShortLink(url)
	if type(url) ~= "string" then return nil end
	url = url:gsub("^%a+://", ""):gsub("/+$", "")
	return url ~= "" and url or nil
end

-- "2026-10-15 18:42" → "15.10. 18:42"; mit today ("2026-10-15") am selben Tag nur "18:42"
function L.FormatStand(stand, today)
	local y, m, d, hh, mm = tostring(stand or ""):match("^(%d+)%-(%d+)%-(%d+)[ T](%d+):(%d+)")
	if not d then return nil end
	if today and today == format("%s-%s-%s", y, m, d) then return format("%s:%s", hh, mm) end
	return format("%s.%s. %s:%s", d, m, hh, mm)
end

-- Gibt players (Schlüssel = NameKey) und eine Zusammenfassung zurück.
-- Doppelte Spieler: Es gilt der letzte Stand mit den meisten Items.
-- Zeilen mit # sind Kommentare; die von priomeister.de landet in info.meta.
function L.ParsePrioList(text)
	local players = {}
	local info = { players = 0, lines = 0, skipped = {}, duplicates = {}, format = "CSV-kurz" }
	if type(text) ~= "string" then return players, info end
	text = text:gsub("^\239\187\191", "")

	local lines = {}
	for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
		local line = L.Trim((raw:gsub("\r", "")))
		if line ~= "" then lines[#lines + 1] = line end
	end

	local cols = findHeader(lines)
	local fmt = "SEMI"
	if cols then
		info.format = "CSV"
	else
		for _, line in ipairs(lines) do
			if line:find("\t") then fmt = "TXT"; info.format = "TXT"; break end
		end
	end

	for _, line in ipairs(lines) do
		local rec, why
		if line:sub(1, 1) == "#" then
			info.meta = L.ParseMeta(line) or info.meta
			why = "kommentar"
		else
			info.lines = info.lines + 1
			rec, why = parseLine(line, cols, fmt)
		end
		if rec then
			local key = L.NameKey(rec.name)
			local prev = players[key]
			if prev then
				local useNew = L.PrioCount(rec) >= L.PrioCount(prev)
				if useNew then players[key] = rec end
				info.duplicates[#info.duplicates + 1] = {
					name = rec.name,
					count = L.PrioCount(players[key]),
					replaced = useNew,
				}
			else
				players[key] = rec
				info.players = info.players + 1
			end
		elseif why ~= "kopf" and why ~= "leer" and why ~= "kommentar" then
			info.skipped[#info.skipped + 1] = line
		end
	end
	return players, info
end

-- Prioliste an den Raid binden: Ein Eintrag, der nur ohne Akzente zu einem Raidmitglied passt
-- („Leryssia“ auf priomeister.de, „Leryssiá“ im Spiel), bekommt dessen Schlüssel und Schreibweise
-- und behält sie, auch wenn der Spieler den Raid wieder verlässt. roster: [Schlüssel] = { name }.
-- Ergebnis: die umgestellten Namen als { from, to }.
function L.BindPlayers(players, roster)
	local moved = {}
	for listKey, rosterKey in pairs(L.MatchFolded(players, roster)) do
		local p = players[listKey]
		local name = roster[rosterKey].name or p.name
		moved[#moved + 1] = { from = p.name, to = name }
		p.name = name
		players[listKey], players[rosterKey] = nil, p
	end
	tsort(moved, function(a, b) return L.SortKey(a.to) < L.SortKey(b.to) end)
	return moved
end

-- Geladene Prioliste als CSV im Format von sahne-team.de, alphabetisch.
-- itemName(id, csvName) liefert den Itemnamen für die Namensspalten.
function L.PrioListCSV(players, itemName)
	local keys = {}
	for key in pairs(players) do keys[#keys + 1] = key end
	tsort(keys, function(a, b) return L.SortKey(players[a].name) < L.SortKey(players[b].name) end)
	local lines = { "Name;Klasse;prio1itemid;prio2itemid;prio3itemid;prio1itemname;prio2itemname;prio3itemname;" }
	for _, key in ipairs(keys) do
		local p = players[key]
		local fields = { p.name, p.class or "" }
		for i = 1, 3 do fields[#fields + 1] = tostring(p.p[i] or 0) end
		for i = 1, 3 do
			local id, csvName = p.p[i] or 0, p.pn and p.pn[i] or ""
			fields[#fields + 1] = (id ~= 0) and (itemName and itemName(id, csvName) or csvName) or ""
		end
		lines[#lines + 1] = concat(fields, ";") .. ";"
	end
	return concat(lines, "\n")
end

-------------------------------------------------------------------------------
-- Raid-Zustand
-------------------------------------------------------------------------------

-- Instanz aus der GUID einer Leiche oder Truhe („Creature-0-5211-309-41265-11382-…“ → 309).
function L.GUIDMapID(guid)
	if type(guid) ~= "string" then return nil end
	local id = tonumber(guid:match("^%a+%-%d+%-%d+%-(%d+)%-"))
	return (id and id > 0) and id or nil
end

-- Instanzen eines Raids in der Reihenfolge, in der sie vorkamen: gespeichert,
-- aus den Vergaben oder aus der Herkunft der Würfelrunden.
function L.RaidInstances(raid)
	local list, seen = {}, {}
	local function add(id)
		id = tonumber(id)
		if id and id > 0 and not seen[id] then
			seen[id] = true
			list[#list + 1] = id
		end
	end
	for _, id in ipairs(raid.instances or {}) do add(id) end
	for _, aw in ipairs(raid.awards or {}) do add(aw.instance) end
	for _, s in ipairs(raid.sessions or {}) do add(L.GUIDMapID(s.source)) end
	return list
end

-- Korrekturen der Würfelstufe von Hand aus dem Protokoll: Nach jedem Eintrag
-- „Würfelstufe von Hand“ galt 100 - to = freie Gewinne + Korrektur. Für Raids,
-- die vor Version 1.14 ohne ihre Korrekturen ins Archiv kamen.
function L.AdjustFromAwards(awards)
	local free, adjust = {}, {}
	for _, aw in ipairs(awards or {}) do
		if aw.key then
			if L.CountsAsFreeWin(aw) then
				free[aw.key] = (free[aw.key] or 0) + 1
			elseif aw.kind == "tier" and aw.to then
				adjust[aw.key] = (100 - aw.to) - (free[aw.key] or 0)
			end
		end
	end
	return adjust
end

-- Eintrag fürs Archiv: alles, was ein Raid zum Fortsetzen braucht, ohne Würfelrunden,
-- aber mit dem Wurf-Protokoll für den Export.
function L.ArchiveEntry(raid, now)
	return {
		started = raid.started, ended = now, awards = raid.awards, instances = L.RaidInstances(raid),
		players = raid.players, imported = raid.imported, importCount = raid.importCount, meta = raid.meta,
		adjust = raid.adjust, rolled = raid.rolled, rollLog = raid.rollLog,
	}
end

-- Archivierten Raid wieder zum laufenden machen. Würfelrunden beginnen neu,
-- ihre Nummern schließen an die der Vergaben und des Wurf-Protokolls an.
-- Sonst bekäme eine neue Runde die Nummer einer alten ohne Vergabe.
function L.ReopenRaid(entry)
	local r = L.NewRaid(entry.started)
	r.awards = entry.awards or {}
	r.instances = entry.instances
	r.players = entry.players or {}
	r.imported, r.importCount, r.meta = entry.imported, entry.importCount, entry.meta
	r.adjust = entry.adjust or L.AdjustFromAwards(r.awards)
	r.rolled = entry.rolled
	r.rollLog = entry.rollLog
	local seq = 0
	for _, aw in ipairs(r.awards) do
		if type(aw.session) == "number" and aw.session > seq then seq = aw.session end
	end
	for _, e in ipairs(r.rollLog or {}) do
		if type(e.sid) == "number" and e.sid > seq then seq = e.sid end
	end
	r.sessionSeq = seq
	return r
end

function L.NewRaid(now)
	return {
		started = now,
		players = {},   -- Prioliste
		awards = {},    -- Vergaben in zeitlicher Reihenfolge
		adjust = {},    -- manuelle Korrektur der freien Würfelsiege
		sessions = {},  -- Würfelrunden (neueste zuletzt)
		activeId = nil, -- Nummer der aktiven Würfelrunde
		sessionSeq = 0,
	}
end

local function normOpts(opts)
	if type(opts) == "number" then return { prio0Mode = opts } end
	return opts or {}
end

-- Prio-Einträge eines Spielers. prio0Mode: 3 = Prio 1+2+3 gleich, 2 = Prio 1+2 gleich, 0 = aus.
function L.GetEntries(player, prio0Mode)
	local a, b, c = L.Canon(player.p[1]), L.Canon(player.p[2]), L.Canon(player.p[3])
	local entries = {}
	if prio0Mode ~= 0 and a and a == b and not L.PRIO0_EXCLUDED[a] then
		if a == c then
			return { { level = 0, item = a } }
		elseif prio0Mode == 2 then
			entries[1] = { level = 0, item = a }
			if c then entries[2] = { level = 3, item = c } end
			return entries
		end
	end
	if a then entries[#entries + 1] = { level = 1, item = a } end
	if b then entries[#entries + 1] = { level = 2, item = b } end
	if c then entries[#entries + 1] = { level = 3, item = c } end
	return entries
end

-- Vergaben, die einem Spieler selbst gehören (nicht Gildenbank oder Entzaubern).
-- given: Weitergabe von einem anderen Spieler (seit 1.18).
L.PERSONAL = { prio = true, free = true, sec = true, recipe = true, plain = true, random = true, none = true, given = true }

-- Hat der Spieler das Item noch? Eigene Vergabe, die er nicht weitergegeben hat.
function L.Holds(aw)
	return L.PERSONAL[aw.kind] and not aw.givenTo and true or false
end

-- Erfüllt diese Vergabe eine Prio? Per Prio vergeben oder an einen Prio-Halter
-- weitergegeben, und nicht selbst weitergegeben.
function L.UsesPrio(aw)
	return (aw.kind == "prio" or (aw.kind == "given" and aw.level ~= nil)) and not aw.givenTo
end

function L.AwardsOf(raid, key)
	local out = {}
	for _, aw in ipairs(raid.awards) do
		if aw.key == key then out[#out + 1] = aw end
	end
	return out
end

function L.CountAwards(raid, key)
	local n = 0
	for _, aw in ipairs(raid.awards) do
		if aw.key == key and L.Holds(aw) then n = n + 1 end
	end
	return n
end

-- Noch offene Prio-Einträge eines Spielers für ein Item (bester zuerst).
function L.OpenEntriesFor(raid, key, canonItem, prio0Mode)
	local player = raid.players and raid.players[key]
	if not player or not canonItem then return {} end
	local used = {}
	for _, aw in ipairs(raid.awards) do
		if aw.key == key and L.UsesPrio(aw) and L.Canon(aw.itemID) == canonItem then
			used[aw.level] = true
		end
	end
	local open = {}
	for _, e in ipairs(L.GetEntries(player, prio0Mode or 3)) do
		if e.item == canonItem and not used[e.level] then open[#open + 1] = e end
	end
	tsort(open, function(x, y) return x.level < y.level end)
	return open
end

-- Wer hat Prio auf das Item? isPresent(key) entscheidet über Anwesenheit.
-- opts: prio0Mode, ignorePrio (Rezept oder Reittier ohne Prio), recipe, recipeRolls,
-- profession, mount, plain (Item zum Verwürfeln ohne Stufen), passed (Spieler,
-- die auf dieses Exemplar verzichtet haben: bleiben gelistet, zählen aber nicht),
-- unusable(key) (Grund, wenn der Spieler das Item nicht tragen kann: wie passed)
-- mode: "single" (genau einer), "roll" (mehrere würfeln), "recipe", "plain" oder "free".
function L.ResolveItem(raid, itemID, isPresent, opts)
	opts = normOpts(opts)
	local canon = L.Canon(itemID)
	local res = {
		item = canon, levels = { [0] = {}, [1] = {}, [2] = {}, [3] = {} }, topHolders = {}, ignored = {},
		recipe = opts.recipe and true or false, profession = opts.profession,
		mount = opts.mount and true or false,
	}
	if canon then
		for key, player in pairs(raid.players) do
			local open = L.OpenEntriesFor(raid, key, canon, opts.prio0Mode)
			if open[1] then
				local lvl = open[1].level
				local holder = {
					key = key,
					name = player.name,
					token = player.token,
					level = lvl,
					present = isPresent(key) and true or false,
					passed = opts.passed and opts.passed[key] and true or false,
					unusable = opts.unusable and opts.unusable(key) or nil,
					received = L.CountAwards(raid, key),
				}
				if opts.ignorePrio then
					res.ignored[#res.ignored + 1] = holder
				else
					local list = res.levels[lvl]
					list[#list + 1] = holder
				end
			end
		end
	end
	local byName = function(x, y) return L.SortKey(x.name) < L.SortKey(y.name) end
	tsort(res.ignored, byName)
	for lvl = 0, 3 do
		tsort(res.levels[lvl], byName)
		if res.top == nil then
			for _, h in ipairs(res.levels[lvl]) do
				if h.present and not h.passed and not h.unusable then res.topHolders[#res.topHolders + 1] = h end
			end
			if #res.topHolders > 0 then res.top = lvl end
		end
	end
	if res.top == nil then
		res.mode = L.NoPrioMode(opts)
	elseif #res.topHolders == 1 then
		res.mode = "single"
	else
		res.mode = "roll"
	end
	return res
end

-- Würfelart ohne Prio: Rezept-Wurf, Wurf ohne Stufen oder freier Wurf mit Stufen.
function L.NoPrioMode(opts)
	if opts.recipe and opts.recipeRolls then return "recipe" end
	if opts.plain then return "plain" end
	return "free"
end

function L.HasHolders(res)
	for lvl = 0, 3 do
		if res.levels[lvl] and #res.levels[lvl] > 0 then return true end
	end
	return false
end

-------------------------------------------------------------------------------
-- Verzicht: /roll 1 (Ergebnis immer 1, Bereich 1-1) heißt „will ich nicht“.
-- Er gilt nur für dieses Exemplar, also dieselbe Leiche oder Truhe, die Prio
-- bleibt für spätere Exemplare. Im Protokoll steht er als Eintrag der Art
-- "pass", der nicht als Vergabe zählt.
-------------------------------------------------------------------------------

function L.IsPass(low, high)
	return low == 1 and high == 1
end

-- p: key, name, itemID, link, level (Prio des Spielers), source, session
function L.RecordPass(raid, p, now)
	local aw = { kind = "pass", key = p.key, name = p.name, itemID = p.itemID, link = p.link,
		level = p.level, source = p.source, session = p.session, t = now }
	raid.awards[#raid.awards + 1] = aw
	return aw
end

-- Spieler, die auf dieses Exemplar verzichtet haben, als Menge ihrer Schlüssel.
-- Ohne Herkunft (Testmodus, /pm-Befehle) zählen nur Verzichte ohne Herkunft.
function L.PassesFor(raid, itemID, source)
	local canon, set = L.Canon(itemID), {}
	if not canon then return set end
	for _, aw in ipairs(raid.awards or {}) do
		if aw.kind == "pass" and aw.source == source and L.Canon(aw.itemID) == canon then set[aw.key] = true end
	end
	return set
end

-- Chat nach einem Verzicht: wer, worauf und wer jetzt Prio hat.
-- res: Prio-Auflösung des Exemplars nach dem Verzicht.
function L.PassMessages(aw, res)
	local head = format(T("%s verzichtet auf %s (Prio %s)"), aw.name, aw.link or (T("Item ") .. tostring(aw.itemID)), tostring(aw.level))
	if res and res.top ~= nil then
		local names = {}
		for _, h in ipairs(res.topHolders) do names[#names + 1] = h.name end
		return L.AppendChunks({}, format(T("%s – jetzt Prio %d: "), head, res.top), names, "")
	end
	return { head .. T(" – jetzt ohne Prio") }
end

-------------------------------------------------------------------------------
-- Würfelstufen: freie Würfelsiege senken das erlaubte Maximum (100, 99, 98 ...)
-------------------------------------------------------------------------------

-- Weitergaben ohne Prio kosten den Empfänger eine Stufe wie ein freier Wurf, außer bei
-- Items, die ohne Stufen verwürfelt werden (50er-, Rezept-Wurf, Wurf ohne Stufen).
L.TIER_NEUTRAL = { sec = true, recipe = true, plain = true }

-- Senkt diese Vergabe die Würfelstufe? Nur, solange der Spieler das Item hat.
function L.CountsAsFreeWin(aw)
	if aw.givenTo then return false end
	if aw.kind == "free" then return true end
	return aw.kind == "given" and aw.level == nil and not L.TIER_NEUTRAL[aw.origin]
end

function L.FreeWins(raid, key)
	local n = 0
	for _, aw in ipairs(raid.awards) do
		if aw.key == key and L.CountsAsFreeWin(aw) then n = n + 1 end
	end
	n = n + ((raid.adjust and raid.adjust[key]) or 0)
	if n < 0 then n = 0 end
	return n
end

function L.AllowedMax(raid, key)
	local m = 100 - L.FreeWins(raid, key)
	if m < 1 then m = 1 end
	return m
end

-------------------------------------------------------------------------------
-- Würfelrunden
-------------------------------------------------------------------------------

-- opts.secondary: 50er-Würfe (Zweitchar/Zweitskillung) erlaubt
-- opts.source: Herkunft der Beute (GUID der Leiche oder Truhe)
-- opts.copies: Anzahl gleicher Items in dieser Beute (für Vergaben per Handel)
function L.NewSession(raid, itemID, link, res, now, opts)
	opts = opts or {}
	raid.sessionSeq = (raid.sessionSeq or 0) + 1
	raid.sessions = raid.sessions or {}
	local s = {
		id = raid.sessionSeq,
		item = L.Canon(itemID),
		itemID = itemID,
		link = link,
		started = now,
		rolls = {},
		winners = {},
		source = opts.source,
		copies = opts.copies,
	}
	if res and res.top ~= nil then
		s.mode = "prio"
		s.level = res.top
		s.eligible = {}
		for _, h in ipairs(res.topHolders) do s.eligible[h.key] = h.name end
	elseif res and res.mode == "recipe" then
		s.mode = "recipe"
		s.profession = res.profession
	elseif res and res.mode == "plain" then
		s.mode = "plain"
	else
		s.mode = "free"
	end
	if opts.secondary and s.mode ~= "prio" then s.secondary = true end
	raid.sessions[#raid.sessions + 1] = s
	while #raid.sessions > 25 do table.remove(raid.sessions, 1) end
	raid.activeId = s.id
	return s
end

-- Aktive Würfelrunde. Gespeichert wird nur ihre Nummer, weil WoW mehrfach
-- referenzierte Tabellen beim Speichern als getrennte Kopien ablegt.
function L.ActiveSession(raid)
	if not raid.activeId or not raid.sessions then return nil end
	for i = #raid.sessions, 1, -1 do
		if raid.sessions[i].id == raid.activeId then return raid.sessions[i] end
	end
	return nil
end

function L.SessionById(raid, id)
	if not id or not raid.sessions then return nil end
	for i = #raid.sessions, 1, -1 do
		if raid.sessions[i].id == id then return raid.sessions[i] end
	end
	return nil
end

-- Gehört eine Würfelrunde zu diesem Exemplar? Erledigte Runden (alle Exemplare
-- vergeben) zählen nie. ctx.session nennt die Runde direkt, ctx.source ist die
-- GUID der Leiche oder Truhe. Ohne beides, etwa bei /pm vergabe, zählt die
-- neueste offene Runde.
function L.SessionMatches(s, ctx)
	if not s or s.done then return false end
	if ctx and ctx.session then return s.id == ctx.session end
	if ctx and ctx.source and s.source then return ctx.source == s.source end
	return true
end

-- Neueste passende Würfelrunde für ein Item.
function L.FindSession(raid, itemID, ctx)
	local canon = L.Canon(itemID)
	if not canon or not raid.sessions then return nil end
	for i = #raid.sessions, 1, -1 do
		local s = raid.sessions[i]
		if s.item == canon and L.SessionMatches(s, ctx) then return s end
	end
	return nil
end

-- Neueste offene Runde für ein Item, in der der Spieler gültig gewürfelt und
-- noch nichts bekommen hat (Vergabe per Handel).
function L.FindSessionWithRoll(raid, itemID, key)
	local canon = L.Canon(itemID)
	if not canon or not key or not raid.sessions then return nil end
	for i = #raid.sessions, 1, -1 do
		local s = raid.sessions[i]
		if s.item == canon and not s.done and not s.winners[key] then
			for _, r in ipairs(s.rolls) do
				if r.key == key and r.status == "ok" then return s end
			end
		end
	end
	return nil
end

-- Verzicht in einer Würfelrunde: Der Spieler scheidet aus, seine bisherigen
-- Würfe zählen nicht mehr (Status "withdrawn"), spätere auch nicht.
-- Mit raid steht das auch im Wurf-Protokoll.
function L.PassInSession(s, key, name, now, raid)
	s.passed = s.passed or {}
	s.passed[key] = true
	for _, r in ipairs(s.rolls) do
		if r.key == key and (r.status == "ok" or r.status == "range") then
			r.was, r.wasReason = r.status, r.reason
			r.status, r.reason = "withdrawn", T("zurückgezogen")
			L.SyncLoggedRoll(raid, s, r)
		end
	end
	local r = { key = key, name = name, value = 1, low = 1, high = 1, t = now, seq = #s.rolls + 1,
		status = "pass", reason = "verzichtet" }
	s.rolls[#s.rolls + 1] = r
	return r
end

-- Verzicht zurücknehmen („Letzte zurücknehmen“): Die Würfe zählen wieder, eine
-- wegen des Verzichts geschlossene Runde ist wieder offen.
function L.UndoPassInSession(s, key, raid)
	if not (s.passed and s.passed[key]) then return end
	s.passed[key] = nil
	for _, r in ipairs(s.rolls) do
		if r.key == key and r.status == "withdrawn" then
			r.status, r.reason, r.was, r.wasReason = r.was, r.wasReason, nil, nil
			L.SyncLoggedRoll(raid, s, r)
		elseif r.key == key and r.status == "pass" then
			r.status, r.reason = "undone", T("Verzicht zurückgenommen")
			L.SyncLoggedRoll(raid, s, r)
		end
	end
	if s.closedByPass and not s.done then s.closed, s.closedByPass = nil, nil end
end

-- Prio-Runde: Berechtigte, die weder verzichtet noch etwas bekommen haben.
function L.RemainingEligible(s)
	local n = 0
	for key in pairs(s.eligible or {}) do
		if not (s.passed and s.passed[key]) and not s.winners[key] then n = n + 1 end
	end
	return n
end

-- Bewertet einen Wurf. isMember(key) prüft die Raid-Zugehörigkeit (darf nil sein).
-- status: ok, range (falscher Bereich), fremd (nicht berechtigt), doppelt,
-- pass (Verzicht mit /roll 1), withdrawn (Wurf vor einem Verzicht).
-- kind "sec": 50er-Wurf für Zweitchar oder Zweitskillung.
-- unusable(key): Grund, wenn der Spieler das Item nicht tragen kann, auch in Prio-Runden.
-- 50er-Würfe zählen trotzdem, sie können für einen Zweitchar sein.
function L.AddRoll(raid, s, name, value, low, high, now, isMember, unusable)
	local key = L.NameKey(name)
	local r = { key = key, name = name, value = value, low = low, high = high, t = now, seq = #s.rolls + 1 }

	-- Wer auf dieses Exemplar verzichtet hat, würfelt nicht mehr mit.
	if (s.passed and s.passed[key]) or (raid and L.PassesFor(raid, s.itemID, s.source)[key]) then
		r.status, r.reason = "fremd", T("hat verzichtet")
		s.rolls[#s.rolls + 1] = r
		return r
	end
	-- /roll 1: Verzicht, auch während eines Stichwurfs
	if L.IsPass(low, high) then
		if s.winners[key] then
			r.status, r.reason = "doppelt", T("hat schon erhalten")
		elseif s.mode == "prio" and not s.eligible[key] then
			r.status, r.reason = "fremd", T("kein Prio ") .. tostring(s.level)
		elseif isMember and not isMember(key) then
			r.status, r.reason = "fremd", T("nicht im Raid")
		else
			return L.PassInSession(s, key, name, now, raid)
		end
		s.rolls[#s.rolls + 1] = r
		return r
	end

	-- Stichwurf: nur die Gleichplatzierten, mit derselben Stufe wie beim ersten Wurf
	local tb = s.tiebreak
	if tb then
		r.expected, r.inTiebreak = tb.high, tb.round
		local already = false
		for _, old in ipairs(s.rolls) do
			if old.key == key and old.tb == tb.round then already = true end
		end
		if not tb.players[key] then
			r.status, r.reason = "fremd", T("nicht im Stichwurf")
		elseif already then
			r.status, r.reason = "doppelt", T("zweiter Stichwurf zählt nicht")
		elseif low ~= 1 or high ~= tb.high then
			r.status, r.reason = "range", format(T("Stichwurf mit /roll %d"), tb.high)
		else
			r.status, r.tb = "ok", tb.round
		end
		s.rolls[#s.rolls + 1] = r
		return r
	end

	local hasValid, hadWrong = false, false
	for _, old in ipairs(s.rolls) do
		if old.key == key then
			if old.status == "ok" then hasValid = true end
			if old.status == "range" then hadWrong = true end
		end
	end

	local expected = 100
	if s.mode == "free" then expected = L.AllowedMax(raid, key) end
	r.expected = expected
	local isSecondary = s.secondary and low == 1 and high == 50 and expected > 50
	local why = not isSecondary and unusable and unusable(key) or nil

	if why then
		r.status, r.reason, r.unusable = "fremd", why, true
	elseif s.mode == "prio" and not s.eligible[key] then
		r.status, r.reason = "fremd", T("kein Prio ") .. tostring(s.level)
	elseif s.mode ~= "prio" and isMember and not isMember(key) then
		r.status, r.reason = "fremd", T("nicht im Raid")
	elseif hasValid then
		r.status, r.reason = "doppelt", T("zweiter Wurf zählt nicht")
	elseif isSecondary then
		r.status, r.kind = "ok", "sec"
		if hadWrong then r.reroll = true end
	elseif low ~= 1 or high > expected or (s.mode ~= "free" and high ~= 100) then
		r.status, r.reason = "range", format(T("muss /roll %d würfeln"), expected)
	else
		r.status = "ok"
		if hadWrong then r.reroll = true end
		if high < expected then r.lower = true end
	end
	s.rolls[#s.rolls + 1] = r
	return r
end

local function rollCategory(r)
	return (r.kind == "sec") and 2 or 1
end

-- Stichwurf-Werte je Spieler: map[key][Runde] = Wert
local function tiebreakMap(s)
	local map = {}
	for _, r in ipairs(s.rolls) do
		if r.tb and r.status == "ok" then
			local t = map[r.key]
			if not t then
				t = {}
				map[r.key] = t
			end
			if t[r.tb] == nil then t[r.tb] = r.value end
		end
	end
	return map
end

local function tbValue(map, r, round)
	local t = map[r.key]
	return t and t[round] or -1
end

local function sameScore(s, map, a, b)
	if rollCategory(a) ~= rollCategory(b) or a.high ~= b.high or a.value ~= b.value then return false end
	for i = 1, (s.tbRound or 0) do
		if tbValue(map, a, i) ~= tbValue(map, b, i) then return false end
	end
	return true
end

-- Gültige Würfe sortiert: normale Würfe vor 50er-Würfen, höhere Würfelstufe
-- vor niedrigerer, dann der Wert, dann die Stichwürfe.
-- Rückgabe: ok, other, first und tied (bei Gleichstand an der Spitze), map (Stichwürfe)
function L.RankRolls(s)
	local ok, other = {}, {}
	for _, r in ipairs(s.rolls) do
		if r.status ~= "ok" then
			other[#other + 1] = r
		elseif not r.tb then
			ok[#ok + 1] = r
		end
	end
	local map = tiebreakMap(s)
	local rounds = s.tbRound or 0
	tsort(ok, function(a, b)
		local ca, cb = rollCategory(a), rollCategory(b)
		if ca ~= cb then return ca < cb end
		if a.high ~= b.high then return a.high > b.high end
		if a.value ~= b.value then return a.value > b.value end
		for i = 1, rounds do
			local va, vb = tbValue(map, a, i), tbValue(map, b, i)
			if va ~= vb then return va > vb end
		end
		return (a.seq or 0) < (b.seq or 0)
	end)
	-- Gleichstand zählt nur, wenn er über die Zahl der noch offenen Exemplare
	-- hinausgeht: Bei zwei Exemplaren und 90, 90, 80 bekommen beide 90er eins.
	local open, given = {}, 0
	for _ in pairs(s.winners) do given = given + 1 end
	for _, r in ipairs(ok) do
		if not s.winners[r.key] then open[#open + 1] = r end
	end
	local remaining = math.max((s.copies or 1) - given, 1)
	local cut, after = open[remaining], open[remaining + 1]
	if cut and after and sameScore(s, map, cut, after) then
		local tied = {}
		for _, r in ipairs(open) do
			if sameScore(s, map, r, cut) then tied[#tied + 1] = r end
		end
		return ok, other, cut, tied, map
	end
	return ok, other, nil, nil, map
end

-- Stichwurf-Werte eines Spielers in Rundenfolge.
function L.TiebreakValues(s, map, key)
	local out = {}
	local t = map and map[key]
	if t then
		for i = 1, (s.tbRound or 0) do
			if t[i] then out[#out + 1] = t[i] end
		end
	end
	return out
end

-- Wartet ein Spieler noch auf seinen Stichwurf?
function L.WaitingForTiebreak(s, key)
	local tb = s.tiebreak
	if not tb or s.closed or not tb.players[key] then return false end
	if s.passed and s.passed[key] then return false end
	-- Haben alle anderen Gleichplatzierten verzichtet, ist kein Stichwurf mehr nötig.
	local others = 0
	for k in pairs(tb.players) do
		if k ~= key and not (s.passed and s.passed[k]) then others = others + 1 end
	end
	if others == 0 then return false end
	for _, r in ipairs(s.rolls) do
		if r.key == key and r.tb == tb.round then return false end
	end
	return true
end

-- Startet einen Stichwurf unter den Gleichplatzierten an der Spitze.
-- Gestochen wird mit derselben Stufe wie beim ersten Wurf.
function L.StartTiebreak(s)
	local _, _, first, tied, map = L.RankRolls(s)
	if not tied then return nil end
	local value, again = first.value, false
	for i = (s.tbRound or 0), 1, -1 do
		local v = tbValue(map, first, i)
		if v >= 0 then
			value, again = v, true
			break
		end
	end
	s.tbRound = (s.tbRound or 0) + 1
	local players = {}
	for _, r in ipairs(tied) do players[r.key] = r.name end
	s.tiebreak = { round = s.tbRound, players = players, high = first.high, value = value, again = again }
	return tied
end

function L.TiebreakMessages(s, link)
	local tb = s.tiebreak
	if not tb then return {} end
	local names = {}
	for _, n in pairs(tb.players) do names[#names + 1] = n end
	L.SortNames(names)
	local prefix = tb.again and format(T("%s – wieder Gleichstand (%d): "), link, tb.value)
		or format(T("%s – Gleichstand bei %d: "), link, tb.value)
	return L.AppendChunks({}, prefix, names, format(T(" – Stichwurf, bitte /roll %d"), tb.high))
end

function L.ValidRollCount(s)
	local n = 0
	for _, r in ipairs(s.rolls) do
		if r.status == "ok" then n = n + 1 end
	end
	return n
end

-- Würfe von Spielern, die in der Runde noch nichts bekommen haben, für die
-- Rückfrage vor „An Entzauberer“ und „Zufällig vergeben“: erst die gültigen in
-- der Reihenfolge des Panels, dann Würfe im falschen Bereich ohne gültigen Wurf.
function L.OpenRolls(s)
	local list, seen = {}, {}
	if not s then return list end
	local ok, other = L.RankRolls(s)
	for _, group in ipairs({ ok, other }) do
		for _, r in ipairs(group) do
			if (r.status == "ok" or r.status == "range") and r.key and not s.winners[r.key] and not seen[r.key] then
				seen[r.key] = true
				list[#list + 1] = r
			end
		end
	end
	return list
end

-- Gewinner des nächsten Exemplars: höchster gültiger Wurf eines Spielers, der
-- in dieser Runde noch nichts bekommen hat. nil ohne Würfe, bei Gleichstand um
-- dieses Exemplar und solange ein Stichwurf aussteht.
function L.RoundWinner(s)
	if not s then return nil end
	local tb = s.tiebreak
	if tb and not s.closed then
		for key in pairs(tb.players) do
			if L.WaitingForTiebreak(s, key) then return nil end
		end
	end
	local ok, _, _, tied = L.RankRolls(s)
	local first
	for _, r in ipairs(ok) do
		if not s.winners[r.key] then
			first = r
			break
		end
	end
	if not first then return nil end
	for _, r in ipairs(tied or {}) do
		if r == first then return nil end
	end
	return first
end

-- Kurzfassung der Würfe für Rückfragen, z. B. „Shanya 87, Mira 45 (1-50), Bodo 95 (ungültig)“.
function L.RollSummary(rolls, maxCount)
	maxCount = maxCount or 5
	local parts = {}
	for i = 1, math.min(#rolls, maxCount) do
		local r = rolls[i]
		local extra = ""
		if r.status ~= "ok" then
			extra = T(" (ungültig)")
		elseif r.high ~= 100 then
			extra = format(" (%d-%d)", r.low, r.high)
		end
		parts[#parts + 1] = format("%s %d%s", r.name, r.value, extra)
	end
	local text = concat(parts, ", ")
	if #rolls > maxCount then text = format(T("%s und %d weitere"), text, #rolls - maxCount) end
	return text
end

-- „Prio 1: Anna, Bodo“ für eine Prio-Runde, sonst nil. Wer verzichtet hat, fehlt.
function L.SessionPrioText(s)
	if not s or s.mode ~= "prio" or not s.eligible then return nil end
	local names = {}
	for key, n in pairs(s.eligible) do
		if not (s.passed and s.passed[key]) then names[#names + 1] = n end
	end
	L.SortNames(names)
	if #names == 0 then return nil end
	return format("Prio %s: %s", tostring(s.level), concat(names, ", "))
end

-- Text einer Rückfrage: Item, Prio-Halter und bisherige Würfe, je eine Zeile.
function L.ConfirmText(link, prioText, rolls)
	local lines = { link or "?" }
	if prioText then lines[#lines + 1] = prioText end
	if rolls and #rolls > 0 then lines[#lines + 1] = T("Gewürfelt: ") .. L.RollSummary(rolls) end
	return concat(lines, "\n")
end

-------------------------------------------------------------------------------
-- Vergaben
-------------------------------------------------------------------------------

-- Ordnet eine bestätigte Vergabe ein.
-- opts: prio0Mode, ignorePrio, reason ("de" bei Klick auf Entzauberer, "helper" bzw.
-- "treasurer" bei automatischer Verteilung, "random"), disenchanter, helper, treasurer
-- (Schlüssel der Rollen), listed (Item steht auf der Liste des Schatzmeisters)
function L.BuildAward(raid, key, name, itemID, link, opts, now)
	opts = normOpts(opts)
	local canon = L.Canon(itemID)
	local aw = { key = key, name = name, itemID = itemID, link = link, t = now, kind = "none" }
	local s = L.FindSession(raid, itemID, opts.ctx)
	local roll
	if s then
		for _, r in ipairs(s.rolls) do
			if r.key == key and r.status == "ok" and not r.inTiebreak then roll = r end
		end
		if not roll then
			for _, r in ipairs(s.rolls) do
				if r.key == key and r.status == "range" and not r.inTiebreak then roll = r; break end
			end
		end
	end
	aw.session = s and s.id or nil

	if opts.reason == "de" or opts.reason == "helper" or opts.reason == "treasurer" then
		aw.kind = opts.reason
		return aw
	end
	if opts.reason == "random" then
		aw.kind = "random"
		if opts.place and opts.of then aw.roll, aw.low, aw.high = opts.place, 1, opts.of end
		return aw
	end

	local open = opts.ignorePrio and {} or L.OpenEntriesFor(raid, key, canon, opts.prio0Mode)
	if open[1] then
		aw.kind, aw.level = "prio", open[1].level
		if roll and s.mode == "prio" then
			aw.roll, aw.low, aw.high = roll.value, roll.low, roll.high
		end
	elseif s and roll and s.mode ~= "prio" then
		aw.roll, aw.low, aw.high = roll.value, roll.low, roll.high
		if roll.kind == "sec" then
			aw.kind = "sec"
		elseif s.mode == "recipe" then
			aw.kind = "recipe"
		elseif s.mode == "plain" then
			aw.kind = "plain"
		else
			aw.kind = "free"
			aw.expected = roll.expected
			if roll.status ~= "ok" then aw.flag = "range" end
		end
	elseif opts.treasurer and key == opts.treasurer and opts.listed then
		aw.kind = "treasurer"
	elseif opts.disenchanter and key == opts.disenchanter then
		aw.kind = "de"
	elseif opts.helper and key == opts.helper then
		aw.kind = "helper"
	end
	if aw.roll and s then
		local values = L.TiebreakValues(s, tiebreakMap(s), key)
		if #values > 0 then aw.tb = values end
	end
	return aw
end

function L.RecordAward(raid, aw)
	raid.awards[#raid.awards + 1] = aw
	local s = L.SessionById(raid, aw.session)
	if s then s.winners[aw.key] = true end
	return #raid.awards
end

-- Würfelstufe von Hand geändert: steht mit Uhrzeit in der Vergabeliste.
-- from/to: erlaubtes Maximum vorher und nachher, prevAdjust für „Letzte zurücknehmen“.
function L.RecordTierChange(raid, key, name, from, to, prevAdjust, now)
	raid.awards[#raid.awards + 1] = { key = key, name = name, kind = "tier", from = from, to = to, prevAdjust = prevAdjust, t = now }
	return #raid.awards
end

-- Einträge im Protokoll, die keine Vergabe sind: Würfelstufe von Hand, Verzicht, Weitergabe.
L.NOTE_KINDS = { tier = true, pass = true, given = true }

-- Anzahl echter Vergaben (ohne Änderungen der Würfelstufe und Verzichte).
function L.AwardCount(raid)
	local n = 0
	for _, aw in ipairs(raid and raid.awards or {}) do
		if not L.NOTE_KINDS[aw.kind] then n = n + 1 end
	end
	return n
end

function L.UndoLast(raid)
	local aw = table.remove(raid.awards)
	if not aw then return nil end
	if aw.kind == "tier" then
		raid.adjust[aw.key] = aw.prevAdjust
		return aw
	end
	if aw.kind == "pass" then
		local s = L.SessionById(raid, aw.session)
		if s then L.UndoPassInSession(s, aw.key, raid) end
		return aw
	end
	if aw.kind == "given" then
		local src = L.HandoverSource(raid, aw)
		if src then src.givenTo, src.givenKey = nil, nil end
		return aw
	end
	if aw.session and raid.sessions then
		for _, s in ipairs(raid.sessions) do
			if s.id == aw.session then
				s.winners[aw.key] = nil
				s.done = nil -- das Exemplar kann neu vergeben werden
				-- Wurde dasselbe Item noch einmal an diesen Spieler vergeben?
				for _, other in ipairs(raid.awards) do
					if other.session == s.id and other.key == aw.key then s.winners[aw.key] = true end
				end
			end
		end
	end
	return aw
end

-------------------------------------------------------------------------------
-- Weitergaben (seit 1.18): Ein Spieler gibt ein Item im Spiel an einen anderen
-- weiter. Das zählt wie eine neue Vergabe an den Empfänger: Hat er Prio darauf, ist
-- sie erfüllt, sonst kostet es ihn eine Würfelstufe wie ein freier Wurf. Die Vergabe
-- des Gebers zählt nicht mehr: Seine Prio ist wieder offen, ein freier Wurfsieg gibt
-- die Stufe zurück. Auch Items von Entzauberer, Plünderhelfer und Schatzmeister lassen
-- sich so an einen Spieler weitergeben.
-------------------------------------------------------------------------------

function L.CanHandOver(aw)
	return aw ~= nil and not aw.givenTo and aw.kind ~= "tier" and aw.kind ~= "pass"
end

-- Vergabe, aus der eine Weitergabe stammt, vom Ende her gesucht.
function L.HandoverSource(raid, given)
	local canon = L.Canon(given.itemID)
	for i = #raid.awards, 1, -1 do
		local o = raid.awards[i]
		if o ~= given and o.key == given.fromKey and o.givenKey == given.key and L.Canon(o.itemID) == canon
			and (given.srcT == nil or o.t == given.srcT) then
			return o, i
		end
	end
	return nil
end

local function HandoverError(src, key)
	if not src then return T("Diese Vergabe gibt es nicht mehr.") end
	if src.givenTo then return format(T("%s hat das Item schon an %s weitergegeben."), src.name, src.givenTo) end
	if not L.CanHandOver(src) then return T("Weitergeben lassen sich nur vergebene Items.") end
	if not key then return T("Kein Name angegeben.") end
	if key == src.key then return format(T("%s hat das Item schon."), src.name) end
	return nil
end

-- Trägt die Weitergabe der Vergabe index an den Spieler key ein: neue Vergabe
-- „Weitergabe“ am Ende der Liste, die Vergabe davor merkt sich, an wen.
-- Ergebnis: neue Vergabe oder nil, Fehlertext.
function L.RecordHandover(raid, index, key, name, now, prio0Mode)
	local src = raid.awards[index]
	local err = HandoverError(src, key)
	if err then return nil, err end
	local open = L.OpenEntriesFor(raid, key, L.Canon(src.itemID), prio0Mode)
	local aw = { key = key, name = name, kind = "given", itemID = src.itemID, link = src.link, t = now,
		from = src.name, fromKey = src.key, srcT = src.t, origin = src.origin or src.kind,
		instance = src.instance, quality = src.quality, level = open[1] and open[1].level or nil }
	src.givenTo, src.givenKey = name, key
	raid.awards[#raid.awards + 1] = aw
	return aw
end

-- Was eine Weitergabe für Prio und Würfelstufe bedeutet, für die Rückfrage: Sie wird
-- probeweise eingetragen und wieder entfernt. Ergebnis: Zeilen oder nil, Fehlertext.
function L.HandoverEffects(raid, index, key, name, prio0Mode)
	local src = raid.awards[index]
	local err = HandoverError(src, key)
	if err then return nil, err end
	local beforeTo, beforeFrom = L.AllowedMax(raid, key), L.AllowedMax(raid, src.key)
	local srcPrio = L.UsesPrio(src) and src.level
	local aw = L.RecordHandover(raid, index, key, name, 0, prio0Mode)
	local afterTo, afterFrom = L.AllowedMax(raid, key), L.AllowedMax(raid, src.key)
	L.UndoLast(raid)
	local lines = {}
	if aw.level then
		lines[#lines + 1] = format(T("%s: Prio %d auf das Item ist damit erfüllt."), name, aw.level)
	elseif afterTo ~= beforeTo then
		lines[#lines + 1] = format(T("%s würfelt dann mit /roll %d statt %d."), name, afterTo, beforeTo)
	else
		lines[#lines + 1] = format(T("%s: Würfelstufe bleibt bei /roll %d."), name, beforeTo)
	end
	if srcPrio then
		lines[#lines + 1] = format(T("%s: Prio %d auf das Item ist wieder offen."), src.name, srcPrio)
	elseif afterFrom ~= beforeFrom then
		lines[#lines + 1] = format(T("%s würfelt wieder mit /roll %d statt %d."), src.name, afterFrom, beforeFrom)
	end
	return lines
end

function L.HandoverUndoLine(aw)
	return format(T("Weitergabe zurückgenommen: %s ist wieder bei %s"), aw.link or (T("Item ") .. tostring(aw.itemID)), tostring(aw.from or "?"))
end

-- Weitergabe zurücknehmen, auch mitten in der Liste: Die Vergabe davor zählt wieder.
-- Nur, solange der Empfänger das Item nicht selbst weitergegeben hat.
-- Ergebnis: entfernte Weitergabe und ihre Quelle oder nil, Fehlertext.
function L.RemoveHandover(raid, index)
	local aw = raid.awards[index]
	if not aw or aw.kind ~= "given" then return nil, T("Das ist keine Weitergabe.") end
	if aw.givenTo then
		return nil, format(T("%s hat das Item schon an %s weitergegeben, erst diese Weitergabe zurücknehmen."), aw.name, aw.givenTo)
	end
	local src = L.HandoverSource(raid, aw)
	if src then src.givenTo, src.givenKey = nil, nil end
	table.remove(raid.awards, index)
	return aw, src
end

L.KIND_TEXT = {
	prio = "Prio", free = "freier Wurf", sec = "50er-Wurf", recipe = "Rezept-Wurf", plain = "Wurf ohne Stufen",
	de = "Entzauberer", helper = "Plünderhelfer", treasurer = "Schatzmeister", random = "zufällig vergeben",
	none = "ohne Wurf", tier = "Würfelstufe von Hand", pass = "Verzicht", given = "Weitergabe",
}

local function TiebreakText(values)
	if not values or #values == 0 then return "" end
	local parts = {}
	for i, v in ipairs(values) do parts[i] = tostring(v) end
	return T(", Stichwurf ") .. concat(parts, "/")
end

local function BaseDetail(aw)
	if aw.kind == "tier" then
		return format(T("Würfelstufe von Hand von %d auf %d"), aw.from or 100, aw.to or 100)
	elseif aw.kind == "pass" then
		return format(T("Verzicht auf Prio %s"), tostring(aw.level))
	elseif aw.kind == "prio" then
		local s = T("Prio ") .. tostring(aw.level)
		if aw.roll then s = s .. format(T(", Wurf %d (%d-%d)"), aw.roll, aw.low, aw.high) .. TiebreakText(aw.tb) end
		return s
	elseif aw.kind == "free" then
		local s = format(T("freier Wurf %d (%d-%d)"), aw.roll, aw.low, aw.high)
		if aw.flag == "range" then s = s .. format(T(", erlaubt war 1-%d"), aw.expected or 100) end
		return s .. TiebreakText(aw.tb)
	elseif aw.kind == "sec" then
		return format(T("50er-Wurf %d (%d-%d)"), aw.roll, aw.low, aw.high) .. TiebreakText(aw.tb)
	elseif aw.kind == "recipe" then
		return format(T("Rezept-Wurf %d (%d-%d)"), aw.roll, aw.low, aw.high) .. TiebreakText(aw.tb)
	elseif aw.kind == "plain" then
		return format(T("Wurf ohne Stufen %d (%d-%d)"), aw.roll, aw.low, aw.high) .. TiebreakText(aw.tb)
	elseif aw.kind == "random" then
		if aw.roll and aw.high then return format(T("zufällig vergeben (Platz %d von %d)"), aw.roll, aw.high) end
		return T("zufällig vergeben")
	elseif aw.kind == "de" then
		return T("zum Entzaubern")
	elseif aw.kind == "helper" then
		return T("Plünderhelfer")
	elseif aw.kind == "treasurer" then
		return T("Schatzmeister")
	elseif aw.kind == "given" then
		local s = T("Weitergabe von ") .. tostring(aw.from or "?")
		if aw.level then s = s .. format(T(", Prio %s"), tostring(aw.level)) end
		return s
	end
	return T("ohne Wurf")
end

function L.AwardDetail(aw)
	local s = BaseDetail(aw)
	if aw.givenTo then s = s .. format(T(", an %s weitergegeben"), aw.givenTo) end
	return s
end

function L.AwardLine(aw)
	if aw.kind == "tier" then
		return format(T("%s: Würfelstufe von Hand von %d auf %d geändert"), aw.name, aw.from or 100, aw.to or 100)
	elseif aw.kind == "pass" then
		return format(T("%s verzichtet auf %s (Prio %s)"), aw.name, aw.link or (T("Item ") .. tostring(aw.itemID)), tostring(aw.level))
	end
	return format(T("%s erhält %s – %s"), aw.name, aw.link or (T("Item ") .. tostring(aw.itemID)), L.AwardDetail(aw))
end

-------------------------------------------------------------------------------
-- Chat-Texte (maximal 255 Zeichen pro Nachricht)
-------------------------------------------------------------------------------

L.MAX_CHAT = 250

-- Hängt Einträge an, bis die Zeile zu lang wird, und beginnt dann eine neue.
function L.AppendChunks(out, prefix, items, suffix, maxLen)
	maxLen = maxLen or L.MAX_CHAT
	suffix = suffix or ""
	local line, count = prefix, 0
	for _, it in ipairs(items) do
		local add = (count == 0) and it or (", " .. it)
		if count > 0 and #line + #add + #suffix > maxLen then
			out[#out + 1] = line
			line, count = "… " .. it, 1
		else
			line, count = line .. add, count + 1
		end
	end
	out[#out + 1] = line .. suffix
	return out
end

-- members: Liste {key, name} der anwesenden Spieler (für die Würfelstufen).
-- opts: tierHints (Stufen ansagen), copies (Anzahl Exemplare). 50er-Würfe nennt der
-- Aufruf nicht, die Regel kennen alle.
function L.BuildRollCall(raid, res, link, members, opts)
	opts = opts or {}
	local msgs = {}
	local copies = opts.copies or 1
	if copies > 1 then link = link .. " x" .. copies end
	local winners = (copies > 1) and format(T(", die %d höchsten Würfe gewinnen"), copies) or ""
	if res.top ~= nil then
		local names = {}
		for _, h in ipairs(res.topHolders) do names[#names + 1] = h.name end
		if #names == 1 then
			msgs[1] = format(T("%s – Prio %d: %s"), link, res.top, names[1])
		else
			L.AppendChunks(msgs, format(T("%s – Prio %d: "), link, res.top), names, T(" – bitte /roll 100") .. winners)
		end
		return msgs
	end

	if res.mode == "recipe" then
		local prof = res.profession and (T(" für ") .. res.profession) or ""
		msgs[1] = format(T("%s – Rezept%s, nur mit passendem Beruf: /roll 100%s"), link, prof, winners)
		return msgs
	end

	if res.mode == "plain" then
		msgs[1] = format(T("%s – kein Prio, Wurf ohne Stufen: alle /roll 100%s"), link, winners)
		return msgs
	end

	msgs[1] = format(T("%s – %skein Prio, freier Wurf: /roll 100%s"), link, res.mount and T("Reittier, ") or "", winners)
	if opts.tierHints == false then return msgs end
	local tiers, maxima = {}, {}
	for _, m in ipairs(members or {}) do
		local allowed = L.AllowedMax(raid, m.key)
		if allowed < 100 then
			if not tiers[allowed] then
				tiers[allowed] = {}
				maxima[#maxima + 1] = allowed
			end
			local t = tiers[allowed]
			t[#t + 1] = m.name
		end
	end
	tsort(maxima, function(a, b) return a > b end)
	for _, mx in ipairs(maxima) do
		L.AppendChunks(msgs, format(T("Mit /roll %d: "), mx), L.SortNames(tiers[mx]), "")
	end
	return msgs
end

-- Beute-Ansage beim Öffnen: pro Item und Prio-Stufe eine Zeile mit den
-- anwesenden Prio-Haltern, sonst "kein Prio" bzw. der Rezept- oder Reittier-Hinweis.
-- Wer auf dieses Exemplar verzichtet hat oder es nicht tragen kann, fehlt.
function L.LootAnnouncement(res, link, copies)
	local label = link .. ((copies and copies > 1) and (" x" .. copies) or "")
	local out = {}
	for lvl = 0, 3 do
		local names = {}
		for _, h in ipairs(res.levels[lvl] or {}) do
			if h.present and not h.passed and not h.unusable then names[#names + 1] = h.name end
		end
		if #names > 0 then L.AppendChunks(out, format(T("%s – Prio %d: "), label, lvl), names, "") end
	end
	if #out == 0 then
		if res.mode == "recipe" then
			out[1] = format(T("%s – Rezept%s, kein Prio"), label, res.profession and (T(" für ") .. res.profession) or "")
		elseif res.mount then
			out[1] = format(T("%s – Reittier, kein Prio"), label)
		else
			out[1] = format(T("%s – kein Prio"), label)
		end
	end
	return out
end

-- Zufällig vergeben: gewürfelt wird 1 bis n, gezählt durch die Gruppen 1 bis 8.
function L.RandomAnnouncement(link, n)
	return format(T("%s wird zufällig vergeben: Wurf 1-%d, gezählt durch die Gruppen 1 bis 8"), link, n)
end

function L.WrongRollMessage(r)
	if r.unusable then return format(T("%s: Wurf %d zählt nicht – %s"), r.name, r.value, r.reason or T("nicht tragbar")) end
	return format(T("%s: Wurf %d (%d-%d) zählt nicht – bitte /roll %d"), r.name, r.value, r.low, r.high, r.expected or 100)
end

-- Ergebnis der Würfelrunde: höchstens die ersten drei Plätze.
function L.ResultMessage(s, maxCount)
	maxCount = math.min(maxCount or 3, 3)
	local ok, _, _, tied, map = L.RankRolls(s)
	local parts, place, prev = {}, 0, nil
	for i, r in ipairs(ok) do
		if i > maxCount then break end
		if not prev or not sameScore(s, map, prev, r) then place = i end
		local values = L.TiebreakValues(s, map, r.key)
		local extra = (#values > 0) and (" " .. TiebreakText(values):sub(3)) or ""
		parts[#parts + 1] = format("%d. %s %d (%d-%d)%s", place, r.name, r.value, r.low, r.high, extra)
		prev = r
	end
	if #parts == 0 then return format(T("%s: keine gültigen Würfe"), s.link or "?") end
	return format("%s: %s%s", s.link or "?", concat(parts, ", "), tied and T(" – Gleichstand") or "")
end

-------------------------------------------------------------------------------
-- Plündermeister-Liste: angeheftete Spieler oben, Rest alphabetisch
-------------------------------------------------------------------------------

function L.SortCandidates(list, pins)
	local pinRank = {}
	for i, n in ipairs(pins or {}) do
		local k = L.NameKey(n)
		if k and not pinRank[k] then pinRank[k] = i end
	end
	for _, c in ipairs(list) do
		c.sortKey = L.SortKey(c.name)
		c.pin = pinRank[L.NameKey(c.name)]
	end
	tsort(list, function(a, b)
		if a.pin and b.pin then return a.pin < b.pin end
		if a.pin then return true end
		if b.pin then return false end
		if a.sortKey ~= b.sortKey then return a.sortKey < b.sortKey end
		return a.index < b.index
	end)
	return list
end

-- Gleiche Knopf-Reihenfolge wie Blizzards MasterLooterFrame_UpdatePlayers.
function L.MasterLootButtonOrder(n)
	local numColumns = math.max(math.ceil(n / 10), 2)
	local numRows = math.ceil(n / numColumns)
	local order, row, column = {}, 0, 0
	for i = 1, n do
		row = row + 1
		if row > numRows then
			row = 1
			column = column + 1
		end
		order[i] = column * 10 + row
	end
	return order
end

-------------------------------------------------------------------------------
-- Export
-------------------------------------------------------------------------------

-- Vergaben eines Raids zum Teilen im Chat: Kopfzeile, eigene Gewinne einzeln,
-- Vergaben an Plünderhelfer, Schatzmeister und Entzauberer je Spieler gebündelt.
-- opts.lowItems: graue und weiße Items des Plünderhelfers mitzählen. Ohne Vergaben nil.
function L.ShareLines(raid, dateFn, opts)
	opts = opts or {}
	local awards = raid and raid.awards or {}
	if #awards == 0 then return nil end
	local personal, groups, order = {}, {}, {}
	for _, aw in ipairs(awards) do
		if L.PERSONAL[aw.kind] or L.NOTE_KINDS[aw.kind] then
			personal[#personal + 1] = aw
		else
			local gkey = aw.kind .. ":" .. tostring(aw.name)
			local g = groups[gkey]
			if not g then
				g = { kind = aw.kind, name = aw.name or "?", items = {}, counts = {}, low = 0 }
				groups[gkey] = g
				order[#order + 1] = g
			end
			if aw.kind == "helper" and aw.quality and aw.quality < 2 then
				g.low = g.low + (aw.count or 1)
			else
				local id = aw.itemID or 0
				if not g.counts[id] then
					g.counts[id] = 0
					g.items[#g.items + 1] = { id = id, link = aw.link or ("Item " .. tostring(id)) }
				end
				g.counts[id] = g.counts[id] + (aw.count or 1)
			end
		end
	end
	local out = { format(T("Vergaben im Raid vom %s:"), dateFn("%d.%m.%Y, %H:%M", raid.started or 0)) }
	for _, aw in ipairs(personal) do
		local line = L.AwardLine(aw)
		if aw.kind == "tier" then line = line .. format(T(" (%s Uhr)"), dateFn("%H:%M", aw.t or 0)) end
		out[#out + 1] = line
	end
	for _, g in ipairs(order) do
		local parts = {}
		for _, it in ipairs(g.items) do
			local n = g.counts[it.id]
			parts[#parts + 1] = it.link .. ((n > 1) and (" x" .. n) or "")
		end
		if g.low > 0 and opts.lowItems then parts[#parts + 1] = format(T("%d graue/weiße Items"), g.low) end
		if #parts > 0 then
			L.AppendChunks(out, format("%s %s: ", T(L.KIND_TEXT[g.kind] or g.kind), g.name), parts, "")
		end
	end
	return out
end

-------------------------------------------------------------------------------
-- Wurf-Protokoll: jeder Wurf in einer Würfelrunde, auch ungültige. Es bleibt
-- mit dem Raid im Archiv und geht mit dem Export an priomeister.de.
-------------------------------------------------------------------------------

L.ROLL_LOG_MAX = 3000 -- Würfe je Raid
L.MODE_TEXT = { prio = "Prio", free = "freier Wurf", plain = "Wurf ohne Stufen", recipe = "Rezept-Wurf" }
L.ROLL_STATUS_TEXT = { ok = "zählt", range = "falscher Bereich", doppelt = "doppelt", fremd = "zählt nicht", pass = "verzichtet",
	withdrawn = "zurückgezogen", undone = "zurückgenommen" }
L.WITHDRAWN_REASON = "Verzicht mit /roll 1"

-- r: bewerteter Wurf aus L.AddRoll, s: seine Runde, instance: Instanz beim Wurf.
-- q: Nummer des Wurfs in seiner Runde, damit spätere Änderungen ihn finden.
function L.LogRoll(raid, s, r, instance)
	raid.rollLog = raid.rollLog or {}
	local e = { t = r.t, n = r.name, v = r.value, lo = r.low, hi = r.high, st = r.status, q = r.seq,
		i = s.itemID, nm = L.LinkName(s.link), sid = s.id, m = s.mode, lvl = s.level, ins = instance }
	if r.reason then e.why = r.reason end
	if r.kind == "sec" then e.sec = true end
	if r.unusable then e.un = true end
	e.tb = r.tb or r.inTiebreak
	raid.rollLog[#raid.rollLog + 1] = e
	while #raid.rollLog > L.ROLL_LOG_MAX do table.remove(raid.rollLog, 1) end
	return e
end

-- Eintrag eines Wurfs im Protokoll: der neueste aus seiner Runde mit Name, Zeit und Wert.
function L.LoggedRoll(raid, s, r)
	local log = raid and raid.rollLog
	if not log then return nil end
	for i = #log, 1, -1 do
		local e = log[i]
		if e.sid == s.id and e.n == r.name and e.t == r.t and e.v == r.value and (e.q == nil or e.q == r.seq) then
			return e
		end
	end
	return nil
end

-- Ändert sich der Status eines Wurfs später (Verzicht, Rücknahme), ändert er sich
-- auch im Protokoll.
function L.SyncLoggedRoll(raid, s, r)
	local e = L.LoggedRoll(raid, s, r)
	if e then e.st, e.why = r.status, r.status == "withdrawn" and L.WITHDRAWN_REASON or r.reason end
	return e
end

-- Protokolle aus 1.17.0: Würfe vor einem Verzicht stehen dort noch als gültig. Ein
-- Verzicht steht als Vergabe „Verzicht“ mit seiner Runde oder als Wurf /roll 1 darin,
-- ein zurückgenommener steht nirgends mehr. Ergebnis: Anzahl geänderter Würfe.
function L.RepairRollLog(raid)
	local log = raid and raid.rollLog
	if not log then return 0 end
	local function id(sid, name, item)
		local key = L.NameKey(name)
		return sid and key and (sid .. ":" .. key .. ":" .. tostring(L.Canon(item))) or nil
	end
	local passed = {} -- Zeitpunkt des letzten Verzichts je Runde, Spieler und Item
	local function mark(k, t)
		if k and t and (passed[k] or 0) < t then passed[k] = t end
	end
	for _, aw in ipairs(raid.awards or {}) do
		if aw.kind == "pass" then mark(id(aw.session, aw.key, aw.itemID), aw.t) end
	end
	for _, e in ipairs(log) do
		if e.st == "pass" then mark(id(e.sid, e.n, e.i), e.t) end
	end
	local n = 0
	for _, e in ipairs(log) do
		local t = passed[id(e.sid, e.n, e.i) or ""]
		if (e.st == "ok" or e.st == "range") and t and e.t and e.t <= t then
			e.st, e.why, n = "withdrawn", L.WITHDRAWN_REASON, n + 1
		elseif e.st == "withdrawn" then
			e.why = L.WITHDRAWN_REASON
		end
	end
	return n
end

-- Status eines Wurfs im Export: zählt, falscher Bereich, doppelt, nicht tragbar …
function L.RollStatusText(e)
	if e.un then return "nicht tragbar" end
	return L.ROLL_STATUS_TEXT[e.st] or e.st or ""
end

L.EXPORT_HEADER = "Datum;Uhrzeit;Spieler;ItemID;Item;Art;Prio;Wurf;Bereich;Stichwurf;Runde;Rundenart;Status;Grund;Instanz;Raid;Zeitstempel"

-- Export aller Vergaben und Würfe, je Raid nach der Zeit: eine Zeile je Eintrag der
-- Vergabeliste und je Wurf (Art „Wurf“). Die ersten zehn Spalten sind dieselben wie
-- vor Version 1.17; wer nur sie liest, bekommt die Vergaben wie bisher.
-- opts.instanceName(id): Name einer Instanz.
function L.ExportCSV(raids, dateFn, opts)
	opts = opts or {}
	local instanceName = opts.instanceName or function(id) return id and tostring(id) or "" end
	local lines = { L.EXPORT_HEADER }
	for _, raid in ipairs(raids) do
		local raidLabel = raid.started and dateFn("%d.%m.%Y %H:%M", raid.started) or ""
		local rows = {}
		for i, aw in ipairs(raid.awards or {}) do
			-- Weitergabe: eine Sekunde nach der Vergabe davor, wie auf priomeister.de nachgetragen
			local at = (aw.kind == "given" and aw.srcT) and (aw.srcT + 1) or (aw.t or 0)
			local notes = {}
			if aw.kind == "given" then notes[#notes + 1] = "von " .. tostring(aw.from or "?") end
			if aw.givenTo then notes[#notes + 1] = "an " .. aw.givenTo end
			rows[#rows + 1] = { t = at, order = 2, seq = i, text = concat({
				dateFn("%d.%m.%Y", at),
				dateFn("%H:%M", at),
				aw.name or "",
				tostring(aw.itemID or ""),
				L.LinkName(aw.link) or "",
				L.KIND_TEXT[aw.kind] or "ohne Wurf",
				aw.level and tostring(aw.level) or "",
				aw.roll and tostring(aw.roll) or "",
				(aw.kind == "tier" and format("1-%d auf 1-%d", aw.from or 100, aw.to or 100))
					or (aw.roll and format("%d-%d", aw.low or 1, aw.high or 100)) or "",
				aw.tb and concat(aw.tb, "/") or "",
				aw.session and tostring(aw.session) or "",
				"",
				aw.givenTo and "weitergegeben" or "",
				concat(notes, ", "),
				aw.instance and instanceName(aw.instance) or "",
				raidLabel,
				tostring(at),
			}, ";") }
		end
		for i, e in ipairs(raid.rollLog or {}) do
			rows[#rows + 1] = { t = e.t or 0, order = 1, seq = i, text = concat({
				dateFn("%d.%m.%Y", e.t or 0),
				dateFn("%H:%M", e.t or 0),
				e.n or "",
				tostring(e.i or ""),
				e.nm or "",
				"Wurf",
				e.lvl and tostring(e.lvl) or "",
				tostring(e.v or ""),
				format("%d-%d", e.lo or 1, e.hi or 100),
				e.tb and tostring(e.tb) or "",
				e.sid and tostring(e.sid) or "",
				L.MODE_TEXT[e.m] or "",
				L.RollStatusText(e),
				e.why or "",
				e.ins and instanceName(e.ins) or "",
				raidLabel,
				tostring(e.t or ""),
			}, ";") }
		end
		tsort(rows, function(a, b)
			if a.t ~= b.t then return a.t < b.t end
			if a.order ~= b.order then return a.order < b.order end
			return a.seq < b.seq
		end)
		for _, row in ipairs(rows) do lines[#lines + 1] = row.text end
	end
	return concat(lines, "\n")
end

return L
