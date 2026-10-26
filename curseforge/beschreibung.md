# PrioMeister

Master looter helper for World of Warcraft Classic Era (1.15.x). PrioMeister reads a prio list, shows who has prio on the loot in a panel next to the loot window, runs roll rounds with roll tiers and records every award. The interface is available in English and German: it follows the game language, and in the options you can set it to English or German.

Players do not need the addon, they enter their prios on priomeister.de. The addon is for whoever loots in the raid. The [help page on priomeister.de](https://priomeister.de/hilfe) explains how both work together, in English via the EN switch at the top.

Open the main window with `/pm` or a left-click on the minimap button. A right-click on the minimap button shows and hides the panel. If another addon brings the LibDBIcon library, e.g. SexyMap, PrioMeister uses it for the button, so minimap addons place it on the edge like the others. The “?” button at the top right of the main window opens the options; the changelog is there too (`/pm changelog`).

## Raid flow

1. **Import the prio list:** on priomeister.de click “Copy for PrioMeister” in your prio run and paste it into `/pm import`. “Import as new raid” resets awards and roll tiers, “Replace list only” keeps them. Lists from sahne-team.de work as well.
2. **Open the loot:** the panel shows every item with its prio holders. With “Announce loot when opened” the raid chat gets the loot and the prios.
3. **Announce / Roll:** with a single prio holder, “To Name” gives them the item directly. With several, “Roll” starts a roll round for the prio holders; without prio it is a free roll. A right-click forces a free roll.
4. **Award:** “To Name (roll)” gives the item to the winner. For epic items the addon asks first. “Award randomly” rolls over all raid members, “To disenchanter” gives it to the disenchanter.
5. **Undo:** “Undo last” in the Loot tab takes back the last entry.

## Rules

- **Roll tiers:** everyone starts with /roll 100. Each free roll win lowers your tier by one (99, 98 …). Prio awards do not change the tier. The Raid tab lists everyone who rolled; plus and minus correct a tier by hand.
- **50 rolls:** /roll 50 for alts or off-specs runs in parallel, ranks behind all normal rolls and never changes a tier.
- **Recipes:** rolled with /roll 100 without tiers, only players with the matching profession should roll. Whether recipes and mounts may be on prio comes with the list from priomeister.de; single items can be allowed as exceptions.
- **Pass:** a prio holder who does not want the item rolls /roll 1. The next prio is up, the prio stays for a later copy.
- **Unusable items:** rolls and prios on items the class cannot use (armor type, weapon type, class restriction) do not count.
- **Ties:** “Tiebreak” lets the tied players roll again with the same tier.
- **Names without accents:** like priomeister.de, the addon compares names without accents. If the list says “Leryssia” and the character in the game is “Leryssiá”, the entry counts for that character. The chat then shows “Prio list: Leryssia is Leryssiá in the raid.” once. Players who join later are matched when they arrive. This also applies to the priocheck and to names in commands such as `/pm award Name`. The exact name wins. If two players in the raid match the same name without accents and neither is exact, the addon matches no one.

## Waitlists

For single items, the raid lead keeps ordered waitlists on priomeister.de, e.g. for the mounts from Zul'Gurub or the Bindings of the Windseeker. They come into the addon with the prio list, in the comment line as `wartelisten=19902:John,Mike,Sara`. The import and `/pm status` show them in the chat.

- The first player on the list who is present is up and beats every prio, even prio 0. If John is absent, Mike is up.
- The announcement names only that player, e.g. “[Item] – waitlist: Mike”. The panel shows the whole order, absent players grey with “(absent)”. “To Mike” gives the item directly, for epic items after a confirmation. In the master looter list everyone on the list has a “W”, green only for the player who is up.
- Passing with `/roll 1` makes room for the next one. The pass only counts for this copy.
- Whoever gets the item drops off the list for the rest of the raid. A second copy goes to the next one. Handing the item over puts the giver back on the old place. If the same item was also on prio, that prio is fulfilled.
- If nobody from the list is present, the usual rules apply: prio, rolls, loot helper, treasurer.
- If a waitlist counts as prio 0 on the site (`wartelistenp0=19902`), its players cannot choose their own prios there. The addon therefore does not list them under “In the raid without prio”.
- **Complete the set:** for sets such as the left and right binding (`sets=18563+18564`), players who already got another piece in this raid move up. Only those who had a piece before according to the site stay ahead; they are marked with a star in the list.
- The export lists these awards with the type `Warteliste`. The site then removes the names from the list.

## Roles and lists

- **Loot helper** gets everything up to the chosen quality that is on no list.
- **Treasurer** gets only the items on the treasurer list (e.g. scarabs and keys in AQ).
- **Disenchanter** gets items nobody rolls for. With a disenchanter set, every armor or weapon item in the panel gets a “To disenchanter” button, no roll needed. The minimum quality is set next to the disenchanter in the Loot options tab: never, green and up, blue and up or epic only, green and up by default. The button is missing while a present player has prio. For epic items the addon asks first.
- Lists exist per instance (“All instances” plus the current one) in the Loot options tab. “Always roll” items are always rolled, never given to loot helper or treasurer.
- Loot from a container in your bags, from fishing and from herbs or ore veins does not go through the master looter. The addon does not announce it, gives nothing away and shows no panel. Boss chests are handled like corpses.

## Hand-overs

If a player gave an item to someone else in the game, right-click the award in the Loot tab and choose the new owner. A hand-over counts like a new award: the recipient's prio is fulfilled, otherwise their tier drops like after a free roll; the giver's prio opens again or their tier comes back. This works for earlier raids too.

## Priocheck

To see who in the raid has not entered prios yet without closing the sign-up on priomeister.de: click “Copy priocheck” under “All prios” on the player page of the prio run, paste it into `/pm import` and choose “Check”. The result appears in the chat and in the Raid tab; “Remind raid” posts the missing names with the link and PIN.

## Export

The Loot tab exports all awards and rolls as CSV for priomeister.de or a spreadsheet. On priomeister.de, paste it in the “Awards” tab of the prio run: the raid lead on the lead page, the master looter on the player page. The column names and values of the export stay German in both languages, because priomeister.de reads them (e.g. type “Wurf” for rolls, “Weitergabe” for hand-overs, “Warteliste” for waitlist awards).

“Reset” next to the raid selection deletes all saved raids after a confirmation, the current one and all earlier ones, with awards, roll tiers, roll logs and prio list. They cannot be exported from the addon afterwards. Settings, lists and roles stay. If you still need the data, save it first with “Export all raids”.

## Commands

| Command | Effect |
|---|---|
| `/pm` | main window |
| `/pm import` | paste a prio list or a priocheck |
| `/pm new`, `/pm resume [n]` | new raid, resume an earlier raid |
| `/pm status` | state of the prio list |
| `/pm table` | prio table of all players |
| `/pm roll [Item]`, `/pm free [Item]`, `/pm stop` | start or end a roll round |
| `/pm tiebreak`, `/pm random [Item]` | tiebreak roll, award randomly |
| `/pm tiers [Name N]` | show or set roll tiers |
| `/pm award Name [Item]` | record an award by hand |
| `/pm undo` | undo the last award |
| `/pm list`, `/pm export [all]` | awards in chat or as CSV |
| `/pm share [guild\|officer\|raid\|party\|Name]` | share the awards |
| `/pm remind`, `/pm check` | remind players without prio, show the priocheck |
| `/pm helper`, `/pm treasurer`, `/pm disenchanter Name` | set roles (`-` clears) |
| `/pm pin Name`, `/pm panel`, `/pm test` | pin a player, toggle the panel, test mode |
| `/pm help` | all commands |

The German commands (`/pm stand`, `/pm erinnern`, `/pm teilen gilde` …) work as well.

## Supported game versions

WoW Classic 1.15.9: Classic Era, Hardcore and Season of Discovery realms, which all run on the same client. Burning Crusade Classic Anniversary, Mists of Pandaria Classic and retail are not supported.

## Bug reports

Please use the [bug report form on GitHub](https://github.com/andi79h/PrioMeister/issues/new/choose), in English or German.

## License

MIT, see [LICENSE.txt](https://github.com/andi79h/PrioMeister/blob/main/LICENSE.txt).

---

# PrioMeister (Deutsch)

Plündermeister-Hilfe für World of Warcraft Classic Era (1.15.x). PrioMeister liest eine Prioliste und zeigt in einem Panel neben dem Beutefenster, wer auf die Beute Prio hat. Es führt Würfelrunden mit Würfelstufen durch und protokolliert jede Vergabe. Die Oberfläche gibt es auf Deutsch und Englisch: Sie folgt der Spielsprache, unter Optionen lässt sie sich fest auf Deutsch oder Englisch stellen.

Spieler brauchen das Addon nicht, sie tragen ihre Prios auf priomeister.de ein. Das Addon braucht, wer im Raid plündert. Wie beides zusammenspielt, erklärt die [Hilfe auf priomeister.de](https://priomeister.de/hilfe).

Das Hauptfenster öffnet `/pm` oder ein Linksklick auf den Minimap-Knopf. Ein Rechtsklick auf den Minimap-Knopf blendet das Panel ein und aus. Bringt ein anderes Addon die Bibliothek LibDBIcon mit, etwa SexyMap, nutzt PrioMeister sie für den Knopf. Minimap-Addons ordnen ihn dann wie die anderen am Rand an. Der Knopf „?“ oben rechts im Hauptfenster öffnet die Optionen, dort steht auch das Changelog (`/pm changelog`).

## Ablauf im Raid

1. **Prioliste importieren:** Auf priomeister.de im Prio-Run auf „Kopieren für PrioMeister“ klicken und die Liste unter `/pm import` einfügen. „Import als neuer Raid“ setzt Vergaben und Würfelstufen zurück, „Nur Liste ersetzen“ behält sie. Listen von sahne-team.de gehen ebenso.
2. **Beute öffnen:** Das Panel zeigt jedes Item mit seinen Prio-Haltern. Mit „Beute beim Öffnen ansagen, mit Prios“ stehen Beute und Prios im Raidchat.
3. **Ansagen und Würfeln:** Hat nur ein Spieler Prio, gibt „An Name“ ihm das Item direkt. Bei mehreren startet „Würfeln“ eine Würfelrunde für die Prio-Halter, ohne Prio ist es ein freier Wurf. Ein Rechtsklick erzwingt einen freien Wurf.
4. **Vergeben:** „An Name (Wurf)“ gibt das Item dem Gewinner. Bei epischen Items fragt das Addon vorher nach. „Zufällig vergeben“ würfelt über alle Spieler im Raid, „An Entzauberer“ gibt das Item dem Entzauberer.
5. **Zurücknehmen:** „Letzte zurücknehmen“ im Reiter Beute nimmt den letzten Eintrag zurück.

## Regeln

- **Würfelstufen:** Alle beginnen mit /roll 100. Jeder Gewinn per freiem Wurf senkt die eigene Stufe um eins (99, 98 …). Vergaben über Prio ändern die Stufe nicht. Der Reiter Raid listet alle, die gewürfelt haben; Plus und Minus korrigieren eine Stufe von Hand.
- **50er-Würfe:** /roll 50 für Zweitcharaktere oder Zweitskillungen läuft parallel, zählt hinter allen normalen Würfen und ändert nie eine Stufe.
- **Rezepte:** werden mit /roll 100 ohne Stufen verwürfelt, würfeln sollen nur Spieler mit dem passenden Beruf. Ob Rezepte und Reittiere auf Prio stehen dürfen, kommt mit der Liste von priomeister.de; einzelne Items lassen sich als Ausnahme freigeben.
- **Verzicht:** Wer Prio hat und das Item nicht will, würfelt /roll 1. Dann ist die nächste Prio dran, die eigene Prio bleibt für ein späteres Exemplar.
- **Nicht tragbare Items:** Würfe und Prios auf Items, die die Klasse nicht tragen kann (Rüstungsart, Waffenart, Klassenbeschränkung), zählen nicht.
- **Gleichstand:** „Stichwurf“ lässt die Gleichplatzierten mit derselben Stufe noch einmal würfeln.
- **Namen ohne Akzente:** Wie priomeister.de vergleicht das Addon Namen ohne Akzente. Steht auf der Liste „Leryssia“ und heißt der Charakter im Spiel „Leryssiá“, gilt der Eintrag für diesen Charakter. Im Chat steht dann einmal „Prioliste: Leryssia ist Leryssiá im Raid.“ Wer später in den Raid kommt, wird dann zugeordnet. Das gilt auch für den Priocheck und für Namen in Befehlen wie `/pm vergabe Name`. Der exakte Name gewinnt. Passen zwei Spieler im Raid zum selben Namen ohne Akzente und keiner exakt, ordnet das Addon niemanden zu.

## Wartelisten

Für einzelne Items führt die Raidleitung auf priomeister.de geordnete Wartelisten, etwa für die Reittiere aus Zul'Gurub oder die Bindungen des Windsuchers. Sie kommen mit der Prioliste ins Addon, in der Kommentarzeile als `wartelisten=19902:John,Mike,Sara`. Beim Import und unter `/pm stand` stehen sie im Chat.

- Der erste Anwesende der Liste ist dran und schlägt jede Prio, auch Prio 0. Fehlt John, ist Mike dran.
- Die Ansage nennt nur diesen Namen, etwa „[Item] – Warteliste: Mike“. Das Panel zeigt die ganze Reihenfolge, Abwesende grau mit „(fehlt)“. „An Mike“ gibt das Item direkt, bei epischen Items nach Rückfrage. In der Plündermeister-Liste steht „W“ bei allen von der Liste, grün nur bei dem, der dran ist.
- Wer nicht will, verzichtet mit `/roll 1`, dann ist der Nächste dran. Der Verzicht gilt nur für dieses Exemplar.
- Wer das Item bekommt, fällt für den Rest des Raids von der Liste. Ein zweites Exemplar geht an den Nächsten. Wer das Item weitergibt, steht wieder auf dem alten Platz. Stand dasselbe Item auch auf Prio, ist diese Prio damit erfüllt.
- Ist niemand von der Liste da, gelten die üblichen Regeln: Prio, Würfeln, Plünderhelfer, Schatzmeister.
- Gilt eine Warteliste auf der Seite als Prio 0 (`wartelistenp0=19902`), können ihre Spieler dort keine eigenen Prios wählen. Das Addon nennt sie deshalb nicht unter „Im Raid ohne Prio“.
- **Set vervollständigen:** Bei Sets wie der linken und rechten Bindung (`sets=18563+18564`) rückt nach vorn, wer im Raid schon ein anderes Teil bekommen hat. Davor bleiben nur die, die laut Seite schon vorher ein Teil hatten; sie stehen in der Liste mit Stern.
- Im Export stehen diese Vergaben mit der Art `Warteliste`. Die Seite nimmt die Namen danach von der Liste.

## Rollen und Listen

- **Plünderhelfer** bekommt alles bis zur eingestellten Qualität, was auf keiner Liste steht.
- **Schatzmeister** bekommt nur die Items seiner Liste, etwa Skarabäen und Schlüssel in AQ.
- **Entzauberer** bekommt Items, auf die niemand würfelt. Ist ein Entzauberer bestimmt, hat jedes Rüstungs- oder Waffen-Item im Panel einen Knopf „An Entzauberer“, ganz ohne Würfelrunde. Ab welcher Qualität, stellst du im Reiter Plünderoptionen neben dem Entzauberer ein: nie, ab Grün, ab Blau oder nur Episch, voreingestellt ab Grün. Solange ein anwesender Spieler Prio hat, fehlt der Knopf. Bei epischen Items fragt das Addon vorher nach.
- Listen gibt es je Instanz im Reiter Plünderoptionen, es gilt „Alle Instanzen“ plus die aktuelle Instanz. Items unter „Immer verwürfeln“ werden immer verwürfelt und gehen nie an Plünderhelfer oder Schatzmeister.
- Beute aus einem Behälter in der eigenen Tasche, beim Angeln und aus Kräutern oder Erzadern läuft nicht über den Plündermeister. Das Addon sagt sie nicht an, verteilt nichts und zeigt kein Panel. Boss-Truhen behandelt es wie Leichen.

## Weitergaben

Hat ein Spieler ein Item im Spiel an jemand anderen weitergegeben, klickst du die Vergabe im Reiter Beute mit rechts an und wählst den neuen Besitzer. Eine Weitergabe zählt wie eine neue Vergabe: Hat der Empfänger Prio auf das Item, ist sie erfüllt, sonst sinkt seine Stufe wie nach einem freien Wurf. Beim Geber ist die Prio wieder offen oder seine Stufe kommt zurück. Das geht auch für frühere Raids.

## Priocheck

So siehst du, wer im Raid noch keine Prios eingetragen hat, ohne die Eintragung auf priomeister.de zu schließen: Auf der Spielerseite des Prio-Runs unter „Alle Prios“ auf „Priocheck kopieren“ klicken, unter `/pm import` einfügen und „Prüfen“ wählen. Das Ergebnis steht im Chat und im Reiter Raid. „Im Raid erinnern“ postet die fehlenden Namen mit Link und PIN.

## Export

Der Reiter Beute exportiert alle Vergaben und Würfe als CSV für priomeister.de oder eine Tabelle. Auf priomeister.de fügst du den Export im Prio-Run im Reiter „Vergaben“ ein: die Raidleitung auf der Leitungsseite, der Plündermeister auf der Spielerseite. Spaltennamen und Werte des Exports sind in beiden Sprachen deutsch, weil priomeister.de sie so liest.

„Reset“ rechts neben der Auswahl der Raids löscht nach einer Rückfrage alle gespeicherten Raids, den laufenden und alle früheren, mit Vergaben, Würfelstufen, Wurf-Protokollen und Prioliste. Sie lassen sich danach nicht mehr aus dem Addon exportieren. Einstellungen, Listen und Rollen bleiben. Wer die Daten noch braucht, sichert sie vorher mit „Export alle Raids“.

## Befehle

| Befehl | Wirkung |
|---|---|
| `/pm` | Hauptfenster |
| `/pm import` | Prioliste oder Priocheck einfügen |
| `/pm neu`, `/pm fortsetzen [n]` | neuer Raid, früheren Raid fortsetzen |
| `/pm stand` | Stand der Prioliste |
| `/pm tabelle` | Prio-Tabelle aller Spieler |
| `/pm würfeln [Item]`, `/pm frei [Item]`, `/pm stopp` | Würfelrunde starten oder beenden |
| `/pm stich`, `/pm zufall [Item]` | Stichwurf, zufällig vergeben |
| `/pm stufen [Name N]` | Würfelstufen zeigen oder setzen |
| `/pm vergabe Name [Item]` | Vergabe von Hand eintragen |
| `/pm undo` | letzte Vergabe zurücknehmen |
| `/pm liste`, `/pm export [alle]` | Vergaben im Chat oder als CSV |
| `/pm teilen [gilde\|offiziere\|raid\|gruppe\|Name]` | Vergaben teilen |
| `/pm erinnern`, `/pm check` | Spieler ohne Prio erinnern, Priocheck zeigen |
| `/pm helfer`, `/pm schatzmeister`, `/pm entzauberer Name` | Rollen setzen (`-` leert) |
| `/pm pin Name`, `/pm panel`, `/pm test` | Spieler anheften, Panel ein- und ausblenden, Testmodus |
| `/pm hilfe` | alle Befehle |

Die englischen Befehle (`/pm status`, `/pm remind`, `/pm share guild` …) gehen ebenso.

## Spielversionen

WoW Classic 1.15.9: Realms von Classic Era, Hardcore und Season of Discovery, die alle mit demselben Client laufen. Burning Crusade Classic Anniversary, Mists of Pandaria Classic und Retail werden nicht unterstützt.

## Fehler melden

Bitte über das [Formular auf GitHub](https://github.com/andi79h/PrioMeister/issues/new/choose), auf Deutsch oder Englisch.

## Lizenz

MIT, siehe [LICENSE.txt](https://github.com/andi79h/PrioMeister/blob/main/LICENSE.txt).
