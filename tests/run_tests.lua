-- Tests für PrioMeister. Aufruf: lua run_tests.lua (im Ordner tests)
TESTDIR = arg and arg[0] and arg[0]:match("^(.*)/[^/]*$") or "."
local ADDON_DIR = TESTDIR .. "/../PrioMeister"
local FILES = { "Locale.lua", "Logic.lua", "Core.lua", "UI.lua", "Main.lua", "Loot.lua" }

local passed, failed = 0, 0
local function check(cond, label, detail)
	if cond then
		passed = passed + 1
	else
		failed = failed + 1
		print("FEHLER: " .. label .. (detail and ("\n   " .. tostring(detail)) or ""))
	end
end
local function eq(a, b, label) check(a == b, label, ("erwartet %s, bekam %s"):format(tostring(b), tostring(a))) end

-------------------------------------------------------------------------------
-- Teil 1: reine Logik
-------------------------------------------------------------------------------

local ns = {}
assert(loadfile(ADDON_DIR .. "/Logic.lua"))("PrioMeister", ns)
local L = ns.Logic

-- Formatstrings
do
	local m = L.FormatToMatcher("%s würfelt. Ergebnis: %d (%d-%d)")
	local r = L.MatchFormat(m, "Sairá würfelt. Ergebnis: 57 (1-100)")
	eq(r and r[1], "Sairá", "Wurf: Name mit Akzent")
	eq(r and r[2], 57, "Wurf: Wert")
	eq(r and r[4], 100, "Wurf: Maximum")
	check(L.MatchFormat(m, "Sairá würfelt. Ergebnis: 57 (1-100) extra") == nil, "Wurf: kein Treffer bei Zusatztext")
	local en = L.FormatToMatcher("%s rolls %d (%d-%d)")
	eq((L.MatchFormat(en, "Gustl rolls 3 (1-99)") or {})[4], 99, "Wurf englisch")
	local pos = L.FormatToMatcher("Beute: %2$s für %1$s.")
	local r3 = L.MatchFormat(pos, "Beute: [Ring] für Gustl.")
	eq(r3 and r3[1], "Gustl", "Positionsangaben %1$s")
	eq(r3 and r3[2], "[Ring]", "Positionsangaben %2$s")
	local loot = L.FormatToMatcher("%s bekommt Beute: %s.")
	local link = "|cffa335ee|Hitem:16914::::::::60:::::::|h[Krone des Netherwinds]|h|r"
	eq((L.MatchFormat(loot, "Bolzenblitz bekommt Beute: " .. link .. ".") or {})[2], link, "Beutemeldung: Link")
	eq(L.ExtractLink("x |cnIQ4:|Hitem:16914::|h[Krone]|h|r y"), "|cnIQ4:|Hitem:16914::|h[Krone]|h|r", "Link mit neuem Farbcode")
end

-- Namen und Items
eq(L.NameKey("Sairá-Everlook"), "sairá", "NameKey ohne Realm")
eq(L.NameKey("ÄRWIN"), "ärwin", "NameKey Umlaut groß")
check(L.SortKey("Ärwin") < L.SortKey("Awfulkitty"), "Sortierung: Ä wie A")
check(L.SortKey("Arcanielle") < L.SortKey("Ärwin"), "Sortierung: Arc vor Är")

-- 1.23: Namen ohne Akzente, wie auf priomeister.de (klein, NFKD ohne Akzente, ß → ss, æ → ae,
-- œ → oe, ø → o, đ und ð → d, þ → th, ł → l)
do
	for _, c in ipairs({
		{ "Leryssiá-Lakeshire", "leryssia" }, { "ÁLVARÔ", "alvaro" }, { "Strauß", "strauss" }, { "Æsir", "aesir" },
		{ "Œdipe", "oedipe" }, { "Øystein", "oystein" }, { "Ðan", "dan" }, { "Đorđe", "dorde" }, { "Þórr", "thorr" },
		{ "Łukasz", "lukasz" }, { "Ýrsa", "yrsa" }, { "Ÿves", "yves" }, { "Ñandú", "nandu" }, { "Çãõ", "cao" },
		{ "Šárka", "sarka" }, { "Ĳsbrand", "ijsbrand" }, { "Arcanaa", "arcanaa" },
	}) do
		eq(L.FoldKey(c[1]), c[2], "FoldKey " .. c[1])
	end
	eq(L.FoldKey(""), nil, "FoldKey: leer")
	eq(L.FoldKey(nil), nil, "FoldKey: nil")
	eq(L.NameKey("Leryssiá"), "leryssiá", "NameKey bleibt exakt, gespeicherte Schlüssel ändern sich nicht")
	check(L.SortKey("Ãlvaro") < L.SortKey("Amon"), "Sortierung: Ã wie A")
	check(L.SortKey("Šárka") < L.SortKey("Sb"), "Sortierung: Š wie S")

	local function set(...)
		local t = {}
		for _, k in ipairs({ ... }) do t[k] = { name = k } end
		return t
	end
	eq(L.MatchFolded(set("leryssia"), set("leryssiá", "gustl")).leryssia, "leryssiá", "ohne Akzent findet den Namen mit Akzent")
	eq(L.MatchFolded(set("leryssiá"), set("leryssia"))["leryssiá"], "leryssia", "und umgekehrt")
	eq(L.MatchFolded(set("leryssìa"), set("leryssiá"))["leryssìa"], "leryssiá", "andere Akzente passen auch")
	eq(next(L.MatchFolded(set("leryssia"), set("leryssia", "leryssiá"))), nil, "exakter Name gewinnt, der andere bekommt nichts")
	eq(next(L.MatchFolded(set("leryssia"), set("leryssiá", "leryssìa"))), nil, "zwei im Raid passen: kein Treffer")
	eq(next(L.MatchFolded(set("leryssia", "léryssia"), set("leryssiá"))), nil, "zwei auf der Liste passen: kein Treffer")
	eq(next(L.MatchFolded(set("arcanaa"), set("arcanaa"))), nil, "exakt gleich: nichts umzustellen")
	eq(next(L.MatchFolded(set("gustl"), set("hesti"))), nil, "verschiedene Namen bleiben verschieden")

	local players = { leryssia = { name = "Leryssia", p = { 16914, 0, 0 }, pn = { "", "", "" } },
		gustl = { name = "Gustl", p = { 17965, 0, 0 }, pn = { "", "", "" } } }
	local entry = players.leryssia
	local moved = L.BindPlayers(players, set("Leryssiá", "gustl"))
	eq(#moved, 1, "eine Zuordnung")
	eq(moved[1] and moved[1].from, "Leryssia", "Zuordnung: Name auf der Liste")
	eq(moved[1] and moved[1].to, "Leryssiá", "Zuordnung: Name im Spiel")
	check(players.leryssia == nil and players["Leryssiá"] == entry and entry.name == "Leryssiá", "Eintrag unter dem Namen im Spiel, mit seinen Prios")
	check(players.gustl and players.gustl.name == "Gustl", "exakte Namen bleiben")
	eq(#L.BindPlayers(players, set("Leryssiá", "gustl")), 0, "zweiter Lauf ändert nichts")

	local chk = L.ParsePrioCheck("# priocheck;v=1;instanzen=Zul'Gurub:3\nLeryssia;Priester;111\nGustl;Krieger;100\nAbwesend;Magier;111\n")
	local res = L.CheckRaid(chk, { { key = "leryssiá", name = "Leryssiá" }, { key = "gustl", name = "Gustl" } })
	eq(res.complete, 1, "Priocheck: Leryssiá vollständig über „Leryssia“")
	eq(#res.none, 0, "Priocheck: niemand ohne Prios")
	eq(#res.partial, 1, "Priocheck: Gustl unvollständig")
	eq(table.concat(res.away, ","), "Abwesend", "Priocheck: nur Abwesend fehlt im Raid")
	res = L.CheckRaid(chk, { { key = "leryssiá", name = "Leryssiá" }, { key = "leryssìa", name = "Leryssìa" } })
	eq(table.concat(res.none, ","), "Leryssiá,Leryssìa", "Priocheck: zwei passen, keiner bekommt den Eintrag")
end

-- 1.26: immer mit /roll 100 würfeln, gewertet wird nach Würfelstufe
do
	local raid = L.NewRaid(0)
	raid.adjust = { gustl = 1, hesti = 2 } -- Gustl Stufe 99, Hesti Stufe 98
	local s = L.NewSession(raid, 18813, "[Ring]", { mode = "free", levels = {} }, 0, { always100 = true, secondary = true })
	check(s.always100, "Runde merkt sich die Regel")
	local function roll(name, v, hi) return L.AddRoll(raid, s, name, v, 1, hi or 100, 1) end
	local g = roll("Gustl", 95)
	eq(g.status, "ok", "Stufe 99 darf /roll 100 würfeln")
	eq(g.tier, 99, "gewertet mit Stufe 99")
	check(not g.lower, "/roll 100 ist nicht „freiwillig niedriger“")
	roll("Arcanaa", 60)
	local h = roll("Hesti", 98, 98)
	eq(h.status, "ok", "/roll 98 mit Stufe 98 geht weiter")
	eq(h.tier, 98, "gewertet mit Stufe 98")
	local z = roll("Zenec", 99, 99)
	eq(z.status, "ok", "Stufe 100 mit /roll 99 gilt")
	eq(z.tier, 100, "zählt mit Stufe 100")
	check(z.lower, "freiwillig niedriger")
	local bad = roll("Kronolus", 120, 1000)
	eq(bad.status, "range", "/roll 1000 zählt nicht")
	eq(L.WrongRollMessage(bad), "Kronolus: Wurf 120 (1-1000) zählt nicht – bitte /roll 100", "Hinweis nennt /roll 100")
	eq(roll("Urmeline", 49, 50).kind, "sec", "50er-Wurf bleibt")
	local ok = L.RankRolls(s)
	local order = {}
	for _, r in ipairs(ok) do order[#order + 1] = r.name end
	eq(table.concat(order, ","), "Zenec,Arcanaa,Gustl,Hesti,Urmeline", "erst Stufe 100, dann 99, dann 98, dann 50er")
	eq(L.RoundWinner(s).name, "Zenec", "Gewinner aus Stufe 100")
	check(L.ResultMessage(s):find("3. Gustl 95 (1-100, Stufe 99)", 1, true), "Ergebnis nennt die Stufe", L.ResultMessage(s))
	check(L.RollSummary(ok):find("Gustl 95 (Stufe 99)", 1, true), "Kurzfassung nennt die Stufe", L.RollSummary(ok))
	local aw = L.BuildAward(raid, "gustl", "Gustl", 18813, "[Ring]", 3, 2)
	eq(aw.kind, "free", "freier Wurf")
	eq(L.AwardDetail(aw), "freier Wurf 95 (1-100), Stufe 99", "Vergabe nennt die Stufe")
	local msgs = L.BuildRollCall(raid, { mode = "free", levels = {}, topHolders = {} }, "[Ring]",
		{ { key = "gustl", name = "Gustl" }, { key = "hesti", name = "Hesti" } }, { always100 = true })
	eq(msgs[1], "[Ring] – kein Prio, freier Wurf: /roll 100", "Aufruf: /roll 100")
	eq(msgs[2], "Stufe 99: Gustl", "Aufruf nennt Stufe 99")
	eq(msgs[3], "Stufe 98: Hesti", "Aufruf nennt Stufe 98")
	-- ohne die Regel wie bisher
	local old = L.NewSession(raid, 18205, "[Kette]", { mode = "free", levels = {} }, 0, {})
	check(not old.always100, "ohne Option: alte Regel")
	eq(L.AddRoll(raid, old, "Gustl", 95, 1, 100, 1).status, "range", "alte Regel: Stufe 99 muss /roll 99")
	-- Stichwurf: /roll 100, auch /roll 99 zählt
	local raid2 = L.NewRaid(0)
	local t = L.NewSession(raid2, 18813, "[Ring]", { mode = "free", levels = {} }, 0, { always100 = true })
	L.AddRoll(raid2, t, "Gustl", 70, 1, 100, 1)
	L.AddRoll(raid2, t, "Hesti", 70, 1, 100, 1)
	check(L.StartTiebreak(t), "Gleichstand: Stichwurf")
	eq(L.TiebreakMessages(t, "[Ring]")[1], "[Ring] – Gleichstand bei 70: Gustl, Hesti – Stichwurf, bitte /roll 100", "Stichwurf mit /roll 100")
	eq(L.AddRoll(raid2, t, "Gustl", 40, 1, 99, 2).status, "ok", "Stichwurf mit /roll 99 zählt")
	eq(L.AddRoll(raid2, t, "Hesti", 50, 1, 1000, 2).status, "range", "Stichwurf mit /roll 1000 nicht")
	-- Weitergabe: Folgen nennen die Würfelstufe
	local raid3 = L.NewRaid(0)
	raid3.awards = { { key = "gustl", name = "Gustl", kind = "free", itemID = 18813, link = "[Ring]", t = 1, roll = 80, low = 1, high = 100 } }
	eq(table.concat(L.HandoverEffects(raid3, 1, "zenec", "Zenec", 3, true), " | "),
		"Zenec hat dann Würfelstufe 99 statt 100. | Gustl hat wieder Würfelstufe 100 statt 99.", "Weitergabe: Würfelstufen")
end

-- 1.24: Wartelisten aus der Kommentarzeile von priomeister.de (Schema 27)
do
	local meta = L.ParseMeta("# PrioMeister: rezepte=wuerfeln; wartelisten=18563:John,Mike|18564:*Anna,Mike, John-Lakeshire ,mike; sets=18563+18564")
	local lists = L.ParseWaitlists(meta.wartelisten)
	eq(lists[18563] and #lists[18563], 2, "Warteliste linke Bindung: zwei Namen")
	eq(lists[18563] and lists[18563][1].name, "John", "Reihenfolge wie auf der Seite")
	check(lists[18564] and lists[18564][1].star and lists[18564][1].name == "Anna", "Stern: hat schon ein Teil des Sets")
	eq(lists[18564] and #lists[18564], 3, "doppelter Name nur einmal")
	eq(lists[18564] and lists[18564][3].name, "John", "Realm abgeschnitten")
	local sets = L.ParseSets(meta.sets)
	check(sets[18563] and sets[18563] == sets[18564], "Set aus linker und rechter Bindung")
	eq(next(L.ParseSets("")), nil, "ohne sets= keine Sets")
	eq(next(L.ParseWaitlists("x:Mike|19902:")), nil, "kaputte Einträge zählen nicht")
	eq(next(L.ParseWaitlists(nil)), nil, "ohne Wartelisten leer")
	eq(L.ParseWaitlists("19902:John,Mike,Sara")[19902][3].name, "Sara", "echte Zeile der Seite")

	local function keyOf(name) return L.NameKey(name), name end
	local function names(list)
		local t = {}
		for _, w in ipairs(list) do t[#t + 1] = w.name end
		return table.concat(t, ",")
	end
	local raid = L.NewRaid(0)
	eq(names(L.WaitlistOrder(raid, 18564, lists, sets, keyOf)), "Anna,Mike,John", "ohne Vergaben wie auf der Seite")
	raid.awards[1] = { key = "john", name = "John", itemID = 18563, kind = "waitlist", t = 1 }
	eq(names(L.WaitlistOrder(raid, 18564, lists, sets, keyOf)), "Anna,John,Mike", "Set vervollständigen: John rückt hinter die Namen mit Stern")
	eq(names(L.WaitlistOrder(raid, 18563, lists, sets, keyOf)), "Mike", "John hat die linke: fällt von ihrer Liste")
	eq(names(L.WaitlistOrder(raid, 18564, lists, nil, keyOf)), "Anna,Mike,John", "ohne Set kein Vorrücken")
	eq(names(L.WaitlistOrder(raid, 18564, L.ParseWaitlists("18564:Mike,John"), sets, keyOf)), "John,Mike", "ohne Stern ganz nach vorn")
	raid.awards[1].givenTo, raid.awards[1].givenKey = "Mike", "mike"
	raid.awards[2] = { key = "mike", name = "Mike", itemID = 18563, kind = "given", from = "John", fromKey = "john", t = 2 }
	eq(names(L.WaitlistOrder(raid, 18563, lists, sets, keyOf)), "John", "Weitergabe: John wieder drauf, Mike nicht mehr")
	eq(L.WaitlistPlace(L.WaitlistOrder(raid, 18563, lists, sets, keyOf), "john"), 1, "Platz auf der Liste")
	eq(#L.WaitlistOrder(raid, 19902, lists, sets, keyOf), 0, "Item ohne Warteliste")
end

-- Onyxia: neun T2-Helme in einer Zeile, je Helm die Namen der Klasse, ohne Sets
do
	local ids = { 16900, 16908, 16914, 16921, 16929, 16939, 16947, 16955, 16963 }
	local parts = {}
	for i, id in ipairs(ids) do
		local c = string.char(96 + i)
		parts[i] = ("%d:Held%sa,Held%sb,Held%sc,Held%sd,Held%se"):format(id, c, c, c, c, c)
	end
	local meta = L.ParseMeta("# PrioMeister: rezepte=wuerfeln; run=Ony 23.10.; wartelisten=" .. table.concat(parts, "|") .. "; stand=2026-10-23 18:00")
	local lists = L.ParseWaitlists(meta.wartelisten)
	local n = 0
	for _ in pairs(lists) do n = n + 1 end
	eq(n, 9, "neun Helme, neun Listen")
	eq(lists[16963] and #lists[16963], 5, "letzter Helm: alle fünf Namen")
	eq(lists[16963] and lists[16963][5].name, "Heldie", "letzter Helm, letzter Name")
	eq(meta.stand, "2026-10-23 18:00", "Angaben nach den Wartelisten bleiben lesbar")
	eq(next(L.ParseSets(meta.sets)), nil, "ohne sets= keine Sets")
end

-- Priocheck der Seite: Wer auf einer Warteliste mit Prio 0 steht, hat in dieser Instanz lauter Einsen,
-- auch ohne eigenen Eintrag („Joe;Magier;000;111“). In den anderen Instanzen fehlt er weiter.
do
	local chk = L.ParsePrioCheck("# priocheck;v=1;run=Ony+ZG;instanzen=Onyxias Hort:3|Zul'Gurub:3\nJoe;Magier;000;111\nMike;Krieger;111;111\n")
	local res = L.CheckRaid(chk, { { key = "joe", name = "Joe" }, { key = "mike", name = "Mike" } })
	eq(res.complete, 1, "Mike vollständig")
	eq(#res.none, 0, "Joe ist nicht ohne Prios")
	eq(res.partial[1] and res.partial[1].detail, "Onyxias Hort fehlt", "Joe: nur Onyxia fehlt, Zul'Gurub gesperrt und erledigt")
	chk = L.ParsePrioCheck("# priocheck;v=1;run=ZG;instanzen=Zul'Gurub:3\nJoe;Magier;111\n")
	eq(L.CheckRaid(chk, { { key = "joe", name = "Joe" } }).complete, 1, "nur Zul'Gurub: Joe vollständig")
end

-- Warteplatz vor jeder Prio, Verzicht, Vergabe, Ansage, Export
do
	local raid = L.NewRaid(0)
	raid.players = {
		gustl = { name = "Gustl", p = { 19902, 19902, 19902 }, pn = { "", "", "" } },
		mike = { name = "Mike", p = { 19902, 0, 0 }, pn = { "", "", "" } },
	}
	local wl = { { key = "john", name = "John" }, { key = "mike", name = "Mike" }, { key = "sara", name = "Sara" } }
	local present = { mike = true, sara = true, gustl = true }
	local function isPresent(k) return present[k] end
	local res = L.ResolveItem(raid, 19902, isPresent, { prio0Mode = 3, waitlist = wl })
	eq(res.top, L.WAITLIST, "Warteplatz schlägt Prio 0")
	eq(res.mode, "single", "einer ist dran")
	eq(res.topHolders[1].name, "Mike", "John fehlt: Mike ist dran")
	check(res.waitlist and #res.waitlist == 3 and not res.waitlist[1].present, "Panel bekommt die ganze Liste, John fehlt")
	check(L.HasHolders(res), "Warteliste zählt wie Prio-Halter")
	eq(L.LootAnnouncement(res, "[Tiger]")[1], "[Tiger] – Warteliste: Mike", "Ansage beim Öffnen")
	eq(#L.LootAnnouncement(res, "[Tiger]"), 1, "Prios werden dann nicht angesagt")
	eq(L.BuildRollCall(raid, res, "[Tiger]", {})[1], "[Tiger] – Warteliste: Mike", "Ansage per Knopf")
	local s = L.NewSession(raid, 19902, "[Tiger]", res, 4)
	eq(L.SessionPrioText(s), "Warteliste: Mike", "Rückfrage nennt den Warteplatz")
	eq(L.AddRoll(raid, s, "Gustl", 50, 1, 100, 4).reason, "nicht auf dem Warteplatz", "Wurf eines anderen zählt nicht")
	raid.sessions, raid.activeId = {}, nil
	local pass = L.RecordPass(raid, { key = "mike", name = "Mike", itemID = 19902, link = "[Tiger]", level = L.WAITLIST, source = "C1" }, 5)
	res = L.ResolveItem(raid, 19902, isPresent, { prio0Mode = 3, waitlist = wl, passed = L.PassesFor(raid, 19902, "C1") })
	eq(res.topHolders[1].name, "Sara", "nach Mikes Verzicht: Sara")
	eq(L.PassMessages(pass, res)[1], "Mike verzichtet auf [Tiger] (Warteliste) – jetzt Warteliste: Sara", "Verzicht im Chat")
	eq(L.AwardLine(pass), "Mike verzichtet auf [Tiger] (Warteliste)", "Verzicht in der Vergabeliste")
	eq(L.AwardDetail(pass), "Verzicht auf den Warteplatz", "Verzicht im Detail")
	res = L.ResolveItem(raid, 19902, function(k) return k == "gustl" end, { prio0Mode = 3, waitlist = wl })
	check(res.top == 0 and res.topHolders[1].name == "Gustl", "niemand von der Liste da: Prio 0 gilt")
	local aw = L.BuildAward(raid, "mike", "Mike", 19902, "[Tiger]", { prio0Mode = 3, waitlist = wl }, 10)
	eq(aw.kind, "waitlist", "Vergabe per Warteliste")
	eq(aw.uses, 1, "Mikes Prio 1 auf den Tiger ist damit erfüllt")
	L.RecordAward(raid, aw)
	eq(#L.OpenEntriesFor(raid, "mike", 19902, 3), 0, "keine offene Prio mehr")
	eq(L.AllowedMax(raid, "mike"), 100, "Warteliste kostet keine Würfelstufe")
	eq(L.AwardLine(aw), "Mike erhält [Tiger] – Warteliste", "Zeile in der Vergabeliste")
	eq(L.CountAwards(raid, "mike"), 1, "zählt als eigener Gewinn")
	eq(L.BuildAward(raid, "gustl", "Gustl", 19902, "[Tiger]", { prio0Mode = 3, waitlist = wl }, 11).kind, "prio", "Gustl: Prio wie bisher")
	local free = L.NewSession(raid, 19902, "[Tiger]", { mode = "free", levels = {} }, 12)
	L.AddRoll(raid, free, "Sara", 70, 1, 100, 12)
	eq(L.BuildAward(raid, "sara", "Sara", 19902, "[Tiger]", { prio0Mode = 3, waitlist = wl }, 13).kind, "free",
		"freier Wurf gewonnen: bleibt ein freier Wurf")
	raid.sessions, raid.activeId = {}, nil
	local csv = L.ExportCSV({ raid }, function(fmt) return fmt == "%H:%M" and "20:00" or "22.10.2026" end)
	check(csv:find(";Mike;19902;Tiger;Warteliste;;;;;;;;;", 1, true), "Export: Art Warteliste, Prio leer", csv)
	check(csv:find(";Mike;19902;Tiger;Verzicht;;;;;;;;Warteliste;", 1, true), "Export: Verzicht auf den Warteplatz", csv)
	local given = L.RecordHandover(raid, #raid.awards, "sara", "Sara", 14, 3)
	check(given and given.origin == "waitlist" and L.AllowedMax(raid, "sara") == 100, "Weitergabe: Sara bleibt bei 100")
end
eq(L.ItemID("https://www.wowhead.com/classic/item=19885/jindos-auge"), 19885, "ItemID aus Wowhead-Link")
eq(L.ItemID("Jin´dos Auge des Bösen-19885"), 19885, "ItemID aus TXT-Feld")
eq(L.ItemID("|cff0070dd|Hitem:19708::::::::60:::::::::|h[Blaues Schmuckstück der Hakkari]|h|r"), 19708, "ItemID aus Itemlink")
eq(L.ItemID("|cffffffff|Hitem:19708::::::::60:::::::::|h[]|h|r"), 19708, "ItemID aus Link ohne geladenen Namen")
eq(L.ItemID("|cffffffff|Hitem:::::::::60::::::::::|h[]|h|r"), nil, "leerer Link eines vergebenen Platzes: keine ItemID, nicht 60")
eq(L.ItemID("|cffffffff|Hitem:0::::::::60:::::::::|h[]|h|r"), nil, "ItemID 0 gilt nicht")
eq(L.ItemID("19229"), 19229, "ItemID als Zahl im Text")
eq(L.Canon(18422), L.Canon(18423), "Onyxia-Kopf Horde = Allianz")
eq(L.Canon(18406), L.Canon(18423), "Onyxia-Blutanhänger zählt als Kopf")
check(L.Canon(18405) ~= L.Canon(18423), "Gürtel des Erzmagiers ist kein Kopf")

local CSV = [[
Name;Klasse;prio1itemid;prio2itemid;prio3itemid;prio1itemname;prio2itemname;prio3itemname;
Awfulkitty;Druide;18422;0;0;Onyxias Kopf;;;
Noraja;Hexenmeister;16929;0;0;Schädelkappe der Nemesis;;;
Drachenwut;Krieger;17075;0;0;Vis'kag der Blutvergießer;;;
Gustl;Krieger;17965;0;0;Gelber Sack voller Edelsteine;;;
Arcanaa;Magier;16914;0;0;Krone des Netherwinds;;;
Arcanielle;Magier;16914;0;0;Krone des Netherwinds;;;
Bolzenblitz;Magier;16914;0;0;Krone des Netherwinds;;;
Urmeline;Magier;16929;0;0;Schädelkappe der Nemesis;;;
Kronolus;Paladin;16955;0;0;Krone des Richturteils;;;
Loladina;Paladin;17966;0;0;Rucksack aus Onyxias Haut;;;
Veldore;Paladin;16955;0;0;;;;
Hesti;Priester;16921;0;0;Heiligenschein der Erhabenheit;;;
Nanuheal;Priester;17962;0;0;Blauer Sack voller Edelsteine;;;
Sairá;Priester;16900;0;0;Bedeckung des Stormrage;;;
]]
do
	local players, info = L.ParsePrioList("\239\187\191" .. CSV:gsub("\n", "\r\n"))
	eq(info.players, 14, "CSV: 14 Spieler")
	eq(info.format, "CSV", "CSV: Format erkannt")
	eq(#info.skipped, 0, "CSV: nichts übersprungen")
	eq(players["sairá"].p[1], 16900, "CSV: Sairá Prio 1")
	eq(players["veldore"].p[1], 16955, "CSV: Veldore ohne Itemname")
	eq(players["awfulkitty"].token, "DRUID", "CSV: Klasse erkannt")
	local short = L.ParsePrioList("Rhako;19885;19890;22637\nGustl;17965;;")
	eq(short["rhako"].p[3], 22637, "CSV kurz: Prio 3")
	eq(short["gustl"].p[2], 0, "CSV kurz: leere Prio")
	local txt = L.ParsePrioList("Rhako\t\tDruide\t\tJin´dos Auge des Bösen-19885\tJin´dos Verhexer-19890\tUrzeitlicher Hakkarigötze-22637")
	eq(txt["rhako"].p[2], 19890, "TXT: Prio 2")
	eq(txt["rhako"].pn[1], "Jin´dos Auge des Bösen", "TXT: Itemname")
end

-- Vergaben teilen: eigene Gewinne einzeln, Rollen gebündelt
do
	local raid = L.NewRaid(1791800000)
	raid.awards = {
		{ key = "gustl", name = "Gustl", itemID = 18813, link = "[Ring]", kind = "free", roll = 88, low = 1, high = 100 },
		{ key = "lola", name = "Lola", itemID = 15000, link = "[Grün]", kind = "helper", quality = 2 },
		{ key = "lola", name = "Lola", itemID = 15000, link = "[Grün]", kind = "helper", quality = 2 },
		{ key = "lola", name = "Lola", itemID = 4000, link = "[Grau]", kind = "helper", quality = 0 },
		{ key = "bank", name = "Bank", itemID = 19726, link = "[Blutrebe]", kind = "treasurer", count = 2 },
		{ key = "de", name = "Zenec", itemID = 18205, link = "[Halsband]", kind = "de" },
	}
	L.RecordTierChange(raid, "bumbanko", "Bumbanko", 98, 100, -1, 1791803000)
	local fakeDate = function(fmt)
		if fmt == "%d.%m.%Y, %H:%M" then return "13.10.2026, 21:05" end
		if fmt == "%H:%M" then return "00:43" end
		return "13.10.2026"
	end
	local lines = L.ShareLines(raid, fakeDate)
	eq(lines[1], "Vergaben im Raid vom 13.10.2026, 21:05:", "Kopfzeile")
	eq(lines[2], "Gustl erhält [Ring] – freier Wurf 88 (1-100)", "eigener Gewinn einzeln")
	eq(lines[3], "Bumbanko: Würfelstufe von Hand von 98 auf 100 geändert (00:43 Uhr)", "Korrektur mit Uhrzeit")
	eq(lines[4], "Plünderhelfer Lola: [Grün] x2", "Plünderhelfer gebündelt, Grau ohne Häkchen weggelassen")
	eq(lines[5], "Schatzmeister Bank: [Blutrebe] x2", "Schatzmeister mit Stückzahl")
	eq(lines[6], "Entzauberer Zenec: [Halsband]", "Entzauberer")
	eq(#lines, 6, "sechs Zeilen")
	local withLow = L.ShareLines(raid, function() return "" end, { lowItems = true })
	eq(withLow[4], "Plünderhelfer Lola: [Grün] x2, 1 graue/weiße Items", "mit Häkchen: Grau gezählt")
	eq(L.AwardCount(raid), 6, "Korrektur zählt nicht als Vergabe")
	check(L.ExportCSV({ raid }, fakeDate):find("13.10.2026;00:43;Bumbanko;;;Würfelstufe von Hand;;;1-98 auf 1-100;", 1, true), "Korrektur im CSV-Export")
	-- Korrektur zurücknehmen stellt die alte Stufe wieder her
	raid.adjust.bumbanko = 1
	local undone = L.UndoLast(raid)
	eq(undone.kind, "tier", "zurückgenommen: die Korrektur")
	eq(raid.adjust.bumbanko, -1, "alte Korrektur wiederhergestellt")
	eq(L.ShareLines(L.NewRaid(0), function() return "" end), nil, "ohne Vergaben nichts zu teilen")
end

-- Kommentarzeile von priomeister.de: Regeln und Stand, keine unerkannte Zeile
do
	local text = "Name;Klasse;prio1itemid;prio2itemid;prio3itemid;prio1itemname;prio2itemname;prio3itemname;\n"
		.. "Zenec;Jäger;19872;0;0;Schneller Razzashiraptor;;;\n"
		.. "# PrioMeister: rezepte=wuerfeln; reittiere=prio; spieler=1; prios=1; stand=2026-10-15 18:42; run=ZG 15.10.; link=https://priomeister.de/r/746312\n"
	local players, info = L.ParsePrioList(text)
	eq(info.players, 1, "Kommentar zählt nicht als Spieler")
	eq(#info.skipped, 0, "Kommentar ist keine unerkannte Zeile")
	eq(players.zenec and players.zenec.p[1], 19872, "Zeile vor dem Kommentar gelesen")
	eq(info.meta and info.meta.reittiere, "prio", "Regel für Reittiere gelesen")
	eq(info.meta.rezepte, "wuerfeln", "Regel für Rezepte gelesen")
	eq(info.meta.run, "ZG 15.10.", "Titel des Prio-Runs")
	eq(L.ShortLink(info.meta.link), "priomeister.de/r/746312", "Link ohne https")
	eq(L.FormatStand(info.meta.stand), "15.10. 18:42", "Stand lesbar")
	eq(L.FormatStand(info.meta.stand, "2026-10-15"), "18:42", "Stand am selben Tag nur mit Uhrzeit")
	eq(L.FormatStand("gestern"), nil, "unlesbarer Stand")
	local withExceptions = L.ParseMeta("# PrioMeister: rezepte=wuerfeln; ausnahmen=18259, 19872; run=MC")
	eq(withExceptions.ausnahmen, "18259, 19872", "Ausnahmen gelesen")
	local set = L.ParseIDSet(withExceptions.ausnahmen)
	check(set[18259] and set[19872] and not set[1], "Ausnahmen als Menge")
	eq(next(L.ParseIDSet(nil)), nil, "ohne Ausnahmen: leer")
	local _, plain = L.ParsePrioList("# irgendein Kommentar\nGustl;100;0;0")
	eq(plain.meta, nil, "fremder Kommentar: keine Angaben")
	eq(#plain.skipped, 0, "fremder Kommentar wird still übersprungen")
	eq(plain.players, 1, "Liste mit fremdem Kommentar gelesen")
end

-- Geladene Liste als CSV: lässt sich wieder einlesen
do
	local players = L.ParsePrioList(CSV)
	local csv = L.PrioListCSV(players)
	local again = L.ParsePrioList(csv)
	local same = true
	for key, p in pairs(players) do
		local q = again[key]
		if not q or q.name ~= p.name or q.class ~= p.class then same = false end
		for i = 1, 3 do
			if not q or q.p[i] ~= p.p[i] or q.pn[i] ~= p.pn[i] then same = false end
		end
	end
	check(same, "CSV der geladenen Liste lässt sich wieder einlesen")
	check(csv:find("Veldore;Paladin;16955;0;0;;;;", 1, true), "Zeile ohne Itemnamen bleibt leer")
	check(csv:find("^Name;Klasse;prio1itemid"), "Kopfzeile wie bei sahne-team.de")
end

-- Punkt 1: doppelte Einträge – letzter Stand mit den meisten Items
do
	local head = "Name;Klasse;prio1itemid;prio2itemid;prio3itemid;prio1itemname;prio2itemname;prio3itemname;\n"
	local p1, i1 = L.ParsePrioList(head .. "Gustl;Krieger;100;200;300;;;\nGustl;Krieger;400;500;0;;;\n")
	eq(p1["gustl"].p[1], 100, "erst drei, dann zwei: der Stand mit drei bleibt")
	eq(i1.duplicates[1].count, 3, "Meldung nennt drei Items")
	check(not i1.duplicates[1].replaced, "nicht ersetzt")
	local p2 = L.ParsePrioList(head .. "Gustl;Krieger;100;200;0;;;\nGustl;Krieger;400;500;0;;;\n")
	eq(p2["gustl"].p[1], 400, "zwei und noch mal zwei: der letzte Stand gilt")
	local p3 = L.ParsePrioList(head .. "Gustl;Krieger;100;0;0;;;\nGustl;Krieger;400;500;600;;;\nGustl;Krieger;0;0;0;;;\n")
	eq(p3["gustl"].p[1], 400, "ein, drei, null Items: der Stand mit drei gilt")
end

-- Prio 0, Auflösung, Vergabe-Verbrauch
do
	local raid = L.NewRaid(0)
	raid.players = L.ParsePrioList([[
Name;Klasse;prio1itemid;prio2itemid;prio3itemid;prio1itemname;prio2itemname;prio3itemname;
Alpha;Magier;16914;16914;16914;;;;
Beta;Magier;16914;0;0;;;;
Gamma;Magier;0;16914;0;;;;
Delta;Krieger;17011;17011;17011;;;;
Eps;Krieger;16914;16914;18813;;;;
]])
	local all = function() return true end
	local res = L.ResolveItem(raid, 16914, all, 3)
	eq(res.top, 0, "Prio 0 schlägt Prio 1")
	eq(res.mode, "single", "Prio 0: ein Halter")
	eq(res.topHolders[1].name, "Alpha", "Prio 0: Alpha")
	eq(#res.levels[1], 2, "Prio 1: Beta und Eps")
	eq(#L.ResolveItem(raid, 16914, all, 2).levels[0], 2, "Modus Prio 1+2: Alpha und Eps haben Prio 0")
	eq(L.ResolveItem(raid, 17011, all, 3).top, 1, "Material: dreimal Lavakern ist kein Prio 0")
	L.RecordAward(raid, L.BuildAward(raid, "alpha", "Alpha", 16914, "[Krone]", 3, 1))
	local after = L.ResolveItem(raid, 16914, all, 3)
	eq(after.top, 1, "nach Prio-0-Vergabe gilt Prio 1")
	eq(after.mode, "roll", "Prio 1: zwei Halter würfeln")
	for lvl = 1, 3 do
		local aw = L.BuildAward(raid, "delta", "Delta", 17011, "[Lavakern]", 3, lvl)
		eq(aw.level, lvl, "Lavakern Nr. " .. lvl .. " auf Prio " .. lvl)
		L.RecordAward(raid, aw)
	end
	eq(L.ResolveItem(raid, 17011, all, 3).mode, "free", "Lavakern danach frei")
	eq(L.ResolveItem(raid, 16914, function(k) return k ~= "beta" and k ~= "eps" end, 3).top, 2, "Beta/Eps fehlen: Gamma mit Prio 2")
	-- Rezepte: Prio ignoriert
	local rec = L.ResolveItem(raid, 16914, all, { prio0Mode = 3, ignorePrio = true, recipe = true, recipeRolls = true, profession = "Verzauberkunst" })
	eq(rec.mode, "recipe", "Rezept ohne Prio: Rezept-Wurf")
	eq(#rec.ignored, 3, "ignorierte Prio-Halter werden genannt")
	eq(L.ResolveItem(raid, 16914, all, { prio0Mode = 3, recipe = true, recipeRolls = true }).mode, "roll", "Rezepte auf Prio erlaubt: normale Prio")
end

-- Würfelstufen, 50er-Würfe, Rezept-Würfe
do
	local raid = L.NewRaid(0)
	local free = { top = nil, topHolders = {}, mode = "free" }
	local s = L.NewSession(raid, 18813, "[Ring]", free, 1, { secondary = true })
	L.AddRoll(raid, s, "Gustl", 88, 1, 100, 1)
	L.AddRoll(raid, s, "Zenec", 40, 1, 100, 2)
	L.RecordAward(raid, L.BuildAward(raid, "gustl", "Gustl", 18813, "[Ring]", 3, 3))
	eq(L.AllowedMax(raid, "gustl"), 99, "Gustl würfelt mit 99")

	local s2 = L.NewSession(raid, 18205, "[Halsband]", free, 4, { secondary = true })
	local bad = L.AddRoll(raid, s2, "Gustl", 95, 1, 100, 5)
	eq(bad.status, "range", "Gustl mit 100 ist falsch")
	eq(L.WrongRollMessage(bad), "Gustl: Wurf 95 (1-100) zählt nicht – bitte /roll 99", "Kritik-Text")
	local good = L.AddRoll(raid, s2, "Gustl", 50, 1, 99, 6)
	check(good.status == "ok" and good.reroll, "Neuwurf mit 99 zählt und ist markiert")
	L.AddRoll(raid, s2, "Zenec", 30, 1, 100, 7)
	eq(L.AddRoll(raid, s2, "Zenec", 99, 1, 100, 8).status, "doppelt", "zweiter Wurf zählt nicht")
	-- Punkt 4: 50er-Würfe laufen parallel und liegen unter allen normalen Würfen
	local sec = L.AddRoll(raid, s2, "Hesti", 49, 1, 50, 9)
	check(sec.status == "ok" and sec.kind == "sec", "50er-Wurf gültig")
	local ok = L.RankRolls(s2)
	eq(ok[1].name, "Zenec", "100er-Wurf (30) schlägt 99er-Wurf (50)")
	eq(ok[2].name, "Gustl", "Gustl Zweiter")
	eq(ok[3].name, "Hesti", "50er-Wurf zuletzt")
	local awSec = L.BuildAward(raid, "hesti", "Hesti", 18205, "[Halsband]", 3, 10)
	eq(awSec.kind, "sec", "Gewinn mit 50er-Wurf")
	L.RecordAward(raid, awSec)
	eq(L.AllowedMax(raid, "hesti"), 100, "50er-Gewinn ändert die Stufe nicht")
	eq(L.AwardDetail(awSec), "50er-Wurf 49 (1-50)", "Text für 50er-Gewinn")
	-- 50er bei Prio-Stichwurf ist falsch
	local sp = L.NewSession(raid, 16914, "[Krone]", { top = 1, topHolders = { { key = "gustl", name = "Gustl" } }, mode = "single" }, 11, { secondary = true })
	eq(L.AddRoll(raid, sp, "Gustl", 40, 1, 50, 12).status, "range", "50er im Prio-Stichwurf zählt nicht")

	-- Punkt 5: Rezept-Würfe ohne Stufen
	local sr = L.NewSession(raid, 18259, "[Formel]", { top = nil, topHolders = {}, mode = "recipe", profession = "Verzauberkunst" }, 13, { secondary = true })
	eq(sr.mode, "recipe", "Rezept-Runde")
	eq(L.AddRoll(raid, sr, "Gustl", 70, 1, 100, 14).status, "ok", "Gustl darf beim Rezept mit 100 würfeln")
	eq(L.AddRoll(raid, sr, "Zenec", 60, 1, 99, 15).status, "range", "Rezept: 99 ist falsch")
	local awRec = L.BuildAward(raid, "gustl", "Gustl", 18259, "[Formel]", 3, 16)
	eq(awRec.kind, "recipe", "Rezept-Gewinn")
	L.RecordAward(raid, awRec)
	eq(L.AllowedMax(raid, "gustl"), 99, "Rezept-Gewinn ändert die Stufe nicht")

	local msgs = L.BuildRollCall(raid, free, "[X]", { { key = "gustl", name = "Gustl" }, { key = "zenec", name = "Zenec" } }, { secondary = true })
	eq(msgs[1], "[X] – kein Prio, freier Wurf: /roll 100", "Ansage ohne 50er-Hinweis")
	eq(msgs[2], "Mit /roll 99: Gustl", "Ansage nennt Würfelstufen")
	eq(#L.BuildRollCall(raid, free, "[X]", { { key = "gustl", name = "Gustl" } }, { tierHints = false }), 1, "ohne Stufenhinweise nur eine Zeile")
	local rmsg = L.BuildRollCall(raid, { top = nil, topHolders = {}, mode = "recipe", profession = "Schmiedekunst" }, "[Bauplan]", {}, { secondary = false })
	eq(rmsg[1], "[Bauplan] – Rezept für Schmiedekunst, nur mit passendem Beruf: /roll 100", "Rezept-Ansage")

	-- Punkt 3: höchstens drei Plätze
	local s3 = L.NewSession(raid, 4000, "[Y]", free, 20, {})
	for i, n in ipairs({ "Aaa", "Bbb", "Ccc", "Ddd", "Eee" }) do L.AddRoll(raid, s3, n, 10 * i, 1, 100, 20 + i) end
	local res3 = L.ResultMessage(s3, 40)
	eq(res3, "[Y]: 1. Eee 50 (1-100), 2. Ddd 40 (1-100), 3. Ccc 30 (1-100)", "nur die ersten drei Plätze")

	L.UndoLast(raid)
	L.UndoLast(raid)
	L.UndoLast(raid)
	eq(L.AllowedMax(raid, "gustl"), 100, "Rückgängig setzt Stufe zurück")
end

-- Stichwurf bei Gleichstand: gleiche Stufe wie beim ersten Wurf
do
	local free = { top = nil, topHolders = {}, mode = "free" }
	-- Fall aus dem Screenshot: 29 zu 29 mit 1-100
	local raid = L.NewRaid(0)
	local s = L.NewSession(raid, 2589, "[Leinenstoff]", free, 1, { secondary = true })
	L.AddRoll(raid, s, "Arcanaa", 29, 1, 100, 1)
	L.AddRoll(raid, s, "Mularusch", 29, 1, 100, 2)
	eq(L.ResultMessage(s), "[Leinenstoff]: 1. Arcanaa 29 (1-100), 1. Mularusch 29 (1-100) – Gleichstand", "Ergebnis zeigt Gleichstand")
	check(L.StartTiebreak(s), "Stichwurf gestartet")
	eq(L.TiebreakMessages(s, "[Leinenstoff]")[1], "[Leinenstoff] – Gleichstand bei 29: Arcanaa, Mularusch – Stichwurf, bitte /roll 100", "Stichwurf-Ansage")
	eq(L.AddRoll(raid, s, "Gustl", 99, 1, 100, 3).reason, "nicht im Stichwurf", "andere zählen nicht")
	L.AddRoll(raid, s, "Arcanaa", 12, 1, 100, 4)
	check(L.WaitingForTiebreak(s, "mularusch"), "Mularusch wartet noch")
	check(not L.WaitingForTiebreak(s, "arcanaa"), "Arcanaa hat gestochen")
	eq(L.AddRoll(raid, s, "Arcanaa", 99, 1, 100, 5).status, "doppelt", "zweiter Stichwurf zählt nicht")
	L.AddRoll(raid, s, "Mularusch", 80, 1, 100, 6)
	local ok, _, tieFirst = L.RankRolls(s)
	check(tieFirst == nil, "Gleichstand aufgelöst")
	eq(ok[1].name, "Mularusch", "Stichwurf entscheidet")
	eq(L.ResultMessage(s), "[Leinenstoff]: 1. Mularusch 29 (1-100) Stichwurf 80, 2. Arcanaa 29 (1-100) Stichwurf 12", "Ergebnis mit Stichwurf")
	local aw = L.BuildAward(raid, "mularusch", "Mularusch", 2589, "[Leinenstoff]", 3, 7)
	eq(L.AwardDetail(aw), "freier Wurf 29 (1-100), Stichwurf 80", "Protokoll nennt beide Würfe")
	L.RecordAward(raid, aw)
	eq(L.AllowedMax(raid, "mularusch"), 99, "Stufe sinkt einmal")
	eq(L.AllowedMax(raid, "arcanaa"), 100, "Verlierer behält Stufe")
	check(L.ExportCSV({ raid }, os.date):find("Mularusch;2589;Leinenstoff;freier Wurf;;29;1-100;80", 1, true), "Export mit Stichwurf")

	-- Gleichstand auf Stufe 99: gestochen wird mit 99, erneuter Gleichstand
	local raid2 = L.NewRaid(0)
	raid2.adjust = { gustl = 1, hesti = 1 }
	local s2 = L.NewSession(raid2, 4000, "[X]", free, 1, {})
	L.AddRoll(raid2, s2, "Gustl", 50, 1, 99, 1)
	L.AddRoll(raid2, s2, "Hesti", 50, 1, 99, 2)
	L.AddRoll(raid2, s2, "Zenec", 40, 1, 100, 3) -- Stufe 100 schlägt beide
	eq(L.RankRolls(s2)[1].name, "Zenec", "100er vor den Gleichstehenden")
	check(L.StartTiebreak(s2) == nil, "kein Gleichstand an der Spitze")
	L.RecordAward(raid2, L.BuildAward(raid2, "zenec", "Zenec", 4000, "[X]", 3, 4))
	check(L.StartTiebreak(s2), "Gleichstand auf Platz 2 nach der ersten Vergabe")
	eq(L.TiebreakMessages(s2, "[X]")[1], "[X] – Gleichstand bei 50: Gustl, Hesti – Stichwurf, bitte /roll 99", "Stichwurf mit Stufe 99")
	local wrong = L.AddRoll(raid2, s2, "Gustl", 70, 1, 100, 5)
	eq(wrong.status, "range", "Stichwurf mit 100 ist falsch")
	eq(L.WrongRollMessage(wrong), "Gustl: Wurf 70 (1-100) zählt nicht – bitte /roll 99", "Hinweis zum Stichwurf")
	L.AddRoll(raid2, s2, "Gustl", 40, 1, 99, 6)
	L.AddRoll(raid2, s2, "Hesti", 40, 1, 99, 7)
	check(L.StartTiebreak(s2), "erneuter Gleichstand")
	eq(L.TiebreakMessages(s2, "[X]")[1], "[X] – wieder Gleichstand (40): Gustl, Hesti – Stichwurf, bitte /roll 99", "zweite Stichwurf-Ansage")
	L.AddRoll(raid2, s2, "Hesti", 10, 1, 99, 8)
	L.AddRoll(raid2, s2, "Gustl", 20, 1, 99, 9)
	eq(L.RankRolls(s2)[2].name, "Gustl", "zweite Runde entscheidet")
	eq(L.AwardDetail(L.BuildAward(raid2, "gustl", "Gustl", 4000, "[X]", 3, 10)), "freier Wurf 50 (1-99), Stichwurf 40/20", "beide Stichwürfe im Protokoll")

	-- Prio-Stichwurf und 50er-Gleichstand
	local raid3 = L.NewRaid(0)
	local sp = L.NewSession(raid3, 16914, "[Krone]", { top = 1, topHolders = { { key = "a", name = "A" }, { key = "b", name = "B" } }, mode = "roll" }, 1, {})
	L.AddRoll(raid3, sp, "A", 77, 1, 100, 1)
	L.AddRoll(raid3, sp, "B", 77, 1, 100, 2)
	L.StartTiebreak(sp)
	eq(sp.tiebreak.high, 100, "Prio-Stichwurf mit 100")
	local s50 = L.NewSession(raid3, 4000, "[Y]", free, 3, { secondary = true })
	L.AddRoll(raid3, s50, "C", 33, 1, 50, 4)
	L.AddRoll(raid3, s50, "D", 33, 1, 50, 5)
	L.StartTiebreak(s50)
	eq(s50.tiebreak.high, 50, "50er-Gleichstand sticht mit 50")
	eq(L.AddRoll(raid3, s50, "C", 20, 1, 50, 6).status, "ok", "50er-Stichwurf gültig")
end

-- Rückfrage vor „An Entzauberer“ und „Zufällig vergeben“: wer hat schon gewürfelt?
do
	local free = { top = nil, topHolders = {}, mode = "free" }
	local raid = L.NewRaid(0)
	raid.adjust = { gustl = 1 }
	local s = L.NewSession(raid, 4000, "[X]", free, 1, { secondary = true })
	eq(#L.OpenRolls(s), 0, "ohne Würfe nichts offen")
	eq(#L.OpenRolls(nil), 0, "ohne Runde nichts offen")
	L.AddRoll(raid, s, "Hesti", 30, 1, 50, 1)
	L.AddRoll(raid, s, "Gustl", 95, 1, 100, 2) -- Stufe 99: ungültig
	L.AddRoll(raid, s, "Zenec", 40, 1, 100, 3)
	L.AddRoll(raid, s, "Gustl", 70, 1, 99, 4) -- Neuwurf zählt
	L.AddRoll(raid, s, "Zenec", 99, 1, 100, 5) -- zweiter Wurf zählt nicht
	L.AddRoll(raid, s, "Ärwin", 88, 1, 120, 6) -- falscher Bereich
	local open = L.OpenRolls(s)
	eq(#open, 4, "vier Spieler haben gewürfelt")
	eq(L.RollSummary(open), "Zenec 40, Gustl 70 (1-99), Hesti 30 (1-50), Ärwin 88 (ungültig)", "Kurzfassung in der Reihenfolge des Panels")
	eq(L.RollSummary(open, 2), "Zenec 40, Gustl 70 (1-99) und 2 weitere", "lange Liste gekürzt")
	eq(L.ConfirmText("[X]", nil, { open[1] }), "[X]\nGewürfelt: Zenec 40", "Rückfrage: Item und Würfe")
	eq(L.ConfirmText("[X]", "Prio 1: A, B", {}), "[X]\nPrio 1: A, B", "Rückfrage: Item und Prio")
	L.RecordAward(raid, L.BuildAward(raid, "zenec", "Zenec", 4000, "[X]", 3, 7))
	eq(L.RollSummary(L.OpenRolls(s)), "Gustl 70 (1-99), Hesti 30 (1-50), Ärwin 88 (ungültig)", "Gewinner zählt nicht mehr")
	local sp = L.NewSession(raid, 16914, "[Krone]", { top = 1, topHolders = { { key = "bodo", name = "Bodo" }, { key = "anna", name = "Anna" } } }, 8, {})
	eq(L.SessionPrioText(sp), "Prio 1: Anna, Bodo", "Prio-Runde nennt die Halter")
	eq(L.SessionPrioText(s), nil, "freier Wurf: keine Prio-Zeile")
end

-- Gewinner der Würfelrunde für den Knopf „An Name“
do
	local free = { top = nil, topHolders = {}, mode = "free" }
	local raid = L.NewRaid(0)
	local s = L.NewSession(raid, 4000, "[X]", free, 1, { secondary = true })
	eq(L.RoundWinner(s), nil, "ohne Würfe kein Gewinner")
	eq(L.RoundWinner(nil), nil, "ohne Runde kein Gewinner")
	L.AddRoll(raid, s, "Anna", 50, 1, 50, 1)
	eq(L.RoundWinner(s).name, "Anna", "nur ein 50er-Wurf: der gewinnt")
	L.AddRoll(raid, s, "Bodo", 20, 1, 100, 2)
	eq(L.RoundWinner(s).name, "Bodo", "normaler Wurf vor 50er-Wurf")
	L.AddRoll(raid, s, "Cora", 20, 1, 100, 3)
	eq(L.RoundWinner(s), nil, "Gleichstand: kein Gewinner")
	L.StartTiebreak(s)
	L.AddRoll(raid, s, "Cora", 40, 1, 100, 4)
	eq(L.RoundWinner(s), nil, "Stichwurf steht noch aus")
	L.AddRoll(raid, s, "Bodo", 10, 1, 100, 5)
	eq(L.RoundWinner(s).name, "Cora", "Stichwurf entscheidet")
	L.RecordAward(raid, L.BuildAward(raid, "cora", "Cora", 4000, "[X]", 3, 6))
	eq(L.RoundWinner(s).name, "Bodo", "wer schon etwas bekommen hat, zählt nicht mehr")
	-- zwei Exemplare: 95, 90, 90 – der 95er ist klar, um das zweite wird gestochen
	local s2 = L.NewSession(raid, 4001, "[Y]", free, 7, { copies = 2 })
	L.AddRoll(raid, s2, "Anna", 90, 1, 100, 7)
	L.AddRoll(raid, s2, "Bodo", 95, 1, 100, 8)
	L.AddRoll(raid, s2, "Dirk", 90, 1, 100, 9)
	eq(L.RoundWinner(s2).name, "Bodo", "zwei Exemplare: der 95er bekommt eins")
	L.RecordAward(raid, L.BuildAward(raid, "bodo", "Bodo", 4001, "[Y]", 3, 10))
	eq(L.RoundWinner(s2), nil, "zweites Exemplar: Gleichstand")
	-- zwei Exemplare: 90, 90, 80 – beide 90er bekommen eins
	local s3 = L.NewSession(raid, 4002, "[Z]", free, 11, { copies = 2 })
	L.AddRoll(raid, s3, "Anna", 90, 1, 100, 11)
	L.AddRoll(raid, s3, "Erik", 90, 1, 100, 12)
	L.AddRoll(raid, s3, "Fritz", 80, 1, 100, 13)
	eq(L.RoundWinner(s3).name, "Anna", "90, 90, 80 bei zwei Exemplaren: erst Anna")
	L.RecordAward(raid, L.BuildAward(raid, "anna", "Anna", 4002, "[Z]", 3, 14))
	eq(L.RoundWinner(s3).name, "Erik", "dann Erik")
end

-- Instanz eines Raids: gespeichert, aus den Vergaben oder aus der Leichen-GUID
do
	eq(L.GUIDMapID("Creature-0-5211-309-41265-11382-00004FC5D6"), 309, "Instanz aus der GUID einer Leiche")
	eq(L.GUIDMapID("GameObject-0-5211-509-1234-180690-0000ABCDEF"), 509, "Instanz aus der GUID einer Truhe")
	eq(L.GUIDMapID("Creature-0-0-0-0-5"), nil, "Instanz 0 zählt nicht")
	eq(L.GUIDMapID("Player-5211-0A1B2C3D"), nil, "Spieler-GUID hat keine Instanz")
	eq(L.GUIDMapID(nil), nil, "ohne GUID keine Instanz")
	local raid = { instances = { 249 }, awards = { { instance = 309 }, { kind = "tier" }, { instance = 249 } },
		sessions = { { source = "Creature-0-5211-309-41265-14507-0000" }, { source = "Creature-0-5211-509-1-15348-0000" } } }
	eq(table.concat(L.RaidInstances(raid), ","), "249,309,509", "Instanzen in der Reihenfolge, ohne doppelte")
	eq(#L.RaidInstances({ awards = {} }), 0, "ohne Angaben keine Instanz")
end

-- Tragbarkeit: Rüstung, Waffen, Schildhand und Klassen laut Tooltip
do
	local plate = L.ItemUsers(4, 4, "INVTYPE_HAND", nil)
	check(plate.WARRIOR and plate.PALADIN and not plate.MAGE and not plate.HUNTER, "Platte: nur Krieger und Paladin")
	eq(L.ItemUsers(4, 1, "INVTYPE_CHEST", nil), nil, "Stoff: alle")
	eq(L.ItemUsers(4, 0, "INVTYPE_FINGER", nil), nil, "Ring: alle")
	local mail = L.ItemUsers(4, 3, "INVTYPE_CHEST", nil)
	check(mail.HUNTER and mail.SHAMAN and not mail.ROGUE and not mail.DRUID, "Kette: Jäger und Schamane ja, Schurke und Druide nein")
	local offhand = L.ItemUsers(2, 15, "INVTYPE_WEAPONOFFHAND", nil)
	check(offhand.ROGUE and offhand.WARRIOR and offhand.HUNTER and not offhand.MAGE and not offhand.PRIEST, "Dolch nur für die Schildhand: nur mit beidhändigem Kampf")
	local dagger = L.ItemUsers(2, 15, "INVTYPE_WEAPON", nil)
	check(dagger.MAGE and dagger.PRIEST and not dagger.PALADIN, "Einhanddolch: Magier ja, Paladin nein")
	local wand = L.ItemUsers(2, 19, "INVTYPE_RANGEDRIGHT", nil)
	check(wand.MAGE and wand.PRIEST and wand.WARLOCK and not wand.WARRIOR, "Zauberstab: nur Magier, Priester, Hexenmeister")
	local polearm = L.ItemUsers(2, 6, "INVTYPE_2HWEAPON", nil)
	check(polearm.HUNTER and polearm.PALADIN and not polearm.DRUID, "Stangenwaffe: Druiden nicht in Classic")
	local robe = L.ItemUsers(4, 1, "INVTYPE_ROBE", { PRIEST = true })
	check(robe.PRIEST and not robe.MAGE, "Stoff mit „Klassen: Priester“: nur Priester")
	local palaPlate = L.ItemUsers(4, 4, "INVTYPE_HEAD", { PALADIN = true })
	check(palaPlate.PALADIN and not palaPlate.WARRIOR, "Platte nur für Paladine: Krieger nicht")
	local info = { users = plate, subType = "Platte" }
	eq(L.UnusableReason(info, "MAGE", "Magier"), "als Magier nicht tragbar (Platte)", "Grund: Rüstungstyp")
	eq(L.UnusableReason(info, "WARRIOR", "Krieger"), nil, "Krieger darf Platte")
	eq(L.UnusableReason({ users = robe, restricted = { PRIEST = true }, restrictedText = "Priester", subType = "Stoff" }, "MAGE", "Magier"),
		"nur für Priester", "Grund: Klassen laut Tooltip")
	eq(L.UnusableReason({ users = offhand, subType = "Dolche", offhand = true }, "MAGE", "Magier"), "als Magier nicht in der Schildhand führbar",
		"Grund: Schildhand")
	eq(L.UnusableReason(nil, "MAGE", "Magier"), nil, "ohne Angaben kein Grund")
	eq(L.UnusableReason(info, nil, nil), nil, "unbekannte Klasse: kein Grund")
	-- Würfe: untragbar zählt nicht, 50er schon, Prio-Runden prüft das Addon nicht
	local raid = L.NewRaid(0)
	local s = L.NewSession(raid, 99001, "[Handschuhe]", { top = nil, topHolders = {}, mode = "free" }, 1, { secondary = true })
	local classes = { urmeline = "MAGE", gustl = "WARRIOR" }
	local function unusable(key)
		return L.UnusableReason(info, classes[key], classes[key] == "MAGE" and "Magier" or "Krieger")
	end
	local r1 = L.AddRoll(raid, s, "Urmeline", 95, 1, 100, 1, nil, unusable)
	check(r1.status == "fremd" and r1.unusable and r1.reason == "als Magier nicht tragbar (Platte)", "Magier auf Platte: Wurf zählt nicht", r1.reason)
	eq(L.WrongRollMessage(r1), "Urmeline: Wurf 95 zählt nicht – als Magier nicht tragbar (Platte)", "Hinweis im Raidchat")
	eq(L.AddRoll(raid, s, "Urmeline", 30, 1, 50, 2, nil, unusable).status, "ok", "50er-Wurf zählt trotzdem, etwa für einen Zweitchar")
	eq(L.AddRoll(raid, s, "Gustl", 40, 1, 100, 3, nil, unusable).status, "ok", "Krieger auf Platte zählt")
	eq(L.RoundWinner(s).name, "Gustl", "Gewinner ist der Krieger, nicht der Magier mit 95")
	local sp = L.NewSession(raid, 99001, "[Handschuhe]", { top = 1, topHolders = { { key = "urmeline", name = "Urmeline" } } }, 4, {})
	local rp = L.AddRoll(raid, sp, "Urmeline", 50, 1, 100, 5, nil, unusable)
	check(rp.status == "fremd" and rp.unusable, "Prio-Runde: untragbar zählt auch hier nicht", rp.reason)
end

-- Wurf-Protokoll und Export mit allen Vergaben und Würfen
do
	local raid = L.NewRaid(1000)
	local s = L.NewSession(raid, 18813, "|cffa335ee|Hitem:18813::::::::60:::::::|h[Ring der Bindung]|h|r",
		{ top = nil, topHolders = {}, mode = "free" }, 1000, { secondary = true })
	local r1 = L.AddRoll(raid, s, "Gustl", 88, 1, 100, 1010)
	L.LogRoll(raid, s, r1, 409)
	local r2 = L.AddRoll(raid, s, "Hesti", 49, 1, 50, 1011)
	L.LogRoll(raid, s, r2, 409)
	local r3 = L.AddRoll(raid, s, "Zenec", 120, 1, 120, 1012)
	L.LogRoll(raid, s, r3, 409)
	local r4 = L.AddRoll(raid, s, "Urmeline", 95, 1, 100, 1013, nil, function() return "als Magier nicht tragbar (Platte)" end)
	L.LogRoll(raid, s, r4, 409)
	eq(#raid.rollLog, 4, "vier Würfe im Protokoll")
	eq(L.RollStatusText(raid.rollLog[1]), "zählt", "Status: zählt")
	eq(L.RollStatusText(raid.rollLog[3]), "falscher Bereich", "Status: falscher Bereich")
	eq(L.RollStatusText(raid.rollLog[4]), "nicht tragbar", "Status: nicht tragbar")
	check(raid.rollLog[2].sec, "50er-Wurf markiert")
	local aw = L.BuildAward(raid, "gustl", "Gustl", 18813, s.link, 3, 1020)
	aw.instance = 409
	L.RecordAward(raid, aw)
	local fmt = function(f, t) return os.date(f, t) end
	local csv = L.ExportCSV({ raid }, fmt, { instanceName = function(id) return id == 409 and "Geschmolzener Kern" or tostring(id) end })
	local lines = {}
	for line in csv:gmatch("[^\n]+") do lines[#lines + 1] = line end
	eq(lines[1], L.EXPORT_HEADER, "Kopfzeile")
	-- priomeister.de verteilt „Export alle Raids“ über Instanz und Zeitstempel auf die Prio-Runs (seit 26.10.)
	eq(L.EXPORT_HEADER, "Datum;Uhrzeit;Spieler;ItemID;Item;Art;Prio;Wurf;Bereich;Stichwurf;Runde;Rundenart;Status;Grund;Instanz;Raid;Zeitstempel",
		"Spalten bleiben, wie priomeister.de sie liest")
	eq(#lines, 6, "Kopf, vier Würfe, eine Vergabe")
	local columns = select(2, L.EXPORT_HEADER:gsub(";", "")) + 1
	eq(columns, 17, "17 Spalten")
	for i = 2, #lines do eq(select(2, lines[i]:gsub(";", "")) + 1, columns, "Zeile " .. i .. " hat alle Spalten") end
	local raidLabel = os.date("%d.%m.%Y %H:%M", 1000)
	eq(lines[2], os.date("%d.%m.%Y;%H:%M", 1010) .. ";Gustl;18813;Ring der Bindung;Wurf;;88;1-100;;1;freier Wurf;zählt;;Geschmolzener Kern;" .. raidLabel .. ";1010",
		"Wurf-Zeile")
	check(lines[5]:find(";Urmeline;18813;Ring der Bindung;Wurf;;95;1-100;;1;freier Wurf;nicht tragbar;als Magier nicht tragbar (Platte);", 1, true), "untragbarer Wurf mit Grund", lines[5])
	check(lines[6]:find(";Gustl;18813;Ring der Bindung;freier Wurf;;88;1-100;;1;;;;Geschmolzener Kern;" .. raidLabel .. ";1020", 1, true), "Vergabe-Zeile: alte Spalten, dann Runde und Instanz", lines[6])
	-- Was ältere Leser von priomeister.de lesen: die ersten sechs Spalten, „Wurf“ ist keine Vergabe
	local kinds = {}
	for i = 2, #lines do kinds[#kinds + 1] = lines[i]:match("^[^;]*;[^;]*;[^;]*;[^;]*;[^;]*;([^;]*)") end
	eq(table.concat(kinds, ","), "Wurf,Wurf,Wurf,Wurf,freier Wurf", "Art je Zeile")
	-- Archiv und Fortsetzen nehmen das Protokoll mit
	local entry = L.ArchiveEntry(raid, 2000)
	check(entry.rollLog == raid.rollLog, "Archiv speichert das Wurf-Protokoll")
	check(L.ReopenRaid(entry).rollLog == raid.rollLog, "Fortsetzen bringt es zurück")
	-- Protokoll hat eine Obergrenze
	local big = L.NewRaid(0)
	for i = 1, L.ROLL_LOG_MAX + 5 do L.LogRoll(big, s, { t = i, name = "X", value = 1, low = 1, high = 100, status = "ok" }) end
	eq(#big.rollLog, L.ROLL_LOG_MAX, "höchstens " .. L.ROLL_LOG_MAX .. " Würfe je Raid")
	eq(big.rollLog[1].t, 6, "die ältesten fallen heraus")
end

-- Prio-Auflösung: wer das Item nicht tragen kann, zählt nicht als Prio-Halter
do
	local raid = L.NewRaid(0)
	raid.players = L.ParsePrioList("Name;Klasse;prio1itemid;prio2itemid;prio3itemid;prio1itemname;prio2itemname;prio3itemname;\n"
		.. "Urmeline;Magier;99001;0;0;;;;\nBartbär;Krieger;0;99001;0;;;;\n")
	local all = function() return true end
	local function unusable(key) if key == "urmeline" then return "als Magier nicht tragbar (Platte)" end end
	local res = L.ResolveItem(raid, 99001, all, { prio0Mode = 3, unusable = unusable })
	eq(res.top, 2, "Prio 1 der Magierin zählt nicht: Prio 2 ist dran")
	eq(res.mode, "single", "dann nur noch Bartbär")
	eq(res.topHolders[1] and res.topHolders[1].name, "Bartbär", "Bartbär bekommt es")
	eq(res.levels[1][1].unusable, "als Magier nicht tragbar (Platte)", "Magierin bleibt gelistet, mit Grund")
	eq(L.LootAnnouncement(res, "[Handschuhe]")[1], "[Handschuhe] – Prio 2: Bartbär", "Beute-Ansage nennt nur Bartbär")
	eq(L.ResolveItem(raid, 99001, all, { prio0Mode = 3 }).top, 1, "ohne Prüfung gilt Prio 1 der Magierin")
end

-- Raid fortsetzen: Eintrag im Archiv und Wiederaufnahme
do
	local raid = L.NewRaid(100)
	raid.players = { anna = { name = "Anna" } }
	raid.imported, raid.importCount, raid.meta = 90, 1, { run = "746312" }
	raid.awards = {
		{ key = "gustl", kind = "free", session = 3 },
		{ key = "gustl", kind = "tier", from = 99, to = 97 },
		{ key = "gustl", kind = "free", session = 7 },
		{ key = "hesti", kind = "tier", from = 100, to = 99 },
	}
	raid.adjust = { gustl = 2, hesti = 1 }
	eq(L.AllowedMax(raid, "gustl"), 96, "Ausgangslage: Gustl würfelt mit 96")
	local entry = L.ArchiveEntry(raid, 200)
	eq(entry.ended, 200, "Archiv: Ende des Raids")
	check(entry.players == raid.players and entry.meta.run == "746312" and entry.imported == 90, "Archiv speichert Prioliste und Prio-Run")
	local r = L.ReopenRaid(entry)
	eq(r.started, 100, "fortgesetzt: Beginn bleibt")
	eq(#r.awards, 4, "fortgesetzt: Vergaben bleiben")
	eq(r.sessionSeq, 7, "neue Würfelrunden schließen an die Nummern an")
	eq(L.AllowedMax(r, "gustl"), 96, "fortgesetzt: Würfelstufe samt Korrektur")
	eq(L.AllowedMax(r, "hesti"), 99, "fortgesetzt: Korrektur von Hesti")
	local legacy = L.ReopenRaid({ started = 50, ended = 60, awards = raid.awards })
	eq(legacy.adjust.gustl, 2, "älterer Raid: Korrektur aus dem Protokoll")
	eq(L.AllowedMax(legacy, "gustl"), 96, "älterer Raid: Würfelstufe stimmt")
	eq(L.AllowedMax(legacy, "hesti"), 99, "älterer Raid: auch Hesti")
	eq(next(legacy.players), nil, "älterer Raid: keine Prioliste gespeichert")
end

-- Entzauberer und Plünderhelfer zählen nicht als eigener Gewinn
do
	local raid = L.NewRaid(0)
	local s = L.NewSession(raid, 18813, "[Ring]", { top = nil, topHolders = {}, mode = "free" }, 1, {})
	local de = L.BuildAward(raid, "zenec", "Zenec", 18813, "[Ring]", { prio0Mode = 3, reason = "de" }, 2)
	eq(de.kind, "de", "Entzauberer-Knopf")
	L.RecordAward(raid, de)
	eq(L.AllowedMax(raid, "zenec"), 100, "Entzauberer behält seine Stufe")
	eq(L.CountAwards(raid, "zenec"), 0, "zählt nicht als bekommen")
	local viaList = L.BuildAward(raid, "zenec", "Zenec", 18205, "[Halsband]", { prio0Mode = 3, disenchanter = "zenec" }, 3)
	eq(viaList.kind, "de", "Zuweisung an den Entzauberer über die Liste ohne Wurf")
	eq(L.BuildAward(raid, "bank", "Bank", 20861, "[Skarabäus]", { helper = "bank" }, 4).kind, "helper", "Plünderhelfer erkannt")
	local upToGreen = { [0] = true, [1] = true, [2] = true }
	local rules = { items = { [20861] = true }, qualities = upToGreen, recipeRolls = true, helper = "Lola", treasurer = "Bank" }
	eq(L.AutoLootTarget(20861, 2, false, rules), "treasurer", "Item der Liste an den Schatzmeister")
	eq(L.AutoLootTarget(4000, 0, false, rules), "helper", "Grau unter Blau an den Plünderhelfer")
	eq(L.AutoLootTarget(15000, 2, false, rules), "helper", "Grün unter Blau an den Plünderhelfer")
	eq(L.AutoLootTarget(16914, 4, false, rules), nil, "Episch nicht automatisch")
	eq(L.AutoLootTarget(18259, 2, true, rules), nil, "Rezepte werden verwürfelt")
	local target, listed = L.AutoLootTarget(20861, 2, false, { items = { [20861] = true }, qualities = upToGreen, helper = "Lola" })
	check(target == nil and listed, "ohne Schatzmeister bleibt ein Item der Liste liegen, auch wenn die Qualität passt")
	eq(L.AutoLootTarget(4000, 0, false, { items = {}, qualities = upToGreen }), nil, "ohne Plünderhelfer nichts")
	local onlyWhite = { items = {}, qualities = { [1] = true }, helper = "Lola" }
	eq(L.AutoLootTarget(4500, 1, false, onlyWhite), "helper", "nur Weiß: weißes Item an den Plünderhelfer")
	eq(L.AutoLootTarget(4000, 0, false, onlyWhite), nil, "nur Weiß: graues Item bleibt")
	eq(L.AutoLootTarget(15000, 2, false, onlyWhite), nil, "nur Weiß: grünes Item bleibt")
	local sm = L.BuildAward(raid, "bank", "Bank", 21761, "[Schlüssel]", { treasurer = "bank", reason = "treasurer" }, 5)
	eq(sm.kind, "treasurer", "Schatzmeister bei automatischer Verteilung")
	eq(L.AwardDetail(sm), "Schatzmeister", "Protokoll: Schatzmeister")
	eq(L.BuildAward(raid, "bank", "Bank", 21761, "[Schlüssel]", { treasurer = "bank", helper = "bank", listed = true }, 6).kind,
		"treasurer", "von Hand: Item der Liste zählt für den Schatzmeister")
	eq(L.BuildAward(raid, "bank", "Bank", 4000, "[Grau]", { treasurer = "bank", helper = "bank", listed = false }, 7).kind,
		"helper", "von Hand: anderes Item für den Plünderhelfer")
	eq(L.BuildAward(raid, "bank", "Bank", 4000, "[Grau]", { treasurer = "bank", listed = false }, 7).kind,
		"none", "von Hand: Item außerhalb der Liste an den Schatzmeister ist eine normale Vergabe")
	L.RecordAward(raid, sm)
	eq(L.CountAwards(raid, "bank"), 0, "Schatzmeister zählt nicht als eigener Gewinn")
	local lists = L.DefaultLootLists()
	check(lists[509][21761] and lists[509][20858] and not lists[509][21762], "Vorbelegung AQ20: Schlüssel und Skarabäen")
	check(lists[531][21761] and lists[531][21762] and lists[531][20865], "Vorbelegung AQ40: auch der große Schlüssel")
	check(lists[0] and next(lists[0]) == nil, "Vorbelegung: Alle Instanzen leer")
	check(lists[509][21214] and lists[509][21307] and not lists[531][21214], "Vorbelegung AQ20: Klassenbücher beim Schatzmeister")
	check(lists[309][19726], "Vorbelegung ZG: Blutrebe beim Schatzmeister")
	local bijous = 0
	for _, id in ipairs(L.HAKKARI_BIJOUS) do
		if lists[309][id] then bijous = bijous + 1 end
	end
	eq(bijous, 9, "Vorbelegung ZG: neun Schmuckstücke der Hakkari beim Schatzmeister")
	check(lists[409][17010] and lists[409][17011] and lists[409][7078] and lists[409][17203],
		"Vorbelegung MC: Feuerkern, Lavakern, Essenz des Feuers und Sulfuronblock beim Schatzmeister")
	check(lists[469][18562] and lists[469][19183] and lists[469][17203],
		"Vorbelegung BWL: Elementiumerz, Stundenglassand und Sulfuronblock beim Schatzmeister")
	local count = 0
	for _ in pairs(L.AQ20_BOOKS) do count = count + 1 end
	eq(count, 27, "27 Klassenbücher")
	local zg = L.DefaultRollLists()[309]
	check(not zg[19726] and zg[19939] and zg[19940] and zg[19941] and zg[19942], "Vorbelegung ZG verwürfeln: die Items vom Rand des Wahnsinns")
	local withRoll = { items = { [19726] = true }, roll = { [19726] = true, [19698] = true },
		qualities = { [0] = true, [1] = true, [2] = true, [3] = true }, helper = "Lola", treasurer = "Bank" }
	local t2, l2 = L.AutoLootTarget(19726, 2, false, withRoll)
	check(t2 == nil and not l2, "Item zum Verwürfeln nie automatisch, auch wenn es auf der Schatzmeister-Liste steht")
	eq(L.AutoLootTarget(19698, 2, false, withRoll), nil, "Item zum Verwürfeln nicht an den Plünderhelfer")
	-- Runden für Vergaben per Handel
	local r2 = L.NewRaid(0)
	local free = { top = nil, topHolders = {}, mode = "free" }
	local a = L.NewSession(r2, 19726, "[Blutrebe]", free, 1, { source = "A", copies = 2 })
	L.AddRoll(r2, a, "Gustl", 80, 1, 100, 2)
	local b = L.NewSession(r2, 19726, "[Blutrebe]", free, 3, { source = "B" })
	L.AddRoll(r2, b, "Hesti", 60, 1, 100, 4)
	eq(a.copies, 2, "Runde kennt die Stückzahl")
	eq(L.FindSessionWithRoll(r2, 19726, "gustl"), a, "Handel an Gustl gehört zur älteren Runde")
	eq(L.FindSessionWithRoll(r2, 19726, "hesti"), b, "Handel an Hesti gehört zur neueren Runde")
	eq(L.FindSessionWithRoll(r2, 19726, "zenec"), nil, "ohne Wurf keine Runde")
	eq(L.FindSession(r2, 19726, { session = a.id }), a, "Runde direkt über ihre Nummer")
	eq(L.BuildAward(r2, "gustl", "Gustl", 19726, "[Blutrebe]", { prio0Mode = 3, ctx = { session = a.id } }, 5).roll, 80, "Vergabe nimmt den Wurf aus der genannten Runde")
end

-- Wurf ohne Stufen (Items zum Verwürfeln): alle mit 100, ein Gewinn senkt keine Stufe
do
	local raid = L.NewRaid(0)
	raid.adjust.gustl = 1
	local all = function() return true end
	local res = L.ResolveItem(raid, 19939, all, { prio0Mode = 3, plain = true })
	eq(res.mode, "plain", "Item zum Verwürfeln: Wurf ohne Stufen")
	eq(L.ResolveItem(raid, 19939, all, { prio0Mode = 3, plain = true, recipe = true, recipeRolls = true }).mode, "recipe", "Rezept bleibt Rezept-Wurf")
	local call = L.BuildRollCall(raid, res, "[Blut]", { { key = "gustl", name = "Gustl" } }, { copies = 2, tierHints = true })
	eq(#call, 1, "keine Zeile mit Stufen")
	eq(call[1], "[Blut] x2 – kein Prio, Wurf ohne Stufen: alle /roll 100, die 2 höchsten Würfe gewinnen", "Aufruf ohne Stufen")
	local s = L.NewSession(raid, 19939, "[Blut]", res, 1, { copies = 2, secondary = true })
	eq(s.mode, "plain", "Runde ohne Stufen")
	eq(L.AddRoll(raid, s, "Gustl", 90, 1, 100, 2).status, "ok", "Stufe 99 darf hier 100 würfeln")
	eq(L.AddRoll(raid, s, "Hesti", 90, 1, 100, 3).status, "ok", "Hesti 90")
	eq(L.AddRoll(raid, s, "Kronolus", 20, 1, 50, 4).kind, "sec", "50er-Wurf auch hier")
	eq(L.AddRoll(raid, s, "Zenec", 80, 1, 99, 5).status, "range", "99 statt 100 zählt nicht")
	local _, _, first = L.RankRolls(s)
	eq(first, nil, "zwei Exemplare: Gleichstand der Ersten ohne Stichwurf")
	local aw = L.BuildAward(raid, "gustl", "Gustl", 19939, "[Blut]", { prio0Mode = 3 }, 6)
	eq(aw.kind, "plain", "Vergabe: Wurf ohne Stufen")
	eq(L.AwardDetail(aw), "Wurf ohne Stufen 90 (1-100)", "Protokoll: Wurf ohne Stufen")
	L.RecordAward(raid, aw)
	eq(L.AllowedMax(raid, "gustl"), 99, "Gewinn ändert die Stufe nicht")
	eq(L.CountAwards(raid, "gustl"), 1, "zählt als bekommen")
	-- zwei Exemplare, 95 / 90 / 90: die beiden 90er stechen um das zweite
	local s2 = L.NewSession(raid, 19940, "[Zahn]", res, 7, { copies = 2 })
	L.AddRoll(raid, s2, "Arcanaa", 95, 1, 100, 8)
	L.AddRoll(raid, s2, "Hesti", 90, 1, 100, 9)
	L.AddRoll(raid, s2, "Kronolus", 90, 1, 100, 10)
	local _, _, cut, tied = L.RankRolls(s2)
	check(cut and #tied == 2 and cut.value == 90, "Gleichstand an der Grenze zum zweiten Exemplar")
	local s3 = L.NewSession(raid, 19940, "[Zahn]", res, 11, {})
	L.AddRoll(raid, s3, "Arcanaa", 70, 1, 100, 12)
	L.AddRoll(raid, s3, "Hesti", 70, 1, 100, 13)
	check(select(3, L.RankRolls(s3)) ~= nil, "ein Exemplar: Gleichstand an der Spitze wie bisher")
end

-- Reittiere: Prio wird ignoriert, wenn sie nicht erlaubt sind
do
	local raid = L.NewRaid(0)
	raid.players = L.ParsePrioList("Gustl;19872;0;0\nHesti;0;0;0")
	local all = function() return true end
	local res = L.ResolveItem(raid, 19872, all, { prio0Mode = 3, mount = true, ignorePrio = true })
	eq(res.mode, "free", "Reittier ohne Prio: freier Wurf")
	eq(#res.ignored, 1, "Gustls Reittier-Prio ignoriert")
	eq(L.LootAnnouncement(res, "[Raptor]")[1], "[Raptor] – Reittier, kein Prio", "Ansage Reittier")
	check(L.BuildRollCall(raid, res, "[Raptor]", {}, {})[1]:find("Reittier, kein Prio, freier Wurf: /roll 100", 1, true), "Würfelaufruf Reittier")
	eq(L.ResolveItem(raid, 19872, all, { prio0Mode = 3, mount = true }).mode, "single", "Reittiere erlaubt: Gustl bekommt ihn")
end

-- lange Namenslisten werden aufgeteilt
do
	local names = {}
	for i = 1, 40 do names[i] = "Spielername" .. string.char(64 + (i % 26) + 1) end
	local out = L.AppendChunks({}, "[Item] – Prio 1: ", names, " – bitte /roll 100")
	check(#out >= 2, "lange Liste aufgeteilt", #out)
	for _, line in ipairs(out) do check(#line <= 255, "Zeilenlänge <= 255", #line) end
end

do
	local o = L.MasterLootButtonOrder(15)
	eq(o[1], 1, "Knopf 1"); eq(o[8], 8, "Knopf 8"); eq(o[9], 11, "Knopf 9 in Spalte 2"); eq(o[15], 17, "Knopf 15")
end

-- Verzicht mit /roll 1: gilt für ein Exemplar, die Prio bleibt
do
	local raid = L.NewRaid(0)
	raid.players = L.ParsePrioList([[
Name;Klasse;prio1itemid;prio2itemid;prio3itemid;prio1itemname;prio2itemname;prio3itemname;
Anna;Magier;16914;0;0;;;;
Bodo;Magier;16914;0;0;;;;
Carl;Krieger;0;0;16914;;;;
]])
	local all = function() return true end
	check(L.IsPass(1, 1) and not L.IsPass(1, 100) and not L.IsPass(0, 1), "nur 1-1 ist ein Verzicht")
	L.RecordPass(raid, { key = "anna", name = "Anna", itemID = 16914, link = "[Krone]", level = 1, source = "A" }, 5)
	local passedA = L.PassesFor(raid, 16914, "A")
	check(passedA.anna and not passedA.bodo, "Verzicht für Leiche A erfasst")
	check(not L.PassesFor(raid, 16914, "B").anna, "andere Leiche: Verzicht gilt nicht")
	check(not L.PassesFor(raid, 16914, nil).anna, "ohne Herkunft gilt er nicht")
	local res = L.ResolveItem(raid, 16914, all, { prio0Mode = 3, passed = passedA })
	eq(res.mode, "single", "nach Annas Verzicht: nur noch Bodo")
	eq(res.topHolders[1].name, "Bodo", "Bodo ist dran")
	check(res.levels[1][1].name == "Anna" and res.levels[1][1].passed, "Anna bleibt gelistet, als verzichtet")
	eq(L.LootAnnouncement(res, "[Krone]")[1], "[Krone] – Prio 1: Bodo", "Beute-Ansage ohne Anna")
	eq(L.ResolveItem(raid, 16914, all, 3).mode, "roll", "anderes Exemplar: beide würfeln wieder")
	eq(L.PassMessages(raid.awards[1], res)[1], "Anna verzichtet auf [Krone] (Prio 1) – jetzt Prio 1: Bodo", "Chat nach dem Verzicht")
	L.RecordPass(raid, { key = "bodo", name = "Bodo", itemID = 16914, link = "[Krone]", level = 1, source = "A" }, 6)
	local res2 = L.ResolveItem(raid, 16914, all, { prio0Mode = 3, passed = L.PassesFor(raid, 16914, "A") })
	check(res2.top == 3 and res2.topHolders[1].name == "Carl", "beide Prio 1 verzichtet: Carl mit Prio 3")
	L.RecordPass(raid, { key = "carl", name = "Carl", itemID = 16914, link = "[Krone]", level = 3, source = "A" }, 7)
	local res3 = L.ResolveItem(raid, 16914, all, { prio0Mode = 3, passed = L.PassesFor(raid, 16914, "A") })
	eq(res3.mode, "free", "alle verzichtet: freier Wurf")
	eq(L.PassMessages(raid.awards[3], res3)[1], "Carl verzichtet auf [Krone] (Prio 3) – jetzt ohne Prio", "Chat: ohne Prio")
	eq(L.AwardCount(raid), 0, "Verzicht zählt nicht als Vergabe")
	eq(L.CountAwards(raid, "anna"), 0, "Verzicht ist kein eigener Gewinn")
	eq(L.OpenEntriesFor(raid, "anna", L.Canon(16914), 3)[1].level, 1, "Annas Prio bleibt für ein späteres Exemplar")
	eq(L.AwardLine(raid.awards[1]), "Anna verzichtet auf [Krone] (Prio 1)", "Zeile im Protokoll")
	eq(L.ShareLines(raid, function() return "16.10.2026, 20:00" end)[2], "Anna verzichtet auf [Krone] (Prio 1)", "Verzicht beim Teilen")
	local csv = L.ExportCSV({ raid }, os.date)
	check(csv:find(";Anna;16914;Krone;Verzicht;1;;;", 1, true), "Verzicht im Export", csv)
	eq(L.UndoLast(raid).kind, "pass", "Letzte zurücknehmen: der Verzicht")
	check(not L.PassesFor(raid, 16914, "A").carl and L.PassesFor(raid, 16914, "A").bodo, "Carl zählt wieder, Bodo nicht")
end

-- Verzicht in Würfelrunden
do
	local raid = L.NewRaid(0)
	local prio = { top = 1, mode = "roll", topHolders = { { key = "anna", name = "Anna" }, { key = "bodo", name = "Bodo" }, { key = "dora", name = "Dora" } } }
	local s = L.NewSession(raid, 16914, "[Krone]", prio, 1, {})
	L.AddRoll(raid, s, "Anna", 95, 1, 100, 2)
	L.AddRoll(raid, s, "Bodo", 40, 1, 100, 3)
	eq(L.RoundWinner(s).name, "Anna", "Anna vorn")
	eq(L.AddRoll(raid, s, "Anna", 1, 1, 1, 4).status, "pass", "/roll 1 ist ein Verzicht")
	eq(L.RoundWinner(s).name, "Bodo", "nach Annas Verzicht gewinnt Bodo")
	eq(L.ValidRollCount(s), 1, "Annas 95 zählt nicht mehr")
	eq(L.AddRoll(raid, s, "Anna", 99, 1, 100, 5).reason, "hat verzichtet", "nach dem Verzicht zählt kein Wurf")
	eq(L.AddRoll(raid, s, "Gustl", 1, 1, 1, 6).reason, "kein Prio 1", "ohne Prio kein Verzicht in der Prio-Runde")
	eq(L.RemainingEligible(s), 2, "Bodo und Dora sind noch dabei")
	eq(L.SessionPrioText(s), "Prio 1: Bodo, Dora", "Rückfrage nennt Anna nicht mehr")
	L.UndoPassInSession(s, "anna")
	eq(L.RoundWinner(s).name, "Anna", "Verzicht zurückgenommen: Annas 95 zählt wieder")
	-- ohne Prio: /roll 1 zieht den eigenen Wurf zurück und zählt nie als Wurf
	local free = { top = nil, topHolders = {}, mode = "free" }
	local f = L.NewSession(raid, 18813, "[Ring]", free, 10, { secondary = true })
	L.AddRoll(raid, f, "Gustl", 30, 1, 100, 11)
	L.AddRoll(raid, f, "Zenec", 1, 1, 1, 12)
	eq(L.RoundWinner(f).name, "Gustl", "1 (1-1) ist kein Wurf")
	L.AddRoll(raid, f, "Gustl", 1, 1, 1, 13)
	eq(L.RoundWinner(f), nil, "Gustl zieht zurück: kein Gewinner")
	eq(#L.OpenRolls(f), 0, "keine offenen Würfe für die Rückfrage vor dem Entzauberer")
	-- Stichwurf: einer der Gleichplatzierten verzichtet, der andere gewinnt ohne Stichwurf
	local t = L.NewSession(raid, 4000, "[X]", free, 20, {})
	L.AddRoll(raid, t, "Hesti", 50, 1, 100, 21)
	L.AddRoll(raid, t, "Wuld", 50, 1, 100, 22)
	check(L.StartTiebreak(t), "Gleichstand")
	eq(L.RoundWinner(t), nil, "Stichwurf steht aus")
	eq(L.AddRoll(raid, t, "Wuld", 1, 1, 1, 23).status, "pass", "Verzicht während des Stichwurfs")
	check(not L.WaitingForTiebreak(t, "hesti") and not L.WaitingForTiebreak(t, "wuld"), "niemand wartet mehr auf den Stichwurf")
	eq(L.RoundWinner(t) and L.RoundWinner(t).name, "Hesti", "Hesti gewinnt")
end

-- 1.17.1: Verzicht und Rücknahme ändern auch das Wurf-Protokoll
do
	local raid = L.NewRaid(0)
	local prio = { top = 1, mode = "roll", topHolders = { { key = "anna", name = "Anna" }, { key = "bodo", name = "Bodo" } } }
	local s = L.NewSession(raid, 16914, "[Krone]", prio, 1, {})
	local function roll(name, v, lo, hi, t) L.LogRoll(raid, s, L.AddRoll(raid, s, name, v, lo, hi, t), 409) end
	roll("Anna", 95, 1, 100, 2)
	roll("Anna", 95, 1, 100, 2)
	roll("Bodo", 40, 1, 100, 3)
	roll("Anna", 1, 1, 1, 4)
	local log = raid.rollLog
	eq(L.RollStatusText(log[1]), "zurückgezogen", "Protokoll: Annas 95 vor dem Verzicht zurückgezogen")
	eq(log[1].why, "Verzicht mit /roll 1", "Grund: Verzicht mit /roll 1")
	eq(L.RollStatusText(log[2]), "doppelt", "der doppelte Wurf in derselben Sekunde bleibt doppelt")
	eq(L.RollStatusText(log[3]), "zählt", "Bodos Wurf zählt weiter")
	eq(L.RollStatusText(log[4]), "verzichtet", "der Verzicht selbst")
	local csv = L.ExportCSV({ raid }, os.date)
	check(csv:find(";Anna;16914;Krone;Wurf;1;95;1-100;;1;Prio;zurückgezogen;Verzicht mit /roll 1;", 1, true), "Export: zurückgezogen mit Grund", csv)
	L.UndoPassInSession(s, "anna", raid)
	eq(L.RollStatusText(log[1]), "zählt", "Rücknahme: Annas 95 zählt im Protokoll wieder")
	eq(log[1].why, nil, "ohne Grund")
	eq(L.RollStatusText(log[4]), "zurückgenommen", "Rücknahme: der Verzicht ist zurückgenommen")
	-- Verzicht als Vergabe (Prio-Runde) und „Letzte zurücknehmen“
	local s2 = L.NewSession(raid, 16914, "[Krone]", prio, 10, {})
	L.LogRoll(raid, s2, L.AddRoll(raid, s2, "Anna", 77, 1, 100, 11), 409)
	L.RecordPass(raid, { key = "anna", name = "Anna", itemID = 16914, link = "[Krone]", level = 1, session = s2.id }, 12)
	L.PassInSession(s2, "anna", "Anna", 12, raid)
	eq(L.RollStatusText(log[#log]), "zurückgezogen", "Verzicht als Vergabe: Wurf zurückgezogen")
	eq(L.UndoLast(raid).kind, "pass", "Letzte zurücknehmen: der Verzicht")
	eq(L.RollStatusText(log[#log]), "zählt", "danach zählt der Wurf im Protokoll wieder")
	eq(L.RollStatusText(log[1]), "zählt", "der Wurf der ersten Runde bleibt, wie er ist")
	-- Ohne Protokoll oder ohne Eintrag passiert nichts
	eq(L.SyncLoggedRoll(nil, s, s.rolls[1]), nil, "ohne Raid kein Eintrag")
	eq(L.LoggedRoll(raid, s, { name = "Zenec", t = 2, value = 95, seq = 1 }), nil, "fremder Wurf: kein Eintrag")
	-- Protokolle aus 1.17.0 nachträglich richtigstellen
	local old = { awards = { { kind = "pass", key = "anna", name = "Anna", itemID = 16914, session = 3, t = 50 } }, rollLog = {
		{ t = 40, n = "Anna", v = 90, lo = 1, hi = 100, st = "ok", i = 16914, sid = 3 },
		{ t = 41, n = "Bodo", v = 20, lo = 1, hi = 100, st = "ok", i = 16914, sid = 3 },
		{ t = 45, n = "Anna", v = 88, lo = 1, hi = 100, st = "ok", i = 16914, sid = 2 },
		{ t = 55, n = "Anna", v = 70, lo = 1, hi = 100, st = "fremd", why = "hat verzichtet", i = 16914, sid = 3 },
		{ t = 60, n = "Gustl", v = 130, lo = 1, hi = 130, st = "range", i = 18813, sid = 4 },
		{ t = 61, n = "Gustl", v = 1, lo = 1, hi = 1, st = "pass", i = 18813, sid = 4 },
		{ t = 62, n = "Hesti", v = 70, lo = 1, hi = 100, st = "withdrawn", why = "zurückgezogen", i = 18813, sid = 4 },
	} }
	eq(L.RepairRollLog(old), 2, "zwei Würfe nachträglich zurückgezogen")
	local st = {}
	for i, e in ipairs(old.rollLog) do st[i] = e.st end
	eq(table.concat(st, ","), "withdrawn,ok,ok,fremd,withdrawn,pass,withdrawn", "nur Würfe vor dem Verzicht in derselben Runde")
	eq(old.rollLog[7].why, "Verzicht mit /roll 1", "älterer Nachtrag bekommt denselben Grund")
	eq(L.RepairRollLog(old), 0, "zweiter Lauf ändert nichts")
	eq(L.RepairRollLog({ awards = {} }), 0, "ohne Protokoll: nichts zu tun")
	-- Fortsetzen: neue Runden bekommen keine Nummer aus dem Protokoll
	eq(L.ReopenRaid({ started = 1, awards = { { kind = "free", session = 2, t = 5 } }, rollLog = { { t = 6, sid = 5 } } }).sessionSeq, 5,
		"Fortsetzen zählt nach der letzten Runde im Protokoll weiter")
end

-- 1.20: Priocheck von priomeister.de: wer welche Prios gesetzt hat, ohne Items
do
	local sample = "# priocheck;v=1;run=Ony+ZG 21.10.;pin=482913;link=https://priomeister.de/r/482913;instanzen=Onyxias Hort:1|Zul'Gurub:3\r\n"
		.. "Arcanaa;Magier;1;111\r\nZenec;Jäger;0;100\r\nLillianaa;Priester;1;000\r\nGustl-Lakeshire;Krieger;0;000\r\n"
	check(L.IsPrioCheck(sample) and L.IsPrioCheck("  # PrioCheck;v=1") and not L.IsPrioCheck("Name;Klasse;prio1itemid\n# priocheck"),
		"Priocheck an der ersten Zeile erkannt")
	local c = L.ParsePrioCheck(sample)
	check(c.meta.run == "Ony+ZG 21.10." and c.meta.pin == "482913" and c.meta.link == "https://priomeister.de/r/482913" and c.meta.v == "1",
		"Kopfzeile gelesen")
	eq(#c.instances, 2, "zwei Instanzen")
	check(c.instances[1].name == "Onyxias Hort" and c.instances[1].slots == 1 and c.instances[2].name == "Zul'Gurub" and c.instances[2].slots == 3,
		"Instanzen mit Anzahl Prios")
	eq(c.count, 4, "vier Charaktere mit Eintrag")
	check(c.players.zenec and c.players.zenec.bits[1] == "0" and c.players.zenec.bits[2] == "100", "Ziffern je Instanz")
	check(c.players.gustl and c.players.gustl.name == "Gustl", "Server-Anhang weg")
	eq(L.CheckMissing(c, c.players.arcanaa), nil, "Arcanaa vollständig")
	eq(L.CheckMissing(c, c.players.zenec), "Onyxias Hort fehlt, Zul'Gurub ohne Prio 2 und 3", "Zenec: was fehlt")
	eq(L.CheckMissing(c, c.players.lillianaa), "Zul'Gurub fehlt", "Lillianaa: ZG fehlt")
	eq(L.CheckMissing(c, c.players.gustl), "all", "Gustl: alles leer")
	local roster = { { key = "arcanaa", name = "Arcanaa" }, { key = "zenec", name = "Zenec" }, { key = "gustl", name = "Gustl" },
		{ key = "bodo", name = "Bodo" }, { key = "anna", name = "Anna" } }
	local res = L.CheckRaid(c, roster)
	eq(table.concat(res.none, ","), "Anna,Bodo,Gustl", "ohne Prios: nicht auf der Seite oder alles leer")
	check(#res.partial == 1 and res.partial[1].name == "Zenec", "unvollständig: Zenec")
	check(res.complete == 1 and table.concat(res.away, ",") == "Lillianaa", "eine vollständig, Lillianaa nicht im Raid")
	local gone = L.ParsePrioCheck("# priocheck;instanzen=Onyxias Hort:1|Zul'Gurub:3\nZora;Magier;0;010\nLeer;Magier;0;000\nBodo;Krieger;1;111\nArcanaa;Magier;1;111\n")
	eq(table.concat(L.CheckRaid(gone, { { key = "arcanaa", name = "Arcanaa" } }).away, ","), "Bodo,Zora",
		"nicht im Raid: wer Prios gesetzt hat, sortiert, ohne leere Einträge")
	-- eine Instanz: ohne ihren Namen; ohne Angabe der Instanzen aus den Zeilen
	local one = L.ParsePrioCheck("# priocheck;run=ZG;instanzen=Zul'Gurub:3\nHesti;Priester;101\n")
	eq(L.CheckMissing(one, one.players.hesti), "ohne Prio 2", "eine Instanz: nur die Prio")
	local bare = L.ParsePrioCheck("# priocheck\nHesti;Priester;10;111\n")
	check(#bare.instances == 2 and bare.instances[1].slots == 2, "Instanzen aus den Zeilen abgeleitet")
	eq(L.ParsePrioCheck("Name;Klasse;prio1itemid;\nHesti;Priester;1;0;0;"), nil, "eine Prioliste ist kein Priocheck")
end

-- 1.18: Weitergaben zählen wie eine neue Vergabe
do
	local raid = L.NewRaid(1000)
	raid.players = L.ParsePrioList("Name;Klasse;prio1itemid;prio2itemid;prio3itemid;prio1itemname;prio2itemname;prio3itemname;\n"
		.. "Hestina;Jäger;18703;0;0;;;;\nValas;Jäger;0;18703;0;;;;\nZenec;Jäger;19019;0;0;;;;\n")
	local function award(key, name, kind, item, t, extra)
		local aw = { key = key, name = name, kind = kind, itemID = item, link = "[Item " .. item .. "]", t = t, instance = 409 }
		for k, v in pairs(extra or {}) do aw[k] = v end
		L.RecordAward(raid, aw)
		return #raid.awards
	end
	local blatt = award("hestina", "Hestina", "prio", 18703, 2000, { level = 1 })
	local krone = award("gustl", "Gustl", "free", 16914, 2100, { roll = 80, low = 1, high = 100 })
	local rezept = award("bodo", "Bodo", "recipe", 18259, 2200, { roll = 50, low = 1, high = 100 })
	eq(L.AwardCount(raid), 3, "drei Vergaben")
	eq(L.AllowedMax(raid, "gustl"), 99, "Gustl nach freiem Wurf bei 99")

	-- Rückfrage: Folgen ausrechnen, ohne etwas zu ändern
	eq(table.concat(L.HandoverEffects(raid, blatt, "valas", "Valas"), " | "),
		"Valas: Prio 2 auf das Item ist damit erfüllt. | Hestina: Prio 1 auf das Item ist wieder offen.", "Folgen: Prio erfüllt, Prio wieder offen")
	eq(table.concat(L.HandoverEffects(raid, krone, "zenec", "Zenec"), " | "),
		"Zenec würfelt dann mit /roll 99 statt 100. | Gustl würfelt wieder mit /roll 100 statt 99.", "Folgen: Würfelstufe wandert")
	eq(table.concat(L.HandoverEffects(raid, rezept, "zenec", "Zenec"), " | "), "Zenec: Würfelstufe bleibt bei /roll 100.",
		"Folgen: Rezept-Wurf kostet keine Stufe")
	check(#raid.awards == 3 and not raid.awards[blatt].givenTo, "die Rückfrage ändert nichts")
	eq(select(2, L.HandoverEffects(raid, blatt, "hestina", "Hestina")), "Hestina hat das Item schon.", "an sich selbst geht nicht")
	eq(select(2, L.HandoverEffects(raid, blatt, nil, nil)), "Kein Name angegeben.", "ohne Name")

	-- Hestina gibt das Blatt an Valas, der Prio 2 darauf hat
	local v = L.RecordHandover(raid, blatt, "valas", "Valas", 3000)
	check(v and v.kind == "given" and v.level == 2 and v.from == "Hestina" and v.origin == "prio" and v.srcT == 2000, "Weitergabe eingetragen")
	eq(raid.awards[blatt].givenTo, "Valas", "Vergabe merkt sich den Empfänger")
	eq(#L.OpenEntriesFor(raid, "valas", 18703), 0, "Valas' Prio 2 ist erfüllt")
	eq(L.OpenEntriesFor(raid, "hestina", 18703)[1] and L.OpenEntriesFor(raid, "hestina", 18703)[1].level, 1, "Hestinas Prio 1 ist wieder offen")
	eq(L.AllowedMax(raid, "valas"), 100, "mit Prio keine Stufe")
	check(L.CountAwards(raid, "hestina") == 0 and L.CountAwards(raid, "valas") == 1, "das Item zählt bei Valas")
	eq(L.AwardCount(raid), 3, "eine Weitergabe ist keine neue Vergabe")
	eq(L.AwardLine(v), "Valas erhält [Item 18703] – Weitergabe von Hestina, Prio 2", "Zeile der Weitergabe")
	eq(L.AwardLine(raid.awards[blatt]), "Hestina erhält [Item 18703] – Prio 1, an Valas weitergegeben", "Zeile der Vergabe davor")
	eq(select(2, L.RecordHandover(raid, blatt, "zenec", "Zenec", 3001)), "Hestina hat das Item schon an Valas weitergegeben.",
		"zweimal weitergeben geht nicht")

	-- Gustl gibt die Krone an Zenec ohne Prio darauf: die Würfelstufe wandert
	local z = L.RecordHandover(raid, krone, "zenec", "Zenec", 3100)
	check(z.level == nil and L.AllowedMax(raid, "zenec") == 99 and L.AllowedMax(raid, "gustl") == 100, "Stufe wandert zu Zenec")
	-- Kette: Valas gibt das Blatt weiter an Zenec, der keine Prio darauf hat
	local vi = #raid.awards - 1
	local z2 = L.RecordHandover(raid, vi, "zenec", "Zenec", 3200)
	check(z2.origin == "prio" and z2.from == "Valas" and L.AllowedMax(raid, "zenec") == 98, "Kette: Zenec jetzt bei 98")
	eq(L.OpenEntriesFor(raid, "valas", 18703)[1] and L.OpenEntriesFor(raid, "valas", 18703)[1].level, 2, "Valas' Prio 2 wieder offen")
	eq(select(2, L.RemoveHandover(raid, vi)), "Valas hat das Item schon an Zenec weitergegeben, erst diese Weitergabe zurücknehmen.",
		"Zurücknehmen erst am Ende der Kette")
	-- Export: Geber „weitergegeben“, Empfänger „Weitergabe“ eine Sekunde nach der Vergabe davor
	local csv = L.ExportCSV({ raid }, os.date)
	check(csv:find(";Hestina;18703;Item 18703;Prio;1;;;;;;weitergegeben;an Valas;", 1, true), "Export: Hestina hat weitergegeben", csv)
	check(csv:find(";Valas;18703;Item 18703;Weitergabe;2;;;;;;weitergegeben;von Hestina, an Zenec;", 1, true), "Export: Valas, Mitte der Kette")
	check(csv:find(";Zenec;18703;Item 18703;Weitergabe;;;;;;;;von Valas;409;", 1, true) and csv:find(";2001\n", 1, true)
		and csv:find(";3001$"), "Export: Zeitpunkte direkt nach der Vergabe davor", csv)
	-- Zurücknehmen: zuerst das Ende der Kette, dann mitten aus der Liste
	local removed, src = L.RemoveHandover(raid, #raid.awards)
	check(removed == z2 and src == v and not v.givenTo, "Kette zurück: Valas hat das Blatt wieder")
	check(L.RemoveHandover(raid, vi) == v and not raid.awards[blatt].givenTo, "mitten aus der Liste: Hestina hat das Blatt wieder")
	eq(L.OpenEntriesFor(raid, "valas", 18703)[1].level, 2, "Valas' Prio offen")
	eq(#L.OpenEntriesFor(raid, "hestina", 18703), 0, "Hestinas Prio wieder erfüllt")
	eq(L.UndoLast(raid), z, "Letzte zurücknehmen: die Weitergabe der Krone")
	check(L.AllowedMax(raid, "gustl") == 99 and L.AllowedMax(raid, "zenec") == 100 and not raid.awards[krone].givenTo, "Krone wieder bei Gustl")
	eq(#raid.awards, 3, "Liste wie vorher")
	eq(L.HandoverUndoLine(z), "Weitergabe zurückgenommen: [Item 16914] ist wieder bei Gustl", "Text der Rücknahme")
	-- Auch vom Entzauberer, aber keine Notizen
	local de = award("arcanielle", "Arcanielle", "de", 19019, 2300)
	local zd = L.RecordHandover(raid, de, "zenec", "Zenec", 3300)
	check(zd and zd.level == 1 and zd.origin == "de", "Fehlklick „An Entzauberer“: an Zenec mit Prio 1")
	L.RecordTierChange(raid, "gustl", "Gustl", 99, 98, 0, 3400)
	eq(select(2, L.RecordHandover(raid, #raid.awards, "zenec", "Zenec", 3500)), "Weitergeben lassen sich nur vergebene Items.",
		"Würfelstufe von Hand lässt sich nicht weitergeben")
	-- Weitergabe aus 50er-Wurf und Wurf ohne Stufen kostet keine Stufe
	for _, kind in ipairs({ "sec", "plain" }) do
		local i = award("bodo", "Bodo", kind, 4000, 2400, { roll = 40, low = 1, high = 50 })
		L.RecordHandover(raid, i, "lola", "Lola", 3600)
		eq(L.AllowedMax(raid, "lola"), 100, "keine Stufe nach Weitergabe aus " .. kind)
	end
end

-------------------------------------------------------------------------------
-- Teil 2: Addon im nachgebauten Spiel
-------------------------------------------------------------------------------

local mock = dofile(TESTDIR .. "/wowmock.lua")
local PM, UI
local NS -- Namensraum des zuletzt geladenen Addons
local function loadAddon()
	local addonNS = {}
	for _, file in ipairs(FILES) do
		assert(loadfile(ADDON_DIR .. "/" .. file))("PrioMeister", addonNS)
	end
	PM, UI, NS = addonNS.PM, addonNS.UI, addonNS
end

-- Altdaten aus Version 1.0: Raidansage war aus
PrioMeisterDB = { dbVersion = 1, settings = { awardsToRaid = false, reportWrongRolls = true,
	autoLootItems = { [2589] = true, [20861] = true } }, pins = {}, history = {} }
loadAddon()

mock.raid = {
	{ "Arcanaa", "MAGE" }, { "Arcanielle", "MAGE" }, { "Bolzenblitz", "MAGE" }, { "Urmeline", "MAGE" },
	{ "Awfulkitty", "DRUID" }, { "Noraja", "WARLOCK" }, { "Drachenwut", "WARRIOR" }, { "Gustl", "WARRIOR" },
	{ "Kronolus", "PALADIN" }, { "Loladina", "PALADIN" }, { "Veldore", "PALADIN" }, { "Hesti", "PRIEST" },
	{ "Nanuheal", "PRIEST" }, { "Sairá", "PRIEST" }, { "Zenec", "HUNTER" }, { "Ärwin", "ROGUE" }, { "Bartbär", "WARRIOR" },
}
mock.candidates = {}
for i, r in ipairs(mock.raid) do mock.candidates[i] = r[1] end

mock.Fire("ADDON_LOADED", "PrioMeister")
mock.Fire("PLAYER_LOGIN")
check(PM.hookedGive and PM.hookedML, "Hooks installiert")
eq(PM.db.settings.awardsToRaid, true, "Punkt 7: Altdaten auf Raidansage umgestellt")
eq(PM.db.dbVersion, 9, "Datenbank-Version 9")
eq(PM.db.settings.always100, false, "1.26: „Immer mit /roll 100 würfeln“ ist voreingestellt aus")
eq(PM.db.settings.autoLootItems, nil, "alte Auto-Liste aufgelöst")
check(PM.db.settings.lootLists[0][2589], "alte Auto-Liste gilt in allen Instanzen")
check(not PM.db.settings.lootLists[0][20861], "Skarabäus steht schon in der AQ-Liste")
check(PM.db.settings.lootLists[509][21761] and PM.db.settings.lootLists[531][20861], "AQ-Listen vorbelegt")
eq(PM.db.settings.mountPrio, false, "Reittiere standardmäßig nicht auf Prio")
eq(PM.db.settings.helperLowChat, false, "Grau/Weiß an den Plünderhelfer standardmäßig nicht melden")
check(_G.PrioMeisterMinimapButton and _G.PrioMeisterMinimapButton:IsShown(), "Minimap-Knopf da")

-- Logo: Fensterkopf, Minimap-Knopf und Addon-Liste zeigen Bilder aus Media, die es gibt und die WoW lesen kann
do
	local function tga(path)
		local rel = path:gsub("^Interface\\AddOns\\PrioMeister\\", ""):gsub("\\", "/")
		local fh = io.open(ADDON_DIR .. "/" .. rel, "rb")
		if not fh then return nil end
		local h = fh:read(18)
		fh:close()
		return { kind = h:byte(3), w = h:byte(13) + 256 * h:byte(14), h = h:byte(15) + 256 * h:byte(16), bpp = h:byte(17) }
	end
	local function pow2(n) local p = 1 while p < n do p = p * 2 end return p == n end
	local function valid(path, label)
		local t = tga(path)
		check(t, label .. ": Datei da", path)
		if t then
			check(t.kind == 2 and t.bpp == 32, label .. ": TGA unkomprimiert mit Alpha", t.kind .. "/" .. t.bpp)
			check(t.w == t.h and pow2(t.w), label .. ": quadratisch, Zweierpotenz", t.w .. "x" .. t.h)
		end
	end
	local main = UI:GetMain()
	eq(main.logo._texture, UI.LOGO, "Logo im Fensterkopf")
	valid(UI.LOGO, "Logo im Fensterkopf")
	local p = main.title._points[1]
	check(p and p[1] == "LEFT" and p[2] == main.logo and p[3] == "RIGHT", "Titel steht rechts neben dem Logo")
	eq(_G.PrioMeisterMinimapButton.icon._texture, UI.LOGO_ROUND, "rundes Logo auf dem Minimap-Knopf")
	valid(UI.LOGO_ROUND, "Minimap-Logo")
	local fh = io.open(ADDON_DIR .. "/PrioMeister.toc", "rb")
	local toc = fh:read("*a")
	fh:close()
	local icon = toc:match("\n## IconTexture: ([^\r\n]+)")
	check(icon, "TOC nennt ein Symbol für die Addon-Liste")
	if icon then valid(icon, "Symbol in der Addon-Liste") end
	eq(toc:match("\n## Version: ([^\r\n]+)"), PM.version, "Version in TOC und Core gleich")
end

-- Import, Punkt 2: Hinweis auf Spieler ohne Prio
SlashCmdList.PRIOMEISTER("import")
check(_G.PrioMeisterImportFrame:IsShown(), "Importfenster offen")
_G.PrioMeisterImportFrameEdit:SetText(CSV .. "Zenec;Jäger;18259;0;0;Formel: Waffe - Zauberkraft;;;\n")
mock.chat = {}
PM:ImportText(_G.PrioMeisterImportFrameEdit:GetText(), true)
check(mock.ChatContains("15 Spieler importiert"), "Import-Meldung", table.concat(mock.chat, "\n"))
check(mock.ChatContains("Ärwin, Bartbär"), "Hinweis auf Spieler ohne Prio", table.concat(mock.chat, "\n"))
check(mock.ChatContains("Rezepte sind nicht auf Prio möglich") and mock.ChatContains("Zenec"), "Punkt 5: Rezept auf Prio gemeldet", table.concat(mock.chat, "\n"))
-- Prio-Tabelle wie bei Prio3: nach dem Import kurz offen
local prioTable = _G.PrioMeisterPrioTable
check(prioTable and prioTable:IsShown() and prioTable.autoClose == 20, "Prio-Tabelle nach dem Import offen")
check(prioTable.info:GetText():find("15 Spieler, davon 15 im Raid", 1, true), "Kopf nennt die Anzahl", prioTable.info:GetText())
check(prioTable.rows[1].name:GetText():find("Arcanaa", 1, true), "Tabelle alphabetisch")
check(prioTable.rows[1].cells[1].text:GetText():find("Krone des Netherwinds", 1, true), "Prio 1 von Arcanaa")
check(prioTable.rows[1].cells[2].text:GetText():find("keine Prio 2", 1, true), "leere Prio markiert")
local zenecRow
for _, r in ipairs(prioTable.rows) do
	if r._shown and r.name:GetText():find("Zenec", 1, true) then zenecRow = r end
end
check(zenecRow and zenecRow.cells[1].text:GetText():find("ignoriert", 1, true), "Rezept-Prio als ignoriert markiert")
zenecRow.cells[1]._scripts.OnEnter(zenecRow.cells[1])
check(GameTooltip._lines[1]:find("item:18259", 1, true), "Tooltip zeigt das Item")
prioTable._scripts.OnUpdate(prioTable, 5)
check(prioTable.footer:GetText():find("Schließt in 15 s", 1, true), "Countdown sichtbar", prioTable.footer:GetText())
prioTable._scripts.OnUpdate(prioTable, 16)
check(not prioTable:IsShown(), "Tabelle schließt von selbst")
UI:ShowPrioTable(20)
prioTable.IsMouseOver = function() return true end
prioTable._scripts.OnUpdate(prioTable, 30)
check(prioTable:IsShown() and prioTable.autoClose == nil, "Maus darüber hält die Tabelle offen")
prioTable.IsMouseOver = nil
prioTable:Hide()
-- neuer Spieler ohne Prio kommt dazu
mock.chat = {}
table.insert(mock.raid, { "Neuling", "ROGUE" })
mock.Fire("GROUP_ROSTER_UPDATE")
mock.Fire("GROUP_ROSTER_UPDATE")
mock.RunTimers()
check(mock.ChatContains("Im Raid ohne Prio:|r Neuling."), "Hinweis auf neuen Spieler ohne Prio", table.concat(mock.chat, "\n"))
local noticeCount = #mock.chat
mock.Fire("GROUP_ROSTER_UPDATE")
mock.RunTimers()
eq(#mock.chat, noticeCount, "kein zweiter Hinweis für denselben Spieler")
mock.sent = {}
SlashCmdList.PRIOMEISTER("erinnern")
check(mock.SentContains("Noch ohne Prio: Ärwin, Bartbär, Neuling – bitte Prios auf priomeister.de eintragen!"), "Erinnerung im Raid", mock.sent[1] and mock.sent[1].msg)
table.remove(mock.raid)
mock.Fire("GROUP_ROSTER_UPDATE")
mock.RunTimers()

-- Rollen über die Namensauswahl (Punkt 6)
local panelBtn
mock.OpenLoot({
	{ id = 16914 }, -- Krone: Prio 1 Arcanaa, Arcanielle, Bolzenblitz
	{ id = 18423 }, -- Kopf von Onyxia (Allianz): Awfulkitty hat 18422 gewählt
	{ id = 18813 }, -- Ring der Bindung: frei
	{ id = 16929 }, -- Schädelkappe: Noraja, Urmeline
	{ money = true },
	{ id = 2589 },  -- Leinenstoff: grau, nicht relevant
	{ id = 18259 }, -- Formel (Rezept), Zenecs Prio wird ignoriert
})
local panel = _G.PrioMeisterPanel
check(panel and panel:IsShown(), "Panel neben dem Plünderfenster")
eq(#PM.lootItems, 5, "5 relevante Items")
panel.helper._scripts.OnClick(panel.helper)
local picker = _G.PrioMeisterPicker
check(picker:IsShown(), "Namensauswahl offen")
local function pickName(name)
	for _, b in ipairs(picker.buttons) do
		if b._shown and b.entry and b.entry.name == name then
			b._scripts.OnClick(b)
			return true
		end
	end
	return false
end
check(pickName("Loladina"), "Loladina in der Auswahl")
eq(PM.db.settings.lootHelper, "Loladina", "Plünderhelfer gesetzt")
check(not picker:IsShown(), "Auswahl schließt nach Klick")
panel.de._scripts.OnClick(panel.de)
_G.PrioMeisterPickerEdit:SetText("Zenec")
_G.PrioMeisterPickerEdit._scripts.OnEnterPressed(_G.PrioMeisterPickerEdit)
eq(PM.db.settings.disenchanter, "Zenec", "Entzauberer über Namenseingabe gesetzt")
panel.treasurer._scripts.OnClick(panel.treasurer)
check(pickName("Nanuheal"), "Nanuheal in der Auswahl")
eq(PM.db.settings.treasurer, "Nanuheal", "Schatzmeister gesetzt")
check(panel.helper:GetText():find("Loladina", 1, true), "Rollen-Knopf zeigt Plünderhelfer")
check(panel.treasurer:GetText():find("SM: ", 1, true) and panel.treasurer:GetText():find("Nanuheal", 1, true),
	"Panel zeigt den Schatzmeister mit Kürzel", panel.treasurer:GetText())

local rows = panel.rows
check(rows[1].info:GetText():find("3 Spieler würfeln um Prio 1", 1, true), "Krone: 3 würfeln", rows[1].info:GetText())
check(rows[2].info:GetText():find("Vergabe an Awfulkitty", 1, true), "Kopf: Awfulkitty", rows[2].info:GetText())
local recipeRow
for _, r in ipairs(rows) do if r._shown and r.data and r.data.itemID == 18259 then recipeRow = r end end
check(recipeRow and recipeRow.info:GetText():find("Rezept, Prio ignoriert:|r Zenec", 1, true), "Rezept-Zeile nennt ignorierte Prio", recipeRow and recipeRow.info:GetText())
check(recipeRow and recipeRow.info:GetText():find("Rezept-Wurf für Verzauberkunst", 1, true), "Rezept-Zeile nennt Beruf")
rows[1]._scripts.OnEnter(rows[1])
check(GameTooltip._lines and #GameTooltip._lines > 3, "Zeilen-Tooltip gefüllt")

-- Würfeln um die Krone
mock.sent = {}
rows[1].btn._scripts.OnClick(rows[1].btn, "LeftButton")
local call = mock.sent[#mock.sent]
check(call and call.msg:find("Prio 1: Arcanaa, Arcanielle, Bolzenblitz – bitte /roll 100", 1, true), "Würfelaufruf Krone", call and call.msg)
mock.Roll("Arcanaa", 57)
mock.Roll("Bolzenblitz", 91)
mock.Roll("Gustl", 99)
mock.Roll("Arcanielle", 91)
mock.Roll("Arcanielle", 12)
local firstSession = L.ActiveSession(PM:Raid())
rows[1].btn._scripts.OnClick(rows[1].btn, "LeftButton")
eq(L.ActiveSession(PM:Raid()), firstSession, "zweiter Klick behält die Würfelrunde")
local s = L.ActiveSession(PM:Raid())
eq(#s.rolls, 5, "5 Würfe erfasst")
local _, _, tie = L.RankRolls(s)
check(tie ~= nil, "Gleichstand erkannt")
check(UI:RollLines(s)[1]:find("Gleichstand", 1, true), "Gleichstand angezeigt")
mock.sent = {}
panel.rollPost._scripts.OnClick(panel.rollPost)
check(mock.sent[1] and select(2, mock.sent[1].msg:gsub("%d%. ", "")) == 3, "Ergebnis: genau drei Plätze", mock.sent[1] and mock.sent[1].msg)

-- Plündermeister-Liste: Rollen, dann Angeheftete, dann A-Z
PM:TogglePin("Hesti")
LootFrame.selectedSlot = 1
MasterLooterFrame_Show()
local order = mock.ListOrder()
eq(order[1], "Loladina", "zuerst Plünderhelfer")
eq(order[2], "Nanuheal", "dann Schatzmeister")
eq(order[3], "Zenec", "dann Entzauberer")
eq(order[4], "Hesti", "dann Angeheftete")
eq(order[5], "Arcanaa", "dann alphabetisch")
for i = 1, 40 do
	local b = MasterLooterFrame["player" .. i]
	if b and b._shown then eq(mock.candidates[b.id], b.Name:GetText(), "Knopf " .. i .. " passt zum Kandidaten") end
end
local tags = {}
for i = 1, 40 do
	local b = MasterLooterFrame["player" .. i]
	if b and b._shown and b.pmTag then tags[b.Name:GetText()] = b.pmTag:GetText() end
end
eq(tags["Bolzenblitz"], "P1", "Bolzenblitz als P1 markiert")
eq(tags["Loladina"], "PH", "Plünderhelfer markiert")
eq(tags["Zenec"], "DE", "Entzauberer markiert")
eq(tags["Nanuheal"], "SM", "Schatzmeister markiert")

-- Krone an Bolzenblitz, Punkt 7: Ergebnis auch im Raidchat
mock.chat, mock.sent = {}, {}
mock.AssignViaList(1, "Bolzenblitz")
check(mock.ChatContains("Bolzenblitz erhält") and mock.ChatContains("Prio 1, Wurf 91 (1-100)"), "Vergabe protokolliert")
check(mock.SentContains("Bolzenblitz erhält"), "Vergabe im Raidchat")
check(s.closed, "Würfelrunde nach Vergabe beendet")
mock.AssignViaList(2, "Awfulkitty")
-- Prio-Tabelle über /pm tabelle: erhaltene Prio markiert, ohne Countdown
SlashCmdList.PRIOMEISTER("tabelle")
check(prioTable:IsShown() and prioTable.autoClose == nil, "/pm tabelle öffnet ohne Countdown")
local bolzRow
for _, r in ipairs(prioTable.rows) do
	if r._shown and r.name:GetText():find("Bolzenblitz", 1, true) then bolzRow = r end
end
check(bolzRow and bolzRow.cells[1].text:GetText():find("erhalten", 1, true), "erhaltene Prio markiert", bolzRow and bolzRow.cells[1].text:GetText())
prioTable:Hide()
-- Importfenster zeigt die geladene Liste als CSV
SlashCmdList.PRIOMEISTER("import")
local csvText = _G.PrioMeisterImportFrameEdit:GetText()
check(csvText:find("^Name;Klasse;prio1itemid;prio2itemid;prio3itemid;prio1itemname;prio2itemname;prio3itemname;\n"), "Importfenster: CSV mit Kopfzeile")
check(csvText:find("Arcanaa;Magier;16914;0;0;Krone des Netherwinds;;;", 1, true), "Importfenster: Zeile von Arcanaa", csvText)
check(csvText:find("Veldore;Paladin;16955;0;0;Krone des Richturteils;;;", 1, true), "fehlender Itemname aus dem Spiel ergänzt")
check(_G.PrioMeisterImportFrame.status:GetText():find("15 Spielern", 1, true), "Hinweis auf die geladene Liste")
_G.PrioMeisterImportFrame:Hide()

-- Ring: freier Wurf mit 50er (Punkt 4)
local function rowFor(id)
	for _, r in ipairs(panel.rows) do
		if r._shown and r.data and r.data.itemID == id then return r end
	end
end
local function sentText() local t = {} for _, x in ipairs(mock.sent) do t[#t + 1] = x.msg end return table.concat(t, "\n") end
mock.sent = {}
local ringRow = rowFor(18813)
ringRow.btn._scripts.OnClick(ringRow.btn, "LeftButton")
check(mock.SentContains("kein Prio, freier Wurf: /roll 100") and not mock.SentContains("/roll 50"), "freier Wurf ohne 50er-Hinweis angesagt")
mock.Roll("Gustl", 88)
mock.Roll("Hesti", 49, 1, 50)
mock.Roll("Zenec", 40)
mock.chat = {}
mock.AssignViaList(3, "Gustl", false)
mock.Fire("CHAT_MSG_LOOT", "Gustl bekommt Beute: " .. mock.Link(18813) .. ".")
check(mock.ChatContains("freier Wurf 88 (1-100) – würfelt ab jetzt mit /roll 99"), "freier Wurf mit Stufenhinweis")
mock.loot[3] = false
mock.Fire("LOOT_SLOT_CLEARED", 3)

-- Rezept-Wurf (Punkt 5)
mock.sent = {}
recipeRow = rowFor(18259)
recipeRow.btn._scripts.OnClick(recipeRow.btn, "LeftButton")
check(mock.SentContains("Rezept für Verzauberkunst, nur mit passendem Beruf: /roll 100"), "Rezept-Wurf angesagt", mock.sent[1] and mock.sent[1].msg)
mock.Roll("Gustl", 95, 1, 100) -- Stufe 99 gilt beim Rezept nicht
mock.Roll("Zenec", 20)
eq(L.RankRolls(L.ActiveSession(PM:Raid()))[1].name, "Gustl", "Gustl darf beim Rezept mit 100 würfeln")
mock.chat = {}
mock.AssignViaList(7, "Gustl")
check(mock.ChatContains("Rezept-Wurf 95 (1-100)"), "Rezept-Gewinn protokolliert", table.concat(mock.chat, "\n"))
eq(L.AllowedMax(PM:Raid(), "gustl"), 99, "Rezept ändert Gustls Stufe nicht")

-- Entzauberer (Punkt 6): Würfelrunde ohne Teilnehmer
mock.sent = {}
local skullRow = rowFor(16929)
skullRow.btn._scripts.OnClick(skullRow.btn, "RightButton")
eq(L.ActiveSession(PM:Raid()).mode, "free", "Rechtsklick startet freien Wurf")
check(panel.rollDE:IsShown() and panel.rollDE._locked, "Entzauberer-Knopf hervorgehoben, wenn niemand würfelt")
mock.chat = {}
panel.rollDE._scripts.OnClick(panel.rollDE)
eq(mock.given[#mock.given].index, 15, "GiveMasterLoot an Zenec")
mock.loot[4] = false
mock.Fire("LOOT_SLOT_CLEARED", 4)
check(mock.ChatContains("Zenec erhält") and mock.ChatContains("zum Entzaubern"), "Entzaubern protokolliert", table.concat(mock.chat, "\n"))
eq(L.AllowedMax(PM:Raid(), "zenec"), 100, "Entzauberer behält Stufe 100")
eq(L.CountAwards(PM:Raid(), "zenec"), 0, "Entzaubern zählt nicht als eigener Gewinn")

-- Fehlgeschlagene Zuweisung
mock.CloseLoot()
mock.OpenLoot({ { id = 17075 } })
mock.AssignViaList(1, "Noraja", false)
mock.Fire("UI_ERROR_MESSAGE", 1, ERR_LOOT_MASTER_INV_FULL)
check(mock.ChatContains("Zuweisung fehlgeschlagen"), "Fehler gemeldet")
eq(#PM.pending, 0, "nichts mehr offen")
mock.CloseLoot()
check(not panel:IsShown(), "Panel schließt mit dem Plünderfenster")

-- Entzauberer nach Würfen: erst nach Rückfrage, die nennt die Würfe
mock.OpenLoot({ { id = 18813 }, { id = 18205 } }, "Creature-Rueckfrage")
rowFor(18205).btn._scripts.OnClick(rowFor(18205).btn, "LeftButton")
mock.Roll("Kronolus", 64)
mock.popup = nil
panel.rollDE._scripts.OnClick(panel.rollDE)
local oldPopup = mock.popup
check(oldPopup and oldPopup.name == "PRIOMEISTER_DE", "Halsband: Rückfrage nach einem Wurf")
-- inzwischen eine andere Runde: die alte Bestätigung vergibt nichts
rowFor(18813).btn._scripts.OnClick(rowFor(18813).btn, "LeftButton")
eq(L.ActiveSession(PM:Raid()).mode, "free", "freier Wurf um den Ring")
mock.popup, mock.chat, mock.given = oldPopup, {}, {}
mock.AcceptPopup()
eq(#mock.given, 0, "Bestätigung für eine alte Runde vergibt nichts")
check(mock.ChatContains("Inzwischen läuft eine andere Würfelrunde"), "Hinweis auf die neue Runde", table.concat(mock.chat, "\n"))
mock.Roll("Kronolus", 77)
mock.Roll("Veldore", 40)
mock.Roll("Hesti", 30, 1, 50)
mock.Roll("Drachenwut", 95, 1, 120)
eq(panel.rollWin:IsShown() and panel.rollWin:GetText(), "An Kronolus (77)", "Gewinner-Knopf nennt den höchsten gültigen Wurf")
mock.popup = nil
panel.rollDE._scripts.OnClick(panel.rollDE)
check(mock.popup and mock.popup.name == "PRIOMEISTER_DE", "Entzauberer nach Würfen: Rückfrage")
check(mock.popup and mock.popup.text:find("Gewürfelt: Kronolus 77, Veldore 40, Hesti 30 (1-50), Drachenwut 95 (ungültig)\n\nSicher an Entzauberer Zenec geben?", 1, true),
	"Rückfrage nennt Würfe und Entzauberer", mock.popup and mock.popup.text)
eq(#mock.given, 0, "ohne Bestätigung nichts vergeben")
mock.AcceptPopup()
eq(mock.given[1] and mock.candidates[mock.given[1].index], "Zenec", "nach Bestätigung an den Entzauberer")
mock.chat = {}
mock.loot[1] = false
mock.Fire("LOOT_SLOT_CLEARED", 1)
check(mock.ChatContains("Zenec erhält") and mock.ChatContains("zum Entzaubern"), "bestätigtes Entzaubern protokolliert", table.concat(mock.chat, "\n"))
mock.CloseLoot()

-- „An Entzauberer“ ohne Würfelrunde (1.22.0): an jedem Item ab der eingestellten Qualität, nur
-- bei Rüstung und Waffen und nicht, solange ein anwesender Spieler Prio hat
do
	eq(PM.db.settings.deButtonQuality, 2, "Knopf „An Entzauberer“ voreingestellt ab Grün")
	mock.OpenLoot({ { id = 99005 }, { id = 99006 }, { id = 99007 }, { id = 16929 }, { id = 18259 } }, "Creature-Entzaubern")
	local function deShown(id) local r = rowFor(id) return r and r.de:IsShown() or false end
	check(deShown(99005) and deShown(99006) and deShown(99007), "Knopf an blauer Rüstung, grüner Waffe und epischer Kette")
	check(not deShown(16929), "kein Knopf, solange ein anwesender Spieler Prio hat")
	check(not deShown(18259), "kein Knopf an Rezepten, die lassen sich nicht entzaubern")
	local cloak = rowFor(99005)
	local p = cloak.de._points[1]
	check(p and p[1] == "TOPRIGHT" and p[3] == -41, "Knopf steht unter „Zufällig vergeben“", p and tostring(p[3]))
	check(cloak:GetHeight() >= 62, "Zeile hoch genug für drei Knöpfe", cloak:GetHeight())

	-- blaues Item ohne Würfe: direkt an den Entzauberer
	mock.chat, mock.given, mock.popup = {}, {}, nil
	cloak.de._scripts.OnClick(cloak.de)
	check(mock.popup == nil, "blaues Item ohne Würfe: keine Rückfrage")
	eq(mock.given[1] and mock.candidates[mock.given[1].index], "Zenec", "Umhang direkt an den Entzauberer")
	mock.loot[1] = false
	mock.Fire("LOOT_SLOT_CLEARED", 1)
	check(mock.ChatContains("Zenec erhält") and mock.ChatContains("zum Entzaubern"), "als Entzaubern protokolliert", table.concat(mock.chat, "\n"))
	eq(L.CountAwards(PM:Raid(), "zenec"), 0, "Entzaubern zählt nicht als eigener Gewinn")

	-- episches Item: erst nach Rückfrage
	mock.given, mock.popup = {}, nil
	rowFor(99007).de._scripts.OnClick(rowFor(99007).de)
	check(mock.popup and mock.popup.name == "PRIOMEISTER_DE_ITEM", "episches Item: Rückfrage")
	check(mock.popup and mock.popup.text:find("Sicher an Entzauberer Zenec geben?", 1, true), "Rückfrage nennt den Entzauberer", mock.popup and mock.popup.text)
	eq(#mock.given, 0, "ohne Bestätigung nichts vergeben")
	mock.AcceptPopup()
	eq(mock.given[1] and mock.given[1].slot, 3, "nach Bestätigung die Kette vergeben")
	mock.loot[3] = false
	mock.Fire("LOOT_SLOT_CLEARED", 3)

	-- schon gewürfelt: Rückfrage nennt die Würfe
	rowFor(99006).btn._scripts.OnClick(rowFor(99006).btn, "LeftButton")
	mock.Roll("Veldore", 55)
	mock.given, mock.popup = {}, nil
	rowFor(99006).de._scripts.OnClick(rowFor(99006).de)
	check(mock.popup and mock.popup.name == "PRIOMEISTER_DE_ITEM" and mock.popup.text:find("Gewürfelt: Veldore 55", 1, true),
		"nach einem Wurf: Rückfrage nennt ihn", mock.popup and mock.popup.text)
	mock.AcceptPopup()
	eq(mock.given[1] and mock.candidates[mock.given[1].index], "Zenec", "nach Bestätigung das Schwert an den Entzauberer")
	mock.loot[2] = false
	mock.Fire("LOOT_SLOT_CLEARED", 2)
	mock.CloseLoot()

	-- Einstellung im Reiter Plündern: nie, ab Grün, ab Blau, nur Episch
	UI:GetMain()
	local dd = _G.PrioMeisterDisenchantDropdown
	eq(dd._selected, PM:QualityLabel(2), "Auswahl zeigt Grün in seiner Farbe wie die Plündergrenze")
	check(dd._entries[1].text == "nie" and dd._entries[4].text == PM:QualityLabel(4) and PM:QualityLabel(4):find("^|c"),
		"Einträge: nie, dann die Qualitäten farbig", dd._entries[4] and dd._entries[4].text)
	local mainPage = UI:GetMain().pages.loot
	eq(mainPage.deLabel:GetText(), "Knopf ab:", "Beschriftung vor der Auswahl")
	local lp = mainPage.deLabel._points[1]
	check(lp and lp[1] == "RIGHT" and lp[2] == dd and lp[3] == "LEFT", "Beschriftung steht links an der Auswahl")
	mock.OpenLoot({ { id = 99005 }, { id = 99006 } }, "Creature-Entzaubern-2")
	mock.PickDropdown(dd, 3)
	eq(PM.db.settings.deButtonQuality, 3, "ab Blau gespeichert")
	check(deShown(99005) and not deShown(99006), "ab Blau: Knopf am blauen Umhang, nicht am grünen Schwert")
	mock.PickDropdown(dd, 1)
	eq(PM.db.settings.deButtonQuality, false, "nie gespeichert")
	eq(dd._selected, "nie", "Auswahl zeigt nie")
	check(not deShown(99005), "nie: kein Knopf")
	mock.PickDropdown(dd, 2)
	PM:SetRole("disenchanter", "-")
	UI:RefreshAll()
	check(not deShown(99005), "ohne Entzauberer kein Knopf")
	PM:SetRole("disenchanter", "Zenec")
	UI:RefreshAll()
	check(deShown(99005), "mit Entzauberer wieder da")
	mock.CloseLoot()
end

-- Reste vergebener Items: WoW liefert für einen vergebenen Platz noch einen
-- leeren Link ohne Item-ID, daraus darf keine Zeile „Item 60“ werden
mock.OpenLoot({ { id = 18813 }, { id = 18205 } }, "Creature-Reste")
eq(#PM.lootItems, 2, "zwei Items in der Beute")
mock.loot[1] = false
mock.Fire("LOOT_SLOT_CLEARED", 1)
eq(#PM.lootItems, 1, "vergebener Platz verschwindet aus dem Panel")
eq(PM.lootItems[1] and PM.lootItems[1].itemID, 18205, "nur das Halsband bleibt")
mock.Fire("GET_ITEM_INFO_RECEIVED", 60)
mock.RunTimers()
eq(#PM.lootItems, 1, "auch nach nachgeladenen Itemdaten kein Rest")
local ghostRow = false
for _, r in ipairs(panel.rows) do
	if r._shown and r.name:GetText():find("Item 60", 1, true) then ghostRow = true end
end
check(not ghostRow, "keine Zeile „Item 60“ im Panel")
eq(PM:SlotOfItem(18813), nil, "der Ring liegt nicht mehr in der Beute")
eq(PM:SlotOfItem(18205), 2, "das Halsband liegt weiter auf Platz 2")
mock.CloseLoot()

-- Alte Runden: Ist das Item vergeben, verschwindet die Runde aus dem Panel,
-- auch beim Plündern der nächsten Leiche
mock.OpenLoot({ { id = 18813 }, { id = 18205 } }, "Creature-Amulett")
rowFor(18813).btn._scripts.OnClick(rowFor(18813).btn, "LeftButton")
mock.Roll("Veldore", 70)
check(panel.rollHeader:IsShown(), "laufende Runde steht im Panel")
check(panel.rollHeaderBox._hyperlinks and panel.rollHeaderBox:IsShown(), "Überschrift der Würfe mit klickbarem Item")
mock.AssignViaList(1, "Veldore")
check(not panel.rollHeader:IsShown() and not panel.rollPost:IsShown(), "vergeben: Runde verschwindet aus dem Panel")
check(not panel.rollHeaderBox:IsShown(), "mit der Überschrift")
mock.CloseLoot()
mock.OpenLoot({ { id = 17075 } }, "Creature-Naechster")
check(panel:IsShown() and not panel.rollHeader:IsShown(), "nächste Leiche: keine alten Würfe im Panel")
mock.CloseLoot()
-- beendet ohne Vergabe: sichtbar, solange das Item in derselben Beute liegt
mock.OpenLoot({ { id = 18205 } }, "Creature-Beenden")
rowFor(18205).btn._scripts.OnClick(rowFor(18205).btn, "LeftButton")
panel.rollEnd._scripts.OnClick(panel.rollEnd)
check(panel.rollHeader:IsShown() and panel.rollHeader:GetText():find("(beendet)", 1, true), "beendet, Item liegt noch da: Runde bleibt sichtbar",
	panel.rollHeader:GetText())
mock.CloseLoot()
mock.OpenLoot({ { id = 17075 } }, "Creature-Naechster2")
check(panel:IsShown() and not panel.rollHeader:IsShown(), "beendete Runde einer anderen Leiche ausgeblendet")
mock.CloseLoot()

-- An den Gewinner: Knopf mit Name und Wurf, bei epischen Items mit Rückfrage
mock.OpenLoot({ { id = 18205 }, { id = 18205 } }, "Creature-Gewinner")
rowFor(18205).btn._scripts.OnClick(rowFor(18205).btn, "LeftButton")
eq(L.ActiveSession(PM:Raid()).copies, 2, "zwei Halsbänder in der Beute")
check(not panel.rollWin:IsShown(), "ohne Würfe kein Gewinner-Knopf")
mock.Roll("Urmeline", 88)
mock.Roll("Sairá", 64)
mock.Roll("Ärwin", 64)
eq(panel.rollWin:IsShown() and panel.rollWin:GetText(), "An Urmeline (88)", "Gewinner-Knopf nennt Urmeline")
check(panel.rollTie:IsShown(), "Gleichstand um das zweite Exemplar: Stichwurf daneben")
mock.popup, mock.given = nil, {}
panel.rollWin._scripts.OnClick(panel.rollWin)
check(mock.popup and mock.popup.name == "PRIOMEISTER_WINNER" and mock.popup.text:find("An Urmeline (Wurf 88) geben?", 1, true),
	"episches Item: Rückfrage wie bei Blizzard", mock.popup and mock.popup.text)
eq(#mock.given, 0, "ohne Bestätigung nichts vergeben")
mock.AcceptPopup()
eq(mock.given[1] and mock.candidates[mock.given[1].index], "Urmeline", "nach Bestätigung an Urmeline")
mock.chat = {}
mock.loot[mock.given[1].slot] = false
mock.Fire("LOOT_SLOT_CLEARED", mock.given[1].slot)
check(mock.ChatContains("Urmeline erhält") and mock.ChatContains("freier Wurf 88 (1-100)"), "Vergabe an den Gewinner protokolliert", table.concat(mock.chat, "\n"))
eq(L.AllowedMax(PM:Raid(), "urmeline"), 99, "Urmeline würfelt ab jetzt mit 99")
check(not panel.rollWin:IsShown() and panel.rollTie:IsShown(), "zweites Exemplar: erst Stichwurf")
panel.rollTie._scripts.OnClick(panel.rollTie)
mock.Roll("Ärwin", 30)
check(not panel.rollWin:IsShown(), "Stichwurf läuft: noch kein Gewinner")
mock.Roll("Sairá", 70)
eq(panel.rollWin:IsShown() and panel.rollWin:GetText(), "An Sairá (64)", "nach dem Stichwurf: Sairá")
mock.popup = nil
panel.rollWin._scripts.OnClick(panel.rollWin)
local sairaPopup = mock.popup
panel.rollEnd._scripts.OnEnter(panel.rollEnd)
check(GameTooltip._lines and table.concat(GameTooltip._lines, " "):find("Neue Würfe zählen nicht mehr", 1, true), "Tooltip erklärt „Beenden“")
panel.rollEnd._scripts.OnClick(panel.rollEnd)
check(panel.rollWin:IsShown() and panel.rollDE:IsShown() and not panel.rollEnd:IsShown(), "nach „Beenden“: Gewinner und Entzauberer bleiben")
-- inzwischen eine neue Runde: die alte Bestätigung vergibt nichts
rowFor(18205).btn._scripts.OnClick(rowFor(18205).btn, "LeftButton")
mock.popup, mock.chat, mock.given = sairaPopup, {}, {}
mock.AcceptPopup()
eq(#mock.given, 0, "Bestätigung für eine alte Runde vergibt nichts")
check(mock.ChatContains("hat sich inzwischen geändert"), "Hinweis bei geänderter Runde", table.concat(mock.chat, "\n"))
mock.CloseLoot()
-- ohne Häkchen keine Rückfrage, auch nicht bei epischen Items
eq(PM.db.settings.confirmEpicWinner, true, "Rückfrage bei epischen Items: standardmäßig an")
PM.db.settings.confirmEpicWinner = false
mock.OpenLoot({ { id = 18813 } }, "Creature-OhneRueckfrage")
rowFor(18813).btn._scripts.OnClick(rowFor(18813).btn, "LeftButton")
mock.Roll("Noraja", 42)
mock.popup, mock.given = nil, {}
panel.rollWin._scripts.OnClick(panel.rollWin)
eq(mock.popup, nil, "ohne Häkchen keine Rückfrage")
eq(mock.given[1] and mock.candidates[mock.given[1].index], "Noraja", "Epic sofort an den Gewinner")
mock.loot[1] = false
mock.Fire("LOOT_SLOT_CLEARED", 1)
PM.db.settings.confirmEpicWinner = true
mock.CloseLoot()
-- schon selbst geplündert: Hinweis auf den Handel, der Handel zählt mit dem Wurf
mock.OpenLoot({ { id = 18813 } }, "Creature-Selbst")
rowFor(18813).btn._scripts.OnClick(rowFor(18813).btn, "LeftButton")
mock.Roll("Bartbär", 55)
mock.loot[1] = false
mock.Fire("LOOT_SLOT_CLEARED", 1)
mock.chat, mock.given = {}, {}
panel.rollWin._scripts.OnClick(panel.rollWin)
eq(#mock.given, 0, "selbst geplündert: kein GiveMasterLoot")
check(mock.ChatContains("selbst plündern und handeln"), "Hinweis auf den Handel", table.concat(mock.chat, "\n"))
mock.CloseLoot()
mock.sent = {}
mock.Trade("Bartbär", { { 18813, 1 } })
check(mock.SentContains("Bartbär erhält") and mock.SentContains("freier Wurf 55 (1-100)"), "Handel an den Gewinner mit Wurf eingetragen",
	(function() local t = {} for _, x in ipairs(mock.sent) do t[#t + 1] = x.msg end return table.concat(t, "\n") end)())

-- Plünderhelfer und Schatzmeister: Liste je Instanz, sonst Qualität
mock.instance = { "Ruinen von Ahn'Qiraj", "raid", 509 }
PM.db.settings.autoLootQualities = { [0] = true, [1] = true, [2] = true }
mock.threshold = 0
mock.given, mock.chat, mock.sent = {}, {}, {}
mock.OpenLoot({ { id = 20861 }, { id = 21761 }, { id = 4000 }, { id = 15000 }, { id = 4500 }, { id = 18205 }, { id = 16914 }, { id = 20861 } })
eq(#mock.given, 6, "sechs Items automatisch verteilt")
local givenTo = {}
for _, g in ipairs(mock.given) do givenTo[g.slot] = mock.candidates[g.index] end
eq(givenTo[1], "Nanuheal", "Skarabäus (AQ20-Liste) an den Schatzmeister")
eq(givenTo[2], "Nanuheal", "weißer Schlüssel an den Schatzmeister")
eq(givenTo[8], "Nanuheal", "zweiter Skarabäus an den Schatzmeister")
eq(givenTo[3], "Loladina", "Grau an den Plünderhelfer")
eq(givenTo[4], "Loladina", "Grün an den Plünderhelfer")
eq(givenTo[5], "Loladina", "Weiß ohne Liste an den Plünderhelfer")
eq(#PM.lootItems, 2, "Panel zeigt nur Halsband und Krone")
for _, slot in ipairs({ 1, 2, 3, 4, 5, 8 }) do
	mock.loot[slot] = false
	mock.Fire("LOOT_SLOT_CLEARED", slot)
end
mock.RunTimers()
local smLine = mock.ChatContains("Schatzmeister Nanuheal erhält: ")
check(smLine and smLine:find("[Bronzeskarabäus]|h|r x2", 1, true) and smLine:find("[Schlüssel für einen Skarabäuskasten]", 1, true),
	"Sammelmeldung Schatzmeister", table.concat(mock.chat, "\n"))
local phLine = mock.ChatContains("Plünderhelfer Loladina erhält: ")
check(phLine and phLine:find("[Grünes Teil]", 1, true) and not phLine:find("graue/weiße", 1, true),
	"Plünderhelfer: Grau und Weiß standardmäßig nicht gemeldet", table.concat(mock.chat, "\n"))
check(mock.SentContains("Plünderhelfer Loladina erhält"), "Sammelmeldung Plünderhelfer im Raid")
check(not mock.SentContains("Schatzmeister Nanuheal erhält"), "Schatzmeister standardmäßig nicht im Raidchat", sentText())
eq(L.CountAwards(PM:Raid(), "loladina"), 0, "Plünderhelfer zählt nicht als eigener Gewinn")
eq(L.CountAwards(PM:Raid(), "nanuheal"), 0, "Schatzmeister zählt nicht als eigener Gewinn")
eq(L.AllowedMax(PM:Raid(), "nanuheal"), 100, "Schatzmeister behält seine Stufe")
mock.CloseLoot()

-- Beute, die nicht über den Plündermeister läuft (1.22.1): Behälter aus der eigenen Tasche, Angeln,
-- Kräuter und Erzadern. Nichts ansagen, nichts verteilen, kein Panel.
do
	local function opened(slots, source)
		mock.given, mock.chat, mock.sent = {}, {}, {}
		mock.OpenLoot(slots, source)
		mock.RunTimers()
	end
	opened({ { id = 4500 }, { id = 20861 }, { id = 18813 } }, "Item-5096-0-4000000ABCDEF12")
	eq(#mock.given, 0, "Behälter aus der Tasche: nichts an Plünderhelfer oder Schatzmeister")
	eq(#mock.sent, 0, "Behälter aus der Tasche: keine Ansage im Raid")
	check(not mock.ChatContains("kann diese Beute nicht erhalten"), "Behälter aus der Tasche: keine Fehlermeldung", table.concat(mock.chat, "\n"))
	eq(#PM.lootItems, 0, "Behälter aus der Tasche: nichts im Panel")
	check(not panel:IsShown(), "Behälter aus der Tasche: Panel bleibt zu")
	mock.Fire("GET_ITEM_INFO_RECEIVED", 4500)
	mock.RunTimers()
	eq(#mock.given + #mock.sent, 0, "auch nach nachgeladenen Itemdaten nichts")
	mock.CloseLoot()
	-- Kraut oder Erzader: ein Objekt ohne Kandidaten für die Plündermeister-Liste
	local savedCandidates = mock.candidates
	mock.candidates = {}
	opened({ { id = 4500 } }, "GameObject-0-5096-309-0-180168-0000ABCDEF")
	eq(#mock.given + #mock.sent, 0, "Kraut: nichts verteilt, nichts angesagt")
	check(not mock.ChatContains("kann diese Beute nicht erhalten"), "Kraut: keine Fehlermeldung", table.concat(mock.chat, "\n"))
	mock.CloseLoot()
	mock.candidates = savedCandidates
	-- Boss-Truhe: auch ein Objekt, aber mit Kandidaten, also wie bisher
	opened({ { id = 4500 }, { id = 18813 } }, "GameObject-0-5096-409-0-179703-0000ABCDEF")
	eq(#mock.given, 1, "Boss-Truhe: Weiß an den Plünderhelfer wie bisher")
	check(mock.SentContains("Ring der Bindung"), "Boss-Truhe: Ansage wie bisher", sentText())
	mock.CloseLoot()
	-- Angeln
	mock.fishing = true
	opened({ { id = 4500 } }, "GameObject-0-5096-309-0-35591-0000ABCDEF")
	eq(#mock.given + #mock.sent, 0, "Angeln: nichts verteilt, nichts angesagt")
	mock.fishing = nil
	mock.CloseLoot()
end
-- nur Grau und Weiß: ohne Häkchen keine Meldung, mit Häkchen gezählt
mock.chat, mock.sent = {}, {}
mock.OpenLoot({ { id = 4000 }, { id = 4500 } })
for slot = 1, 2 do mock.loot[slot] = false; mock.Fire("LOOT_SLOT_CLEARED", slot) end
mock.RunTimers()
check(not mock.ChatContains("Plünderhelfer Loladina erhält") and #mock.sent == 0, "nur Grau und Weiß: keine Meldung", table.concat(mock.chat, "\n"))
mock.CloseLoot()
PM.db.settings.helperLowChat = true
mock.OpenLoot({ { id = 4000 }, { id = 4500 } })
for slot = 1, 2 do mock.loot[slot] = false; mock.Fire("LOOT_SLOT_CLEARED", slot) end
mock.RunTimers()
check(mock.SentContains("Plünderhelfer Loladina erhält: 2 graue/weiße Items"), "mit Häkchen: Grau und Weiß gemeldet", mock.sent[1] and mock.sent[1].msg)
PM.db.settings.helperLowChat = false
mock.CloseLoot()
-- mit Häkchen gehen auch die Vergaben an den Schatzmeister in den Raidchat
eq(PM.db.settings.treasurerChat, false, "Schatzmeister im Raidchat: standardmäßig aus")
PM.db.settings.treasurerChat = true
mock.chat, mock.sent = {}, {}
mock.OpenLoot({ { id = 21761 } })
mock.loot[1] = false
mock.Fire("LOOT_SLOT_CLEARED", 1)
mock.RunTimers()
check(mock.SentContains("Schatzmeister Nanuheal erhält: ") and mock.SentContains("[Schlüssel für einen Skarabäuskasten]"),
	"mit Häkchen: Schatzmeister im Raidchat", sentText())
PM.db.settings.treasurerChat = false
mock.CloseLoot()
-- außerhalb von AQ gilt die AQ-Liste nicht: der grüne Skarabäus geht an den Plünderhelfer
mock.instance = nil
mock.given = {}
mock.OpenLoot({ { id = 20861 } })
eq(mock.given[1] and mock.candidates[mock.given[1].index], "Loladina", "außerhalb von AQ an den Plünderhelfer")
mock.CloseLoot()
-- ohne Schatzmeister bleiben Items der Liste liegen, einmal ein Hinweis
mock.instance = { "Ruinen von Ahn'Qiraj", "raid", 509 }
PM:SetRole("treasurer", "-")
mock.given, mock.chat = {}, {}
mock.OpenLoot({ { id = 21761 }, { id = 4500 } })
eq(#mock.given, 1, "ohne Schatzmeister: Schlüssel bleibt liegen")
eq(mock.candidates[mock.given[1].index], "Loladina", "weißes Item trotzdem an den Plünderhelfer")
check(mock.ChatContains("Kein Schatzmeister bestimmt") and mock.ChatContains("Schlüssel für einen Skarabäuskasten"), "Hinweis: kein Schatzmeister", table.concat(mock.chat, "\n"))
mock.CloseLoot()
mock.chat = {}
mock.OpenLoot({ { id = 21761 } })
check(not mock.ChatContains("Kein Schatzmeister bestimmt"), "Hinweis nur einmal")
mock.CloseLoot()
PM:SetRole("treasurer", "Nanuheal")
-- Shift beim Öffnen: nichts automatisch
mock.shift = true
mock.given = {}
mock.OpenLoot({ { id = 20861 } })
eq(#mock.given, 0, "Shift verhindert automatisches Verteilen")
mock.shift = false
mock.CloseLoot()
-- Item mit Prio wird nie automatisch verteilt, Grau unter der Grenze nicht möglich
mock.threshold = 2
mock.given, mock.chat = {}, {}
PM.thresholdHintShown = false
mock.OpenLoot({ { id = 15000 }, { id = 4000 } })
eq(#mock.given, 1, "nur das grüne Item, Grau liegt unter der Grenze")
check(mock.ChatContains("unter der Plündergrenze"), "Hinweis auf Plündergrenze")
mock.CloseLoot()
mock.given = {}
PM:AddListItem("treasurer", 509, 16914)
mock.OpenLoot({ { id = 16914 } })
eq(#mock.given, 0, "Krone mit Prio-Haltern nie automatisch")
PM:RemoveListItem("treasurer", 509, 16914)
mock.CloseLoot()

-- Hauptfenster (Punkt 8)
SlashCmdList.PRIOMEISTER("")
local main = _G.PrioMeisterMainFrame
check(main:IsShown(), "Hauptfenster offen")
for _, tab in ipairs({ "raid", "awards", "loot", "options" }) do
	local okCall, err = pcall(UI.SelectTab, UI, tab)
	check(okCall, "Reiter " .. tab, err)
	check(main.pages[tab]:IsShown(), "Seite " .. tab .. " sichtbar")
end
UI:SelectTab("raid")
-- 1.19.1: Optionen oben rechts statt als Reiter, ein zweiter Klick führt zurück; seit 1.19.2 roter Knopf „?“
check(main.tabs.options == nil and main.tabs.raid and main.tabs.awards and main.tabs.loot, "Optionen ohne eigenen Reiter")
-- seit 1.25: „Beute“ statt „Vergaben“, „Plünderoptionen“ statt „Plündern“, breit genug für den längeren Namen
eq(main.tabs.awards:GetText(), "Beute", "Reiter Beute")
eq(main.tabs.loot:GetText(), "Plünderoptionen", "Reiter Plünderoptionen")
check(main.tabs.loot:GetWidth() >= 130, "Reiter Plünderoptionen breit genug")
check(main.changelog == nil, "kein Changelog-Knopf mehr oben")
eq(main.gear:GetText(), "?", "roter Knopf mit Fragezeichen")
check(main.gear._w == 24 and main.gear._h == 24 and main.gear._points[1][1] == "RIGHT" and main.gear._points[1][2] == main.close
	and main.gear._points[1][3] == "LEFT" and main.gear._points[1][5] == 0, "„?“ quadratisch und mittig neben dem Kreuz")
-- 1.19.3: Trennlinie zwischen Reitern und Inhalt, über die ganze Breite
do
	local d = main.divider
	check(d and d._points[1][1] == "TOPLEFT" and d._points[1][5] == -68 and d._points[2][1] == "TOPRIGHT"
		and d._points[2][5] == -68, "Trennlinie unter den Reitern")
	eq(main.pages.raid._points[1][3], -78, "Inhalt 10 unter der Trennlinie")
end
main.gear._scripts.OnClick(main.gear)
check(main.pages.options:IsShown() and main.gear._locked, "Knopf „?“ öffnet die Optionen")
main.gear._scripts.OnClick(main.gear)
check(main.pages.raid:IsShown() and not main.pages.options:IsShown() and not main.gear._locked, "zweiter Klick führt zurück")
eq(main.pages.raid.table:GetText(), "Anzeigen", "Prio-Tabelle heißt jetzt „Anzeigen“")
main.pages.raid.newRaid._scripts.OnEnter(main.pages.raid.newRaid)
check(table.concat(GameTooltip._lines or {}, " "):find("Prioliste beginnen leer", 1, true), "Tooltip erklärt „Neuer Raid“")
main.pages.raid.newRaid._scripts.OnLeave(main.pages.raid.newRaid)
-- Rollen-Knöpfe reichen bis zum rechten Rand
do
	local r = main.pages.raid
	local right = r.helper._points[1][4] + r.helper._w + 6 + r.treasurer._w + 6 + r.de._w
	eq(right, 588, "Rollen bündig mit dem rechten Rand")
end
check(main.pages.raid.noPrio:GetText():find("Ärwin", 1, true), "Raid-Seite: ohne Prio", main.pages.raid.noPrio:GetText())
main.pages.raid.table._scripts.OnClick(main.pages.raid.table)
check(prioTable:IsShown(), "Knopf öffnet die Prio-Tabelle")
prioTable:Hide()
check(main.pages.raid.recipes:GetText():find("Zenec", 1, true), "Raid-Seite: Rezept-Prio")
-- Rezepte und Reittiere auf Prio: Items klickbar wie im Chat
do
	local box = main.pages.raid.recipeBox
	check(box._hyperlinks and main.pages.raid.recipes:GetParent() == box, "Rezept-Prios mit klickbaren Links")
	box._scripts.OnHyperlinkEnter(box, "item:18259::::::::60:::::::", mock.Link(18259))
	eq(GameTooltip._lines and GameTooltip._lines[1], "item:18259::::::::60:::::::", "Rezept: Maus darüber zeigt das Item")
	box._scripts.OnHyperlinkClick(box, "item:18259::::::::60:::::::", mock.Link(18259), "LeftButton")
	eq(mock.itemRefs[#mock.itemRefs].link, "item:18259::::::::60:::::::", "Rezept: Klick öffnet das Item")
	GameTooltip._lines = nil
	box._scripts.OnHyperlinkEnter(box, "player:Zenec", "[Zenec]")
	eq(GameTooltip._lines, nil, "andere Links zeigen keinen Item-Tooltip")
end
local gustlRow
for _, r in ipairs(main.pages.raid.tierRows) do if r._shown and r.key == "gustl" then gustlRow = r end end
check(gustlRow, "Raid-Seite: Würfelstufe Gustl")
mock.sent = {}
gustlRow.minus._scripts.OnClick(gustlRow.minus)
eq(L.AllowedMax(PM:Raid(), "gustl"), 98, "Minus senkt Gustls Stufe")
check(mock.sent[1] and mock.sent[1].msg == "Gustl: Würfelstufe von Hand von 99 auf 98 geändert" and mock.sent[1].channel == "RAID",
	"Änderung der Würfelstufe im Raidchat", mock.sent[1] and mock.sent[1].msg)
gustlRow.plus._scripts.OnClick(gustlRow.plus)
eq(L.AllowedMax(PM:Raid(), "gustl"), 99, "Plus hebt sie wieder")
local tierEntries = {}
for _, aw in ipairs(PM:Raid().awards) do
	if aw.kind == "tier" then tierEntries[#tierEntries + 1] = L.AwardLine(aw) end
end
eq(tierEntries[1], "Gustl: Würfelstufe von Hand von 99 auf 98 geändert", "Minus steht in der Vergabeliste")
eq(tierEntries[2], "Gustl: Würfelstufe von Hand von 98 auf 99 geändert", "Plus steht in der Vergabeliste")
check(PM:Raid().awards[1].kind ~= "tier", "Korrekturen hängen hinten an")
local tierCount = #PM:Raid().awards
PM.db.settings.tierChangesToRaid = false
mock.sent = {}
SlashCmdList.PRIOMEISTER("stufen Gustl 0")
eq(#mock.sent, 0, "Häkchen aus: nichts im Raidchat")
PM.db.settings.tierChangesToRaid = true
SlashCmdList.PRIOMEISTER("stufen Gustl 1")
check(mock.SentContains("Gustl: Würfelstufe von Hand von 100 auf 99 geändert"), "/pm stufen im Raidchat")
eq(#PM:Raid().awards, tierCount + 2, "auch /pm stufen wird protokolliert")
SlashCmdList.PRIOMEISTER("stufen Gustl 1")
eq(#PM:Raid().awards, tierCount + 2, "ohne Änderung kein Eintrag")
local raidLabel = UI:RaidLabel(0)
check(raidLabel:find("^Aktueller Raid") and raidLabel:find("(" .. L.AwardCount(PM:Raid()) .. ")", 1, true), "Auswahl zählt nur echte Vergaben", raidLabel)
check(raidLabel:find(" · Ruinen von Ahn'Qiraj", 1, true), "Auswahl nennt die Instanz", raidLabel)

UI:SelectTab("awards")
check(main.pages.awards.lines[1]:GetText():find("Bolzenblitz erhält", 1, true), "Vergaben-Liste")
-- Items in der Vergabenliste: Tooltip und Klick wie im Chat
do
	local content = main.pages.awards.rows[1] -- jede Zeile hat ihre Links (seit 1.18 mit Rechtsklick)
	check(content._hyperlinks, "Vergabenliste mit klickbaren Links")
	content._scripts.OnHyperlinkEnter(content, "item:16914::::::::60:::::::", mock.Link(16914))
	eq(GameTooltip._lines and GameTooltip._lines[1], "item:16914::::::::60:::::::", "Maus über dem Item zeigt das Item")
	content._scripts.OnHyperlinkLeave(content)
	content._scripts.OnHyperlinkClick(content, "item:16914::::::::60:::::::", mock.Link(16914), "LeftButton")
	local ref = mock.itemRefs[#mock.itemRefs]
	check(ref and ref.link == "item:16914::::::::60:::::::" and ref.button == "LeftButton", "Klick öffnet das Item wie im Chat")
end
-- Changelog: Knopf in den Optionen (seit 1.19.1)
main.pages.options.changelog._scripts.OnClick(main.pages.options.changelog)
local changelogFrame = _G.PrioMeisterChangelog
check(changelogFrame and changelogFrame:IsShown(), "Knopf öffnet den Changelog")
eq(UI.CHANGELOG[1][1], PM.version, "Changelog beginnt mit der aktuellen Version")
check(changelogFrame.text:GetText():find("Version " .. PM.version, 1, true) and changelogFrame.text:GetText():find("Version 1.0", 1, true),
	"Changelog von der aktuellen Version bis 1.0")
check(changelogFrame.text:GetText():find("Vergaben teilen", 1, true), "Changelog nennt die Änderungen")
for _, frame in ipairs({ changelogFrame, _G.PrioMeisterPanel, _G.PrioMeisterPrioTable, _G.PrioMeisterImportFrame, _G.PrioMeisterPicker }) do
	check(frame._backdrop.bgFile == "Interface\\Buttons\\WHITE8X8" and frame._bgColor[4] == 1,
		"deckender Hintergrund: " .. tostring(frame._name))
end
check(main._backdrop.bgFile == "Interface\\Tooltips\\UI-Tooltip-Background" and main._bgColor[4] < 1, "Hauptfenster leicht durchscheinend")
changelogFrame:Hide()
SlashCmdList.PRIOMEISTER("changelog")
check(changelogFrame:IsShown(), "/pm changelog")
changelogFrame:Hide()

-- Plündern-Reiter (Punkt 10): Plündermeister und Grenze Grau
UI:SelectTab("loot")
local lootPage = main.pages.loot
mock.lootMethod, mock.threshold, mock.lootCalls = 3, 2, {}
eq(#lootPage.threshold._entries, 5, "Dropdown mit fünf Qualitäten")
mock.PickDropdown(lootPage.threshold, 1)
eq(mock.lootCalls[1] and mock.lootCalls[1][1], "method", "erst Plündermethode")
eq(mock.lootCalls[1] and mock.lootCalls[1][2], 2, "Methode 2 = Plündermeister")
eq(mock.lootCalls[1] and mock.lootCalls[1][3], "Arcanaa", "Plündermeister: ich")
mock.RunTimers()
eq(mock.lootCalls[2] and mock.lootCalls[2][2], 0, "dann Grenze Grau")
mock.chat = {}
mock.RunTimers()
check(mock.ChatContains("Plündergrenze: |cff9d9d9dGrau|r."), "Grenze bestätigt", table.concat(mock.chat, "\n"))
-- schon Plündermeister: nur die Grenze, mit Wiederholung
mock.lootCalls, mock.thresholdStuck = {}, true
mock.PickDropdown(lootPage.threshold, 2)
eq(#mock.lootCalls, 1, "nur Grenze setzen")
mock.RunTimers(); mock.RunTimers(); mock.RunTimers()
eq(#mock.lootCalls, 3, "zwei Wiederholungen")
check(mock.ChatContains("konnte nicht auf"), "Fehlschlag gemeldet")
mock.thresholdStuck = false
-- anderer Plündermeister über die Auswahl
lootPage.ml._scripts.OnClick(lootPage.ml)
pickName("Hesti")
eq(PM.db.settings.masterLooterName, "Hesti", "Plündermeister Hesti gewählt")
mock.lootCalls = {}
mock.PickDropdown(lootPage.threshold, 3)
eq(mock.lootCalls[1][3], "Hesti", "Plündermeister Hesti gesetzt")
mock.RunTimers(); mock.RunTimers()
PM.db.settings.masterLooterName = nil
-- Qualitäten für den Plünderhelfer einzeln, Liste des Schatzmeisters je Instanz
mock.threshold = 1
UI:RefreshAll()
eq(lootPage.threshold._selected, "|cffffffffWeiß|r", "Dropdown zeigt die aktuelle Grenze")
PM.db.settings.autoLootQualities = {}
UI:RefreshAll()
check(lootPage.qualityButtons[1]:GetText():find("Weiß: nein", 1, true), "Weiß: nein", lootPage.qualityButtons[1]:GetText())
lootPage.qualityButtons[1]._scripts.OnClick(lootPage.qualityButtons[1])
eq(PM.db.settings.autoLootQualities[1], true, "Weiß angeschaltet")
check(lootPage.qualityButtons[1]:GetText():find("Weiß|r: ja", 1, true) and lootPage.qualityButtons[1]._locked, "Weiß: ja", lootPage.qualityButtons[1]:GetText())
eq(PM.db.settings.autoLootQualities[0], nil, "Grau bleibt aus")
lootPage.qualityButtons[1]._scripts.OnClick(lootPage.qualityButtons[1])
eq(PM.db.settings.autoLootQualities[1], nil, "Weiß wieder aus")
lootPage.qualityButtons[1]._scripts.OnClick(lootPage.qualityButtons[1])
check(lootPage.treasurer:GetText():find("Schatzmeister: ", 1, true), "Plündern-Reiter zeigt den Schatzmeister")
eq(lootPage.selected, 509, "in AQ20 ist dessen Liste gewählt")
check(lootPage.listTitle:GetText():find("Ruinen von Ahn'Qiraj", 1, true), "Titel nennt die Instanz", lootPage.listTitle:GetText())
check(lootPage.state:GetText():find("Ruinen von Ahn'Qiraj", 1, true), "Kopfzeile nennt die aktuelle Instanz")
local instRow
for _, r in ipairs(lootPage.instRows) do
	if r._shown and r.instanceID == 509 then instRow = r end
end
check(instRow and instRow.text:GetText():find("|cff40ff40>|r Ruinen von Ahn'Qiraj |cff808080(36)|r", 1, true), "Spalte markiert die aktuelle Instanz mit Anzahl", instRow and instRow.text:GetText())
local naxxRow
for _, r in ipairs(lootPage.instRows) do
	if r._shown and r.instanceID == 533 then naxxRow = r end
end
naxxRow._scripts.OnClick(naxxRow)
eq(lootPage.selected, 533, "Naxxramas gewählt")
check(lootPage.itemEmpty:IsShown(), "leere Liste mit Hinweis")
_G.PrioMeisterLootListEdit:SetText(mock.Link(21761))
_G.PrioMeisterLootListEdit._scripts.OnEnterPressed(_G.PrioMeisterLootListEdit)
check(PM.db.settings.lootLists[533][21761], "Item per Link in die Naxx-Liste")
mock.cursorItem = 20863
_G.PrioMeisterLootListEdit._scripts.OnReceiveDrag(_G.PrioMeisterLootListEdit)
check(PM.db.settings.lootLists[533][20863], "Item per Ziehen hinzugefügt")
check(not PM.db.settings.lootLists[0][21761], "andere Listen unverändert")
_G.PrioMeisterLootListEdit:SetFocus()
ChatFrameUtil.InsertLink(mock.Link(18205))
check(_G.PrioMeisterLootListEdit:GetText():find("item:18205", 1, true), "Shift-Klick fügt Link ins Feld ein")
_G.PrioMeisterLootListEdit:SetText("")
_G.PrioMeisterLootListEdit:ClearFocus()
-- 1.19.1: Hinweis im leeren Feld, Zeile bündig unter der Liste
do
	local edit = _G.PrioMeisterLootListEdit
	edit._scripts.OnEditFocusLost(edit)
	check(edit.hint:IsShown() and edit.hint:GetText():find("Shift-Klick, hineinziehen oder Item-ID", 1, true), "leeres Feld sagt, was hineingehört")
	edit:SetText("19019")
	edit._scripts.OnTextChanged(edit)
	check(not edit.hint:IsShown(), "Hinweis weg, sobald etwas im Feld steht")
	edit:SetText("")
	edit._scripts.OnTextChanged(edit)
	check(edit.hint:IsShown(), "Hinweis wieder da")
	local loot = main.pages.loot
	local p = loot.clear._points[1]
	check(p[1] == "RIGHT" and p[2] == loot and p[3] == "TOPRIGHT" and p[4] == 0, "„Liste leeren“ bündig mit dem rechten Rand")
	check(edit._points[1][4] == 6 and edit._points[2][2] == loot.add, "Feld vom linken Rand bis „Hinzufügen“")
	check(edit.hint._points[2] and edit.hint._points[2][1] == "RIGHT", "Hinweis nicht breiter als das Feld")
	local q = loot.qualityButtons
	eq(q[0]._points[1][4] + 4 * 78 + 3 * 2, 588, "Qualitäten bündig mit dem rechten Rand")
	eq(loot.ml._points[1][4], loot.threshold._points[1][4], "Plündermeister und Grenze untereinander")
end
local listRow = lootPage.itemRows[2]
check(listRow and listRow._shown and listRow.text:GetText():find("Schlüssel für einen Skarabäuskasten", 1, true), "Liste zeigt Item", listRow and listRow.text:GetText())
check(listRow._hyperlinks, "Items in den Listen klickbar")
listRow._scripts.OnHyperlinkClick(listRow, "item:21761::::::::60:::::::", mock.Link(21761), "LeftButton")
eq(mock.itemRefs[#mock.itemRefs].link, "item:21761::::::::60:::::::", "Listen-Item: Klick öffnet das Item")
listRow.remove._scripts.OnClick(listRow.remove)
check(not PM.db.settings.lootLists[533][21761], "Item entfernt")
mock.popup = nil
lootPage.clear._scripts.OnClick(lootPage.clear)
check(mock.popup and mock.popup.text == "Liste des Schatzmeisters für „Naxxramas“ leeren?", "Leeren nur mit Rückfrage", mock.popup and mock.popup.text)
mock.AcceptPopup()
check(next(PM.db.settings.lootLists[533]) == nil, "Liste geleert")
check(PM.db.settings.lootLists[509][21761], "AQ20-Liste bleibt")
mock.instance = { "Tempel von Ahn'Qiraj", "raid", 531 }
UI:RefreshAll()
eq(lootPage.selected, 531, "neue Instanz: deren Liste wird gezeigt")
mock.instance = { "Stratholme", "party", 329 }
UI:RefreshAll()
local stratRow
for _, r in ipairs(lootPage.instRows) do
	if r._shown and r.instanceID == 329 then stratRow = r end
end
check(stratRow and stratRow.text:GetText():find("Stratholme", 1, true), "andere Instanz erscheint in der Spalte", stratRow and stratRow.text:GetText())
mock.instance = nil
UI:RefreshAll()

-- Optionen-Reiter (Punkt 9)
UI:SelectTab("options")
-- Häkchen über die Nummer oder den Namen der Einstellung
local function option(i)
	if type(i) == "string" then
		for n = 1, 40 do
			local cb = _G["PrioMeisterOption" .. n]
			if not cb or cb.optKey == i then return cb end
		end
		return nil
	end
	return _G["PrioMeisterOption" .. i]
end
local wanted = { "enabled", "announceLoot", "awardsToRaid", "treasurerChat", "helperLowChat", "tierHints", "reportWrongRolls", "tierChangesToRaid",
	"raidWarning", "always100", "secondaryRolls", "usableRolls", "recipeRolls", "recipePrio", "mountPrio", "prio0two", "confirmEpicWinner", "sortMasterLoot", "alwaysShow",
	"showTableAfterImport", "showMinimap" }
for i, key in ipairs(wanted) do
	eq(option(i).optKey, key, "Checkbox " .. i .. " ist " .. key)
end
eq(option(#wanted + 1), nil, "keine weiteren Häkchen")
-- Gruppen: alles, was im Chat erscheint, steht zusammen
do
	local optionsPage = main.pages.options
	local titles = {}
	for _, h in ipairs(optionsPage.titles) do titles[#titles + 1] = h:GetText() end
	eq(table.concat(titles, " | "), "Im Chat posten | Würfeln und Prio | Anzeige", "Gruppen der Optionen")
	for _, key in ipairs({ "announceLoot", "awardsToRaid", "treasurerChat", "helperLowChat", "tierHints", "reportWrongRolls", "tierChangesToRaid", "raidWarning" }) do
		eq(option(key).group, "Im Chat posten", key .. " steht unter „Im Chat posten“")
	end
	for _, key in ipairs({ "always100", "secondaryRolls", "usableRolls", "recipeRolls", "recipePrio", "mountPrio", "prio0two", "confirmEpicWinner" }) do
		eq(option(key).group, "Würfeln und Prio", key .. " steht unter „Würfeln und Prio“")
	end
	local tips = 0
	for i = 1, #wanted do
		local cb = option(i)
		GameTooltip._lines = nil
		cb._scripts.OnEnter(cb)
		if GameTooltip._lines and #GameTooltip._lines > 0 then tips = tips + 1 end
	end
	eq(tips, #wanted, "jedes Häkchen erklärt sich im Tooltip")
	local delayY = _G.PrioMeisterAnnounceDelay._points[1][3]
	local announceY, awardsY = option("announceLoot")._points[1][3], option("awardsToRaid")._points[1][3]
	check(delayY < announceY and delayY > awardsY, "Schieberegler steht unter der Beute-Ansage")
	check(option("secondaryRolls")._points[1][2] > option("announceLoot")._points[1][2], "zweite Spalte rechts daneben")
end
check(not option("helperLowChat"):GetChecked(), "Grau/Weiß an den Plünderhelfer: Häkchen aus")
check(not option("always100"):GetChecked(), "immer 100: in diesem Ablauf aus")
GameTooltip._lines = nil
option("always100")._scripts.OnEnter(option("always100"))
do
	local tip = table.concat(GameTooltip._lines or {}, "\n")
	check(tip:find("An:|r Alle würfeln mit /roll 100", 1, true) and tip:find("Aus:|r Wer frei gewonnen hat", 1, true)
		and tip:find("Beispiel:|r Anna", 1, true) and tip:find("Anna gewinnt, weil Stufe 100 vor Stufe 99 kommt", 1, true),
		"Tooltip erklärt beide Regeln mit Beispiel", tip)
end
option("always100"):SetChecked(true); option("always100")._scripts.OnClick(option("always100"))
eq(PM.db.settings.always100, true, "immer 100 per Häkchen an")
option("always100"):SetChecked(false); option("always100")._scripts.OnClick(option("always100"))
eq(PM.db.settings.always100, false, "immer 100 per Häkchen wieder aus")
check(not option("treasurerChat"):GetChecked(), "Schatzmeister im Raidchat: Häkchen aus")
check(option("confirmEpicWinner"):GetChecked(), "Rückfrage bei epischen Items: Häkchen an")
option("confirmEpicWinner"):SetChecked(false); option("confirmEpicWinner")._scripts.OnClick(option("confirmEpicWinner"))
eq(PM.db.settings.confirmEpicWinner, false, "Rückfrage bei epischen Items aus")
option("confirmEpicWinner"):SetChecked(true); option("confirmEpicWinner")._scripts.OnClick(option("confirmEpicWinner"))
eq(PM.db.settings.confirmEpicWinner, true, "Rückfrage bei epischen Items wieder an")
check(not option("mountPrio"):GetChecked(), "Reittiere auf Prio: Häkchen aus")
check(option("tierChangesToRaid"):GetChecked(), "Würfelstufe von Hand im Raidchat: Häkchen an")
option("helperLowChat"):SetChecked(true); option("helperLowChat")._scripts.OnClick(option("helperLowChat"))
eq(PM.db.settings.helperLowChat, true, "Grau/Weiß melden an")
option("helperLowChat"):SetChecked(false); option("helperLowChat")._scripts.OnClick(option("helperLowChat"))
option("treasurerChat"):SetChecked(true); option("treasurerChat")._scripts.OnClick(option("treasurerChat"))
eq(PM.db.settings.treasurerChat, true, "Schatzmeister im Raidchat an")
option("treasurerChat"):SetChecked(false); option("treasurerChat")._scripts.OnClick(option("treasurerChat"))
eq(PM.db.settings.treasurerChat, false, "Schatzmeister im Raidchat wieder aus")
option("tierHints"):SetChecked(false); option("tierHints")._scripts.OnClick(option("tierHints"))
eq(PM.db.settings.tierHints, false, "Stufenhinweise aus")
option("tierHints"):SetChecked(true); option("tierHints")._scripts.OnClick(option("tierHints"))
option("recipePrio"):SetChecked(true); option("recipePrio")._scripts.OnClick(option("recipePrio"))
eq(PM.db.settings.recipePrio, true, "Rezepte auf Prio an")
eq(#PM:RecipePrioEntries(), 0, "dann keine Rezept-Meldung")
option("recipePrio"):SetChecked(false); option("recipePrio")._scripts.OnClick(option("recipePrio"))
option("mountPrio"):SetChecked(true); option("mountPrio")._scripts.OnClick(option("mountPrio"))
eq(PM.db.settings.mountPrio, true, "Reittiere auf Prio an")
option("mountPrio"):SetChecked(false); option("mountPrio")._scripts.OnClick(option("mountPrio"))
option("prio0two"):SetChecked(true); option("prio0two")._scripts.OnClick(option("prio0two"))
eq(PM.db.settings.prio0Mode, 2, "Prio 0 bei Prio 1+2")
option("prio0two"):SetChecked(false); option("prio0two")._scripts.OnClick(option("prio0two"))
eq(PM.db.settings.prio0Mode, 3, "Prio 0 zurück")
option("showMinimap"):SetChecked(false); option("showMinimap")._scripts.OnClick(option("showMinimap"))
check(not _G.PrioMeisterMinimapButton:IsShown(), "Minimap-Knopf aus")
option("showMinimap"):SetChecked(true); option("showMinimap")._scripts.OnClick(option("showMinimap"))
check(option("showTableAfterImport"):GetChecked(), "Prio-Tabelle nach dem Import: Häkchen an")
option("showTableAfterImport"):SetChecked(false); option("showTableAfterImport")._scripts.OnClick(option("showTableAfterImport"))
-- alle Optionen samt Schieberegler und angehefteten Spielern passen ins Hauptfenster
do
	local pins = _G.PrioMeisterPinsEdit
	local anchor = pins._points[1] -- seit 1.19.1: LEFT an TOPLEFT der Seite, y ist die Mitte des Felds
	check(anchor[1] == "LEFT" and anchor[3] == "TOPLEFT", "Feld der angehefteten Spieler mittig in seiner Zeile")
	local bottom = -anchor[5] + pins._h / 2
	local pageHeight = _G.PrioMeisterMainFrame._h - 78 - 14
	check(bottom <= pageHeight, "Optionen passen ins Hauptfenster", bottom .. " > " .. pageHeight)
end
local playersBefore = 0
for _ in pairs(PM:Raid().players) do playersBefore = playersBefore + 1 end
PM:ImportText(PM:PrioListCSV(), false)
check(not prioTable:IsShown(), "Häkchen aus: keine Tabelle nach dem Import")
local playersAfter = 0
for _ in pairs(PM:Raid().players) do playersAfter = playersAfter + 1 end
eq(playersAfter, playersBefore, "CSV aus dem Importfenster lässt sich wieder importieren")
option("showTableAfterImport"):SetChecked(true); option("showTableAfterImport")._scripts.OnClick(option("showTableAfterImport"))
-- Pins über die Mehrfachauswahl
main.pages.options.pins:SetText("")
PM.db.pins = {}
UI:ShowPicker(main.pages.options.pins, "Spieler anheften", {
	multi = true,
	isSelected = function(name) return PM:IsPinned(name) end,
	onToggle = function(name) PM:TogglePin(name) end,
})
pickName("Kronolus")
pickName("Veldore")
pickName("Kronolus")
eq(PM:PinsText(), "Veldore", "Mehrfachauswahl schaltet um")
check(picker:IsShown(), "Mehrfachauswahl bleibt offen")
picker.done._scripts.OnClick(picker.done)
-- Addon ausschalten (Punkt 9)
option(1):SetChecked(false); option(1)._scripts.OnClick(option(1))
eq(PM:IsEnabled(), false, "Addon aus")
mock.OpenLoot({ { id = 18813 } })
check(not panel:IsShown(), "ausgeschaltet: kein Panel")
local awardsBefore = #PM:Raid().awards
mock.AssignViaList(1, "Gustl")
eq(#PM:Raid().awards, awardsBefore, "ausgeschaltet: nichts protokolliert")
mock.CloseLoot()
option(1):SetChecked(true); option(1)._scripts.OnClick(option(1))

-- Vergaben-Reiter: Korrekturen sichtbar, Rückgängig mit Rückfrage
UI:SelectTab("awards")
local raidNow = PM:Raid()
eq(raidNow.awards[#raidNow.awards].kind, "tier", "letzter Eintrag: Würfelstufe von Hand")
check(main.pages.awards.lines[#raidNow.awards]:GetText():find("Gustl: Würfelstufe von Hand von 100 auf 99 geändert", 1, true),
	"Vergaben-Reiter zeigt die Korrektur", main.pages.awards.lines[#raidNow.awards]:GetText())
mock.sent = {}
SlashCmdList.PRIOMEISTER("undo")
eq(L.AllowedMax(PM:Raid(), "gustl"), 100, "Zurücknehmen der Korrektur stellt die Stufe davor her")
check(mock.SentContains("Gustl: Änderung der Würfelstufe zurückgenommen, wieder 100"), "Zurücknehmen im Raidchat", mock.sent[1] and mock.sent[1].msg)
SlashCmdList.PRIOMEISTER("undo")
eq(L.AllowedMax(PM:Raid(), "gustl"), 99, "zweite Korrektur zurückgenommen")
SlashCmdList.PRIOMEISTER("undo")
eq(L.AllowedMax(PM:Raid(), "gustl"), 98, "dritte Korrektur zurückgenommen")
SlashCmdList.PRIOMEISTER("undo")
eq(L.AllowedMax(PM:Raid(), "gustl"), 99, "Gustl wieder bei seinem echten Stand")
eq(PM:Raid().adjust.gustl, nil, "keine Korrektur mehr gespeichert")
local undoBefore = #PM:Raid().awards
SlashCmdList.PRIOMEISTER("undo")
eq(#PM:Raid().awards, undoBefore - 1, "undo entfernt eine Vergabe")
StaticPopup_Show("PRIOMEISTER_UNDO", "x")
mock.AcceptPopup()
eq(#PM:Raid().awards, undoBefore - 2, "Rückfrage bestätigt entfernt eine weitere")

-- Vergaben teilen: Kanal wählen, auch später und privat
local function finishSharing()
	for _ = 1, 200 do
		if not PM.sharing then return end
		mock.RunTimers()
	end
end
local awardsPage = main.pages.awards
eq(#awardsPage.channel._entries, 5, "fünf Kanäle zum Teilen")
eq(awardsPage.channel._selected, "Gilde", "Standard: Gilde")
check(not awardsPage.target:IsShown(), "Namensfeld nur beim Flüstern")
mock.sent, mock.chat = {}, {}
awardsPage.share._scripts.OnClick(awardsPage.share)
eq(#mock.sent, 1, "erste Zeile sofort, der Rest nacheinander")
check(mock.sent[1].msg:find("^Vergaben im Raid vom ") and mock.sent[1].channel == "GUILD", "Kopfzeile in der Gilde", mock.sent[1] and mock.sent[1].msg)
eq(awardsPage.share:GetText(), "Teilt …", "Knopf zeigt das laufende Teilen")
check(not awardsPage.share:IsEnabled(), "Knopf gesperrt, solange geteilt wird")
awardsPage.share._scripts.OnClick(awardsPage.share)
SlashCmdList.PRIOMEISTER("teilen gilde")
check(mock.ChatContains("gerade schon geteilt"), "kein zweites Teilen gleichzeitig")
finishSharing()
local guildLines = {}
for _, m in ipairs(mock.sent) do
	eq(m.channel, "GUILD", "alles in der Gilde")
	guildLines[#guildLines + 1] = m.msg
end
check(table.concat(guildLines, "\n"):find("Bolzenblitz erhält", 1, true), "Vergabe geteilt", table.concat(guildLines, "\n"))
check(mock.ChatContains("Vergaben geteilt."), "Abschluss gemeldet")
eq(awardsPage.share:GetText(), "Teilen", "Knopf wieder frei")
-- privat: Flüstern an einen Namen
mock.PickDropdown(awardsPage.channel, 5)
eq(PM.db.settings.shareChannel, "WHISPER", "Flüstern gewählt")
check(awardsPage.target:IsShown(), "Namensfeld sichtbar")
awardsPage.target:SetText("")
mock.chat = {}
awardsPage.share._scripts.OnClick(awardsPage.share)
check(mock.ChatContains("Bitte einen Namen"), "Flüstern ohne Namen geht nicht")
awardsPage.target:SetText("Gustl")
mock.sent = {}
awardsPage.share._scripts.OnClick(awardsPage.share)
finishSharing()
check(#mock.sent > 1 and mock.sent[1].channel == "WHISPER" and mock.sent[1].target == "Gustl", "an Gustl geflüstert", mock.sent[1] and mock.sent[1].channel)
eq(PM.db.settings.shareTarget, "Gustl", "Name bleibt gespeichert")
-- ohne Gilde
mock.PickDropdown(awardsPage.channel, 1)
mock.inGuild = false
mock.sent, mock.chat = {}, {}
awardsPage.share._scripts.OnClick(awardsPage.share)
check(mock.ChatContains("Du bist in keiner Gilde.") and #mock.sent == 0, "ohne Gilde nichts gesendet")
mock.inGuild = true
-- per Befehl in den Schlachtzug
mock.sent = {}
SlashCmdList.PRIOMEISTER("teilen raid")
finishSharing()
check(#mock.sent > 1 and mock.sent[1].channel == "RAID", "/pm teilen raid")
eq(PM.db.settings.shareChannel, "GUILD", "Befehl ändert die Auswahl nicht")

-- Slash-Befehle laufen fehlerfrei
local link = mock.Link(16914)
for _, cmd in ipairs({
	"", "hilfe", "liste", "export", "export alle", "prio Arcanaa", "prio " .. link, "prio", "stufen", "stufen Gustl 2",
	"pin", "pins", "pin Hesti", "pins leeren", "panel", "panel", "optionen", "plündern", "würfeln " .. link, "frei " .. link,
	"stopp", "helfer Bartbär", "entzauberer -", "schatzmeister Hesti", "erinnern", "unsinn",
}) do
	local okCall, err = pcall(SlashCmdList.PRIOMEISTER, cmd)
	check(okCall, "Slash /pm " .. cmd, err)
end
eq(PM.db.settings.lootHelper, "Bartbär", "Slash setzt Plünderhelfer")
eq(PM.db.settings.disenchanter, nil, "Slash leert Entzauberer")
eq(PM.db.settings.treasurer, "Hesti", "Slash setzt Schatzmeister")
check(_G.PrioMeisterTextFrameEdit:GetText():find("Bolzenblitz;16914;Krone des Netherwinds;Prio;1;91;1-100", 1, true), "Export-Zeile")

-- Neuer Raid mit Rückfrage
SlashCmdList.PRIOMEISTER("")
UI:SelectTab("raid")
StaticPopup_Show("PRIOMEISTER_NEWRAID")
mock.AcceptPopup()
eq(#PM.db.raid.awards, 0, "neuer Raid ohne Vergaben")
check(#PM.db.history >= 1, "alter Raid archiviert")
-- früheren Raid ansehen und später noch teilen
UI:SelectTab("awards")
local histPage = main.pages.awards
check(#histPage.raidSelect._entries >= 2, "Auswahl: aktueller und früherer Raid")
eq(histPage.raidSelect._selected, "Aktueller Raid (0)", "zuerst der aktuelle Raid")
check(histPage.raidSelect._entries[2].text:find("^Raid vom .- · Ruinen von Ahn'Qiraj"), "früherer Raid nennt seine Instanz",
	histPage.raidSelect._entries[2].text)
check(not histPage.share:IsEnabled(), "leerer Raid: nichts zu teilen")
mock.PickDropdown(histPage.raidSelect, 2)
eq(histPage.view, 1, "früherer Raid gewählt")
check(histPage.header:GetText():find("^Raid vom "), "Kopf nennt den früheren Raid", histPage.header:GetText())
check(histPage.lines[1]:GetText():find("Bolzenblitz erhält", 1, true), "Vergaben des früheren Raids sichtbar")
check(not histPage.undo:IsEnabled(), "Zurücknehmen nur im aktuellen Raid")
mock.sent = {}
histPage.share._scripts.OnClick(histPage.share)
finishSharing()
check(#mock.sent > 1 and mock.sent[1].channel == "GUILD" and table.concat((function() local t = {} for _, m in ipairs(mock.sent) do t[#t + 1] = m.msg end return t end)(), "\n"):find("Bolzenblitz erhält", 1, true),
	"früheren Raid in der Gilde geteilt")
mock.PickDropdown(histPage.raidSelect, 1)
eq(histPage.view, 0, "zurück zum aktuellen Raid")

-- Testmodus verändert die echten Daten nicht
PM:ImportText(CSV, false)
local realAwards = #PM.db.raid.awards
SlashCmdList.PRIOMEISTER("test")
check(PM.testMode and panel:IsShown(), "Testmodus mit Panel")
mock.sent = {}
panel.rows[1].btn._scripts.OnClick(panel.rows[1].btn, "LeftButton")
eq(#mock.sent, 0, "Testmodus sendet nichts in den Raid")
SlashCmdList.PRIOMEISTER("testwurf Gustl 77 98")
SlashCmdList.PRIOMEISTER("testwurf Hesti 30 50")
SlashCmdList.PRIOMEISTER("vergabe Gustl")
eq(#PM:Raid().awards, realAwards + 1, "Testvergabe in Testdaten")
mock.nextRandom = 1
mock.popup = nil
panel.rows[1].random._scripts.OnClick(panel.rows[1].random)
check(mock.popup and mock.popup.name == "PRIOMEISTER_RANDOM", "Testmodus: Rückfrage bei Prio-Item")
mock.AcceptPopup()
eq(PM:Raid().awards[#PM:Raid().awards].kind, "random", "Testmodus: zufällig vergeben")
mock.nextRandom = nil
SlashCmdList.PRIOMEISTER("test")
eq(#PM.db.raid.awards, realAwards, "echte Vergaben unverändert")

mock.Fire("GET_ITEM_INFO_RECEIVED", 16914, true)
mock.Fire("PARTY_LOOT_METHOD_CHANGED")
mock.RunTimers()

-- /reload mitten in einer Würfelrunde, danach dieselbe Leiche erneut öffnen
mock.OpenLoot({ { id = 18205 } }, "Creature-Reload")
panel.rows[1].btn._scripts.OnClick(panel.rows[1].btn, "LeftButton")
mock.Roll("Zenec", 61)
local saved = mock.Serialize(PrioMeisterDB)
mock.CloseLoot()
mock.ResetUI()
PrioMeisterDB = assert(loadstring("return " .. saved))()
loadAddon()
mock.Fire("ADDON_LOADED", "PrioMeister")
mock.Fire("PLAYER_LOGIN")
local active = L.ActiveSession(PM:Raid())
check(active and #active.rolls == 1, "aktive Würfelrunde nach /reload gefunden")
mock.Roll("Nanuheal", 90)
mock.OpenLoot({ { id = 18205 } }, "Creature-Reload")
panel = _G.PrioMeisterPanel
mock.chat = {}
mock.AssignViaList(1, "Nanuheal")
check(mock.ChatContains("Nanuheal erhält") and mock.ChatContains("freier Wurf 90 (1-100)"), "Wurf nach /reload gezählt", mock.LastChat())
eq(PM.db.settings.lootHelper, "Bartbär", "Rollen bleiben nach /reload")

-- Würfe gehören zu ihrem Exemplar (Fehler aus den Screenshots)
mock.CloseLoot()
PM:ImportText("Name;Klasse;prio1itemid;prio2itemid;prio3itemid;\nArcanaa;Magier;2589;0;0;\nHexstiffi;Hexenmeister;2589;0;0;\nGustl;Krieger;0;0;0;\n", true)
table.insert(mock.raid, { "Hexstiffi", "WARLOCK" })
mock.candidates = {}
for i, r in ipairs(mock.raid) do mock.candidates[i] = r[1] end
mock.Fire("GROUP_ROSTER_UPDATE")
PM.db.settings.autoLootQualities, PM.db.settings.lootLists[0] = {}, {}
mock.threshold = 0
local function row1() return panel.rows[1] end
-- 1. Leinenstoff: Hexstiffi und Arcanaa stechen, Hexstiffi gewinnt
mock.OpenLoot({ { id = 2589 } }, "Creature-A")
row1().btn._scripts.OnClick(row1().btn, "LeftButton")
mock.Roll("Hexstiffi", 87)
mock.Roll("Arcanaa", 62)
mock.AssignViaList(1, "Hexstiffi")
mock.CloseLoot()
-- 2. neuer Leinenstoff, Arcanaa ist einzige Prio 1: nur ansagen, kein Wurf
mock.OpenLoot({ { id = 2589 } }, "Creature-B")
eq(row1().btn:GetText(), "Ansagen", "zweiter Leinenstoff: nur ansagen")
mock.chat = {}
mock.AssignViaList(1, "Arcanaa")
check(mock.ChatContains("Arcanaa erhält") and mock.ChatContains("– Prio 1") and not mock.ChatContains("Wurf 62"),
	"Screenshot 1: kein alter Wurf bei Prio ohne Würfeln", table.concat(mock.chat, "\n"))
mock.CloseLoot()
-- 3. freier Wurf: Gustl verliert, bekommt später ein neues Exemplar ohne Wurf
mock.OpenLoot({ { id = 4000 } }, "Creature-C")
row1().btn._scripts.OnClick(row1().btn, "LeftButton")
mock.Roll("Gustl", 50)
mock.Roll("Zenec", 90)
mock.AssignViaList(1, "Zenec")
mock.CloseLoot()
mock.OpenLoot({ { id = 4000 } }, "Creature-D")
mock.chat = {}
mock.AssignViaList(1, "Gustl")
check(mock.ChatContains("Gustl erhält") and mock.ChatContains("ohne Wurf"), "neues Exemplar ohne Wurf", table.concat(mock.chat, "\n"))
eq(L.AllowedMax(PM:Raid(), "gustl"), 100, "Gustls Stufe bleibt 100")
mock.CloseLoot()
-- 4. Screenshot 3: alte Runde ohne Vergabe übers Addon, neues Exemplar wird neu gewürfelt
mock.OpenLoot({ { id = 15000 } }, "Creature-E")
row1().btn._scripts.OnClick(row1().btn, "LeftButton")
local oldRound = L.ActiveSession(PM:Raid())
mock.Roll("Arcanaa", 90)
mock.Roll("Hesti", 69)
mock.CloseLoot() -- von Hand anders entschieden, nichts über das Addon vergeben
mock.OpenLoot({ { id = 15000 } }, "Creature-F")
row1().btn._scripts.OnClick(row1().btn, "LeftButton")
local newRound = L.ActiveSession(PM:Raid())
check(newRound ~= oldRound, "neues Exemplar: neue Würfelrunde")
eq(#newRound.rolls, 0, "neue Runde startet ohne alte Würfe")
mock.Roll("Arcanaa", 12)
mock.Roll("Gustl", 40)
mock.chat = {}
mock.AssignViaList(1, "Hesti")
check(mock.ChatContains("Hesti erhält") and mock.ChatContains("ohne Wurf") and not mock.ChatContains("69"),
	"Screenshot 3: Hesti hat in der neuen Runde nicht gewürfelt", table.concat(mock.chat, "\n"))
eq(L.AllowedMax(PM:Raid(), "hesti"), 100, "Hestis Stufe bleibt 100")
mock.CloseLoot()
-- 5. dieselbe Leiche erneut öffnen: Würfe bleiben gültig
mock.OpenLoot({ { id = 17075 } }, "Creature-G")
row1().btn._scripts.OnClick(row1().btn, "LeftButton")
mock.Roll("Gustl", 77)
mock.CloseLoot()
mock.OpenLoot({ { id = 17075 } }, "Creature-G")
row1().btn._scripts.OnClick(row1().btn, "LeftButton")
eq(#L.ActiveSession(PM:Raid()).rolls, 1, "erneut geöffnet: Runde läuft weiter")
mock.chat = {}
mock.AssignViaList(1, "Gustl")
check(mock.ChatContains("freier Wurf 77 (1-100)"), "erneut geöffnet: Wurf zählt", table.concat(mock.chat, "\n"))
mock.CloseLoot()
-- 6. zwei gleiche Items in einer Beute: die Runde gilt für beide
mock.OpenLoot({ { id = 18813 }, { id = 18813 } }, "Creature-H")
row1().btn._scripts.OnClick(row1().btn, "LeftButton")
mock.Roll("Zenec", 80)
mock.Roll("Hesti", 60)
mock.AssignViaList(1, "Zenec")
check(not L.ActiveSession(PM:Raid()).done, "zweites Exemplar offen")
mock.chat = {}
mock.AssignViaList(2, "Hesti")
check(mock.ChatContains("Hesti erhält") and mock.ChatContains("freier Wurf 60 (1-100)"), "zweites Exemplar mit Wurf", table.concat(mock.chat, "\n"))
check(L.ActiveSession(PM:Raid()).done, "Runde danach erledigt")
mock.CloseLoot()
-- 7. Runden aus älteren Versionen werden beim Laden abgeschlossen
do
	local legacy = { dbVersion = 2, settings = {}, pins = {}, history = {}, raid = L.NewRaid(0) }
	legacy.raid.sessions = { { id = 1, item = 2589, itemID = 2589, mode = "free", rolls = {
		{ key = "gustl", name = "Gustl", value = 50, low = 1, high = 100, status = "ok", seq = 1 } }, winners = {} } }
	legacy.raid.activeId = 1
	local saved = PrioMeisterDB
	PrioMeisterDB = legacy
	PM:InitDB()
	check(legacy.raid.sessions[1].done, "alte Runde abgeschlossen")
	eq(L.BuildAward(legacy.raid, "gustl", "Gustl", 2589, "[Leinenstoff]", 3, 1).kind, "none", "alter Wurf zählt nicht mehr")
	PrioMeisterDB = saved
	PM:InitDB()
end
-- 8. Version 1.4: Qualität „bis Grün“ und Blutrebe auf der Liste zum Verwürfeln
do
	local old = { dbVersion = 4, pins = {}, history = {}, raid = L.NewRaid(0), settings = {
		autoLootBelow = 3,
		lootLists = { [0] = {}, [509] = { [21761] = true } },
		rollLists = { [0] = {}, [309] = { [19726] = true, [19939] = true } },
	} }
	local saved = PrioMeisterDB
	PrioMeisterDB = old
	PM:InitDB()
	local s = old.settings
	check(s.autoLootQualities[0] and s.autoLootQualities[1] and s.autoLootQualities[2] and not s.autoLootQualities[3],
		"„bis Grün“ wird zu Grau, Weiß und Grün")
	eq(s.autoLootBelow, nil, "alte Qualitätsgrenze aufgelöst")
	check(not s.rollLists[309][19726] and s.rollLists[309][19939], "Blutrebe nicht mehr verwürfeln, Gri'leks Blut schon")
	check(s.lootLists[309][19726], "Blutrebe an den Schatzmeister")
	check(s.lootLists[509][21214] and s.lootLists[509][21307], "Klassenbücher in der AQ20-Liste")
	check(s.lootLists[509][21761], "eigene Einträge bleiben")
	check(s.lootLists[309][19707] and s.lootLists[309][19715], "Schmuckstücke der Hakkari in die ZG-Liste übernommen")
	PrioMeisterDB = saved
	PM:InitDB()
end
-- 1.26: Listen aus 1.25 bekommen die Materialien aus MC und BWL (DB-Version 8)
do
	local old = { dbVersion = 8, pins = {}, history = {}, raid = L.NewRaid(0), settings = {
		lootLists = { [0] = { [2589] = true }, [409] = { [17012] = true } },
	} }
	local saved = PrioMeisterDB
	PrioMeisterDB = old
	PM:InitDB()
	local loot = old.settings.lootLists
	eq(old.dbVersion, 9, "Datenbank auf Version 9")
	check(loot[409][17010] and loot[409][17011] and loot[409][7078] and loot[409][17203], "MC-Materialien in die MC-Liste übernommen")
	check(loot[469] and loot[469][18562] and loot[469][19183] and loot[469][17203], "BWL-Liste mit ihren Materialien angelegt")
	check(loot[409][17012] and loot[0][2589], "eigene Einträge bleiben")
	PrioMeisterDB = saved
	PM:InitDB()
end

-- Stichwurf über das Panel
mock.OpenLoot({ { id = 4000 } }, "Creature-Tie")
row1().btn._scripts.OnClick(row1().btn, "LeftButton")
mock.Roll("Arcanaa", 29)
mock.Roll("Kronolus", 29)
check(panel.rollTie:IsShown() and not panel.rollDE:IsShown(), "Knopf Stichwurf statt Entzauberer")
mock.sent = {}
panel.rollPost._scripts.OnClick(panel.rollPost)
check(mock.SentContains("1. Arcanaa 29 (1-100), 1. Kronolus 29 (1-100) – Gleichstand"), "gepostetes Ergebnis zeigt Gleichstand", mock.sent[1] and mock.sent[1].msg)
mock.sent = {}
panel.rollTie._scripts.OnClick(panel.rollTie)
check(mock.SentContains("Gleichstand bei 29: Arcanaa, Kronolus – Stichwurf, bitte /roll 100"), "Stichwurf im Raid angesagt", mock.sent[1] and mock.sent[1].msg)
mock.sent = {}
row1().btn._scripts.OnClick(row1().btn, "LeftButton")
check(mock.SentContains("Stichwurf, bitte /roll 100") and not mock.SentContains("freier Wurf"), "zweiter Klick auf Würfeln sagt den Stichwurf an")
mock.Roll("Gustl", 95)
mock.Roll("Kronolus", 61)
check(UI:RollLines(L.ActiveSession(PM:Raid()))[2]:find("wartet auf Stichwurf", 1, true), "Panel: Arcanaa wartet")
mock.Roll("Arcanaa", 44)
local lines = UI:RollLines(L.ActiveSession(PM:Raid()))
check(lines[1]:find("Stichwurf 61", 1, true), "Panel zeigt Stichwurf", lines[1])
check(not panel.rollTie:IsShown(), "Knopf verschwindet nach Auflösung")
mock.chat, mock.sent = {}, {}
mock.AssignViaList(1, "Kronolus")
check(mock.ChatContains("Kronolus erhält") and mock.ChatContains("freier Wurf 29 (1-100), Stichwurf 61"), "Vergabe mit Stichwurf", table.concat(mock.chat, "\n"))
check(mock.SentContains("freier Wurf 29 (1-100), Stichwurf 61"), "Vergabe mit Stichwurf im Raidchat")
mock.CloseLoot()
-- /stich ohne Gleichstand
mock.chat = {}
SlashCmdList.PRIOMEISTER("stich")
check(mock.ChatContains("Keine Würfelrunde aktiv") or mock.ChatContains("Kein Gleichstand"), "Stichwurf ohne Gleichstand meldet sich")

-- Beute-Ansage beim Öffnen, samt Prios (wie Prio3)
mock.CloseLoot()
PM:ImportText(CSV .. "Zenec;Jäger;18259;0;0;;;;\nGustl;Krieger;18813;18813;18813;;;;\nLoladina;Paladin;17966;16914;0;;;;\n", true)
mock.threshold = 2
PM.db.settings.lootLists[0], PM.db.settings.autoLootQualities = { [15000] = true }, {}
PM.db.settings.announceDelay = 90
mock.sent = {}
mock.OpenLoot({ { id = 16914 }, { id = 18423 }, { id = 18813 }, { id = 18259 }, { id = 2589 }, { id = 16929 }, { id = 16929 }, { id = 15000 } }, "Creature-Boss")
check(mock.SentContains("[Krone des Netherwinds]|h|r – Prio 1: Arcanaa, Arcanielle, Bolzenblitz"), "Ansage Krone Prio 1", sentText())
check(mock.SentContains("[Krone des Netherwinds]|h|r – Prio 2: Loladina"), "Ansage Krone Prio 2")
check(mock.SentContains("[Kopf von Onyxia]|h|r – Prio 1: Awfulkitty"), "Ansage Kopf")
check(mock.SentContains("[Ring der Bindung]|h|r – Prio 0: Gustl"), "Ansage Prio 0 (doppelter Eintrag mit drei Items gilt)")
check(mock.SentContains("[Formel: Waffe - Zauberkraft]|h|r – Rezept für Verzauberkunst, kein Prio"), "Ansage Rezept")
check(mock.SentContains("[Schädelkappe der Nemesis]|h|r x2 – Prio 1: Noraja, Urmeline"), "Ansage zwei Exemplare")
check(not mock.SentContains("Leinenstoff"), "Item unter der Grenze nicht angesagt")
check(not mock.SentContains("Grünes Teil"), "Item der Auto-Liste nicht angesagt")
eq(mock.sent[1].channel, "RAID", "Ansage im Raidchat")
mock.CloseLoot()
mock.sent = {}
mock.OpenLoot({ { id = 16914 } }, "Creature-Boss")
eq(#mock.sent, 0, "dieselbe Beute innerhalb der Wartezeit nicht erneut")
mock.CloseLoot()
mock.clock = mock.clock + 91
mock.OpenLoot({ { id = 16914 } }, "Creature-Boss")
check(mock.SentContains("Prio 1: Arcanaa"), "nach der Wartezeit erneut angesagt")
mock.CloseLoot()
mock.sent = {}
mock.OpenLoot({ { id = 16914 } }, "Creature-Boss2")
check(mock.SentContains("Prio 1: Arcanaa"), "neue Leiche sofort angesagt")
mock.CloseLoot()
PM.db.settings.announceDelay = 0
mock.sent = {}
mock.OpenLoot({ { id = 16914 } }, "Creature-Boss2")
check(mock.SentContains("Prio 1: Arcanaa"), "Wartezeit 0: bei jedem Öffnen")
mock.CloseLoot()
PM.db.settings.announceDelay = 90
local savedCandidates = mock.candidates
mock.candidates = {}
for _, r in ipairs(mock.raid) do
	if r[1] ~= "Arcanielle" then mock.candidates[#mock.candidates + 1] = r[1] end
end
mock.sent = {}
mock.OpenLoot({ { id = 16914 } }, "Creature-Boss5")
check(mock.SentContains("Prio 1: Arcanaa, Bolzenblitz"), "nicht berechtigte Halter werden nicht genannt", sentText())
mock.CloseLoot()
mock.candidates = savedCandidates
PM.db.settings.announceLoot = false
mock.sent = {}
mock.OpenLoot({ { id = 16914 } }, "Creature-Boss6")
eq(#mock.sent, 0, "Häkchen aus: keine Ansage")
mock.CloseLoot()
PM.db.settings.announceLoot = true
mock.isML = false
mock.sent = {}
mock.OpenLoot({ { id = 16914 } }, "Creature-Boss7")
eq(#mock.sent, 0, "nur der Plündermeister sagt an")
mock.CloseLoot()
mock.isML = true
UI:ShowMain("options")
check(option("announceLoot"), "Häkchen für die Beute-Ansage")
check(option("announceLoot"):GetChecked(), "Häkchen ist gesetzt")
eq(_G.PrioMeisterAnnounceDelay:GetValue(), 90, "Schieberegler zeigt 90 s")
_G.PrioMeisterAnnounceDelay:SetValue(150)
eq(PM.db.settings.announceDelay, 150, "Schieberegler setzt die Wartezeit")
_G.PrioMeisterAnnounceDelay:SetValue(900)
eq(PM.db.settings.announceDelay, 600, "höchstens 600 Sekunden")
_G.PrioMeisterAnnounceDelay:SetValue(0)
eq(PM.db.settings.announceDelay, 0, "mindestens 0 Sekunden")
PM.db.settings.announceDelay = 90

-- Zufällig vergeben: Wurf über alle Spieler, gezählt durch die Gruppen 1 bis 8
mock.raid[1].group = 2 -- Arcanaa steht in Gruppe 2, alle anderen in Gruppe 1
mock.Fire("GROUP_ROSTER_UPDATE")
mock.RunTimers()
local order = PM:RandomOrder()
eq(order[1], "Arcanielle", "Platz 1: erster Spieler in Gruppe 1")
eq(order[#order], "Arcanaa", "letzter Platz: Gruppe 2")
-- laufende Würfelrunde darf vom Zufallswurf nicht berührt werden
mock.CloseLoot()
mock.OpenLoot({ { id = 18205 }, { id = 19229 } }, "Creature-Karten")
row1().btn._scripts.OnClick(row1().btn, "LeftButton")
local running = L.ActiveSession(PM:Raid())
mock.Roll("Gustl", 55)
mock.sent, mock.chat = {}, {}
mock.nextRandom = #order
local cardRow
for _, r in ipairs(panel.rows) do if r._shown and r.data and r.data.itemID == 19229 then cardRow = r end end
eq(cardRow.random:GetText(), "Zufällig vergeben", "Knopf „Zufällig vergeben“")
mock.popup = nil
cardRow.random._scripts.OnClick(cardRow.random)
eq(mock.popup, nil, "ohne Prio keine Rückfrage")
check(mock.SentContains("[Sechs der Bestien]|h|r wird zufällig vergeben: Wurf 1-" .. #order .. ", gezählt durch die Gruppen 1 bis 8"), "Zufall angesagt", mock.sent[1] and mock.sent[1].msg)
eq(mock.randomCalls[#mock.randomCalls][2], #order, "Wurf 1 bis Anzahl der Spieler")
eq(#running.rolls, 1, "Zufallswurf nicht in der laufenden Würfelrunde")
eq(mock.candidates[mock.given[#mock.given].index], "Arcanaa", "Item geht an Platz " .. #order)
mock.loot[2] = false
mock.Fire("LOOT_SLOT_CLEARED", 2)
check(mock.ChatContains("Arcanaa erhält") and mock.ChatContains("zufällig vergeben (Platz " .. #order .. " von " .. #order .. ")"), "Protokoll: zufällig vergeben", table.concat(mock.chat, "\n"))
check(mock.SentContains("– zufällig vergeben (Platz"), "im Raidchat als zufällig markiert")
eq(L.AllowedMax(PM:Raid(), "arcanaa"), 100, "Zufall ändert keine Würfelstufe")
check(PM:ExportText(false):find("Arcanaa;19229;Sechs der Bestien;zufällig vergeben;;" .. #order .. ";1-" .. #order, 1, true), "Export der Zufallsvergabe")
mock.CloseLoot()
-- gezogener Spieler kann nicht plündern: Hinweis, dann von Hand
mock.OpenLoot({ { id = 19229 } }, "Creature-Karten2")
local savedCandidates2 = mock.candidates
mock.candidates = {}
for _, r in ipairs(mock.raid) do if r[1] ~= "Arcanielle" then mock.candidates[#mock.candidates + 1] = r[1] end end
mock.sent, mock.chat = {}, {}
mock.nextRandom = 1
row1().random._scripts.OnClick(row1().random)
check(mock.SentContains("Platz 1 von " .. #order .. " ist Arcanielle – kann die Beute gerade nicht erhalten"), "Hinweis bei nicht berechtigtem Spieler", mock.sent[2] and mock.sent[2].msg)
mock.candidates = savedCandidates2
mock.chat = {}
mock.AssignViaList(1, "Arcanielle")
check(mock.ChatContains("Arcanielle erhält") and mock.ChatContains("zufällig vergeben (Platz 1 von"), "von Hand nachgereicht: trotzdem als zufällig markiert", table.concat(mock.chat, "\n"))
mock.CloseLoot()
-- ohne Raidansage der Vergaben steht das Ergebnis trotzdem im Chat
PM.db.settings.awardsToRaid = false
mock.OpenLoot({ { id = 19229 } }, "Creature-Karten3")
mock.sent = {}
mock.nextRandom = 2
SlashCmdList.PRIOMEISTER("zufall " .. mock.Link(19229))
check(mock.SentContains("zufällig vergeben: Platz 2 von"), "Ergebnis im Raidchat ohne Vergabe-Ansage", mock.sent[2] and mock.sent[2].msg)
mock.loot[1] = false
mock.Fire("LOOT_SLOT_CLEARED", 1)
PM.db.settings.awardsToRaid = true
mock.CloseLoot()
mock.raid[1].group = nil
mock.Fire("GROUP_ROSTER_UPDATE")
mock.RunTimers()
mock.nextRandom = nil
-- Item mit Prio: erst nach Rückfrage „Sicher?“
mock.OpenLoot({ { id = 16914 } }, "Creature-Krone")
mock.popup, mock.sent = nil, {}
local rollCalls = #mock.randomCalls
row1().random._scripts.OnClick(row1().random)
check(mock.popup and mock.popup.name == "PRIOMEISTER_RANDOM", "Rückfrage bei Item mit Prio")
check(mock.popup and mock.popup.text:find("Prio 1: Arcanaa, Arcanielle, Bolzenblitz", 1, true)
	and mock.popup.text:find("Sicher zufällig vergeben?", 1, true), "Rückfrage nennt die Prio-Halter", mock.popup and mock.popup.text)
eq(#mock.randomCalls, rollCalls, "ohne Bestätigung kein Wurf")
eq(#mock.sent, 0, "ohne Bestätigung keine Ansage")
mock.nextRandom = 3
mock.AcceptPopup()
eq(#mock.randomCalls, rollCalls + 1, "nach Bestätigung gewürfelt")
check(mock.SentContains("[Krone des Netherwinds]|h|r wird zufällig vergeben"), "nach Bestätigung angesagt")
eq(#mock.given > 0 and mock.given[#mock.given].slot, 1, "Krone nach Bestätigung vergeben")
mock.loot[1] = false
mock.Fire("LOOT_SLOT_CLEARED", 1)
mock.CloseLoot()
mock.popup = nil
SlashCmdList.PRIOMEISTER("zufall " .. mock.Link(16914))
check(mock.popup and mock.popup.name == "PRIOMEISTER_RANDOM", "/pm zufall fragt bei Prio ebenfalls nach")
mock.popup = nil
mock.nextRandom = nil
-- Prio-Runde: „An Entzauberer“ fragt auch ohne Würfe nach
PM:SetRole("disenchanter", "Zenec")
mock.OpenLoot({ { id = 16914 } }, "Creature-Krone2")
row1().btn._scripts.OnClick(row1().btn, "LeftButton")
eq(L.ActiveSession(PM:Raid()).mode, "prio", "Prio-Runde um die Krone")
mock.popup, mock.given = nil, {}
panel.rollDE._scripts.OnClick(panel.rollDE)
check(mock.popup and mock.popup.name == "PRIOMEISTER_DE" and mock.popup.text:find("Prio 1: Arcanaa, Arcanielle, Bolzenblitz\n\nSicher an Entzauberer Zenec geben?", 1, true),
	"Prio-Runde: Rückfrage vor dem Entzauberer", mock.popup and mock.popup.text)
mock.popup = nil
eq(#mock.given, 0, "abgelehnt: nichts vergeben")
-- „Zufällig vergeben“ nennt Prio und Würfe
mock.Roll("Bolzenblitz", 64)
mock.Roll("Arcanaa", 12)
row1().random._scripts.OnClick(row1().random)
check(mock.popup and mock.popup.name == "PRIOMEISTER_RANDOM"
	and mock.popup.text:find("Prio 1: Arcanaa, Arcanielle, Bolzenblitz\nGewürfelt: Bolzenblitz 64, Arcanaa 12\n\nSicher zufällig vergeben?", 1, true),
	"Zufall: Rückfrage nennt Prio und Würfe", mock.popup and mock.popup.text)
mock.popup = nil
mock.CloseLoot()
PM:SetRole("disenchanter", "-")
-- ohne Prio, aber schon gewürfelt: „Zufällig vergeben“ fragt ebenfalls nach
mock.OpenLoot({ { id = 19229 } }, "Creature-Karten4")
row1().btn._scripts.OnClick(row1().btn, "LeftButton")
mock.Roll("Kronolus", 33)
mock.popup = nil
local randomBefore = #mock.randomCalls
row1().random._scripts.OnClick(row1().random)
check(mock.popup and mock.popup.name == "PRIOMEISTER_RANDOM" and mock.popup.text:find("\nGewürfelt: Kronolus 33", 1, true)
	and not mock.popup.text:find("Prio", 1, true), "Zufall nach Würfen: Rückfrage ohne Prio-Zeile", mock.popup and mock.popup.text)
eq(#mock.randomCalls, randomBefore, "ohne Bestätigung kein Zufallswurf")
mock.nextRandom = 1
mock.AcceptPopup()
eq(#mock.randomCalls, randomBefore + 1, "nach Bestätigung gewürfelt")
mock.loot[1] = false
mock.Fire("LOOT_SLOT_CLEARED", 1)
mock.CloseLoot()
mock.nextRandom = nil

-- Reittiere auf Prio: ohne Häkchen ignoriert, mit Häkchen zählen sie
mock.CloseLoot()
mock.chat = {}
PM:ImportText(CSV .. "Zenec;Jäger;19872;0;0;;;;\nBartbär;Krieger;21218;0;0;;;;\n", true)
check(mock.ChatContains("Reittiere sind nicht auf Prio möglich") and mock.ChatContains("Bartbär") and mock.ChatContains("Zenec"),
	"Reittier-Prios beim Import gemeldet", table.concat(mock.chat, "\n"))
mock.sent = {}
mock.OpenLoot({ { id = 19872 }, { id = 21218 } }, "Creature-Raptor")
local raptorRow = rowFor(19872)
check(raptorRow and raptorRow.info:GetText():find("Reittier, Prio ignoriert:|r Zenec", 1, true), "Panel: Reittier-Prio ignoriert", raptorRow and raptorRow.info:GetText())
check(raptorRow and raptorRow.info:GetText():find("Kein Prio – freier Wurf", 1, true), "Panel: freier Wurf um das Reittier")
check(mock.SentContains("[Schneller Razzashiraptor]|h|r – Reittier, kein Prio"), "Ansage: Reittier ohne Prio")
check(mock.SentContains("[Blauer Qirajiresonanzkristall]|h|r – Reittier, kein Prio"), "Qiraji-Kristall als Reittier erkannt")
mock.sent = {}
raptorRow.btn._scripts.OnClick(raptorRow.btn, "LeftButton")
check(mock.SentContains("Reittier, kein Prio, freier Wurf: /roll 100"), "Würfelaufruf: Reittier, freier Wurf", mock.sent[1] and mock.sent[1].msg)
PM:EndSession()
UI:ShowMain("raid")
check(_G.PrioMeisterMainFrame.pages.raid.recipes:GetText():find("Zenec", 1, true), "Raid-Seite nennt die Reittier-Prio")
mock.sent = {}
SlashCmdList.PRIOMEISTER("prio Zenec")
mock.CloseLoot()
PM:SetOption("mountPrio", true)
mock.OpenLoot({ { id = 19872 } }, "Creature-Raptor2")
raptorRow = rowFor(19872)
check(raptorRow and raptorRow.info:GetText():find("Vergabe an Zenec", 1, true), "Häkchen an: Reittier-Prio zählt", raptorRow and raptorRow.info:GetText())
mock.CloseLoot()
PM:SetOption("mountPrio", false)

-- Liste von priomeister.de: Regeln für Rezepte und Reittiere, Stand, Link in der Erinnerung
mock.CloseLoot()
mock.chat = {}
PM.db.settings.recipePrio = true
PM:ImportText(CSV .. "Zenec;Jäger;19872;0;0;;;;\n# PrioMeister: rezepte=wuerfeln; reittiere=prio; spieler=12; prios=30; stand=2026-10-15 18:42; run=ZG 15.10.; link=https://priomeister.de/r/746312\n", true)
check(PM.db.settings.mountPrio == true and PM.db.settings.recipePrio == false, "Regeln aus der Liste übernommen")
check(mock.ChatContains("Regeln vom Prio-Run übernommen: Rezepte werden gewürfelt, Reittiere auf Prio."), "Meldung zu den Regeln", table.concat(mock.chat, "\n"))
check(mock.ChatContains("Prio-Run ZG 15.10.: 12 Spieler, 30 Prios, letzte Änderung 15.10. 18:42."), "Stand beim Import")
check(not mock.ChatContains("Reittiere sind nicht auf Prio möglich"), "Reittier-Prio zählt laut Regel")
check(not mock.ChatContains("nicht erkannt"), "Kommentarzeile nicht als Fehler gemeldet")
mock.chat = {}
SlashCmdList.PRIOMEISTER("stand")
check(mock.ChatContains("Aktueller Stand und Eintragen: priomeister.de/r/746312"), "/pm stand nennt den Link", table.concat(mock.chat, "\n"))
check(mock.ChatContains("Prio-Run ZG 15.10., letzte Änderung auf der Seite 15.10. 18:42"), "/pm stand nennt den Stand")
check(mock.ChatContains("Prioliste: ") and mock.ChatContains(" Prios, importiert "), "/pm stand zählt Spieler und Prios")
mock.sent = {}
PM:RemindNoPrio()
check(mock.SentContains("bitte Prios auf priomeister.de/r/746312 eintragen!"), "Erinnerung mit Link zum Prio-Run", sentText())
UI:ShowMain("raid")
local raidPage = _G.PrioMeisterMainFrame.pages.raid
check(raidPage.listInfo:GetText():find(" · Stand ", 1, true), "Reiter Raid zeigt den Stand", raidPage.listInfo:GetText())
raidPage.listHover._scripts.OnEnter(raidPage.listHover)
check(table.concat(GameTooltip._lines or {}, "\n"):find("priomeister.de/r/746312", 1, true), "Tooltip über der Prioliste nennt den Link")
-- 1.19: Ausnahmen der Positivliste: Rezept trotz „werden gewürfelt“ auf Prio
mock.chat = {}
PM:ImportText(CSV .. "Zenec;Jäger;18259;0;0;Formel: Waffe - Zauberkraft;;;\n"
	.. "# PrioMeister: rezepte=wuerfeln; reittiere=prio; ausnahmen=18259; run=MC 18.10.; link=https://priomeister.de/r/746312\n", true)
check(mock.ChatContains("Rezepte werden gewürfelt, Reittiere auf Prio, trotzdem auf Prio: "), "Meldung nennt die Ausnahmen",
	table.concat(mock.chat, "\n"))
check(not mock.ChatContains("Rezepte sind nicht auf Prio möglich"), "Prio auf das Rezept wird nicht als ignoriert gemeldet",
	table.concat(mock.chat, "\n"))
check(PM:IgnoredKind(18259) == nil and PM:PrioException(18259), "Rezept aus der Positivliste zählt auf Prio")
local exRes = PM:ResolveForItem(18259)
check(exRes.top == 1 and exRes.topHolders[1] and exRes.topHolders[1].name == "Zenec", "Prio-Auflösung: Zenec hat Prio 1 auf das Rezept")
check(table.concat(PM:ListInfo(), "\n"):find("Trotzdem auf Prio: ", 1, true), "/pm stand nennt die Ausnahmen")
PM:ImportText(CSV .. "Zenec;Jäger;18259;0;0;;;;\n# PrioMeister: rezepte=wuerfeln; run=MC 18.10.\n", true)
check(PM:IgnoredKind(18259) == "recipe" and not PM:PrioException(18259), "ohne Ausnahme wird das Rezept wieder gewürfelt")
check(PM:ResolveForItem(18259).top == nil, "dann kein Prio-Halter")

-- 1.20: Priocheck im Spiel: ändert die Prioliste nicht, zeigt, wer im Raid fehlt
do
	mock.CloseLoot()
	local raid = PM:Raid()
	local playersBefore, awardsBefore, startedBefore = raid.players, #raid.awards, raid.started
	local sample = "# priocheck;v=1;run=Ony+ZG 21.10.;pin=482913;link=https://priomeister.de/r/482913;instanzen=Onyxias Hort:1|Zul'Gurub:3\n"
		.. "Arcanaa;Magier;1;111\nZenec;Jäger;0;100\nLillianaa;Priester;1;000\n"
	for _, r in ipairs(mock.raid) do
		if r[1] ~= "Arcanaa" and r[1] ~= "Zenec" then sample = sample .. r[1] .. ";Krieger;1;111\n" end
	end
	sample = sample:gsub("Gustl;Krieger;1;111\n", "Gustl;Krieger;0;000\n"):gsub("Hesti;Krieger;1;111\n", "")
	-- im Importfenster: Knopf „Prüfen“ statt der Import-Knöpfe
	SlashCmdList.PRIOMEISTER("import")
	local f = _G.PrioMeisterImportFrame
	check(f.newRaid:IsShown() and f.replace:IsShown() and not f.check:IsShown(), "erst die Import-Knöpfe")
	f.edit:SetText(sample)
	f.edit._scripts.OnTextChanged(f.edit)
	check(f.check:IsShown() and not f.newRaid:IsShown() and not f.replace:IsShown(), "Priocheck erkannt: Knopf „Prüfen“")
	check(f.status:GetText():find("Priocheck von priomeister.de erkannt", 1, true), "Hinweis im Fenster", f.status:GetText())
	mock.chat = {}
	f.check._scripts.OnClick(f.check)
	check(raid.players == playersBefore and #raid.awards == awardsBefore and PM:Raid().started == startedBefore, "Prioliste, Vergaben und Raid bleiben")
	local complete = #PM:RosterList() - 3 -- alle im Raid außer Gustl und Hesti (ohne) und Zenec (unvollständig)
	check(f.status:GetText():find(string.format("Im Raid 2 ohne Prios, 1 unvollständig, %d vollständig. Nicht im Raid: 1 mit Prios. Details", complete), 1, true),
		"Ergebnis im Fenster, mit der Zahl derer, die mit Prios fehlen", f.status:GetText())
	check(mock.ChatContains("Priocheck Ony+ZG 21.10.") and mock.ChatContains("Ohne Prios:|r Gustl, Hesti")
		and mock.ChatContains("Zenec: Onyxias Hort fehlt, Zul'Gurub ohne Prio 2 und 3") and mock.ChatContains("Mit Prios, aber nicht im Raid:|r Lillianaa"),
		"Ergebnis im Chat", table.concat(mock.chat, "\n"))
	-- „Import als neuer Raid“ mit einem Priocheck startet keinen neuen Raid
	check(PM:ImportText(sample, true) and PM:Raid() == raid and raid.players == playersBefore, "auch über den Import-Knopf nur geprüft")
	-- Reiter Raid und Erinnerung nutzen den Priocheck
	eq(table.concat(PM:NoPrioMembers(), ","), "Gustl,Hesti", "ohne Prio laut Priocheck")
	UI:ShowMain("raid")
	local page = _G.PrioMeisterMainFrame.pages.raid
	check(page.noPrio:GetText():find("Gustl", 1, true) and page.checkLine:GetText():find(string.format("1 unvollständig, %d vollständig, 1 nicht im Raid.", complete), 1, true),
		"Reiter Raid zeigt den Priocheck", page.checkLine:GetText())
	page.checkHover._scripts.OnEnter(page.checkHover)
	check(table.concat(GameTooltip._lines or {}, "\n"):find("Zenec: Onyxias Hort fehlt", 1, true), "Tooltip mit Details")
	check(table.concat(GameTooltip._lines or {}, "\n"):find("Mit Prios, aber nicht im Raid:|r Lillianaa", 1, true), "Tooltip nennt, wer mit Prios fehlt")
	page.checkHover._scripts.OnLeave(page.checkHover)
	mock.sent = {}
	PM:RemindNoPrio()
	check(mock.SentContains("Noch ohne Prio: Gustl, Hesti – bitte Prios auf priomeister.de/r/482913 eintragen!"), "Erinnerung mit Link und PIN", sentText())
	mock.chat = {}
	SlashCmdList.PRIOMEISTER("check")
	check(mock.ChatContains("Priocheck Ony+ZG 21.10."), "/pm check zeigt das Ergebnis")
	-- eine neuere Prioliste löst den Priocheck ab
	raid.imported = raid.check.t + 1
	check(PM:CurrentCheck() == nil and PM:CheckResult() == nil, "neuere Liste: Priocheck gilt nicht mehr")
	page.refresh()
	check(page.checkLine:GetText():find("„Priocheck kopieren“ unter „Alle Prios“ auf der Spielerseite", 1, true), "Hinweis auf den Priocheck", page.checkLine:GetText())
	raid.check = nil
	f:Hide()
end

-- Liste ohne Kommentar (z. B. von sahne-team.de): Optionen bleiben, keine Angaben zum Run
PM:ImportText(CSV, true)
eq(PM:Raid().meta, nil, "Liste ohne Kommentar: keine Angaben zum Run")
check(PM.db.settings.mountPrio == true, "Liste ohne Kommentar ändert die Optionen nicht")
mock.chat = {}
SlashCmdList.PRIOMEISTER("stand")
check(mock.ChatContains("nicht von priomeister.de"), "/pm stand ohne Angaben", table.concat(mock.chat, "\n"))
PM:SetOption("mountPrio", false)

-- Zul'Gurub: Items zum Verwürfeln bei Grenze Blau, Vergabe per Handel
mock.CloseLoot()
PM:ImportText(CSV .. "Zenec;Jäger;19941;0;0;;;;\n", true)
mock.instance = { "Zul'Gurub", "raid", 309 }
mock.threshold = 3
PM.db.settings.autoLootQualities = { [0] = true, [1] = true, [2] = true, [3] = true }
PM:SetRole("lootHelper", "Loladina")
PM:SetRole("treasurer", "Nanuheal")
PM:SetRole("disenchanter", "Bartbär")
PM:SetWins("Gustl", 1)
mock.given, mock.sent, mock.chat = {}, {}, {}
mock.OpenLoot({ { id = 19942 }, { id = 19939 }, { id = 19698 }, { id = 19939 }, { id = 19726 } }, "Creature-Grilek")
eq(#mock.given, 0, "Grenze Blau: nichts Grünes automatisch verteilt")
local dreamRow = rowFor(19942)
check(dreamRow and dreamRow.info:GetText():find("Unter der Plündergrenze: selbst plündern", 1, true), "Panel zeigt Traumfaden mit Handels-Hinweis", dreamRow and dreamRow.info:GetText())
check(not rowFor(19698), "Münze unter der Grenze nicht im Panel")
check(not rowFor(19726), "Blutrebe gehört dem Schatzmeister, nicht im Panel")
check(mock.SentContains("[Hazza'rahs Traumfaden]|h|r – kein Prio"), "Ansage Traumfaden", sentText())
check(mock.SentContains("[Gri'leks Blut]|h|r x2 – kein Prio"), "Ansage zweimal Gri'leks Blut")
check(not mock.SentContains("Zulianische Münze") and not mock.SentContains("Blutrebe"), "Münze und Blutrebe nicht angesagt")
local bloodRow = rowFor(19939)
check(bloodRow and bloodRow.info:GetText():find("Kein Prio – Wurf ohne Stufen", 1, true), "Panel: Wurf ohne Stufen", bloodRow and bloodRow.info:GetText())
mock.sent = {}
bloodRow.btn._scripts.OnClick(bloodRow.btn, "LeftButton")
check(mock.SentContains("[Gri'leks Blut]|h|r x2 – kein Prio, Wurf ohne Stufen: alle /roll 100, die 2 höchsten Würfe gewinnen")
	and not mock.SentContains("/roll 50"), "Würfelaufruf ohne Stufen für zwei Exemplare", sentText())
check(not mock.SentContains("Mit /roll 99"), "keine Stufenhinweise")
local bloodRound = L.ActiveSession(PM:Raid())
eq(bloodRound.mode, "plain", "Runde ohne Stufen")
eq(bloodRound.copies, 2, "Runde kennt zwei Exemplare")
mock.sent = {}
mock.Roll("Gustl", 90)
mock.Roll("Hesti", 90)
mock.Roll("Kronolus", 40)
eq(bloodRound.rolls[1].status, "ok", "Gustl darf trotz Stufe 99 mit 100 würfeln")
eq(#mock.sent, 0, "kein Hinweis auf falschen Wurf")
local _, _, bloodTie = L.RankRolls(bloodRound)
eq(bloodTie, nil, "Gleichstand der beiden Ersten zählt bei zwei Exemplaren nicht")
check(not panel.rollTie:IsShown(), "kein Stichwurf-Knopf")
for _, slot in ipairs({ 2, 4 }) do
	mock.loot[slot] = false
	mock.Fire("LOOT_SLOT_CLEARED", slot)
end
mock.CloseLoot()
eq(L.AwardCount(PM:Raid()), 0, "selbst geplündert: noch keine Vergabe")
mock.chat, mock.sent = {}, {}
mock.Trade("Gustl", { { 19939, 1 } })
check(mock.SentContains("Gustl erhält") and mock.SentContains("Wurf ohne Stufen 90 (1-100)"), "Handel an Gustl eingetragen", sentText())
eq(L.AllowedMax(PM:Raid(), "gustl"), 99, "Gewinn ohne Stufen senkt die Stufe nicht")
check(not mock.SentContains("würfelt ab jetzt"), "kein Stufenhinweis")
check(not bloodRound.done, "zweites Exemplar noch offen")
mock.Trade("Hesti", { { 19939, 1 } })
check(mock.SentContains("Hesti erhält") and mock.SentContains("Wurf ohne Stufen 90 (1-100)"), "Handel an Hesti eingetragen", sentText())
check(bloodRound.done, "Runde nach beiden Exemplaren erledigt")
eq(L.AllowedMax(PM:Raid(), "hesti"), 100, "Hestis Stufe bleibt 100")
local awardCount = #PM:Raid().awards
mock.Trade("Kronolus", { { 4000, 1 } })
eq(#PM:Raid().awards, awardCount, "gewöhnlicher Handel wird nicht eingetragen")
mock.Trade("Kronolus", { { 19939, 1 } })
eq(#PM:Raid().awards, awardCount, "Handel nach erledigter Runde wird nicht eingetragen")
mock.sent = {}
mock.Trade("Zenec", { { 19941, 1 } })
check(mock.SentContains("Zenec erhält") and mock.SentContains("– Prio 1"), "Prio-Vergabe per Handel eingetragen", sentText())
mock.sent, mock.chat = {}, {}
mock.Trade("Nanuheal", { { 19726, 2 } })
local bloodLine = mock.ChatContains("Schatzmeister Nanuheal erhält: ")
check(bloodLine and bloodLine:find("[Blutrebe]|h|r x2", 1, true), "Blutrebe per Handel an den Schatzmeister", table.concat(mock.chat, "\n"))
check(not mock.SentContains("Schatzmeister Nanuheal erhält"), "ohne Häkchen nicht im Raidchat", sentText())
eq(L.CountAwards(PM:Raid(), "nanuheal"), 0, "Schatzmeister zählt nicht als eigener Gewinn")
-- Entzauberer unter der Grenze: per Handel
mock.OpenLoot({ { id = 19942 } }, "Creature-Hazzarah")
rowFor(19942).btn._scripts.OnClick(rowFor(19942).btn, "RightButton")
eq(L.ActiveSession(PM:Raid()).mode, "plain", "Rechtsklick bleibt bei Wurf ohne Stufen")
mock.chat, mock.given = {}, {}
panel.rollDE._scripts.OnClick(panel.rollDE)
check(mock.ChatContains("selbst plündern und handeln"), "Entzauberer: Hinweis auf Handel", table.concat(mock.chat, "\n"))
eq(#mock.given, 0, "unter der Grenze kein GiveMasterLoot")
mock.loot[1] = false
mock.Fire("LOOT_SLOT_CLEARED", 1)
mock.CloseLoot()
mock.sent = {}
mock.Trade("Bartbär", { { 19942, 1 } })
check(mock.SentContains("Bartbär erhält") and mock.SentContains("zum Entzaubern"), "Entzaubern per Handel eingetragen", sentText())
eq(L.CountAwards(PM:Raid(), "bartbär"), 0, "Entzaubern per Handel zählt nicht als eigener Gewinn")
-- Zufällig vergeben unter der Grenze: Ergebnis im Chat, eingetragen beim Handel
mock.OpenLoot({ { id = 19940 } }, "Creature-Renataki")
mock.sent, mock.given = {}, {}
mock.nextRandom = 2
rowFor(19940).random._scripts.OnClick(rowFor(19940).random)
check(mock.SentContains("zufällig vergeben: Platz 2 von"), "Zufall unter der Grenze: Ergebnis im Chat", sentText())
eq(#mock.given, 0, "Zufall unter der Grenze: kein GiveMasterLoot")
mock.CloseLoot()
mock.sent = {}
mock.Trade("Arcanielle", { { 19940, 1 } })
check(mock.SentContains("Arcanielle erhält") and mock.SentContains("zufällig vergeben (Platz 2 von"), "Zufall per Handel eingetragen", sentText())
mock.nextRandom = nil
-- Schmuckstück der Hakkari (blau) bei Grenze Blau an den Schatzmeister
mock.given = {}
mock.OpenLoot({ { id = 19707 } }, "Creature-ZG-Priester")
eq(mock.given[1] and mock.candidates[mock.given[1].index], "Nanuheal", "Schmuckstück an den Schatzmeister")
mock.CloseLoot()
-- Grenze Grün: Münze an den Plünderhelfer, Blutrebe an den Schatzmeister, Gri'leks Blut bleibt
mock.threshold = 2
mock.given = {}
mock.OpenLoot({ { id = 19698 }, { id = 19939 }, { id = 19726 } }, "Creature-ZG-Trash")
local zgGiven = {}
for _, g in ipairs(mock.given) do zgGiven[g.slot] = mock.candidates[g.index] end
eq(zgGiven[1], "Loladina", "Münze an den Plünderhelfer")
eq(zgGiven[3], "Nanuheal", "Blutrebe an den Schatzmeister")
eq(zgGiven[2], nil, "Gri'leks Blut bleibt fürs Würfeln")
check(rowFor(19939), "Gri'leks Blut im Panel")
mock.CloseLoot()
-- Plündern-Reiter: Liste „Immer verwürfeln“
UI:ShowMain("loot")
local zgPage = _G.PrioMeisterMainFrame.pages.loot
eq(zgPage.selected, 309, "in ZG ist dessen Liste gewählt")
zgPage.kindButtons.roll._scripts.OnClick(zgPage.kindButtons.roll)
check(zgPage.listTitle:GetText():find("Immer verwürfeln in", 1, true) and zgPage.listTitle:GetText():find("Zul'Gurub", 1, true), "Titel der Liste zum Verwürfeln", zgPage.listTitle:GetText())
local zgRows = {}
for _, r in ipairs(zgPage.itemRows) do if r._shown then zgRows[#zgRows + 1] = r.text:GetText() end end
eq(#zgRows, 4, "vier Items vorbelegt")
check(table.concat(zgRows, "\n"):find("Gri'leks Blut", 1, true) and not table.concat(zgRows, "\n"):find("Blutrebe", 1, true), "Gri'leks Blut ja, Blutrebe nein")
_G.PrioMeisterLootListEdit:SetText(mock.Link(19698))
_G.PrioMeisterLootListEdit._scripts.OnEnterPressed(_G.PrioMeisterLootListEdit)
check(PM.db.settings.rollLists[309][19698], "Münze in die Liste zum Verwürfeln")
check(not PM.db.settings.lootLists[309][19698], "Schatzmeister-Liste unverändert")
mock.popup = nil
zgPage.clear._scripts.OnClick(zgPage.clear)
check(mock.popup and mock.popup.text == "Immer verwürfeln in „Zul'Gurub“ leeren?", "Leeren fragt nach", mock.popup and mock.popup.text)
mock.popup = nil
zgPage.kindButtons.treasurer._scripts.OnClick(zgPage.kindButtons.treasurer)
check(zgPage.listTitle:GetText():find("Liste des Schatzmeisters", 1, true), "zurück zur Schatzmeister-Liste")
local zgTreasurer = {}
for _, r in ipairs(zgPage.itemRows) do if r._shown then zgTreasurer[#zgTreasurer + 1] = r.text:GetText() end end
eq(#zgTreasurer, 10, "Schatzmeister-Liste in ZG: Blutrebe und neun Schmuckstücke")
check(table.concat(zgTreasurer, "\n"):find("Blutrebe", 1, true) and table.concat(zgTreasurer, "\n"):find("Rotes Schmuckstück der Hakkari", 1, true),
	"Schatzmeister-Liste in ZG zeigt Blutrebe und Schmuckstücke")
PM:RemoveListItem("roll", 309, 19698)

-- Klassenbücher aus AQ20: kein Rezept, Prio zählt, sonst an den Schatzmeister
check(not PM:IsRecipe(21214), "Klassenbuch ist kein Berufsrezept")
check(PM:IsRecipe(18259), "Formel bleibt ein Rezept")
mock.instance = { "Ruinen von Ahn'Qiraj", "raid", 509 }
mock.threshold = 1
PM:ImportText(CSV, true)
mock.given = {}
mock.OpenLoot({ { id = 21214 } }, "Creature-Moam")
eq(mock.given[1] and mock.candidates[mock.given[1].index], "Nanuheal", "Klassenbuch ohne Prio an den Schatzmeister")
mock.CloseLoot()
PM:ImportText(CSV .. "Zenec;Jäger;21214;0;0;;;;\n", true)
mock.given, mock.chat = {}, {}
mock.OpenLoot({ { id = 21214 } }, "Creature-Moam2")
eq(#mock.given, 0, "Klassenbuch mit Prio nicht automatisch")
local bookRow = rowFor(21214)
check(bookRow and bookRow.info:GetText():find("Vergabe an Zenec (Prio 1)", 1, true) and not bookRow.info:GetText():find("Rezept", 1, true),
	"Prio auf Klassenbuch zählt", bookRow and bookRow.info:GetText())
check(not mock.ChatContains("Rezepte sind nicht auf Prio möglich"), "kein Rezept-Hinweis beim Import")
mock.CloseLoot()
mock.instance = nil
mock.threshold = 2
PM.db.settings.autoLootQualities = {}

-- Item ohne geladene Daten (Screenshot mit „[]“): Platzhalter, danach richtige Zeile und Ansage
mock.CloseLoot()
PM.db.settings.announceLoot, PM.db.settings.announceDelay = true, 90
mock.uncached[19802] = true
mock.sent = {}
mock.OpenLoot({ { id = 19802 }, { id = 18205 } }, "Creature-Hakkar")
local heartRow = rowFor(19802)
check(heartRow and heartRow.name:GetText():find("Item 19802, Daten werden geladen", 1, true), "Platzhalter statt „[]“", heartRow and heartRow.name:GetText())
check(not mock.SentContains("[]"), "kein leerer Link in der Ansage", sentText())
check(mock.SentContains("[Eskhandars Halsband]|h|r – kein Prio"), "übrige Items sofort angesagt")
mock.uncached[19802] = nil
mock.Fire("GET_ITEM_INFO_RECEIVED", 19802, true)
mock.RunTimers()
heartRow = rowFor(19802)
check(heartRow and heartRow.name:GetText():find("[Herz von Hakkar]", 1, true), "Zeile zeigt das Item, sobald die Daten da sind", heartRow and heartRow.name:GetText())
check(mock.SentContains("[Herz von Hakkar]|h|r – kein Prio"), "Ansage folgt nach", sentText())
local necklaceCount = 0
for _, m in ipairs(mock.sent) do
	if m.msg:find("Eskhandars Halsband", 1, true) then necklaceCount = necklaceCount + 1 end
end
eq(necklaceCount, 1, "bereits angesagte Items nicht doppelt")
mock.CloseLoot()
-- auch bei Wartezeit 0 nichts doppelt im selben Fenster
PM.db.settings.announceDelay = 0
mock.uncached[19802] = true
mock.sent = {}
mock.OpenLoot({ { id = 19802 }, { id = 18205 } }, "Creature-Hakkar2")
mock.uncached[19802] = nil
mock.Fire("GET_ITEM_INFO_RECEIVED", 19802, true)
mock.RunTimers()
necklaceCount = 0
for _, m in ipairs(mock.sent) do
	if m.msg:find("Eskhandars Halsband", 1, true) then necklaceCount = necklaceCount + 1 end
end
eq(necklaceCount, 1, "Wartezeit 0: trotzdem nur einmal pro Fenster")
check(mock.SentContains("[Herz von Hakkar]|h|r – kein Prio"), "Wartezeit 0: Nachzügler angesagt")
mock.CloseLoot()
PM.db.settings.announceDelay = 90
-- nachgeladenes graues Item geht danach noch an den Plünderhelfer, außer Shift war gedrückt
PM.db.settings.autoLootQualities = { [0] = true }
mock.threshold = 0
mock.uncached[4000] = true
mock.given = {}
mock.OpenLoot({ { id = 4000 } }, "Creature-Trash-Lade")
eq(#mock.given, 0, "ohne Daten noch nichts verteilt")
mock.uncached[4000] = nil
mock.Fire("GET_ITEM_INFO_RECEIVED", 4000, true)
mock.RunTimers()
eq(mock.given[1] and mock.candidates[mock.given[1].index], "Loladina", "nach dem Laden an den Plünderhelfer")
mock.CloseLoot()
mock.shift = true
mock.uncached[4000] = true
mock.given = {}
mock.OpenLoot({ { id = 4000 } }, "Creature-Trash-Lade2")
mock.shift = false
mock.uncached[4000] = nil
mock.Fire("GET_ITEM_INFO_RECEIVED", 4000, true)
mock.RunTimers()
eq(#mock.given, 0, "Shift beim Öffnen gilt auch für Nachzügler")
mock.CloseLoot()
PM.db.settings.autoLootQualities = {}
mock.threshold = 2

-- Früheren Raid fortsetzen: Vergaben, Würfelstufen und Prioliste gelten weiter
do
	mock.CloseLoot()
	local raid = PM:Raid()
	local listBefore = raid.players
	SlashCmdList.PRIOMEISTER("stufen Gustl 3")
	local gustlMax, count = L.AllowedMax(raid, "gustl"), L.AwardCount(raid)
	eq(gustlMax, 97, "Gustl würfelt nach der Korrektur mit 97")
	PM:NewRaid(true)
	local archived = PM.db.history[1]
	check(archived.players == listBefore and archived.adjust and archived.adjust.gustl ~= nil, "Archiv speichert Prioliste und Korrekturen")
	eq(L.AllowedMax(PM:Raid(), "gustl"), 100, "neuer Raid: Gustl wieder bei 100")
	UI:ShowMain("awards")
	local histPage = _G.PrioMeisterMainFrame.pages.awards -- nach dem Neuladen oben ein neues Fenster
	mock.PickDropdown(histPage.raidSelect, 2)
	check(histPage.resume:IsShown() and not histPage.undo:IsShown(), "früherer Raid: „Raid fortsetzen“ statt „Letzte zurücknehmen“")
	mock.popup = nil
	histPage.resume._scripts.OnClick(histPage.resume)
	check(mock.popup and mock.popup.name == "PRIOMEISTER_REOPEN" and mock.popup.text:find("fortsetzen?", 1, true)
		and mock.popup.text:find("wird verworfen", 1, true), "Rückfrage vor dem Fortsetzen", mock.popup and mock.popup.text)
	check(mock.popup and mock.popup.text:find("Die Prioliste mit %d+ Spielern vom [%d.]+ [%d:]+ wird mitgeladen%."),
		"Rückfrage sagt, dass die Prioliste mitkommt", mock.popup and mock.popup.text)
	local historyBefore = #PM.db.history
	mock.chat = {}
	mock.AcceptPopup()
	eq(L.AwardCount(PM:Raid()), count, "fortgesetzter Raid hat seine Vergaben")
	eq(L.AllowedMax(PM:Raid(), "gustl"), gustlMax, "Würfelstufe samt Korrektur wie zuletzt")
	check(PM:Raid().players == listBefore, "Prioliste des Raids gilt wieder")
	eq(#PM.db.history, historyBefore - 1, "leerer laufender Raid wird nicht archiviert")
	eq(histPage.view, 0, "Auswahl springt auf den laufenden Raid")
	check(histPage.undo:IsShown() and not histPage.resume:IsShown(), "laufender Raid: wieder „Letzte zurücknehmen“")
	check(mock.ChatContains("fortgesetzt"), "Meldung im Chat", table.concat(mock.chat, "\n"))
	local maxSession = 0
	for _, aw in ipairs(PM:Raid().awards) do
		if type(aw.session) == "number" and aw.session > maxSession then maxSession = aw.session end
	end
	eq(PM:Raid().sessionSeq, maxSession, "Rundennummern schließen an die Vergaben an")
	-- /pm fortsetzen: Liste, dann Rückfrage; der laufende Raid mit Vergaben kommt ins Archiv
	mock.chat = {}
	SlashCmdList.PRIOMEISTER("fortsetzen")
	check(mock.ChatContains("/pm fortsetzen Nummer") and mock.ChatContains("1: Raid vom"), "/pm fortsetzen listet frühere Raids", table.concat(mock.chat, "\n"))
	local resumedStart, nextOld = PM:Raid().started, PM.db.history[1]
	mock.popup = nil
	SlashCmdList.PRIOMEISTER("fortsetzen 1")
	check(mock.popup and mock.popup.text:find("kommt ins Archiv", 1, true), "Rückfrage nennt das Archiv", mock.popup and mock.popup.text)
	mock.AcceptPopup()
	eq(PM:Raid().started, nextOld.started, "/pm fortsetzen 1 setzt den letzten Raid fort")
	eq(PM.db.history[1].started, resumedStart, "der vorher laufende Raid liegt im Archiv")
	-- Raid aus einer Version vor 1.14: ohne Prioliste, keine fremde Liste übernehmen
	local current = PM:Raid()
	local legacy = { started = 1000, ended = 2000,
		awards = { { key = "zenec", name = "Zenec", kind = "free", t = 1500, itemID = 18813, link = mock.Link(18813),
			roll = 70, low = 1, high = 100, expected = 100 } } }
	table.insert(PM.db.history, 1, legacy)
	mock.chat = {}
	PM:ReopenRaid(legacy)
	check(next(current.players) ~= nil, "vorher war eine Liste geladen")
	eq(next(PM:Raid().players), nil, "alter Raid ohne Liste: startet ohne Liste")
	check(mock.ChatContains("keine Prioliste gespeichert") and mock.ChatContains("Nur Liste ersetzen"), "Hinweis: Liste importieren",
		table.concat(mock.chat, "\n"))
	eq(L.AllowedMax(PM:Raid(), "zenec"), 99, "alter Raid: Würfelstufe aus den Vergaben")
	-- der fortgesetzte Raid bekommt seine eigene Liste, auch wenn die laufende neuer ist
	local newer = PM:Raid()
	newer.players = { test = { name = "Test", p = {}, pn = {} } }
	newer.imported = (newer.imported or 0) + 100000
	local older = PM.db.history[1]
	check(older.players ~= nil and older.players ~= newer.players, "Archiv hat eine eigene Liste")
	PM:ReopenRaid(older)
	check(PM:Raid().players == older.players and PM:Raid().imported == older.imported, "fortgesetzter Raid bekommt seine eigene Prioliste")
	eq(PM:ReopenRaid({}), false, "unbekannter Eintrag: nichts passiert")
	-- Rückfrage bei einem alten Raid ohne Liste
	local noList = { started = 3000, ended = 4000, awards = { { key = "zenec", name = "Zenec", kind = "none", t = 3500, itemID = 18813, link = mock.Link(18813) } } }
	table.insert(PM.db.history, 1, noList)
	mock.popup = nil
	UI:RequestReopen(1)
	check(mock.popup and mock.popup.text:find("keine Prioliste gespeichert", 1, true), "Rückfrage warnt: keine Liste gespeichert", mock.popup and mock.popup.text)
	mock.popup = nil
	table.remove(PM.db.history, 1)
end

-- Jeder Weg ins Archiv nimmt die Prioliste mit, Fortsetzen bringt genau sie zurück
do
	local function csvFor(name, item)
		return "Name;Klasse;prio1itemid;prio2itemid;prio3itemid;prio1itemname;prio2itemname;prio3itemname;\n"
			.. name .. ";Krieger;" .. item .. ";0;0;;;;\n"
	end
	local function award(name)
		PM:ConfirmAward({ key = L.NameKey(name), name = name, itemID = 18813, link = mock.Link(18813) })
	end
	-- Liste A, Vergabe, dann Liste B als neuer Raid importiert
	PM:ImportText(csvFor("Annalist", 16914), true)
	local listA = PM:Raid().players
	award("Gustl")
	PM:ImportText(csvFor("Bertlist", 16929), true)
	local listB = PM:Raid().players
	check(PM.db.history[1].players == listA, "Import als neuer Raid: der alte Raid kommt mit seiner Liste ins Archiv")
	award("Hesti")
	-- Neuer Raid über den Knopf und über /pm neu
	StaticPopup_Show("PRIOMEISTER_NEWRAID")
	mock.AcceptPopup()
	check(PM.db.history[1].players == listB, "Knopf „Neuer Raid“: Liste kommt mit ins Archiv")
	PM:ImportText(csvFor("Cilist", 16955), false)
	local listC = PM:Raid().players
	award("Zenec")
	SlashCmdList.PRIOMEISTER("neu")
	check(PM.db.history[1].players == listC, "/pm neu: Liste kommt mit ins Archiv")
	-- A fortsetzen, dann B: jeweils genau die eigene Liste, und der vorher laufende Raid behält seine
	local function indexOf(list)
		for i, h in ipairs(PM.db.history) do if h.players == list then return i end end
	end
	PM:ReopenRaid(PM.db.history[indexOf(listA)])
	check(PM:Raid().players == listA and PM:Raid().players.annalist, "Raid A fortgesetzt: Liste A ist wieder da")
	PM:ReopenRaid(PM.db.history[indexOf(listB)])
	check(PM:Raid().players == listB and PM:Raid().players.bertlist, "Raid B fortgesetzt: Liste B ist wieder da")
	check(indexOf(listA) ~= nil, "Raid A liegt wieder mit seiner Liste im Archiv")
	PM:ReopenRaid(PM.db.history[indexOf(listC)])
	check(PM:Raid().players == listC and PM:Raid().players.cilist, "Raid C fortgesetzt: Liste C ist wieder da")
end

-- 1.15: „An Name“ beim einzigen Prio-Halter, Verzicht mit /roll 1, Würfelstufen aller Würfler
do
	mock.CloseLoot()
	PM:EndSession()
	mock.isML, mock.threshold, mock.instance = true, 2, nil
	PM.db.settings.autoLootQualities = {}
	PM.db.settings.confirmEpicWinner, PM.db.settings.awardsToRaid, PM.db.settings.announceLoot = true, true, true
	check(not PM.testMode, "kein Testmodus")
	PM:ImportText("Name;Klasse;prio1itemid;prio2itemid;prio3itemid;\n"
		.. "Arcanielle;Magier;16914;0;18205;\nBolzenblitz;Magier;16914;0;0;\nUrmeline;Magier;16914;0;0;\n"
		.. "Kronolus;Paladin;0;0;16914;\nAwfulkitty;Druide;18422;0;0;\nNoraja;Hexenmeister;16929;0;18205;\n", true)
	local p = _G.PrioMeisterPanel
	local function row(id)
		for _, r in ipairs(p.rows) do
			if r._shown and r.data and r.data.itemID == id then return r end
		end
	end
	local function info(id) return row(id) and row(id).info:GetText() or "" end

	-- einziger Prio-Halter: „An Name“ unter „Ansagen“, episch erst nach Rückfrage
	mock.OpenLoot({ { id = 18423 }, { id = 16914 } }, "Creature-Verzicht-1")
	local head = row(18423)
	check(head.give:IsShown() and head.give:GetText() == "An Awfulkitty", "einziger Prio-Halter: Knopf „An Awfulkitty“", head.give:GetText())
	eq(head.btn:GetText(), "Ansagen", "darüber weiter „Ansagen“")
	check(head._h >= 62, "Zeile hat Platz für drei Knöpfe")
	check(not row(16914).give:IsShown(), "mehrere Prio-Halter: kein „An Name“")
	mock.popup, mock.given = nil, {}
	head.give._scripts.OnClick(head.give)
	check(mock.popup and mock.popup.name == "PRIOMEISTER_HOLDER" and mock.popup.text:find("An Awfulkitty (Prio 1) geben?", 1, true),
		"episches Item: erst Rückfrage", mock.popup and mock.popup.text)
	eq(#mock.given, 0, "ohne Bestätigung nichts vergeben")
	mock.AcceptPopup()
	eq(mock.given[1] and mock.candidates[mock.given[1].index], "Awfulkitty", "nach Bestätigung an Awfulkitty")
	mock.chat = {}
	mock.loot[1] = false
	mock.Fire("LOOT_SLOT_CLEARED", 1)
	check(mock.ChatContains("Awfulkitty erhält") and mock.ChatContains("– Prio 1"), "als Prio 1 eingetragen", table.concat(mock.chat, "\n"))

	-- Prio-Runde um die Krone: Arcanielle würfelt 97 und verzichtet dann
	local krone = row(16914)
	mock.sent = {}
	krone.btn._scripts.OnClick(krone.btn, "LeftButton")
	check(mock.SentContains("Prio 1: Arcanielle, Bolzenblitz, Urmeline – bitte /roll 100"), "Würfelaufruf Krone", sentText())
	mock.Roll("Arcanielle", 97)
	mock.Roll("Bolzenblitz", 45)
	eq(p.rollWin:GetText(), "An Arcanielle (97)", "vor dem Verzicht vorn: Arcanielle")
	mock.sent = {}
	mock.Roll("Arcanielle", 1, 1, 1)
	check(mock.SentContains("Arcanielle verzichtet auf " .. mock.Link(16914) .. " (Prio 1) – jetzt Prio 1: Bolzenblitz, Urmeline"),
		"Verzicht im Raidchat, mit den übrigen Prio-Haltern", sentText())
	eq(p.rollWin:GetText(), "An Bolzenblitz (45)", "Arcanielles 97 zählt nicht mehr")
	local logged
	for _, e in ipairs(PM:Raid().rollLog or {}) do
		if e.n == "Arcanielle" and e.v == 97 then logged = e end
	end
	eq(logged and L.RollStatusText(logged), "zurückgezogen", "Wurf-Protokoll: Arcanielles 97 zurückgezogen")
	check(info(16914):find("Arcanielle (verzichtet)", 1, true), "Panel: Arcanielle als verzichtet", info(16914))
	local passLine
	for _, l in ipairs(UI:RollLines(L.ActiveSession(PM:Raid()))) do
		if l:find("verzichtet", 1, true) then passLine = l end
	end
	check(passLine and passLine:find("Arcanielle", 1, true), "Würfe im Panel: Arcanielle verzichtet", passLine)
	-- Plündermeister-Liste: Arcanielle nicht mehr grün
	LootFrame.selectedSlot = 2
	MasterLooterFrame_Show()
	local tagged = {}
	for i = 1, 40 do
		local b = MasterLooterFrame["player" .. i]
		if b and b._shown and b.pmTag then tagged[b.Name:GetText()] = b end
	end
	check(tagged.Arcanielle and tagged.Arcanielle.pmTag._color[2] < 0.9, "Liste: Arcanielle grau statt grün")
	check(tagged.Bolzenblitz and tagged.Bolzenblitz.pmTag._color[2] == 1, "Liste: Bolzenblitz weiter grün")
	MasterLooterFrame:Hide()
	-- die anderen beiden verzichten auch: Runde zu, Kronolus mit Prio 3 ist dran
	mock.sent = {}
	mock.Roll("Bolzenblitz", 1, 1, 1)
	mock.Roll("Urmeline", 1, 1, 1)
	local s = L.ActiveSession(PM:Raid())
	check(s.closed and s.closedByPass, "alle Prio 1 verzichtet: Runde geschlossen")
	check(mock.SentContains("Urmeline verzichtet auf " .. mock.Link(16914) .. " (Prio 1) – jetzt Prio 3: Kronolus"), "dann Prio 3: Kronolus", sentText())
	krone = row(16914)
	check(krone.give:IsShown() and krone.give:GetText() == "An Kronolus", "jetzt „An Kronolus“", krone.give:GetText())
	-- Kronolus verzichtet nach der Ansage, ganz ohne Würfelrunde
	mock.sent = {}
	krone.btn._scripts.OnClick(krone.btn, "LeftButton")
	check(mock.SentContains("Prio 3: Kronolus"), "Ansage Prio 3", sentText())
	mock.Roll("Kronolus", 1, 1, 1)
	check(mock.SentContains("Kronolus verzichtet auf " .. mock.Link(16914) .. " (Prio 3) – jetzt ohne Prio"), "Verzicht ohne Würfelrunde", sentText())
	krone = row(16914)
	check(not krone.give:IsShown() and krone.btn:GetText() == "Würfeln", "danach freier Wurf")
	check(info(16914):find("Kein Prio", 1, true), "Panel: kein Prio mehr", info(16914))
	eq(L.AwardCount(PM:Raid()), 1, "Verzichte zählen nicht als Vergabe")
	-- freier Wurf: wer verzichtet hat, würfelt nicht mehr mit
	krone.btn._scripts.OnClick(krone.btn, "LeftButton")
	eq(L.ActiveSession(PM:Raid()).mode, "free", "neue Runde: freier Wurf")
	mock.Roll("Kronolus", 80)
	mock.Roll("Gustl", 60)
	eq(p.rollWin:GetText(), "An Gustl (60)", "Kronolus' Wurf zählt nach dem Verzicht nicht")
	-- Letzte zurücknehmen: Kronolus hat wieder Prio
	mock.sent = {}
	SlashCmdList.PRIOMEISTER("undo")
	check(mock.SentContains("Kronolus: Verzicht auf " .. mock.Link(16914) .. " zurückgenommen, wieder Prio 3"), "Rücknahme im Raidchat", sentText())
	check(row(16914).give:IsShown() and row(16914).give:GetText() == "An Kronolus", "Rücknahme: wieder „An Kronolus“")
	PM:EndSession()
	mock.CloseLoot()

	-- Prio auf zwei Items derselben Beute: /roll 1 erst nach Ansage eindeutig
	mock.OpenLoot({ { id = 16929 }, { id = 18205 } }, "Creature-Verzicht-2")
	mock.chat, mock.sent = {}, {}
	mock.Roll("Noraja", 1, 1, 1)
	check(mock.ChatContains("Noraja hat /roll 1 gewürfelt, hat aber auf mehrere Items Prio"), "mehrdeutig: Hinweis im eigenen Chat", table.concat(mock.chat, "\n"))
	eq(#mock.sent, 0, "mehrdeutig: nichts im Raidchat")
	local skull = row(16929)
	skull.btn._scripts.OnClick(skull.btn, "LeftButton")
	mock.Roll("Noraja", 1, 1, 1)
	check(mock.SentContains("Noraja verzichtet auf " .. mock.Link(16929) .. " (Prio 1) – jetzt ohne Prio"), "nach „Ansagen“ gilt der Verzicht dem angesagten Item", sentText())
	check(info(18205):find("Noraja", 1, true) and not info(18205):find("Noraja (verzichtet)", 1, true), "Halsband: Noraja hat dort weiter Prio", info(18205))
	-- kurz nach dem Schließen gilt /roll 1 noch der zuletzt offenen Beute
	mock.CloseLoot()
	mock.sent = {}
	mock.Roll("Arcanielle", 1, 1, 1)
	check(mock.SentContains("Arcanielle verzichtet auf " .. mock.Link(18205) .. " (Prio 3) – jetzt Prio 3: Noraja"), "Verzicht nach dem Schließen", sentText())
	mock.OpenLoot({ { id = 16929 }, { id = 18205 } }, "Creature-Verzicht-2")
	check(row(18205).give:IsShown() and row(18205).give:GetText() == "An Noraja", "dieselbe Leiche wieder offen: „An Noraja“")
	mock.OpenLoot({ { id = 18205 } }, "Creature-Verzicht-3")
	check(not row(18205).give:IsShown(), "neue Leiche: Arcanielle und Noraja haben wieder Prio")
	mock.CloseLoot()
	mock.now = mock.now + 400
	mock.sent = {}
	mock.Roll("Arcanielle", 1, 1, 1)
	eq(#mock.sent, 0, "Minuten später gilt /roll 1 keiner Beute mehr")

	-- Würfelstufen: alle, die gewürfelt haben, auch ein Wurf nach dem Ende der Runde
	mock.Roll("Bartbär", 99)
	UI:ShowMain("raid")
	local raidPage = _G.PrioMeisterMainFrame.pages.raid
	local bartRow, gustlRow
	for _, r in ipairs(raidPage.tierRows) do
		if r._shown and r.key == "bartbär" then bartRow = r end
		if r._shown and r.key == "gustl" then gustlRow = r end
	end
	check(bartRow and bartRow.text:GetText():find("Bartbär", 1, true) and bartRow.text:GetText():find("/roll 100", 1, true),
		"Bartbär mit /roll 100, obwohl sein Wurf zu spät kam", bartRow and bartRow.text:GetText())
	check(gustlRow, "Gustl steht da, er hat gewürfelt")
	check(not bartRow.plus:IsEnabled(), "bei 100 geht es nicht höher")
	check(bartRow.minus:IsEnabled(), "Minus senkt auch die 100")
	bartRow.plus._scripts.OnEnter(bartRow.plus)
	eq(GameTooltip._text, "Eine Stufe höher", "Plus hebt die Stufe")
	bartRow.minus._scripts.OnEnter(bartRow.minus)
	eq(GameTooltip._text, "Eine Stufe tiefer", "Minus senkt sie")
	bartRow.minus._scripts.OnLeave(bartRow.minus)
	mock.sent = {}
	bartRow.minus._scripts.OnClick(bartRow.minus)
	eq(L.AllowedMax(PM:Raid(), "bartbär"), 99, "Minus: Bartbär würfelt mit 99")
	check(mock.SentContains("Bartbär: Würfelstufe von Hand von 100 auf 99 geändert"), "Korrektur im Raidchat", sentText())
	check(bartRow.text:GetText():find("1 gewonnen", 1, true), "Zeile zeigt den Gewinn", bartRow.text:GetText())
	check(bartRow.plus:IsEnabled(), "unter 100 geht es wieder höher")
	check(raidPage.tierContent._h >= 21, "Liste ist hoch genug für ihre Zeilen")
	_G.PrioMeisterMainFrame:Hide()
	-- Archiv und Fortsetzen behalten, wer gewürfelt hat
	local entry = L.ArchiveEntry(PM:Raid(), 1)
	check(L.ReopenRaid(entry).rolled["bartbär"], "fortgesetzter Raid kennt die Würfler")
end

-- Würfe auf untragbare Items zählen nicht: Panel, Raidchat, Gewinner-Knopf
do
	mock.CloseLoot()
	mock.isML = true
	mock.Fire("GROUP_ROSTER_UPDATE")
	mock.RunTimers()
	eq(PM.roster.urmeline and PM.roster.urmeline.class, "MAGE", "Urmeline ist Magierin")
	eq(PM.roster["bartbär"] and PM.roster["bartbär"].class, "WARRIOR", "Bartbär ist Krieger")
	PM.db.settings.usableRolls, PM.db.settings.reportWrongRolls = true, true
	local panel = _G.PrioMeisterPanel
	local function rowOf(id)
		for _, r in ipairs(panel.rows) do
			if r._shown and r.data and r.data.itemID == id then return r end
		end
	end
	local function maxFor(key) return L.AllowedMax(PM:Raid(), key) end
	-- Platte: die Magierin zählt nicht, der Krieger gewinnt
	mock.OpenLoot({ { id = 99001 } }, "Creature-Platte")
	rowOf(99001).btn._scripts.OnClick(rowOf(99001).btn, "LeftButton")
	mock.sent = {}
	mock.Roll("Urmeline", 95, 1, maxFor("urmeline"))
	check(mock.SentContains("Urmeline: Wurf 95 zählt nicht – als Magier nicht tragbar (Platte)"), "Hinweis im Raidchat",
		mock.sent[1] and mock.sent[1].msg)
	mock.Roll("Bartbär", 40, 1, maxFor("bartbär"))
	eq(panel.rollWin:IsShown() and panel.rollWin:GetText(), "An Bartbär (40)", "Gewinner-Knopf: der Krieger")
	local lines = table.concat(UI:RollLines(L.ActiveSession(PM:Raid())), "\n")
	check(lines:find("Urmeline 95", 1, true) and lines:find("als Magier nicht tragbar (Platte)", 1, true), "Panel nennt den Grund", lines)
	mock.CloseLoot()
	-- Klassen laut Tooltip: Robe nur für Priester; die Daten werden einmal gelesen und gemerkt
	local scans = mock.tooltipScans
	mock.OpenLoot({ { id = 99004 } }, "Creature-Robe")
	rowOf(99004).btn._scripts.OnClick(rowOf(99004).btn, "LeftButton")
	mock.sent = {}
	mock.Roll("Arcanaa", 77, 1, maxFor("arcanaa"))
	mock.Roll("Sairá", 20, 1, maxFor("sairá"))
	check(mock.SentContains("Arcanaa: Wurf 77 zählt nicht – nur für Priester"), "Robe: nur für Priester", mock.sent[1] and mock.sent[1].msg)
	eq(panel.rollWin:GetText(), "An Sairá (20)", "Robe geht an die Priesterin")
	eq(mock.tooltipScans - scans, 1, "Tooltip nur einmal gelesen")
	mock.CloseLoot()
	-- Dolch nur für die Schildhand: Magierin nein, Schurke ja
	mock.OpenLoot({ { id = 99002 } }, "Creature-Dolch")
	rowOf(99002).btn._scripts.OnClick(rowOf(99002).btn, "LeftButton")
	mock.sent = {}
	mock.Roll("Urmeline", 88, 1, maxFor("urmeline"))
	mock.Roll("Ärwin", 12, 1, maxFor("ärwin"))
	check(mock.SentContains("Urmeline: Wurf 88 zählt nicht – als Magier nicht in der Schildhand führbar"), "Schildhand: Hinweis",
		mock.sent[1] and mock.sent[1].msg)
	eq(panel.rollWin:GetText(), "An Ärwin (12)", "Schildhand-Dolch geht an den Schurken")
	mock.CloseLoot()
	-- abgeschaltet: jeder Wurf zählt
	PM.db.settings.usableRolls = false
	mock.OpenLoot({ { id = 99003 } }, "Creature-Stab")
	rowOf(99003).btn._scripts.OnClick(rowOf(99003).btn, "LeftButton")
	mock.sent = {}
	mock.Roll("Bartbär", 66, 1, maxFor("bartbär"))
	eq(#mock.sent, 0, "abgeschaltet: kein Hinweis")
	eq(panel.rollWin:GetText(), "An Bartbär (66)", "abgeschaltet: der Krieger zählt auch beim Zauberstab")
	PM.db.settings.usableRolls = true
	mock.CloseLoot()
	-- Prio: wer das Item nicht tragen kann, wird übersprungen
	PM:ImportText("Name;Klasse;prio1itemid;prio2itemid;prio3itemid;prio1itemname;prio2itemname;prio3itemname;\n"
		.. "Urmeline;Magier;99001;99002;0;;;;\nBartbär;Krieger;99002;99001;0;;;;\nÄrwin;Schurke;99002;0;0;;;;\n", false)
	mock.sent = {}
	mock.OpenLoot({ { id = 99001 } }, "Creature-PrioPlatte")
	local row = rowOf(99001)
	check(row and row.info:GetText():find("Urmeline (nicht tragbar)", 1, true), "Panel: Magierin „nicht tragbar“", row and row.info:GetText())
	check(row and row.give:IsShown() and row.give:GetText() == "An Bartbär", "„An Bartbär“: die nächste Prio ist dran", row and row.give:GetText())
	check(mock.SentContains("– Prio 2: Bartbär") and not mock.SentContains("Prio 1: Urmeline"), "Beute-Ansage: nur Bartbär", sentText())
	mock.CloseLoot()
	-- Prio-Runde: Bartbär und Ärwin würfeln, der Wurf der Magierin zählt nicht
	mock.OpenLoot({ { id = 99002 } }, "Creature-PrioDolch")
	rowOf(99002).btn._scripts.OnClick(rowOf(99002).btn, "LeftButton")
	local ps = L.ActiveSession(PM:Raid())
	check(ps.mode == "prio" and ps.eligible["bartbär"] and ps.eligible["ärwin"] and not ps.eligible.urmeline, "Prio-Runde ohne die Magierin")
	mock.sent = {}
	mock.Roll("Urmeline", 99)
	check(mock.SentContains("Urmeline: Wurf 99 zählt nicht – als Magier nicht in der Schildhand führbar"), "Prio-Runde: Hinweis im Raidchat", sentText())
	mock.Roll("Bartbär", 70)
	mock.Roll("Ärwin", 30)
	eq(panel.rollWin:GetText(), "An Bartbär (70)", "Gewinner der Prio-Runde")
	mock.CloseLoot()
	-- alles steht im Wurf-Protokoll und im Export
	local log = PM:Raid().rollLog
	local last = log[#log]
	check(last.n == "Ärwin" and last.v == 30 and last.m == "prio" and last.lvl == 1, "letzter Wurf im Protokoll", last.n)
	local csv = PM:ExportCSV({ PM:Raid() })
	check(csv:find(";Urmeline;99002;Testdolch der Schildhand;Wurf;1;99;1-100;;", 1, true) and csv:find(";Prio;nicht tragbar;als Magier nicht in der Schildhand führbar;", 1, true),
		"Export: untragbarer Wurf in der Prio-Runde", csv:sub(-600))
	check(csv:find(";Bartbär;99002;Testdolch der Schildhand;Wurf;1;70;1-100;;", 1, true), "Export: Wurf des Gewinners")
end

-- 1.18: Weitergabe per Rechtsklick in der Vergabenliste
do
	mock.CloseLoot()
	PM:EndSession()
	local raid = PM:Raid()
	local savedAwards, savedPlayers = raid.awards, raid.players
	local saved = { awardsToRaid = PM.db.settings.awardsToRaid, tierHints = PM.db.settings.tierHints }
	PM.db.settings.awardsToRaid, PM.db.settings.tierHints = true, true
	raid.players = L.ParsePrioList("Name;Klasse;prio1itemid;prio2itemid;prio3itemid;\nHestina;Jäger;18813;0;0;\nValas;Jäger;0;18813;0;\n")
	raid.awards = {
		{ key = "hestina", name = "Hestina", kind = "prio", level = 1, itemID = 18813, link = mock.Link(18813), t = 5000 },
		{ key = "gustl", name = "Gustl", kind = "free", itemID = 16914, link = mock.Link(16914), t = 5100, roll = 80, low = 1, high = 100 },
	}
	UI:SelectTab("awards")
	local page = _G.PrioMeisterMainFrame.pages.awards
	page.view = 0
	page.refresh()
	local picker
	check(page.hint:IsShown() and page.hint:GetText():find("Rechtsklick", 1, true), "Hinweis auf den Rechtsklick")
	check(page.rows[1]._hyperlinks and page.lines[1]:GetText():find("Hestina erhält", 1, true), "Zeilen mit Links und Rechtsklick")
	-- Linksklick auf den Link wie bisher, Rechtsklick öffnet die Namensauswahl
	page.rows[1]._scripts.OnHyperlinkClick(page.rows[1], "item:18813::::::::60:::::::", mock.Link(18813), "LeftButton")
	check(mock.itemRefs[#mock.itemRefs].button == "LeftButton" and not (_G.PrioMeisterPicker and _G.PrioMeisterPicker:IsShown()),
		"Linksklick auf den Link öffnet das Item")
	page.rows[1]._scripts.OnMouseUp(page.rows[1], "RightButton")
	picker = _G.PrioMeisterPicker -- nach einem Neuladen des Addons entsteht die Auswahl neu
	check(picker:IsShown() and picker.title:GetText() == "Hestina hat es weitergegeben an:", "Rechtsklick: Namensauswahl", picker.title:GetText())
	local names = {}
	for _, b in ipairs(picker.buttons) do
		if b:IsShown() then names[#names + 1] = b.entry.name or b.entry.label end
	end
	check(table.concat(names, ","):find("Valas", 1, true) and not table.concat(names, ","):find("Hestina", 1, true)
		and not table.concat(names, ","):find("niemand", 1, true), "Auswahl ohne Geber und ohne „niemand“", table.concat(names, ","))
	check(not picker.action:IsShown(), "kein Zurücknehmen bei einer normalen Vergabe")
	-- Valas wählen: Rückfrage mit den Folgen, dann eintragen
	for _, b in ipairs(picker.buttons) do
		if b:IsShown() and b.entry.name == "Valas" then b._scripts.OnClick(b) end
	end
	check(mock.popup and mock.popup.name == "PRIOMEISTER_HANDOVER", "Rückfrage vor der Weitergabe")
	check(mock.popup.text:find("Hestina hat " .. mock.Link(18813) .. " an Valas weitergegeben?", 1, true)
		and mock.popup.text:find("Valas: Prio 2 auf das Item ist damit erfüllt.", 1, true)
		and mock.popup.text:find("Hestina: Prio 1 auf das Item ist wieder offen.", 1, true), "Rückfrage nennt die Folgen", mock.popup.text)
	mock.chat, mock.sent = {}, {}
	mock.AcceptPopup()
	eq(#raid.awards, 3, "Weitergabe eingetragen")
	check(mock.ChatContains("Valas erhält " .. mock.Link(18813) .. " – Weitergabe von Hestina, Prio 2"), "im eigenen Chat", table.concat(mock.chat, "\n"))
	check(mock.SentContains("Valas erhält " .. mock.Link(18813) .. " – Weitergabe von Hestina, Prio 2"), "im Raidchat", sentText())
	page.refresh() -- im Spiel ist das Fenster offen und frischt sich selbst auf
	check(page.lines[1]:GetText():find("an Valas weitergegeben", 1, true) and page.lines[3]:GetText():find("Weitergabe von Hestina", 1, true),
		"Liste zeigt beides")
	-- ein zweites Mal geht nicht
	mock.chat = {}
	picker:Hide()
	page.rows[1]._scripts.OnMouseUp(page.rows[1], "RightButton")
	check(not picker:IsShown() and mock.ChatContains("Hestina hat " .. mock.Link(18813) .. " schon an Valas weitergegeben."),
		"schon weitergegeben", table.concat(mock.chat, "\n"))
	-- Gustls Krone an jemanden, der nicht im Raid war: Name eintippen
	page.rows[2]._scripts.OnMouseUp(page.rows[2], "RightButton")
	_G.PrioMeisterPickerEdit:SetText("zenec")
	_G.PrioMeisterPickerEdit._scripts.OnEnterPressed(_G.PrioMeisterPickerEdit)
	check(mock.popup and mock.popup.text:find("an Zenec weitergegeben?", 1, true)
		and mock.popup.text:find("Zenec würfelt dann mit /roll 99 statt 100.", 1, true)
		and mock.popup.text:find("Gustl würfelt wieder mit /roll 100 statt 99.", 1, true), "Name eingetippt: Rückfrage mit Würfelstufen", mock.popup and mock.popup.text)
	mock.chat, mock.sent = {}, {}
	mock.AcceptPopup()
	check(mock.SentContains("Zenec erhält " .. mock.Link(16914) .. " – Weitergabe von Gustl – würfelt ab jetzt mit /roll 99"), "Raidchat mit Würfelstufe", sentText())
	check(mock.ChatContains("Gustl würfelt wieder mit /roll 100."), "Gustl hat seine Stufe zurück", table.concat(mock.chat, "\n"))
	-- Letzte zurücknehmen hebt die Weitergabe auf
	mock.sent = {}
	PM:UndoLast()
	check(L.AllowedMax(raid, "gustl") == 99 and not raid.awards[2].givenTo, "Letzte zurücknehmen: Krone wieder bei Gustl")
	check(mock.SentContains("Weitergabe zurückgenommen: " .. mock.Link(16914) .. " ist wieder bei Gustl"), "Rücknahme im Raidchat", sentText())
	-- Ältere Weitergabe per Rechtsklick zurücknehmen, auch über den Link
	page.rows[3]._scripts.OnHyperlinkClick(page.rows[3], "item:18813::::::::60:::::::", mock.Link(18813), "RightButton")
	check(picker:IsShown() and picker.action:IsShown() and picker.action:GetText() == "Weitergabe zurücknehmen",
		"Rechtsklick auf den Link einer Weitergabe: Zurücknehmen möglich")
	picker.action._scripts.OnClick(picker.action)
	check(not picker:IsShown() and mock.popup and mock.popup.name == "PRIOMEISTER_HANDOVER_UNDO", "Rückfrage vor dem Zurücknehmen")
	mock.AcceptPopup()
	check(#raid.awards == 2 and not raid.awards[1].givenTo, "Weitergabe zurückgenommen")
	page.refresh()
	check(not page.rows[3]:IsShown(), "Zeile der Weitergabe weg")
	-- Früherer Raid, ohne gespeicherte Prioliste (vor 1.14): Weitergabe auch dort, ohne Raidchat
	local old = { started = 10, ended = 20, awards = { { key = "hestina", name = "Hestina", kind = "free", itemID = 16914,
		link = mock.Link(16914), t = 11, roll = 5, low = 1, high = 100 } } }
	table.insert(PM.db.history, 1, old)
	page.view = 1
	page.refresh()
	check(page.hint:IsShown(), "Rechtsklick-Hinweis auch bei früheren Raids")
	page.rows[1]._scripts.OnMouseUp(page.rows[1], "RightButton")
	_G.PrioMeisterPickerEdit:SetText("Valas")
	_G.PrioMeisterPickerEdit._scripts.OnEnterPressed(_G.PrioMeisterPickerEdit)
	check(mock.popup and mock.popup.text:find("Valas würfelt dann mit /roll 99 statt 100.", 1, true), "Rückfrage im früheren Raid", mock.popup and mock.popup.text)
	mock.chat, mock.sent = {}, {}
	mock.AcceptPopup()
	check(#old.awards == 2 and old.awards[1].givenTo == "Valas" and old.awards[2].kind == "given", "Weitergabe im früheren Raid eingetragen")
	eq(#raid.awards, 2, "der laufende Raid bleibt unberührt")
	check(mock.ChatContains("Valas erhält") and #mock.sent == 0, "nur im eigenen Chat, nicht im Raidchat", sentText())
	page.refresh()
	page.rows[2]._scripts.OnMouseUp(page.rows[2], "RightButton")
	_G.PrioMeisterPicker.action._scripts.OnClick(_G.PrioMeisterPicker.action)
	mock.AcceptPopup()
	check(#old.awards == 1 and not old.awards[1].givenTo and #mock.sent == 0, "im früheren Raid zurückgenommen, ohne Raidchat")
	table.remove(PM.db.history, 1)
	page.view = 0
	picker:Hide()
	raid.awards, raid.players = savedAwards, savedPlayers
	PM.db.settings.awardsToRaid, PM.db.settings.tierHints = saved.awardsToRaid, saved.tierHints
	page.refresh()
end

-- Archiv: Wurf-Protokolle nur für die letzten zehn Raids
do
	local saved = PM.db.history
	PM.db.history = {}
	for i = 1, 12 do PM.db.history[i] = { started = i, awards = { {} }, rollLog = { { t = i } } } end
	local awards = PM:Raid().awards
	local added = #awards == 0
	if added then awards[1] = { kind = "none", t = 1 } end
	PM:ArchiveCurrentRaid()
	check(PM.db.history[1].rollLog ~= nil and PM.db.history[10].rollLog ~= nil, "die letzten zehn behalten ihr Protokoll")
	check(PM.db.history[11].rollLog == nil and PM.db.history[13].rollLog == nil, "ältere ohne Protokoll")
	if added then table.remove(awards) end
	PM.db.history = saved
end

-- Wurf-Protokoll aus den Runden einer älteren Version (DB-Version 6)
do
	mock.CloseLoot()
	mock.ResetUI()
	PrioMeisterDB = { dbVersion = 6, settings = {}, pins = {}, history = {}, raid = {
		started = 100, players = {}, awards = {}, adjust = {}, sessionSeq = 1, activeId = 1,
		sessions = { { id = 1, item = 18813, itemID = 18813, link = mock.Link(18813), started = 100, mode = "free", winners = {},
			source = "Creature-0-5211-409-1-11502-0000", rolls = {
				{ key = "gustl", name = "Gustl", value = 55, low = 1, high = 100, t = 110, status = "ok", seq = 1 },
				{ key = "hesti", name = "Hesti", value = 120, low = 1, high = 120, t = 111, status = "range", reason = "muss /roll 100 würfeln", seq = 2 },
			} } } } }
	loadAddon()
	mock.Fire("ADDON_LOADED", "PrioMeister")
	mock.Fire("PLAYER_LOGIN")
	eq(PM.db.dbVersion, 9, "Datenbank auf Version 9")
	local log = PM:Raid().rollLog
	eq(log and #log, 2, "Würfe der gespeicherten Runde stehen im Protokoll")
	eq(log and log[1].ins, 409, "Instanz aus der Leichen-GUID")
	check(PM:ExportCSV({ PM:Raid() }):find(";Gustl;18813;Ring der Bindung;Wurf;;55;1-100;;1;freier Wurf;zählt;;Geschmolzener Kern;", 1, true),
		"Export: alter Wurf mit Instanz", PM:ExportCSV({ PM:Raid() }))
	check(PM:ExportCSV({ PM:Raid() }):find(";Hesti;18813;Ring der Bindung;Wurf;;120;1-120;;1;freier Wurf;falscher Bereich;muss /roll 100 würfeln;", 1, true),
		"Export: ungültiger Wurf mit Grund")
end

-- 1.17.1: Protokolle aus 1.17.0 bekommen ihre zurückgezogenen Würfe (DB-Version 7)
do
	mock.CloseLoot()
	mock.ResetUI()
	local function log() return {
		{ t = 110, n = "Gustl", v = 55, lo = 1, hi = 100, st = "ok", i = 18813, nm = "Ring der Bindung", sid = 1, m = "prio", lvl = 1 },
		{ t = 111, n = "Hesti", v = 40, lo = 1, hi = 100, st = "ok", i = 18813, nm = "Ring der Bindung", sid = 1, m = "prio", lvl = 1 },
	} end
	local pass = { kind = "pass", key = "gustl", name = "Gustl", itemID = 18813, level = 1, session = 1, t = 112 }
	PrioMeisterDB = { dbVersion = 7, settings = {}, pins = {},
		history = { { started = 50, ended = 90, awards = { pass }, rollLog = log() } },
		raid = { started = 100, players = {}, awards = { pass }, adjust = {}, sessionSeq = 1, sessions = {}, rollLog = log() } }
	loadAddon()
	mock.Fire("ADDON_LOADED", "PrioMeister")
	mock.Fire("PLAYER_LOGIN")
	eq(PM.db.dbVersion, 9, "Datenbank auf Version 9")
	eq(L.RollStatusText(PM:Raid().rollLog[1]), "zurückgezogen", "laufender Raid: Wurf vor dem Verzicht zurückgezogen")
	eq(L.RollStatusText(PM:Raid().rollLog[2]), "zählt", "der Wurf des anderen zählt weiter")
	eq(L.RollStatusText(PM.db.history[1].rollLog[1]), "zurückgezogen", "Archiv: ebenso")
	local csv = PM:ExportCSV({ PM:Raid() })
	check(csv:find(";Gustl;18813;Ring der Bindung;Wurf;1;55;1-100;;1;Prio;zurückgezogen;Verzicht mit /roll 1;", 1, true), "Export nach dem Update", csv)
end

-- 1.23: Namen ohne Akzente. Auf priomeister.de steht „Leryssia“, im Spiel heißt sie „Leryssiá“.
do
	mock.CloseLoot()
	mock.ResetUI()
	local rosterBefore, candidatesBefore = mock.raid, mock.candidates
	mock.raid = { { "Arcanaa", "MAGE" }, { "Gustl", "WARRIOR" }, { "Leryssiá", "PRIEST" } }
	mock.candidates = { "Arcanaa", "Gustl", "Leryssiá" }
	PrioMeisterDB = { dbVersion = 8, settings = {}, pins = {}, history = {} }
	loadAddon()
	mock.Fire("ADDON_LOADED", "PrioMeister")
	mock.Fire("PLAYER_LOGIN")
	local head = "Name;Klasse;prio1itemid;prio2itemid;prio3itemid;\n"
	mock.chat = {}
	PM:ImportText(head .. "Leryssia;Priester;16914;0;0;\nGustl;Krieger;16914;0;0;\nArcanaa;Magier;18205;0;0;\nNandu;Jäger;19865;0;0;\n", true)
	local raid = PM:Raid()
	check(mock.ChatContains("Prioliste: Leryssia ist Leryssiá im Raid."), "Zuordnung im Chat", table.concat(mock.chat, "\n"))
	check(raid.players["leryssiá"] and raid.players["leryssiá"].name == "Leryssiá" and raid.players.leryssia == nil,
		"Eintrag unter dem Namen im Spiel")
	check(mock.ChatContains("Auf der Prioliste, aber nicht im Raid: Nandu") and not mock.ChatContains("ohne Prio"),
		"Leryssiá gilt als anwesend und mit Prio", table.concat(mock.chat, "\n"))

	-- Prio-Runde um die Krone: Leryssiá ist dabei, ihr Wurf zählt
	local present
	for _, h in ipairs(PM:ResolveForItem(16914).levels[1]) do
		if h.key == "leryssiá" then present = h.present end
	end
	eq(present, true, "Prio 1 auf die Krone, anwesend")
	mock.sent = {}
	local s = PM:StartRoll(16914, mock.Link(16914))
	check(mock.SentContains("Prio 1: Gustl, Leryssiá – bitte /roll 100"), "Würfelaufruf nennt Leryssiá", sentText())
	mock.Roll("Leryssiá", 80)
	mock.Roll("Gustl", 40)
	eq(s and s.rolls[1] and s.rolls[1].status, "ok", "ihr Wurf zählt in der Prio-Runde")

	-- Befehle mit dem Namen ohne Akzent treffen Leryssiá
	mock.chat = {}
	SlashCmdList.PRIOMEISTER("vergabe leryssia " .. mock.Link(16914))
	local aw = raid.awards[#raid.awards]
	check(aw and aw.key == "leryssiá" and aw.name == "Leryssiá" and aw.kind == "prio" and aw.level == 1,
		"/pm vergabe leryssia: Prio 1 für Leryssiá", aw and (aw.key .. "/" .. aw.kind))
	check(#L.OpenEntriesFor(raid, "leryssiá", L.Canon(16914), 3) == 0, "ihre Prio ist damit erfüllt")
	SlashCmdList.PRIOMEISTER("stufen leryssia 2")
	eq(L.AllowedMax(raid, "leryssiá"), 98, "/pm stufen leryssia 2: Leryssiá würfelt mit 98")
	eq(raid.adjust.leryssia, nil, "keine Würfelstufe unter einem fremden Schlüssel")
	PM:TogglePin("LERYSSIA")
	eq(PM.db.pins[1], "Leryssiá", "/pm pin: angeheftet in der Schreibweise des Spiels")
	PM:TogglePin("Leryssiá")
	eq(#PM.db.pins, 0, "zweites Mal: wieder gelöst")
	PM:SetRole("treasurer", "leryssia")
	eq(PM.db.settings.treasurer, "Leryssiá", "Rolle per Befehl: Schreibweise des Spiels")
	PM:SetRole("treasurer", "-")

	-- Priocheck mit „Leryssia“
	mock.chat = {}
	PM:ApplyPrioCheck("# priocheck;v=1;run=ZG;instanzen=Zul'Gurub:3\nLeryssia;Priester;111\nGustl;Krieger;111\nArcanaa;Magier;111\n")
	local res = PM:CheckResult()
	check(res and #res.none == 0 and res.complete == 3 and #res.away == 0, "Priocheck: alle drei vollständig, niemand abwesend",
		res and (#res.none .. "/" .. res.complete .. "/" .. #res.away))
	check(mock.ChatContains("Alle mit Prios sind im Raid."), "Chat: alle mit Prios sind im Raid", table.concat(mock.chat, "\n"))
	raid.check = nil

	-- kommt erst später in den Raid: Zuordnung, sobald er da ist
	mock.chat = {}
	table.insert(mock.raid, { "Ñandú", "HUNTER" })
	mock.Fire("GROUP_ROSTER_UPDATE")
	mock.RunTimers()
	check(mock.ChatContains("Prioliste: Nandu ist Ñandú im Raid.") and raid.players["ñandú"] and raid.players.nandu == nil,
		"später dazu: Eintrag wandert zum Namen im Spiel", table.concat(mock.chat, "\n"))
	mock.chat = {}
	mock.Fire("GROUP_ROSTER_UPDATE")
	check(not mock.ChatContains("Prioliste:"), "Zuordnung nur einmal gemeldet", table.concat(mock.chat, "\n"))

	-- zwei passen zum Namen ohne Akzent: keiner bekommt den Eintrag
	table.insert(mock.raid, { "Leryssìa", "MAGE" })
	mock.Fire("GROUP_ROSTER_UPDATE")
	mock.chat = {}
	PM:ImportText(head .. "Leryssia;Priester;16914;0;0;\nGustl;Krieger;16914;0;0;\n", false)
	check(raid.players.leryssia and raid.players["leryssiá"] == nil and raid.players["leryssìa"] == nil, "zwei passen: Eintrag bleibt ohne Zuordnung")
	check(mock.ChatContains("Auf der Prioliste, aber nicht im Raid: Leryssia") and mock.ChatContains("Leryssiá, Leryssìa"),
		"Hinweise: Leryssia fehlt, beide ohne Prio", table.concat(mock.chat, "\n"))
	eq(PM:ResolveKey("Léryssia"), "léryssia", "eingegebener Name passt zu mehreren: kein Treffer")
	eq(PM:ResolveKey("LERYSSÌA"), "leryssìa", "exakter Name im Raid gewinnt")

	-- exakter Name im Raid gewinnt gegen den mit Akzent
	mock.raid = { { "Arcanaa", "MAGE" }, { "Leryssia", "PRIEST" }, { "Leryssiá", "PRIEST" } }
	mock.Fire("GROUP_ROSTER_UPDATE")
	mock.chat = {}
	PM:ImportText(head .. "Leryssia;Priester;16914;0;0;\n", false)
	check(raid.players.leryssia and raid.players.leryssia.name == "Leryssia" and raid.players["leryssiá"] == nil, "Leryssia behält ihren Eintrag")
	check(not mock.ChatContains("Prioliste:") and mock.ChatContains("Im Raid ohne Prios:|r Arcanaa, Leryssiá"),
		"Leryssiá bekommt nichts", table.concat(mock.chat, "\n"))

	mock.raid, mock.candidates = rosterBefore, candidatesBefore
	mock.Fire("GROUP_ROSTER_UPDATE")
	mock.RunTimers()
end

-- 1.27: Kennt das Spiel einen Namen im Raid noch nicht, heißt er „Unbekannt“. So jemand zählt erst mit Namen.
do
	mock.CloseLoot()
	mock.ResetUI()
	local rosterBefore, candidatesBefore = mock.raid, mock.candidates
	mock.raid = { { "Arcanaa", "MAGE" }, { "Gustl", "WARRIOR" }, { UNKNOWNOBJECT, "PRIEST" } }
	mock.candidates = { "Arcanaa", "Gustl" }
	PrioMeisterDB = { dbVersion = 9, settings = {}, pins = {}, history = {} }
	loadAddon()
	mock.Fire("ADDON_LOADED", "PrioMeister")
	mock.Fire("PLAYER_LOGIN")
	check(PM.roster.arcanaa and PM.roster.gustl and not PM.roster[L.NameKey(UNKNOWNOBJECT)], "„Unbekannt“ steht nicht im Raid")
	mock.chat = {}
	PM:ApplyPrioCheck("# priocheck;v=1;run=ZG;instanzen=Zul'Gurub:3\nArcanaa;Magier;111\nGustl;Krieger;111\n")
	check(mock.ChatContains("Alle im Raid haben Prios eingetragen.") and not mock.ChatContains(UNKNOWNOBJECT),
		"Priocheck ohne „Unbekannt“", table.concat(mock.chat, "\n"))
	mock.raid[3] = { "Hesti", "PRIEST" }
	mock.chat = {}
	mock.Fire("UNIT_NAME_UPDATE", "raid3")
	mock.RunTimers()
	check(PM.roster.hesti, "Name angekommen: Hesti steht im Raid")
	local res = PM:CheckResult()
	eq(res and table.concat(res.none, ","), "Hesti", "Priocheck: Hesti ohne Prios")
	check(mock.ChatContains("Im Raid ohne Prio:|r Hesti"), "Hinweis auf Hesti, sobald ihr Name da ist", table.concat(mock.chat, "\n"))

	mock.raid, mock.candidates = rosterBefore, candidatesBefore
	mock.Fire("GROUP_ROSTER_UPDATE")
	mock.RunTimers()
end

-- 1.24: Wartelisten im Spiel. Tiger: John fehlt, Mike ist dran. Bindungen mit „Set vervollständigen“.
do
	mock.CloseLoot()
	mock.ResetUI()
	local rosterBefore, candidatesBefore = mock.raid, mock.candidates
	mock.raid = { { "Arcanaa", "MAGE" }, { "Mike", "WARRIOR" }, { "Sara", "PRIEST" }, { "Gustl", "WARRIOR" } }
	mock.candidates = { "Arcanaa", "Mike", "Sara", "Gustl" }
	PrioMeisterDB = { dbVersion = 8, settings = {}, pins = {}, history = {} }
	loadAddon()
	mock.Fire("ADDON_LOADED", "PrioMeister")
	mock.Fire("PLAYER_LOGIN")
	mock.isML, mock.threshold, mock.instance = true, 2, nil
	PM.db.settings.autoLootQualities = {}
	PM.db.settings.confirmEpicWinner, PM.db.settings.awardsToRaid, PM.db.settings.announceLoot = true, true, true
	local head = "Name;Klasse;prio1itemid;prio2itemid;prio3itemid;\n"
	mock.chat = {}
	PM:ImportText(head .. "Gustl;Krieger;19902;19902;19902;\nMike;Krieger;18205;0;0;\n"
		.. "# PrioMeister: rezepte=wuerfeln; reittiere=prio; run=ZG 22.10.; wartelisten=19902:John,Mike,Sara\n", true)
	check(mock.ChatContains("Warteliste " .. mock.Link(19902) .. ": John, Mike, Sara"), "Import nennt die Warteliste", table.concat(mock.chat, "\n"))
	local raid = PM:Raid()
	eq(table.concat(PM:NoPrioMembers(), ","), "Arcanaa,Sara", "ohne Häkchen: Sara ohne Prio")
	raid.meta.wartelistenp0 = "19902"
	eq(table.concat(PM:NoPrioMembers(), ","), "Arcanaa", "Warteliste gilt als Prio 0: Sara nicht ohne Prio")
	raid.meta.wartelistenp0 = "16914"
	eq(table.concat(PM:NoPrioMembers(), ","), "Arcanaa,Sara", "Prio 0 für ein anderes Item: Sara wieder ohne Prio")
	raid.meta.wartelistenp0 = nil

	mock.sent = {}
	mock.OpenLoot({ { id = 19902 } })
	check(mock.SentContains(mock.Link(19902) .. " – Warteliste: Mike"), "Ansage beim Öffnen: Mike", sentText())
	check(not mock.SentContains("Prio 0"), "Gustls Prio 0 wird nicht angesagt", sentText())
	local p = _G.PrioMeisterPanel
	local info = p.rows[1].info:GetText()
	check(info:find("Warteliste:", 1, true) and info:find("John (fehlt)", 1, true) and info:find("Vergabe an Mike (Warteliste)", 1, true),
		"Panel: ganze Reihenfolge, John fehlt", info)
	eq(p.rows[1].give:GetText(), "An Mike", "Knopf „An Mike“")
	eq(p.rows[1].btn:GetText(), "Ansagen", "darüber „Ansagen“")
	LootFrame.selectedSlot = 1
	MasterLooterFrame_Show()
	local tagged = {}
	for i = 1, 40 do
		local b = MasterLooterFrame["player" .. i]
		if b and b._shown and b.pmTag then tagged[b.Name:GetText()] = b end
	end
	check(tagged.Mike and tagged.Mike.pmTag:GetText() == "W" and tagged.Mike.pmTag._color[2] == 1, "Plündermeister-Liste: Mike mit W in Grün")
	check(tagged.Sara and tagged.Sara.pmTag:GetText() == "W" and tagged.Sara.pmTag._color[2] < 0.9, "Plündermeister-Liste: Sara mit W in Grau")
	MasterLooterFrame:Hide()

	-- Mike verzichtet mit /roll 1: Sara ist dran, sie bekommt den Tiger nach Rückfrage
	mock.sent = {}
	mock.Roll("Mike", 1, 1, 1)
	check(mock.SentContains("Mike verzichtet auf " .. mock.Link(19902) .. " (Warteliste) – jetzt Warteliste: Sara"), "Verzicht: Sara ist dran", sentText())
	eq(p.rows[1].give:GetText(), "An Sara", "Knopf jetzt „An Sara“")
	mock.popup, mock.given = nil, {}
	p.rows[1].give._scripts.OnClick(p.rows[1].give)
	check(mock.popup and mock.popup.text:find("An Sara (Warteliste) geben?", 1, true), "Rückfrage nennt die Warteliste", mock.popup and mock.popup.text)
	mock.AcceptPopup()
	eq(mock.given[1] and mock.candidates[mock.given[1].index], "Sara", "Tiger an Sara")
	mock.sent = {}
	mock.loot[1] = false
	mock.Fire("LOOT_SLOT_CLEARED", 1)
	local aw = raid.awards[#raid.awards]
	check(aw and aw.kind == "waitlist" and aw.key == "sara", "als Warteliste eingetragen", aw and aw.kind)
	check(mock.SentContains("Sara erhält " .. mock.Link(19902) .. " – Warteliste"), "Vergabe im Raidchat", sentText())
	mock.CloseLoot()
	mock.OpenLoot({ { id = 19902 } })
	eq(_G.PrioMeisterPanel.rows[1].give:GetText(), "An Mike", "zweiter Tiger: Mikes Verzicht galt nur dem ersten")
	mock.CloseLoot()
	local res = PM:ResolveForItem(19902, { arcanaa = 1, gustl = 4 })
	check(res.top == 0 and res.topHolders[1].name == "Gustl", "niemand von der Liste da: Gustl mit Prio 0")
	check(PM:ExportCSV({ raid }):find(";Sara;19902;Schneller zulianischer Tiger;Warteliste;", 1, true), "Export: Art Warteliste")
	mock.chat = {}
	SlashCmdList.PRIOMEISTER("stand")
	check(mock.ChatContains("Warteliste " .. mock.Link(19902) .. ": John, Mike"), "/pm stand: Sara steht nicht mehr darauf", table.concat(mock.chat, "\n"))
	local lines = table.concat(PM:PlayerLines("mike", 19902), "\n")
	check(lines:find("Warteliste " .. mock.Link(19902) .. ": Platz 2", 1, true), "Spielerinfo nennt den Platz", lines)
	-- Handel unter der Grenze an jemanden von der Warteliste wird eingetragen
	mock.Trade("Mike", { { 19902, 1 } })
	aw = raid.awards[#raid.awards]
	check(aw and aw.kind == "waitlist" and aw.key == "mike", "Handel an Mike: per Warteliste eingetragen", aw and aw.kind)

	-- Bindungen mit „Set vervollständigen“: Mike bekommt die linke, bei der rechten ist er vor Sara dran
	PM:ImportText(head .. "Gustl;Krieger;18564;0;0;\n# PrioMeister: run=MC 22.10.; wartelisten=18563:Mike,Sara|18564:Sara,Mike; sets=18563+18564\n", true)
	raid = PM:Raid()
	mock.OpenLoot({ { id = 18563 } })
	p = _G.PrioMeisterPanel
	eq(p.rows[1].give:GetText(), "An Mike", "linke Bindung: Mike")
	mock.popup, mock.given = nil, {}
	p.rows[1].give._scripts.OnClick(p.rows[1].give)
	mock.AcceptPopup()
	mock.loot[1] = false
	mock.Fire("LOOT_SLOT_CLEARED", 1)
	mock.CloseLoot()
	mock.OpenLoot({ { id = 18564 } })
	eq(_G.PrioMeisterPanel.rows[1].give:GetText(), "An Mike", "rechte Bindung: Mike rückt vor Sara")
	mock.CloseLoot()
	PM:UndoLast()
	eq(PM:ResolveForItem(18564).topHolders[1].name, "Sara", "nach dem Zurücknehmen: Sara wieder vorn")

	-- klassengebundene Items wie die T2-Helme bei Onyxia: Wer das Item nicht tragen kann, wird übersprungen
	table.insert(mock.raid, { "Kronolus", "PALADIN" })
	table.insert(mock.candidates, "Kronolus")
	mock.Fire("GROUP_ROSTER_UPDATE")
	PM:ImportText(head .. "Gustl;Krieger;16955;0;0;\n# PrioMeister: run=Ony 23.10.; wartelisten=16955:Gustl,Kronolus|16914:Arcanaa\n", true)
	local helm = PM:ResolveForItem(16955)
	check(helm.topHolders[1] and helm.topHolders[1].name == "Kronolus" and helm.waitlist[1].unusable,
		"Krieger auf der Liste des Paladin-Helms: übersprungen, Kronolus ist dran")
	check(UI:ResolutionText(helm):find("Gustl (nicht tragbar)", 1, true), "Panel: Gustl nicht tragbar", UI:ResolutionText(helm))
	eq(PM:ResolveForItem(16914).topHolders[1].name, "Arcanaa", "jeder Helm hat seine eigene Liste")

	mock.raid, mock.candidates = rosterBefore, candidatesBefore
	mock.Fire("GROUP_ROSTER_UPDATE")
	mock.RunTimers()
end

-- 1.24.1: Minimap-Knopf. Mit LibDBIcon (etwa von SexyMap) meldet PrioMeister den Knopf dort an,
-- sonst richtet sich der eigene Knopf nach der Form der Minimap (GetMinimapShape).
do
	local function near(a, b) return a and b and math.abs(a - b) < 0.1 end
	local x, y = UI.MinimapOffset(315, "ROUND", 140, 140)
	check(near(x, 53.03) and near(y, -53.03), "rund: auf dem Kreis", x .. "/" .. y)
	x, y = UI.MinimapOffset(315, "SQUARE", 140, 140)
	check(near(x, 67.93) and near(y, -67.93), "eckig: unten rechts bis in die Ecke", x .. "/" .. y)
	x, y = UI.MinimapOffset(200, "SQUARE", 140, 140)
	check(near(x, -75) and near(y, -32.86), "eckig: links auf dem Rand", x .. "/" .. y)
	x, y = UI.MinimapOffset(315, "CORNER-BOTTOMRIGHT", 140, 140)
	check(near(x, 53.03) and near(y, -53.03), "rundes Viertel bleibt rund", x .. "/" .. y)
	check(near(UI.MinimapOffset(0, "SQUARE", 200, 200), 105), "größere Minimap: weiter außen")
	check(near(UI.MinimapOffset(0, "UNBEKANNT", 0, 0), 75), "unbekannte Form ohne Größe: rund mit 140")

	-- eigener Knopf auf der eckigen Minimap von SexyMap, ohne LibDBIcon
	GetMinimapShape = function() return "SQUARE" end
	PM.db.settings.minimapIcon, PM.db.settings.minimapAngle = nil, 315
	UI:UpdateMinimapButton()
	local b = UI.minimapButton
	local p = b and b._points[1]
	check(p and p[1] == "CENTER" and p[2] == Minimap and near(p[4], 67.93) and near(p[5], -67.93),
		"eigener Knopf auf eckiger Minimap in der Ecke", p and (tostring(p[4]) .. "/" .. tostring(p[5])))
	eq(PM.db.settings.minimapIcon.minimapPos, 315, "bisherige Position übernommen")
	mock.cursor = { 150, 100 }
	b._scripts.OnDragStart(b)
	b._scripts.OnUpdate(b)
	b._scripts.OnDragStop(b)
	eq(PM.db.settings.minimapIcon.minimapPos, 0, "gezogen: Winkel 0")
	check(near(b._points[1][4], 75) and near(b._points[1][5], 0), "gezogen: rechts auf dem Rand")
	mock.cursor = { 150, 120 }
	GetMinimapShape = nil

	-- mit LibDBIcon und LibDataBroker aus einem anderen Addon: dort anmelden statt eigenem Knopf
	local objects, icon = {}, { registered = {}, shown = {} }
	function icon:Register(name, obj, db) self.registered[name] = { obj = obj, db = db }; self.shown[name] = not db.hide end
	function icon:IsRegistered(name) return self.registered[name] ~= nil end
	function icon:Show(name) self.registered[name].db.hide = false; self.shown[name] = true end
	function icon:Hide(name) self.registered[name].db.hide = true; self.shown[name] = false end
	local libs = {
		["LibDataBroker-1.1"] = {
			NewDataObject = function(_, name, obj)
				if objects[name] then return nil end
				objects[name] = obj
				return obj
			end,
			GetDataObjectByName = function(_, name) return objects[name] end,
		},
		["LibDBIcon-1.0"] = icon,
	}
	LibStub = setmetatable({}, { __call = function(_, name) return libs[name] end })
	mock.CloseLoot()
	mock.ResetUI()
	PrioMeisterDB = { dbVersion = 8, settings = { minimapAngle = 120 }, pins = {}, history = {} }
	loadAddon()
	mock.Fire("ADDON_LOADED", "PrioMeister")
	mock.Fire("PLAYER_LOGIN")
	local reg = icon.registered.PrioMeister
	check(reg and reg.obj.type == "launcher" and reg.obj.icon == UI.LOGO_ROUND, "bei LibDBIcon angemeldet, mit rundem Logo")
	eq(reg and reg.db.minimapPos, 120, "Position des bisherigen Knopfs übernommen")
	check(icon.shown.PrioMeister, "Knopf sichtbar")
	eq(UI.minimapButton, nil, "kein eigener Knopf")
	reg.obj.OnClick(nil, "LeftButton")
	check(UI:GetMain():IsShown(), "Linksklick: Hauptfenster")
	reg.obj.OnClick(nil, "LeftButton")
	check(not UI:GetMain():IsShown(), "zweiter Linksklick: Hauptfenster zu")
	local before = UI:GetPanel():IsShown()
	reg.obj.OnClick(nil, "RightButton")
	check(UI:GetPanel():IsShown() ~= before, "Rechtsklick: Panel umgeschaltet")
	reg.obj.OnClick(nil, "RightButton")
	local lines = {}
	reg.obj.OnTooltipShow({ AddLine = function(_, text) lines[#lines + 1] = text end })
	check(lines[1] == "PrioMeister" and (lines[2] or ""):find("Linksklick", 1, true), "Tooltip wie beim eigenen Knopf")
	PM:SetOption("showMinimap", false)
	check(not icon.shown.PrioMeister and reg.db.hide == true, "Option aus: Knopf versteckt")
	PM:SetOption("showMinimap", true)
	check(icon.shown.PrioMeister and reg.db.hide == false, "Option an: Knopf wieder da")
	UI:UpdateMinimapButton()
	eq(UI.minimapButton, nil, "auch danach kein zweiter Knopf")
	LibStub = nil
end

-- 1.25: „Reset“ löscht nach Rückfrage alle gespeicherten Raids; „Teilen“ direkt neben dem Kanal
do
	mock.CloseLoot()
	mock.ResetUI()
	local function raidWith(started, n)
		local r = { started = started, ended = started + 3600, awards = {},
			players = { gustl = { name = "Gustl", p = { 18813, 0, 0 }, pn = { "", "", "" } } } }
		for i = 1, n do
			r.awards[i] = { key = "gustl", name = "Gustl", kind = "free", itemID = 18813, link = mock.Link(18813), t = started + i,
				roll = 50, low = 1, high = 100, expected = 100 }
		end
		return r
	end
	local current = raidWith(5000, 2)
	current.adjust, current.sessions, current.sessionSeq = {}, {}, 0
	PrioMeisterDB = { dbVersion = 8, settings = { treasurer = "Hesti", lootLists = { [0] = { [2589] = true } } }, pins = { "Gustl" },
		history = { raidWith(3000, 3), raidWith(1000, 1) }, raid = current }
	loadAddon()
	mock.Fire("ADDON_LOADED", "PrioMeister")
	mock.Fire("PLAYER_LOGIN")
	UI:ShowMain("awards")
	local page = _G.PrioMeisterMainFrame.pages.awards
	local reset = page.reset
	check(reset and reset:IsShown() and reset:GetText() == "Reset", "Knopf „Reset“")
	local p = reset and reset._points[1]
	check(p and p[1] == "TOPRIGHT" and p[3] == "TOPRIGHT", "Reset ganz rechts oben")
	local d = page.raidSelect._points[1]
	check(d and d[1] == "TOPRIGHT" and d[2] == reset and d[3] == "TOPLEFT", "Auswahl der Raids direkt links daneben")
	reset._scripts.OnEnter(reset)
	check(table.concat(GameTooltip._lines or {}, "\n"):find("Mit dem Reset werden die Daten aller gespeicherten Raids gelöscht und können danach nicht mehr aus dem Addon exportiert werden.", 1, true),
		"Tooltip erklärt den Reset", table.concat(GameTooltip._lines or {}, "\n"))
	reset._scripts.OnLeave(reset)
	mock.popup = nil
	reset._scripts.OnClick(reset)
	check(mock.popup and mock.popup.name == "PRIOMEISTER_RESET" and mock.popup.text:find("Wirklich alle gespeicherten Raids löschen?", 1, true)
		and mock.popup.text:find("der laufende Raid und 2 frühere Raids mit zusammen 6 Vergaben", 1, true),
		"Rückfrage nennt, was gelöscht wird", mock.popup and mock.popup.text)
	eq(#PM.db.history, 2, "ohne Bestätigung nichts gelöscht")
	mock.chat = {}
	mock.AcceptPopup()
	eq(#PM.db.history, 0, "Archiv leer")
	check(#PM:Raid().awards == 0 and next(PM:Raid().players) == nil, "laufender Raid leer, ohne Prioliste")
	check(mock.ChatContains("Alle gespeicherten Raids gelöscht."), "Meldung im Chat", table.concat(mock.chat, "\n"))
	check(PM.db.settings.treasurer == "Hesti" and PM.db.settings.lootLists[0][2589] and PM.db.pins[1] == "Gustl",
		"Einstellungen, Listen und Rollen bleiben")
	eq(page.view, 0, "Auswahl auf dem laufenden Raid")
	eq(#page.raidSelect._entries, 1, "Auswahl nur noch mit dem laufenden Raid")
	mock.popup, mock.chat = nil, {}
	reset._scripts.OnClick(reset)
	check(mock.popup == nil and mock.ChatContains("Es sind keine Raids gespeichert."), "nichts gespeichert: keine Rückfrage")

	-- nur frühere Raids, laufender leer: Rückfrage nennt nur sie
	PM.db.history = { raidWith(3000, 1) }
	mock.popup = nil
	reset._scripts.OnClick(reset)
	check(mock.popup and mock.popup.text:find("Gelöscht werden ein früherer Raid mit einer Vergabe,", 1, true),
		"nur ein früherer Raid", mock.popup and mock.popup.text)
	mock.popup = nil

	-- „Teilen“ direkt neben dem Kanal, beim Flüstern hinter dem Namensfeld
	PM.db.settings.shareChannel = "GUILD"
	page.refresh()
	local sp = page.share._points[1]
	check(sp and sp[1] == "BOTTOMLEFT" and sp[4] == 212, "Gilde: Teilen direkt neben dem Kanal", sp and sp[4])
	PM.db.settings.shareChannel = "WHISPER"
	page.refresh()
	sp = page.share._points[1]
	check(page.target:IsShown() and sp and sp[4] == 356, "Flüstern: Teilen hinter dem Namensfeld", sp and sp[4])
	PM.db.settings.shareChannel = "GUILD"
end

-- 1.26: immer mit /roll 100 im Spiel: Aufruf, Würfe, Panel, Vergabe; ausgeschaltet die alte Regel
do
	mock.CloseLoot()
	mock.ResetUI()
	local rosterBefore, candidatesBefore = mock.raid, mock.candidates
	mock.raid = { { "Arcanaa", "MAGE" }, { "Gustl", "WARRIOR" }, { "Hesti", "PRIEST" } }
	mock.candidates = { "Arcanaa", "Gustl", "Hesti" }
	PrioMeisterDB = { dbVersion = 8, settings = {}, pins = {}, history = {},
		raid = { started = 100, players = {}, awards = {}, adjust = { gustl = 1 }, sessions = {}, sessionSeq = 0 } }
	loadAddon()
	mock.Fire("ADDON_LOADED", "PrioMeister")
	mock.Fire("PLAYER_LOGIN")
	eq(PM.db.settings.always100, false, "voreingestellt aus")
	PM:SetOption("always100", true)
	mock.sent = {}
	local s = PM:StartRoll(18813, mock.Link(18813))
	check(mock.SentContains(mock.Link(18813) .. " – kein Prio, freier Wurf: /roll 100") and mock.SentContains("Stufe 99: Gustl"),
		"Aufruf: /roll 100, dazu Stufe 99", sentText())
	check(not mock.SentContains("Mit /roll 99"), "kein „Mit /roll 99“", sentText())
	mock.sent = {}
	mock.Roll("Gustl", 95)
	mock.Roll("Hesti", 60)
	eq(#mock.sent, 0, "kein Hinweis auf einen falschen Wurf")
	eq(s.rolls[1].status, "ok", "Gustl mit Stufe 99 darf /roll 100")
	local lines = table.concat(UI:RollLines(s), "\n")
	check(lines:find("Stufe 99", 1, true), "Panel nennt die Stufe", lines)
	eq(L.RoundWinner(s).name, "Hesti", "Hestis 60 mit Stufe 100 schlägt Gustls 95 mit Stufe 99")
	mock.sent = {}
	SlashCmdList.PRIOMEISTER("vergabe Hesti " .. mock.Link(18813))
	check(mock.SentContains("Hesti erhält " .. mock.Link(18813) .. " – freier Wurf 60 (1-100) – ab jetzt Würfelstufe 99"),
		"Vergabe nennt die neue Würfelstufe", sentText())
	-- ausgeschaltet: alte Regel mit /roll 99
	PM:SetOption("always100", false)
	mock.sent = {}
	PM:StartRoll(18205, mock.Link(18205))
	check(mock.SentContains("Mit /roll 99: Gustl, Hesti"), "alte Regel: Aufruf mit /roll 99", sentText())
	mock.sent = {}
	mock.Roll("Gustl", 50)
	check(mock.SentContains("Gustl: Wurf 50 (1-100) zählt nicht – bitte /roll 99"), "alte Regel: /roll 100 zählt nicht", sentText())
	mock.raid, mock.candidates = rosterBefore, candidatesBefore
	mock.Fire("GROUP_ROSTER_UPDATE")
	mock.RunTimers()
end

-- 1.21: Englisch. Jeder Text, der übersetzt wird, hat eine englische Fassung (Quelltext durchsucht)
do
	local LNS = {}
	assert(loadfile(ADDON_DIR .. "/Locale.lua"))("PrioMeister", LNS)
	local EN = LNS.EN
	local function isIdentifier(s)
		return s:match("^[a-z_]+$") or s:match("^[A-Z_]+$") or s:match("^[a-z]+[A-Z][%a]*$") or s:match("^On%u%a*$")
	end
	local function needsText(s)
		if isIdentifier(s) or s:find("^Interface\\") then return false end
		local t = s:gsub("|c%x%x%x%x%x%x%x%x", " "):gsub("|r", " "):gsub("%%[-0-9.]*[sdif]", " ")
		return t:find("%a%a") ~= nil
	end
	-- String-Literale einer Datei mit dem Text davor; liest Lua wie der Compiler: Kommentare
	-- (auch --[[…]]), Strings in "…" und '…' sowie lange Strings [[…]]
	local function literals(src)
		local out = {}
		local i, n = 1, #src
		while i <= n do
			local c = src:sub(i, i)
			if c == "-" and src:sub(i + 1, i + 1) == "-" then
				local eq = src:match("^%-%-%[(=*)%[", i)
				if eq then
					local close = src:find("]" .. eq .. "]", i, true)
					i = (close or n) + #eq + 2
				else
					local nl = src:find("\n", i, true)
					i = (nl or n) + 1
				end
			elseif c == "[" and src:match("^%[=*%[", i) then
				local eq = src:match("^%[(=*)%[", i)
				local close = src:find("]" .. eq .. "]", i, true)
				i = (close or n) + #eq + 2
			elseif c == '"' or c == "'" then
				local j = i + 1
				while j <= n do
					local d = src:sub(j, j)
					if d == "\\" then j = j + 2
					elseif d == c then break
					else j = j + 1 end
				end
				if c == '"' then
					local value = loadstring("return " .. src:sub(i, j))
					out[#out + 1] = { pos = i, before = src:sub(math.max(1, i - 60), i - 1), value = value and value() or "" }
				end
				i = j + 1
			else
				i = i + 1
			end
		end
		return out, src
	end
	local CONTEXTS = { "T%(%s*$", ":Print%(%s*$", "%.Button%([^,()]+,%s*$", "%.Tooltip%([^,()]+,%s*$",
		"%.Tooltip%([^,()]+,[^,]+,%s*$", "Heading%([^,()]+,%s*$", "ShowPicker%([^,()]+,%s*$", "[%s{,]text = $",
		"[%s{,]button1 = $", "[%s{,]button2 = $", "[%s{,]label = $", "[%s{,]tip = $", "[%s{,]title = $" }
	-- feste Tabellen, deren Texte erst bei der Anzeige übersetzt werden
	local BLOCKS = { ["Core.lua"] = { "local HELP = {", "PM.METHOD_TEXT = Translated", "PM.QUALITY_TEXT = Translated",
			"PM.ROLE_TEXT = Translated", "PM.ROLE_SHORT = Translated", "PM.SHARE_CHANNELS = {", "local IGNORED_TEXT = {", "local LIST_RULES = {" },
		["Main.lua"] = { "local TABS = {", "local CHANGELOG = {" }, ["UI.lua"] = { "local ROLE_HELP = {" },
		["Logic.lua"] = { "L.RAIDS = {", "L.KIND_TEXT = {" } }
	local missing, checked = {}, 0
	for _, file in ipairs({ "Logic.lua", "Core.lua", "UI.lua", "Main.lua", "Loot.lua" }) do
		local f = assert(io.open(ADDON_DIR .. "/" .. file))
		local list, src = literals(f:read("*a"))
		f:close()
		local ranges = {}
		for _, marker in ipairs(BLOCKS[file] or {}) do
			local a = assert(src:find(marker, 1, true), marker)
			local lineEnd = src:find("\n", a, true) or #src
			-- Tabelle in einer Zeile, etwa Translated({ … }) oder local X = { … }: nur diese Zeile
			local first = src:sub(a, lineEnd)
			local b = (first:find("})", 1, true) or first:find("}%s*$")) and lineEnd or (src:find("\n}", a, true) or #src)
			ranges[#ranges + 1] = { a, b }
		end
		for _, l in ipairs(list) do
			local wanted = false
			for _, c in ipairs(CONTEXTS) do
				if l.before:find(c) then wanted = true end
			end
			for _, r in ipairs(ranges) do
				if l.pos > r[1] and l.pos < r[2] then wanted = true end
			end
			if wanted and needsText(l.value) then
				checked = checked + 1
				if not EN[l.value] then missing[#missing + 1] = file .. ": " .. l.value end
			end
		end
	end
	check(checked > 500, "Texte im Quelltext gefunden: " .. checked)
	eq(#missing, 0, "jeder Text hat eine englische Fassung")
	for i = 1, math.min(#missing, 15) do print("   ohne Übersetzung: " .. missing[i]) end
	-- Formatangaben stimmen überein, sonst bricht string.format im Spiel ab
	local bad = {}
	for de, en in pairs(EN) do
		local a, b = {}, {}
		for spec in de:gmatch("%%[-0-9.]*[sdif%%]") do a[#a + 1] = spec end
		for spec in en:gmatch("%%[-0-9.]*[sdif%%]") do b[#b + 1] = spec end
		if table.concat(a, ",") ~= table.concat(b, ",") then bad[#bad + 1] = de end
	end
	eq(#bad, 0, "Formatangaben in jeder Übersetzung gleich", table.concat(bad, " | "))
	eq(LNS.ResolveLanguage("auto", "deDE"), "de", "deutscher Client: Deutsch")
	eq(LNS.ResolveLanguage("auto", "enUS"), "en", "anderer Client: Englisch")
	eq(LNS.ResolveLanguage("en", "deDE"), "en", "Englisch von Hand")
	eq(LNS.ResolveLanguage("de", "frFR"), "de", "Deutsch von Hand")
end

-- 1.21: Das Addon auf Englisch durchspielen; nirgends darf Deutsch stehen bleiben
do
	mock.CloseLoot()
	mock.ResetUI()
	local firstWidget = #mock.widgets + 1
	PrioMeisterDB = { dbVersion = 8, settings = { language = "en", awardsToRaid = true, announceLoot = true, announceDelay = 0 },
		pins = {}, history = {} }
	loadAddon()
	mock.Fire("ADDON_LOADED", "PrioMeister")
	mock.Fire("PLAYER_LOGIN")
	eq(NS.lang, "en", "Sprache Englisch")
	mock.chat, mock.sent = {}, {}
	SlashCmdList.PRIOMEISTER("help")
	check(mock.ChatContains("commands:") and mock.ChatContains("/pm remind"), "Hilfe auf Englisch", table.concat(mock.chat, "\n"))
	SlashCmdList.PRIOMEISTER("status")
	check(mock.ChatContains("No prio list imported yet."), "englischer Befehl /pm status", table.concat(mock.chat, "\n"))
	PM:ImportText(CSV .. "Zenec;Jäger;16914;0;0;;;;\nArcanaa;Magier;16914;18813;0;;;;\n"
		.. "# PrioMeister: rezepte=wuerfeln; reittiere=prio; run=EN Test\n", true)
	check(mock.ChatContains("players imported (format"), "Import auf Englisch", table.concat(mock.chat, "\n"))
	check(mock.ChatContains("Rules taken from the prio run: Recipes are rolled, Mounts on prio."), "Regeln auf Englisch", table.concat(mock.chat, "\n"))
	-- Beute mit Prio: Ansage, Würfelrunde, Vergabe, Verzicht
	mock.isML, mock.threshold = true, 2
	mock.OpenLoot({ { id = 16914 }, { id = 18813 } }, "Creature-EN-1")
	local p = _G.PrioMeisterPanel
	local function row(id)
		for _, r in ipairs(p.rows) do
			if r._shown and r.data and r.data.itemID == id then return r end
		end
	end
	local krone = row(16914)
	krone.btn._scripts.OnClick(krone.btn, "LeftButton")
	check(mock.SentContains("– please /roll 100"), "Würfelaufruf auf Englisch", table.concat((function() local t = {} for _, x in ipairs(mock.sent) do t[#t + 1] = x.msg end return t end)(), "\n"))
	mock.Roll("Zenec", 80)
	mock.Roll("Arcanaa", 40)
	mock.Roll("Gustl", 99)
	eq(p.rollWin:GetText(), "To Zenec (80)", "Knopf für den Gewinner")
	p.rollWin._scripts.OnClick(p.rollWin)
	if mock.popup then mock.AcceptPopup() end
	mock.loot[1] = false
	mock.Fire("LOOT_SLOT_CLEARED", 1)
	check(mock.ChatContains("Zenec receives"), "Vergabe auf Englisch", table.concat(mock.chat, "\n"))
	mock.Roll("Arcanaa", 1, 1, 1)
	mock.CloseLoot()
	-- Hauptfenster: alle Reiter, Optionen, Changelog, Import mit Priocheck
	UI:ShowMain("raid")
	local main = _G.PrioMeisterMainFrame
	eq(main.tabs.awards:GetText(), "Loot", "Reiter Loot")
	eq(main.tabs.loot:GetText(), "Loot options", "Reiter Loot options")
	for _, tab in ipairs({ "raid", "awards", "loot", "options" }) do UI:SelectTab(tab) end
	eq(main.pages.options.language._selected, "Language: English", "Sprachwahl zeigt Englisch")
	main.pages.options.changelog._scripts.OnClick(main.pages.options.changelog)
	check(_G.PrioMeisterChangelog.text:GetText():find("Priocheck: priomeister.de offers", 1, true), "Changelog auf Englisch")
	_G.PrioMeisterChangelog:Hide()
	SlashCmdList.PRIOMEISTER("import")
	local imp = _G.PrioMeisterImportFrame
	imp.edit:SetText("# priocheck;v=1;run=EN;pin=1;link=https://priomeister.de/r/1;instanzen=Zul'Gurub:3\nZenec;Hunter;111\n")
	imp.edit._scripts.OnTextChanged(imp.edit)
	eq(imp.check:GetText(), "Check", "Knopf „Check“")
	imp.check._scripts.OnClick(imp.check)
	check(imp.status:GetText():find("Checked.", 1, true), "Priocheck auf Englisch", imp.status:GetText())
	imp:Hide()
	UI:SelectTab("raid")
	-- Popups auf Englisch
	eq(StaticPopupDialogs.PRIOMEISTER_UNDO.text, "Undo the last award?\n%s", "Popup übersetzt")
	-- keine deutschen Reste: Chat, Raidchat, alle Texte der neuen Fenster
	local GERMAN = { "und", "oder", "nicht", "der", "die", "das", "mit", "ohne", "für", "wird", "werden", "bitte", "kein",
		"keine", "noch", "auf", "schon", "Vergabe", "Vergaben", "Spieler", "Liste", "niemand", "zählt", "Stufe", "erhält",
		"Verzicht", "Weitergabe", "gewürfelt", "Prioliste", "Raidchat", "Reiter", "Knopf", "Fenster", "Würfe", "Wurf" }
	local NAMES = { "Ruinen von Ahn'Qiraj", "Tempel von Ahn'Qiraj", "Geschmolzener Kern" }
	for _, r in ipairs(mock.raid) do NAMES[#NAMES + 1] = r[1] end
	local function clean(text)
		text = text:gsub("|c%x%x%x%x%x%x%x%x|H.-|h%[.-%]|h|r", ""):gsub("%[.-%]", "")
		-- Werte des Exports, die bewusst deutsch bleiben, in Anführungszeichen genannt
		for _, w in ipairs({ "“Wurf”", "“Weitergabe”", "“weitergegeben”" }) do text = text:gsub(w, "") end
		for _, n in ipairs(NAMES) do text = text:gsub(n:gsub("%p", "%%%0"), "") end
		return text
	end
	local function german(text)
		text = clean(text)
		for _, u in ipairs({ "ä", "ö", "ü", "Ä", "Ö", "Ü", "ß" }) do
			if text:find(u, 1, true) then return true end
		end
		for _, w in ipairs(GERMAN) do
			if text:find("%f[%a]" .. w .. "%f[%A]") then return true end
		end
		return false
	end
	local leaks = {}
	local function scan(where, text)
		if type(text) == "string" and german(text) then leaks[#leaks + 1] = where .. ": " .. text end
	end
	for _, line in ipairs(mock.chat) do scan("Chat", line) end
	for _, m in ipairs(mock.sent) do scan("Raidchat", m.msg) end
	for i = firstWidget, #mock.widgets do
		local w = mock.widgets[i]
		if w._kind ~= "EditBox" then scan(w._kind .. " " .. tostring(w._name), w._text) end
	end
	for name, def in pairs(StaticPopupDialogs) do
		if name:find("^PRIOMEISTER") then scan("Popup " .. name, def.text); scan("Popup " .. name, def.button1) end
	end
	eq(#leaks, 0, "keine deutschen Texte auf Englisch")
	for i = 1, math.min(#leaks, 25) do print("   Deutsch: " .. leaks[i]) end
	-- zurück auf Deutsch für die folgenden Tests
	PrioMeisterDB.settings.language = "de"
	NS.SetLanguage("de")
end

-- Alte TOC ohne Main.lua (WoW noch nicht neu gestartet): keine Lua-Fehler
mock.CloseLoot()
mock.ResetUI()
do
	local oldNS = {}
	for _, file in ipairs({ "Logic.lua", "Core.lua", "UI.lua", "Loot.lua" }) do
		assert(loadfile(ADDON_DIR .. "/" .. file))("PrioMeister", oldNS)
	end
	local okLoad, err = pcall(function()
		mock.Fire("ADDON_LOADED", "PrioMeister")
		mock.Fire("PLAYER_LOGIN")
		mock.chat = {}
		SlashCmdList.PRIOMEISTER("")
		mock.OpenLoot({ { id = 18813 } })
		local p = _G.PrioMeisterPanel
		p.menu._scripts.OnClick(p.menu)
		mock.CloseLoot()
	end)
	check(okLoad, "ohne Main.lua keine Fehler", err)
	check(mock.ChatContains("komplett neu starten"), "Hinweis auf Neustart")
end

-- CHANGELOG.md (englisch, für CurseForge und GitHub) passt zur neuesten Version im Changelog
do
	local root = TESTDIR .. "/.."
	local render = assert(loadfile(root .. "/scripts/changelog.lua"))("module")
	local fh = io.open(root .. "/CHANGELOG.md", "rb")
	local text = fh and fh:read("*a")
	if fh then fh:close() end
	eq(text, render(root), "CHANGELOG.md aktuell (neu erzeugen: lua5.1 scripts/changelog.lua > CHANGELOG.md)")
	check(text and text:find("^# PrioMeister " .. PM.version:gsub("%.", "%%.") .. " "), "CHANGELOG.md nennt die aktuelle Version", text)
end

-- Beschreibung für CurseForge: Englisch zuerst, dann Deutsch, Links absolut auf GitHub
do
	local root = TESTDIR .. "/.."
	local render = assert(loadfile(root .. "/scripts/curseforge.lua"))("module")
	local fh = io.open(root .. "/curseforge/beschreibung.md", "rb")
	local text = fh and fh:read("*a")
	if fh then fh:close() end
	eq(text, render(root), "curseforge/beschreibung.md aktuell (neu erzeugen: lua5.1 scripts/curseforge.lua > curseforge/beschreibung.md)")
	local en, de = text and text:find("# PrioMeister\n", 1, true), text and text:find("# PrioMeister (Deutsch)", 1, true)
	check(en == 1 and de and de > en, "Beschreibung: Englisch zuerst, dann Deutsch")
	check(text and not text:find("%]%(LICENSE"), "Beschreibung: keine relativen Links", text and text:match("%]%([^)]*%)"))
end

print(("%d bestanden, %d fehlgeschlagen"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
