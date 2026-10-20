# PrioMeister

Master looter helper for World of Warcraft Classic Era (1.15.x). PrioMeister reads a prio list, shows who has prio on the loot in a panel next to the loot window, runs roll rounds with roll tiers and records every award. The interface is available in English and German: it follows the game language, and in the options you can set it to English or German.

Open the main window with `/pm` or a left-click on the minimap button. A right-click on the minimap button shows and hides the panel. The “?” button at the top right of the main window opens the options; the changelog is there too (`/pm changelog`).

## Raid flow

1. **Import the prio list:** on priomeister.de click “Copy for PrioMeister” in your prio run and paste it into `/pm import`. “Import as new raid” resets awards and roll tiers, “Replace list only” keeps them. Lists from sahne-team.de work as well.
2. **Open the loot:** the panel shows every item with its prio holders. With “Announce loot when opened” the raid chat gets the loot and the prios.
3. **Announce / Roll:** with a single prio holder, “To Name” gives them the item directly. With several, “Roll” starts a roll round for the prio holders; without prio it is a free roll. A right-click forces a free roll.
4. **Award:** “To Name (roll)” gives the item to the winner. For epic items the addon asks first. “Award randomly” rolls over all raid members, “To disenchanter” gives it to the disenchanter.
5. **Undo:** “Undo last” in the Awards tab takes back the last entry.

## Rules

- **Roll tiers:** everyone starts with /roll 100. Each free roll win lowers your tier by one (99, 98 …). Prio awards do not change the tier. The Raid tab lists everyone who rolled; plus and minus correct a tier by hand.
- **50 rolls:** /roll 50 for alts or off-specs runs in parallel, ranks behind all normal rolls and never changes a tier.
- **Recipes:** rolled with /roll 100 without tiers, only players with the matching profession should roll. Whether recipes and mounts may be on prio comes with the list from priomeister.de; single items can be allowed as exceptions.
- **Pass:** a prio holder who does not want the item rolls /roll 1. The next prio is up, the prio stays for a later copy.
- **Unusable items:** rolls and prios on items the class cannot use (armor type, weapon type, class restriction) do not count.
- **Ties:** “Tiebreak” lets the tied players roll again with the same tier.

## Roles and lists

- **Loot helper** gets everything up to the chosen quality that is on no list.
- **Treasurer** gets only the items on the treasurer list (e.g. scarabs and keys in AQ).
- **Disenchanter** gets items nobody rolls for. With a disenchanter set, every armor or weapon item in the panel gets a “To disenchanter” button, no roll needed. The minimum quality is set next to the disenchanter in the Loot tab: never, green and up, blue and up or epic only, green and up by default. The button is missing while a present player has prio. For epic items the addon asks first.
- Lists exist per instance (“All instances” plus the current one) in the Loot tab. “Always roll” items are always rolled, never given to loot helper or treasurer.

## Hand-overs

If a player gave an item to someone else in the game, right-click the award in the Awards tab and choose the new owner. A hand-over counts like a new award: the recipient's prio is fulfilled, otherwise their tier drops like after a free roll; the giver's prio opens again or their tier comes back. This works for earlier raids too.

## Priocheck

To see who in the raid has not entered prios yet without closing the sign-up on priomeister.de: click “Copy priocheck” under “All prios” on the player page of the prio run, paste it into `/pm import` and choose “Check”. The result appears in the chat and in the Raid tab; “Remind raid” posts the missing names with the link and PIN.

## Export

The Awards tab exports all awards and rolls as CSV for priomeister.de or a spreadsheet. On priomeister.de, paste it in the “Awards” tab of the prio run: the raid lead on the lead page, the master looter on the player page. The column names and values of the export stay German in both languages, because priomeister.de reads them (e.g. type “Wurf” for rolls, “Weitergabe” for hand-overs).

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

MIT, see [LICENSE.txt](LICENSE.txt).
