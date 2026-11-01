# PrioMeister 1.30.0 (2026-11-01)

- Take over a raid: when a deputy becomes loot master, their addon asks whether to continue the raid from their copy. With “Take over” they have all awards, roll tiers and the prio list, their previous raid goes to the archive. By hand this works with /pm takeover.
- This makes a change of loot master work, for example after a disconnect or when a character is needed in the raid: the new loot master should be assistant beforehand and have PrioMeister 1.29.0 or newer, then they already have the copy. If it changes back later, the takeover works the same way in the other direction.
- When bringing back the state after a crash, the addon now says that this takes one to two minutes for a large raid.
- Roles, lists and roll rules travel with the backup: loot helper, treasurer, disenchanter, the lists per instance and rules such as “Always roll /roll 100”. After a takeover those of the previous loot master apply, after a crash your own come back. The loot threshold stays up to the raid leader: items below it are looted by players themselves and do not count as awards.
- The backup now whispers players from connected realms with their realm name, so it arrives there reliably as well.
