# PrioMeister (Deutsch)

Plündermeister-Hilfe für World of Warcraft Classic Era (1.15.x). PrioMeister liest eine Prioliste und zeigt in einem Panel neben dem Beutefenster, wer auf die Beute Prio hat. Es führt Würfelrunden mit Würfelstufen durch und protokolliert jede Vergabe. Die Oberfläche gibt es auf Deutsch und Englisch: Sie folgt der Spielsprache, unter Optionen lässt sie sich fest auf Deutsch oder Englisch stellen.

Das Hauptfenster öffnet `/pm` oder ein Linksklick auf den Minimap-Knopf. Ein Rechtsklick auf den Minimap-Knopf blendet das Panel ein und aus. Der Knopf „?“ oben rechts im Hauptfenster öffnet die Optionen, dort steht auch das Changelog (`/pm changelog`).

## Ablauf im Raid

1. **Prioliste importieren:** Auf priomeister.de im Prio-Run auf „Kopieren für PrioMeister“ klicken und die Liste unter `/pm import` einfügen. „Import als neuer Raid“ setzt Vergaben und Würfelstufen zurück, „Nur Liste ersetzen“ behält sie. Listen von sahne-team.de gehen ebenso.
2. **Beute öffnen:** Das Panel zeigt jedes Item mit seinen Prio-Haltern. Mit „Beute beim Öffnen ansagen, mit Prios“ stehen Beute und Prios im Raidchat.
3. **Ansagen und Würfeln:** Hat nur ein Spieler Prio, gibt „An Name“ ihm das Item direkt. Bei mehreren startet „Würfeln“ eine Würfelrunde für die Prio-Halter, ohne Prio ist es ein freier Wurf. Ein Rechtsklick erzwingt einen freien Wurf.
4. **Vergeben:** „An Name (Wurf)“ gibt das Item dem Gewinner. Bei epischen Items fragt das Addon vorher nach. „Zufällig vergeben“ würfelt über alle Spieler im Raid, „An Entzauberer“ gibt das Item dem Entzauberer.
5. **Zurücknehmen:** „Letzte zurücknehmen“ im Reiter Vergaben nimmt den letzten Eintrag zurück.

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
- **Entzauberer** bekommt Items, auf die niemand würfelt. Ist ein Entzauberer bestimmt, hat jedes Rüstungs- oder Waffen-Item im Panel einen Knopf „An Entzauberer“, ganz ohne Würfelrunde. Ab welcher Qualität, stellst du im Reiter Plündern neben dem Entzauberer ein: nie, ab Grün, ab Blau oder nur Episch, voreingestellt ab Grün. Solange ein anwesender Spieler Prio hat, fehlt der Knopf. Bei epischen Items fragt das Addon vorher nach.
- Listen gibt es je Instanz im Reiter Plündern, es gilt „Alle Instanzen“ plus die aktuelle Instanz. Items unter „Immer verwürfeln“ werden immer verwürfelt und gehen nie an Plünderhelfer oder Schatzmeister.
- Beute aus einem Behälter in der eigenen Tasche, beim Angeln und aus Kräutern oder Erzadern läuft nicht über den Plündermeister. Das Addon sagt sie nicht an, verteilt nichts und zeigt kein Panel. Boss-Truhen behandelt es wie Leichen.

## Weitergaben

Hat ein Spieler ein Item im Spiel an jemand anderen weitergegeben, klickst du die Vergabe im Reiter Vergaben mit rechts an und wählst den neuen Besitzer. Eine Weitergabe zählt wie eine neue Vergabe: Hat der Empfänger Prio auf das Item, ist sie erfüllt, sonst sinkt seine Stufe wie nach einem freien Wurf. Beim Geber ist die Prio wieder offen oder seine Stufe kommt zurück. Das geht auch für frühere Raids.

## Priocheck

So siehst du, wer im Raid noch keine Prios eingetragen hat, ohne die Eintragung auf priomeister.de zu schließen: Auf der Spielerseite des Prio-Runs unter „Alle Prios“ auf „Priocheck kopieren“ klicken, unter `/pm import` einfügen und „Prüfen“ wählen. Das Ergebnis steht im Chat und im Reiter Raid. „Im Raid erinnern“ postet die fehlenden Namen mit Link und PIN.

## Export

Der Reiter Vergaben exportiert alle Vergaben und Würfe als CSV für priomeister.de oder eine Tabelle. Auf priomeister.de fügst du den Export im Prio-Run im Reiter „Vergaben“ ein: die Raidleitung auf der Leitungsseite, der Plündermeister auf der Spielerseite. Spaltennamen und Werte des Exports sind in beiden Sprachen deutsch, weil priomeister.de sie so liest.

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

MIT, siehe [LICENSE.txt](LICENSE.txt).
