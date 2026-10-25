# PrioMeister

*English version: [README.en.md](README.en.md). Das Addon spricht Deutsch und Englisch, die Sprache folgt der Spielsprache und lässt sich unter Optionen fest einstellen.*

Plündermeister-Hilfe für WoW Classic Era (1.15.9). Das Addon liest die Prioliste von priomeister.de (gleiches Format wie sahne-team.de), sortiert die Plündermeister-Liste, prüft Würfelstufen, verteilt Kleinkram automatisch und protokolliert jede Vergabe im Raidchat.

Spieler brauchen das Addon nicht, sie tragen ihre Prios auf priomeister.de ein. Das Addon braucht, wer im Raid plündert. Wie beides zusammenspielt, erklärt die [Hilfe auf priomeister.de](https://priomeister.de/hilfe).

Öffnen: `/pm` oder Linksklick auf den Minimap-Knopf. Rechtsklick auf den Minimap-Knopf blendet das Panel ein und aus. Bringt ein anderes Addon die Bibliothek LibDBIcon mit, etwa SexyMap, nutzt PrioMeister sie für den Knopf. Minimap-Addons ordnen ihn dann wie die anderen am Rand an. Der Knopf „?“ oben rechts im Hauptfenster öffnet die Optionen, dort zeigt „Changelog“ alle Versionen mit ihren Änderungen, ebenso `/pm changelog`.

## Ablauf im Raid

1. Auf priomeister.de im Prio-Run unter „Für PrioMeister“ auf „Kopieren“ klicken, dann im Hauptfenster unter **Raid** auf „Importieren …“ klicken und die Liste einfügen. Eine CSV von sahne-team.de geht ebenso. „Import als neuer Raid“ setzt Vergaben und Würfelstufen zurück, „Nur Liste ersetzen“ behält sie. Ist schon eine Liste geladen, steht sie markiert als CSV im Feld, eine neue CSV einfügen ersetzt sie.
   Nach dem Import erscheint 20 Sekunden lang die **Prio-Tabelle** wie bei Prio3: pro Spieler eine Zeile mit Prio 1 bis 3, erhaltene Prios grün, ignorierte orange. Hältst du die Maus darüber, bleibt sie offen. Der Knopf „Anzeigen“ unter **Raid** oder `/pm tabelle` öffnet sie jederzeit.
2. Unter **Raid** stehen Spieler ohne Prio. „Im Raid erinnern“ bittet sie im Raidchat, Prios einzutragen. Kommt später jemand ohne Prio dazu, erscheint ein Hinweis im Chat.
3. Oben im Panel bestimmst du **Plünderhelfer** (PH), **Schatzmeister** (SM) und **Entzauberer** (DE) über eine Namensauswahl. Eine Person darf mehrere Rollen haben.
4. Beim Plündern sagt das Addon im Raidchat an, was in der Beute liegt, samt Prios der anwesenden Spieler. Öffnest du dieselbe Beute erneut, wartet es mit der nächsten Ansage die eingestellte Zeit ab, 0 bis 600 Sekunden.
5. Rechts neben dem Plünderfenster erscheint das Panel. Pro Item steht dort, wer Prio hat, wer fehlt und wer schon etwas bekommen hat (orange `+1`).
6. **Ansagen** nennt den einzigen Prio-Halter, darunter gibt **An Name** ihm das Item direkt, bei epischen Items nach Rückfrage wie bei „An Name (Wurf)“. **Würfeln** startet die Würfelrunde und sagt sie an. Rechtsklick startet einen freien Wurf, auch wenn jemand Prio hat. Die Würfe stehen unten im Panel, bis das Item vergeben ist. Darunter gibt „An Name (Wurf)“ das Item dem Gewinner, bei mehreren Exemplaren dem nächsten. Bei epischen Items fragt das Addon vorher nach, wie Blizzards Plündermeister-Liste, abschaltbar unter **Optionen**. „Beenden“ schließt die Runde: Neue Würfe zählen nicht mehr, die bisherigen bleiben gültig, und das Item lässt sich weiter an den Gewinner oder den Entzauberer geben.
7. **Zufällig vergeben** würfelt 1 bis Anzahl der Spieler im Raid und gibt das Item dem Spieler auf diesem Platz, gezählt wie im Raidfenster durch die Gruppen 1 bis 8. Gedacht ist das etwa für Teile von Kartensets. Im Chat steht dann „zufällig vergeben“ mit dem Platz. Hat ein anwesender Spieler Prio auf das Item oder wurde dafür schon gewürfelt, fragt das Addon vorher „Sicher?“ und nennt Prio-Halter und Würfe.
8. Würfelt niemand, gibt „An Entzauberer“ das Item an den Entzauberer. Hat schon jemand gewürfelt oder ist es eine Prio-Runde, fragt das Addon vorher nach und nennt die Würfe. Ohne Würfelrunde geht es auch: Ist ein Entzauberer bestimmt, steht „An Entzauberer“ an jedem Item im Panel, bei Rüstung und Waffen ab der Qualität, die du im Reiter **Plündern** neben dem Entzauberer einstellst (nie, ab Grün, ab Blau oder nur Episch, voreingestellt ab Grün). Hat ein anwesender Spieler Prio, fehlt der Knopf. Bei epischen Items fragt das Addon vorher nach.
9. Items unter der Plündergrenze, die auf „Immer verwürfeln“ stehen, erscheinen trotzdem im Panel und in der Ansage. Du plünderst sie selbst und handelst sie an den Gewinner. Die Frage von WoW, ob du ein gebundenes Item aufheben willst, bleibt dabei bestehen, denn das Addon plündert nie selbst. Den Handel trägt das Addon als Vergabe ein, wenn der Empfänger gewürfelt hat, Prio hat, zufällig gezogen oder als Entzauberer gewählt wurde. Behältst du das Item selbst, trägst du es mit `/pm vergabe Name` ein.
10. Jede bestätigte Vergabe steht im Raidchat, damit ein anderer Spieler sie mitschreiben kann, zum Beispiel:
   `Gustl erhält [Ring der Bindung] – freier Wurf 88 (1-100) – würfelt ab jetzt mit /roll 99`

## Vergaben teilen

Im Reiter **Vergaben** wählst du oben den Raid: den aktuellen oder einen früheren. So kannst du die Vergaben auch später noch teilen, wenn schon ein neuer Raid läuft. Die Auswahl nennt die Instanz, das Addon merkt sie sich seit Version 1.11 bei jeder Vergabe. Items in der Liste sind klickbar wie im Chat: Maus darüber zeigt das Item, Shift-Klick verlinkt es. Das gilt überall, wo Items farbig stehen, auch in den Listen unter **Plündern** und bei Rezepten und Reittieren im Reiter **Raid**.

Unten wählst du bei „Teilen in“ den Kanal: Gilde, Offiziere, Schlachtzug, Gruppe oder Flüstern an einen Namen. „Teilen“ postet die Vergaben Zeile für Zeile, eine pro halbe Sekunde. Eigene Gewinne stehen einzeln da, Vergaben an Plünderhelfer, Schatzmeister und Entzauberer gebündelt je Spieler. „Sagen“ und öffentliche Kanäle gehen nicht, dafür verlangt WoW bei jeder Zeile einen Tastendruck.

## Export und Wurf-Protokoll

„Export (CSV)“ im Reiter **Vergaben**, „Export alle Raids“ und `/pm export` liefern das komplette Protokoll eines Raids, nach der Zeit sortiert: jede Vergabe, auch an Schatzmeister, Plünderhelfer und Entzauberer, jeden Verzicht, jede Korrektur der Würfelstufe und jeden Wurf in einer Würfelrunde, auch ungültige. Das Wurf-Protokoll bleibt beim Archivieren erhalten, für die letzten zehn Raids im Archiv, höchstens 3000 Würfe je Raid.

Spalten, getrennt durch Semikolon:

| Spalte | Inhalt |
|---|---|
| Datum, Uhrzeit | Zeitpunkt, `16.10.2026` und `21:17` |
| Spieler, ItemID, Item | wer, welches Item |
| Art | bei Vergaben wie in der Vergabeliste: Prio, Warteliste, freier Wurf, 50er-Wurf, Rezept-Wurf, Wurf ohne Stufen, zufällig vergeben, ohne Wurf, Entzauberer, Plünderhelfer, Schatzmeister, Verzicht, Würfelstufe von Hand, Weitergabe; bei Würfen immer `Wurf` |
| Prio | Prio-Stufe der Vergabe bzw. der Prio-Runde |
| Wurf, Bereich | Wert und Bereich, etwa `87` und `1-100`; bei „zufällig vergeben“ Platz und Anzahl |
| Stichwurf | bei Vergaben die Stichwürfe, bei Würfen die Nummer der Stichwurf-Runde |
| Runde | Nummer der Würfelrunde im Raid, verbindet Würfe und Vergabe |
| Rundenart | bei Würfen: Prio, Warteliste, freier Wurf, Wurf ohne Stufen oder Rezept-Wurf |
| Status, Grund | bei Würfen: zählt, falscher Bereich, doppelt, zählt nicht, nicht tragbar, verzichtet oder zurückgezogen (Wurf vor einem Verzicht mit /roll 1), dazu der Grund; bei Vergaben `weitergegeben` mit `an Name`, bei Weitergaben `von Name` |
| Instanz | Name der Instanz, sofern bekannt |
| Raid | Beginn des Raids, `16.10.2026 19:06` |
| Zeitstempel | Sekunden seit 1970, für die genaue Reihenfolge |

Auf priomeister.de fügst du den Export im Prio-Run im Reiter „Vergaben“ ein. Das darf die Raidleitung auf ihrer Leitungsseite und der Plündermeister auf der Spielerseite.

Die ersten zehn Spalten sind dieselben wie vor Version 1.17. Wer nur sie liest, bekommt die Vergaben wie bisher und überspringt die Würfe an der Art `Wurf`.

## Raid fortsetzen

Einen früheren Raid machst du wieder zum laufenden Raid, etwa nach einem versehentlichen „Neuer Raid“ oder am zweiten Abend. Im Reiter **Vergaben** wählst du ihn oben aus und klickst „Raid fortsetzen“, oder du nutzt `/pm fortsetzen`, ohne Nummer zeigt der Befehl die Liste. Vergaben und Würfelstufen gelten weiter, der laufende Raid kommt ins Archiv und lässt sich genauso wieder fortsetzen.

Der Raid bekommt seine eigene Prioliste zurück, das Archiv speichert sie bei jedem Weg dorthin mit: „Neuer Raid“, `/pm neu`, „Import als neuer Raid“ und beim Fortsetzen eines anderen Raids. Die Rückfrage vor dem Fortsetzen nennt die Liste mit Spielerzahl und Importzeit. Eine neuere Liste importierst du danach mit „Nur Liste ersetzen“. Raids, die vor Version 1.14 ins Archiv kamen, haben ihre Liste nicht gespeichert. Sie starten ohne Liste, du importierst sie mit „Nur Liste ersetzen“. Die Korrekturen der Würfelstufe holt das Addon bei ihnen aus dem Protokoll.

## Priocheck

Wer im Raid noch keine Prios hat, siehst du, ohne die Eintragung auf priomeister.de zu schließen. Die Seite bietet dafür eine Kurzform des Prio-Runs an: wer welche Prios gesetzt hat, ohne Items. Der Knopf „Priocheck kopieren“ steht auf der Spielerseite des Prio-Runs im Reiter „Alle Prios“, für alle sichtbar. Du fügst den Priocheck unter „Importieren …“ ein, das Fenster erkennt sie und zeigt statt der Import-Knöpfe „Prüfen“. Die Prioliste, Vergaben und Würfelstufen bleiben, wie sie sind.

Das Ergebnis steht im Chat und im Reiter **Raid** unter „Im Raid ohne Prio“: wer ohne Prios ist, wer unvollständig ist und was fehlt, etwa „Onyxias Hort fehlt, Zul'Gurub ohne Prio 2 und 3“, und wie viele vollständig sind. Die Maus über dem Bereich zeigt alles. „Im Raid erinnern“ und `/pm erinnern` nennen die Spieler ohne Prios mit Link und PIN, `/pm check` zeigt das Ergebnis erneut, auch nachdem neue Spieler in den Raid gekommen sind. Der Priocheck gilt, bis du eine neuere Prioliste importierst.

## Weitergaben

Hat ein Spieler ein Item im Spiel an einen anderen gegeben, ohne dich, trägst du das nach: Rechtsklick auf die Vergabe im Reiter **Vergaben**, dann den neuen Besitzer wählen oder eintippen. Die Rückfrage nennt die Folgen für Prio und Würfelstufe. Das geht auch in früheren Raids, ohne sie fortzusetzen. Im laufenden Raid steht die Weitergabe im Raidchat, wenn Vergaben dort gepostet werden.

Eine Weitergabe zählt wie eine neue Vergabe an den Empfänger. Hat er Prio auf das Item, ist sie erfüllt, sonst sinkt seine Würfelstufe wie nach einem freien Wurf. Die Vergabe des Gebers zählt nicht mehr: Seine Prio ist wieder offen, ein freier Wurfsieg gibt ihm die Stufe zurück. Items aus 50er-Würfen, Rezept-Würfen und Würfen ohne Stufen ändern keine Stufe. Auch Items von Entzauberer, Plünderhelfer und Schatzmeister lassen sich so weitergeben, etwa nach einem Fehlklick.

„Letzte zurücknehmen“ hebt eine gerade eingetragene Weitergabe auf. Eine ältere nimmst du per Rechtsklick auf die Weitergabe zurück, solange der Empfänger das Item nicht selbst weitergegeben hat. Im Export steht der Geber mit dem Status `weitergegeben` und dem Grund `an Name`, der Empfänger mit der Art `Weitergabe` und dem Grund `von Name`, eine Sekunde nach der Vergabe davor.

## Regeln

- Prio 0 schlägt Prio 1, Prio 1 schlägt Prio 2, Prio 2 schlägt Prio 3. Prio 0 heißt dasselbe Item auf Prio 1, 2 und 3.
- Mehrere Halter auf derselben Stufe würfeln mit `/roll 100`. Das ändert keine Würfelstufe.
- **Verzicht:** Wer Prio hat und das Item nicht will, würfelt `/roll 1`. Das gilt nur für dieses Exemplar, die Prio bleibt für ein späteres. Danach ist die nächste Prio dran oder es gibt einen Wurf ohne Prio. Im Raidchat steht, wer verzichtet und wer jetzt Prio hat, im Panel steht er als „verzichtet“. Das geht direkt nach der Beute-Ansage, auch ohne Würfelrunde und noch ein paar Minuten nach dem Schließen der Beute. Hat jemand auf mehrere Items derselben Beute Prio, gilt `/roll 1` dem Item, das gerade angesagt oder verwürfelt wird. Sonst fragt das Addon im eigenen Chat nach. In einer Runde ohne Prio zieht `/roll 1` den eigenen Wurf zurück, ein Wurf von 1 (1-1) zählt nie als normaler Wurf. Verzichte stehen in der Vergabeliste, im Export und beim Teilen, zählen aber nicht als Vergabe. „Letzte zurücknehmen“ hebt einen versehentlichen Verzicht auf.
- Ohne Prio gibt es einen freien Wurf. Jeder freie Gewinn senkt die eigene Stufe um eins: 100, dann 99, dann 98. Ein 100er-Wurf schlägt jeden 99er-Wurf.
- **50er-Würfe** sind für Zweitchar oder Zweitskillung. Sie laufen parallel, liegen hinter allen normalen Würfen und ändern keine Stufe. Die Würfelaufrufe nennen sie nicht, die Regel kennen alle.
- **Rezepte** werden mit `/roll 100` ohne Stufen verwürfelt, nur Spieler mit passendem Beruf sollen würfeln. Ein Rezept-Gewinn ändert keine Stufe.
- Items auf der Liste **Immer verwürfeln** gehen ohne Prio in einen **Wurf ohne Stufen**: Alle würfeln mit `/roll 100`, ein Gewinn senkt keine Stufe.
- Liegen mehrere gleiche Items in der Beute, gewinnen die entsprechend vielen höchsten Würfe. Bei zwei Exemplaren und 90, 90, 80 bekommen beide 90er eins, ein Stichwurf ist nur an der Grenze nötig.
- Klassenbücher wie „Foliant des Frostblitzes XI“ zählen nicht als Rezept. Prio auf ein Klassenbuch gilt.
- Rezepte und Reittiere auf Prio werden standardmäßig ignoriert, beides lässt sich unter **Optionen** erlauben. Beim Import meldet das Addon, wer ein Rezept oder Reittier auf Prio hat. Ein Reittier ohne gültige Prio geht in den freien Wurf.
- Eine Liste von priomeister.de endet mit einer Kommentarzeile (`# PrioMeister: rezepte=wuerfeln; reittiere=prio; spieler=…; prios=…; stand=…; run=…; link=…`). Daraus übernimmt das Addon beim Import, ob Rezepte und Reittiere in diesem Prio-Run auf Prio dürfen, und merkt sich Stand und Link. Seit 1.19 kann die Zeile `ausnahmen=18259,18260` enthalten: Diese Items stehen auf der Positivliste des Prio-Runs, Prios darauf zählen auch dann, wenn Rezepte oder Reittiere sonst gewürfelt werden. Die Meldung beim Import und `/pm stand` nennen sie. `/pm stand` und der Tooltip über „Prioliste“ im Reiter **Raid** zeigen Spieler, Prios, die letzte Änderung auf der Seite und den Link; „Im Raid erinnern“ nennt den Link samt PIN.
- Wer mit falscher Stufe würfelt, wird im Raidchat darauf hingewiesen. Ein Neuwurf mit der richtigen Stufe zählt.
- Würfe auf Items, die der Spieler nicht tragen kann, zählen nicht: Rüstung, die seine Klasse nicht tragen kann, etwa ein Magier auf Platte, Waffen, die sie in Classic nicht führen kann, Waffen nur für die Schildhand ohne beidhändigen Kampf und Items, die laut Tooltip nur für andere Klassen sind. Das Panel nennt den Grund, im Raidchat steht ein Hinweis. 50er-Würfe zählen trotzdem, sie können für einen Zweitchar sein. Auch eine Prio gilt nur, wenn der Spieler das Item tragen kann, sonst ist die nächste Prio dran; im Panel steht er als „nicht tragbar“. Abschaltbar unter **Optionen**.
- Änderst du eine Würfelstufe von Hand, mit Plus oder Minus im Reiter **Raid** oder mit `/pm stufen Name 2`, steht das mit Uhrzeit in der Vergabeliste, im CSV-Export und beim Teilen. Im Reiter **Raid** stehen alle, die in diesem Raid gewürfelt haben, auch mit 100 und auch, wenn ihr Wurf erst nach dem Ende der Runde kam. So senkst du etwa nach einer Vergabe aus Kulanz die Stufe mit Plus. Außerdem geht es in den Raidchat, abschaltbar unter **Optionen**. „Letzte zurücknehmen“ macht auch so eine Änderung rückgängig und meldet das ebenfalls im Raidchat.
- Bei **Gleichstand** an der Spitze erscheint im Panel der Knopf „Stichwurf“. Die Gleichplatzierten stechen mit derselben Stufe wie beim ersten Wurf, alle anderen Würfe zählen dann nicht. Steht es wieder gleich, folgt ein weiterer Stichwurf. Das Protokoll nennt beide Würfe, die Stufe sinkt nur einmal.
- Ein Wurf zählt nur für das Exemplar, für das gewürfelt wurde. Das Addon erkennt die Beute an ihrer Leiche oder Truhe.
- Steht ein Spieler doppelt auf der Liste, gilt der letzte Stand mit den meisten Items.
- **Namen ohne Akzente:** Das Addon vergleicht Namen wie priomeister.de ohne Akzente. Steht auf der Liste „Leryssia“ und heißt der Charakter im Spiel „Leryssiá“, gilt der Eintrag für diesen Charakter. Im Chat steht dann einmal „Prioliste: Leryssia ist Leryssiá im Raid.“ Kommt jemand erst später in den Raid, ordnet das Addon den Eintrag dann zu. Das gilt auch für den Priocheck und für Namen in Befehlen wie `/pm vergabe Name` oder `/pm stufen Name 2`. Der exakte Name gewinnt. Passen zwei Spieler im Raid zum selben Namen ohne Akzente und keiner exakt, ordnet das Addon niemanden zu. Gespeicherte Vergaben, Würfelstufen und Würfe bleiben, wie sie sind.
- Ein erhaltenes Prio-Item verbraucht genau diese Prio. Onyxias Kopf, Nefarians Kopf, Herz von Hakkar und Ossirians Kopf zählen zusammen mit ihren Quest-Belohnungen als ein Item.
- Vergaben an Plünderhelfer, Schatzmeister und Entzauberer zählen nicht als eigener Gewinn und ändern keine Stufe.

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

## Plündern

Im Reiter **Plündern** des Hauptfensters:

- **Plündermeister und Grenze:** Das Dropdown „Plündergrenze“ setzt bei Bedarf zuerst dich oder den gewählten Spieler als Plündermeister und danach die Grenze, von Grau bis Episch. Grau und Weiß gehen nur hier, nicht über Blizzards Menü. Das geht nur als Gruppen- bzw. Schlachtzugsleitung.
- **Plünderhelfer:** Für Grau, Weiß, Grün und Blau gibt es je einen Ja/Nein-Knopf. Der Plünderhelfer bekommt automatisch alle Items der Qualitäten mit „ja“, die auf keiner Liste stehen. So gehen zum Beispiel nur weiße Items an ihn.
- **Schatzmeister:** bekommt automatisch nur die Items seiner Liste, etwa die weißen Schlüssel für die Skarabäuskästen in AQ. Ist kein Schatzmeister bestimmt, bleiben diese Items liegen und das Addon weist einmal darauf hin.
- **Listen je Instanz:** Links wählst du die Instanz, oben rechts die Liste: **Schatzmeister** oder **Immer verwürfeln**. Es gilt jeweils „Alle Instanzen“ plus die Liste der Instanz, in der du gerade bist. Items fügst du per Shift-Klick ins Feld, per Ziehen oder per Item-ID hinzu. „Liste leeren“ fragt vorher nach.
- **Vorbelegt beim Schatzmeister:** AQ20 und AQ40 mit den Skarabäen und den Kastenschlüsseln, AQ20 zusätzlich mit allen 27 Klassenbüchern, Zul'Gurub mit der Blutrebe und den neun Schmuckstücken der Hakkari.
- **Vorbelegt unter „Immer verwürfeln“:** Zul'Gurub mit Gri'leks Blut, Renatakis Zahn, Wushoolays Mähne und Hazza'rahs Traumfaden.
- **Immer verwürfeln:** Diese Items gehen nie automatisch an Plünderhelfer oder Schatzmeister. Sie stehen immer im Panel und in der Beute-Ansage, auch unter der Plündergrenze. Mit Prio gehen sie an den Prio-Halter, sonst gibt es einen Wurf ohne Stufen.
- Items mit Prio werden nie automatisch verteilt. Wer beim Öffnen der Beute Shift hält, verteilt nichts automatisch.
- Beute aus einem Behälter in der eigenen Tasche, beim Angeln und aus Kräutern oder Erzadern läuft nicht über den Plündermeister. Das Addon sagt sie nicht an, verteilt nichts und zeigt kein Panel. Boss-Truhen behandelt es wie Leichen.
- Vergaben an Plünderhelfer und Schatzmeister stehen gesammelt in einer Zeile im Chat. Graue und weiße Items an den Plünderhelfer erscheinen dort nur mit dem passenden Häkchen unter **Optionen**. Vergaben an den Schatzmeister stehen immer im eigenen Chatfenster, im Raidchat nur mit dem Häkchen „Vergaben an den Schatzmeister im Raidchat melden“ (Standard aus).

## Plündermeister-Liste

- Plünderhelfer, Schatzmeister, Entzauberer und angeheftete Spieler stehen oben, alle anderen alphabetisch.
- Prio-Halter des Items sind grün mit `P1` markiert, die Rollen mit `PH`, `SM` und `DE`.
- Der Tooltip eines Namens zeigt Prios, Würfelstufe und bisher erhaltene Items.

## Optionen

Unter **Optionen**, hinter dem Knopf „?“ oben rechts, stehen die Häkchen nach Themen, jedes erklärt sich im Tooltip. Ganz oben schaltet „Addon aktiv“ alles ab.

- **Im Chat posten:** Beute-Ansage beim Öffnen samt Wartezeit für dieselbe Beute, Vergaben für das Protokoll, Vergaben an den Schatzmeister, graue und weiße Items an den Plünderhelfer, Hinweise zu Würfelstufen und bei falschem Wurf, Würfelstufe von Hand geändert, Würfelaufrufe als Schlachtzugswarnung.
- **Würfeln und Prio:** 50er-Würfe, Rezept-Würfe, Rezepte und Reittiere auf Prio, Prio 0 schon bei Prio 1 und 2, Rückfrage vor Epics an den Gewinner.
- **Anzeige:** Plündermeister-Liste sortieren, Panel auch ohne Plündermeister-Rolle, Prio-Tabelle nach dem Import, Minimap-Knopf.

Darunter legst du die angehefteten Spieler fest.

## Befehle

| Befehl | Wirkung |
|---|---|
| `/pm` | Hauptfenster |
| `/pm hilfe` | alle Befehle |
| `/pm import`, `/pm neu` | Prioliste einfügen bzw. als CSV ansehen, neuer Raid |
| `/pm tabelle` | Prio-Tabelle aller Spieler |
| `/pm stand` | Stand der Prioliste: Spieler, Prios, letzte Änderung und Link zum Prio-Run |
| `/pm liste`, `/pm export` | Vergaben im Chat bzw. als CSV |
| `/pm teilen` | Vergaben teilen, ohne Angabe im gewählten Kanal; `/pm teilen gilde`, `offiziere`, `raid`, `gruppe` oder ein Name zum Flüstern |
| `/pm undo` | letzte Vergabe zurücknehmen |
| `/pm vergabe Name [Item]` | Vergabe von Hand eintragen, etwa nach einem Handel |
| `/pm prio Name` oder `/pm prio [Item]` | Prios nachsehen |
| `/pm stufen` | Würfelstufen, `/pm stufen Name 2` setzt zwei freie Gewinne |
| `/pm stich` | Stichwurf bei Gleichstand an der Spitze |
| `/pm zufall [Item]` | Item zufällig vergeben |
| `/pm erinnern` | Spieler ohne Prio im Raid erinnern |
| `/pm helfer Name`, `/pm schatzmeister Name`, `/pm entzauberer Name` | Rollen setzen, `-` leert |
| `/pm test` | Testmodus ohne Raid, dazu `/pm testwurf Name 87 99` und `/pm vergabe Name` |

## Spielversionen

WoW Classic 1.15.9: Realms von Classic Era, Hardcore und Season of Discovery, sie laufen alle mit demselben Client. Burning Crusade Classic Anniversary, Mists of Pandaria Classic und Retail unterstützt PrioMeister nicht.

## Fehler melden

Über das [Formular auf GitHub](https://github.com/andi79h/PrioMeister/issues/new/choose), auf Deutsch oder Englisch.

## Tests

Die Tests laufen außerhalb des Spiels mit Lua 5.1 und einer Nachbildung der Classic-Era-Schnittstellen:

```bash
lua5.1 tests/run_tests.lua
```

GitHub führt sie bei jedem Push und Pull Request aus.

## Veröffentlichen

Veröffentlicht wird über GitHub, von Hand muss niemand eine Zip bauen:

1. Version in `PrioMeister/PrioMeister.toc` und `PrioMeister/Core.lua` erhöhen, oben im Changelog in `PrioMeister/Main.lua` einen Eintrag ergänzen und seine englische Fassung in `PrioMeister/Locale.lua`.
2. `lua5.1 scripts/changelog.lua > CHANGELOG.md` erzeugt die englischen Release-Notizen. Die Tests prüfen, dass die Datei aktuell ist.
3. Pull Request nach `main` mergen. Hat die Version noch keinen Tag, setzt GitHub den Tag `v<Version>`, baut die Zip mit dem [BigWigs-Packager](https://github.com/BigWigsMods/packager) (Einstellungen in `.pkgmeta`) und veröffentlicht sie als GitHub-Release und auf CurseForge.

Die Beschreibung auf CurseForge ändert das Release nicht. Sie steht fertig zum Einfügen in `curseforge/beschreibung.md`, erst Englisch aus `README.en.md`, dann Deutsch aus `curseforge/beschreibung.de.md`. Nach einer Änderung an einer der beiden Dateien `lua5.1 scripts/curseforge.lua > curseforge/beschreibung.md` ausführen und den Inhalt im CurseForge-Projekt unter Description ersetzen. Die Tests prüfen, dass die Datei aktuell ist.

Das CurseForge-Projekt 1755238 steht in der TOC (`## X-Curse-Project-ID`). Hochladen kann der Lauf, sobald das Repo das Secret `CF_API_TOKEN` mit einem [CurseForge-API-Schlüssel](https://authors.curseforge.com/#/settings/api-tokens) hat. Ohne Schlüssel überspringt er CurseForge, das GitHub-Release entsteht trotzdem.

## Lizenz

MIT, siehe [LICENSE.txt](LICENSE.txt). Jeder darf das Addon nutzen, ändern und weitergeben, solange der Copyright-Hinweis erhalten bleibt.
