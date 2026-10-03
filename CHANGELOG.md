# RazagathWoW - Changelog

The launcher reads the machine-readable copy of this from `manifest.json`
(`changelog[]`). Keep the newest entry at the top; keep notes short and player-facing.

---

## 2026.10.03 - Goblins and Worgen

- New playable race: Goblin (Horde) - Rocket Barrage, Rocket Jump, Time is Money, Best Deals Anywhere, Better Living Through Chemistry and Pack Hobgoblin racials, with retail voices, names and customisation
- New playable race: Worgen (Alliance, worgen form) - Viciousness, Aberration, Flayer, Darkflight and Running Wild racials, with retail names and customisation
- Every Horde race is now friendly with every Horde starting zone and every Alliance race with every Alliance starting zone, and racial starter quests are open to all races of your faction - level wherever you like
- Launcher 1.6.7 re-patches Wow.exe for the extra races - run the launcher once before playing
- Not yet available: the Worgen human form (Two Forms)

## 2026.10.02c - Retail parity: character creation

- Retail parity: the character creation screen now matches modern retail - round race and class icons, gender buttons, a customise page with Head, Mirror and Accessories tabs, and the name box at the top
- Races and classes that are not implemented on this realm are shown grayed out with a Not implemented tooltip
- New: scroll the mouse wheel on the customise page to zoom in on your characters face (each race is framed individually)

## 2026.10.02b - Hotfix: mailbox art

- Fixed the mailbox showing a tall spellbook scroll over the right side of the inbox - the retail spellbook art now uses its own files so the mail window gets its normal art back

## 2026.10.02 - Retail parity: Mounts and Pets window

- Retail parity: new Mounts and Pets window (Collections Journal) with retail layout and art, 3D model preview with zoom and rotate, search, filter, favorites (right-click a mount), Mount/Dismount button and drag to action bars
- Retail parity: open it from the new micro menu button at the bottom right of the screen, the N key, or /mounts and /pets - the old Pets tab on the Character panel is hidden
- Change: Spell Blade UI, big bag support and the new window are now one Razagath addon - the old addon folders are removed automatically on update

## 2026.09.30b - Fix Spellblade grimoire icons

- Fixed Journeyman and Master Spellblades Grimoire showing a broken/question-mark icon (custom icon records were dropped from a prior client patch pass)

## 2026.09.30 - Eternal Recipes expansion + Eternal Cooking

- Eternal Recipes: expanded from 5 to 121 discoverable Alchemy recipes
- Eternal Minor Buff Potion now requires all 6 recipes (added Eternal Elixir of Minor Agility)
- New: Eternal Cooking - 75 discoverable infinite-use foods (1hr Well Fed buffs)
- All eternal recipe cooldowns dropped to 30 minutes
- Eternal discovery rates finalized to their intended long-term value

## 2026.09.29b - Eternal Recipes & Mounted Gathering

- New: Eternal Recipes - crafting Elixir of Lion's Strength, Minor Fortitude, Wisdom, Minor Defense, or Weak Troll's Blood Elixir has a small chance to teach you a permanent, infinite-use Eternal version with a boosted effect
- New: once you've learned all 5 Eternal recipes, craft the Eternal Minor Buff Potion to apply all 5 buffs at once
- New: Mounted Gathering - a Prestige Master perk that lets you gather herbs, ore, and skins while mounted
- Change: Razagath Utility Page renamed to Razagath Utility Tome and upgraded to Heirloom quality with a new icon

## 2026.09.29 - Race unlocks, new mount, dungeon-clear autopilot

- New: Celestial Dragon Wyrm flying mount (Reins of the Celestial Dragon Wyrm)
- New: many more race/class combos unlocked - Human/Dwarf/Night Elf Shaman, Undead Paladin, Gnome Priest, and 18 more (see the Guide NPC for the full list)
- New: flying mounts now work on every continent, not just Outland/Northrend (grounded, not blocked, inside the 8 capital cities)
- New: oversized bags (Razagath Satchel/Rucksack/Pack/Trunk)
- New: Razagath Guide NPC with an intro quest covering the server's custom systems
- New: dungeon and raid attunement quests/keys are now auto-completed for everyone, bots included - no more farming old quest chains just to zone in
- New: dungeon-clear bots now start clearing automatically once you and a tank are both inside - no more typing .dc on
- Fix: Horde and Alliance bots can now understand each other's open-world chat
- Fix: Spectral Wolf mount rarity corrected to Rare (blue); Celestial Dragon Wyrm corrected to Epic (purple)
- Fix: Shaman totems no longer show as a placeholder cube for Human, Night Elf, Undead, Gnome, or Blood Elf characters
- Fix: every character now has full cross-faction language comprehension (previously only applied to brand-new characters)
- Fix: Spell Blade duplicate starting gear
- Fix: Stormwind Trade District guards now direct you to the Spell Blade trainer

## 2026.09.21 - Spellblade BC-leveling fix

- Fixed a flat damage/healing/absorb dead-zone at levels 57-70 across Spellblade Strike, Arcane Ignition, Spellblades' Presence, Aegis, Holy Restore, and Mending Light
- Each of those abilities gained a new intermediate rank (levels 58-63) plus continuous scaling within every rank, so power now ramps smoothly through the BC leveling range instead of sitting flat for 8-12 levels
- Battleplate of the Fractured Sigil (the Spellblade's top-tier armor set) now drops from working Icecrown Citadel 10-player Heroic bosses (Lord Marrowgar through the Lich King) instead of a broken boss list that had no functioning drop source

## 2026.09.20 - New Classes, Flying Mounts Everywhere & Prestige Overhaul

- New playable race/class combos: Human Hunter; Orc Paladin, Priest, Druid, Mage; Dwarf Spellblade, Druid, Warlock; Night Elf Warlock, Mage, Paladin; Undead Hunter, Druid; Tauren Mage, Paladin, Priest, Spellblade, Warlock
- Fixed missing starting weapon proficiency, missing Utility Page, and duplicate starter gear on several race/class combos
- Flying mounts now work on every continent, not just Outland/Northrend - grounded to ground speed inside the 8 racial capital cities
- Added the Razagath Members Amulet as a reward from Scott Knight's welcome quest, alongside the guidebook
- City guards in all 8 capitals now give directions to the Spellblade trainer, same as the other classes
- 4 new oversized bags: Razagath Satchel (16 slot), Rucksack (22 slot), Pack (30 slot), and Trunk (36 slot)
- New characters now start with Green Woolen Bags instead of Traveler's Backpacks
- Prestige Master: new Bag Upgrade perk - 4 tiers, grants the new bags and auto-swaps out smaller empty bags
- Prestige Master: new Global Cooldown Reduction stat
- Prestige points per prestige increased to 15, with a one-time retroactive catch-up on 'Reset my allocation' for characters who prestiged before the increase
- Prestige stat costs reworked: ranks now cost the same in pairs before stepping up in price, instead of increasing every single rank

## 2026.09.17 - Spellblade balance + Aegis + new talents

- Arcane Bloom rebalanced: damage/heal significantly increased at ranks 1-6 (rank 7/level 80 unchanged), and a hidden mana-cost bug fixed - it was silently costing 35% of your mana pool on top of the listed number. Rank 7 is now a clean 600 mana, with lower ranks scaled down from that.
- Aegis now also grants immunity to stuns for its duration, not just a damage shield.
- Three new talents, one per tree (Battle Focus/Serene Mind/Arcane Economy): up to 10% reduced mana cost for that tree's spells.
- New Arcane talent: Arcane Contagion - your Arcane spells have up to a 10% chance per enemy hit to apply Arcane Wound.
- Spellblade talent point pacing increased slightly (now averages 1.2 points per level instead of 1).

## 2026.09.16b - Arcane Bloom balance fix

- Arcane Bloom (ranks 1-6): damage and heal significantly increased - the original numbers were undertuned for leveling/dungeon content and felt weak below level 80. Rank 7 (level 80) is unchanged.

## 2026.09.16 - Arcane Bloom (Spellblade)

- New Spellblade spell: Arcane Bloom (Arcane tree, trained from Vaeryn at level 25, 7 ranks up to level 80) - an instant, minimal-cooldown burst that deals Arcane damage to all enemies within 10 yards and heals you plus up to 3 injured allies in range.
- New talent: Volatile Bloom (Arcane tree) - increases Arcane Bloom's damage by up to 10% at 5/5.
- Arcane Bloom's mana cost reduced by roughly 40% across all ranks.

## 2026.09.10b - Journeyman Grimoire

- New Spellblade off-hand from Instructor Vaeryn: Journeyman Spellblades Grimoire (level 40), filling the gap between Adept and Apprentice.
- Journeyman and Master grimoires now use distinct book models.

## 2026.09.10 - Spellblade utility kit

- New Spellblade trainer abilities: Dispel Magic, Cure Poison, Cure Disease and Remove Curse.
- New Spellblade trainer abilities: Disrupting Cut (spell interrupt) and Pommel Bash (5 sec stun).

## 2026.09.09c - Spectral Wolf prestige reward

- Prestige reward: the first time a character prestiges it now also learns the Spectral Wolf - a ghostly ground mount usable at any riding skill - alongside its first title. Characters already prestiged get it on next login.
- The Spectral Wolf mount is ground-only now (a running wolf looked wrong in the air) and renders at normal size.
- Removed the oversized, loud daily-dungeon boss hologram that hovered near Archmage Lan'dalock in Dalaran.

## 2026.09.09b - 4 GB client + Spectral Wolf mount

- Fixes the out-of-memory crashes in Dalaran and other busy zones with the HD graphics patches - the game client can now use 4 GB of memory instead of 2 GB. Fully close and reopen WoW once after this update so the new client takes effect.
- New epic mount: Reins of the Spectral Wolf. A ghostly worg usable at any riding skill (no training or gold needed) that also flies where flying is permitted - Outland always, Northrend with Cold Weather Flying.

## 2026.09.09 - Prestige heirlooms, display badges & XP scaling

- New "Prestige" and "XP Rate" buffs - other players can see your prestige tier and current XP rate at a glance.
- The Prestige Master now sells heirlooms. Spend prestige points to unlock, then buy them from the "Allocate prestige points" menu.
- New heirloom slots that never existed in 3.3.5: head, legs, cloak, neck, rings and off-hands, plus extra weapon types - retail models and icons where possible.
- Heirlooms moved off the Assistant NPC; the Prestige Master is the only source now.
- Your personal XP rate now steps down a little with each prestige, reaching 1x at max prestige. 1x and 0.5x Hardmode are unaffected.
- Spellblade (test realm): expanded talent trees - 9 new passive talents, a resurrection spell (Reawaken), a combat battle-rez, an Innervate-style mana cooldown and build-defining capstone talents. All specs can now wear plate.

## 2026.09.07b - Launcher auto sign-in + patch-notes tab

- Launcher: optional auto sign-in - turn it on in Settings and the launcher signs you in and drops you at character select, no WoW login screen
- Launcher: new Launcher tab with its own patch notes, separate from the game changelog
- Launcher: downloads now resume and retry, so the big HD patches survive a dropped connection
- Launcher: app icon now renders correctly at every size
- Client patch refreshed (bundled add-ons, dungeon maps, Spellblade Sundered/Fractured armour reskin, Mental Quickness, Blade Shatter melee fix, Questie compatibility)

## 2026.09.07 - Bundled add-ons + HD patches + Spellblade update

- MogIt, Bagnon and WoW Dungeon Maps are now built in - no add-on install needed. MogIt also lists every custom Spellblade item.
- Classic and Burning Crusade dungeon interior maps now show on the world map.
- The HD graphics patches are delivered by the launcher now (large one-time download, resumable).
- Launcher: interrupted downloads resume where they left off instead of restarting.
- New Spellblade passive, Mental Quickness: spell power equal to 50% of your attack power, so your gear powers melee and casting both.
- New Arcane talent, Sudden Ignition: a chance after Arcane Ignition or Spellblade Strike to make your next Arcane Ignition instant.
- Blade Shatter is now an instant melee strike (was a next-swing ability) and shows the correct melee range.
- Spellblade Strike damage retuned.
- The Fractured and Sundered Sigil plate sets have a new look; Sundered pieces show the green Heroic tag.
- 'of the Viper' gear now drops from classic and vanilla content, as a random suffix on greens and as guaranteed pieces from dungeon bosses.
- Spellblade grimoires show the right icon and equip correctly again.
- A max-geared level 80 sweeps through pre-WotLK dungeons and raids, while WotLK dungeons stay a real fight.
- Questie no longer breaks on the Spellblade class.

## 2026.09.06 - Spellblade armour + Arcane Haste

- Spellblade armour sets - Strength/Intellect/Spirit gear in leather, mail and plate. Blue sets are BoE drops; epic sets come from dungeon and raid bosses; the top plate set is heroic-raid best-in-slot and carries a 4- and 8-piece set bonus (bonus attack power and spell power).
- Green armour can now roll "of the Viper" - Strength, Intellect and Spirit.
- Spellblade armour proficiency now unlocks with level: leather from level 1, mail at 35, plate at 70.
- Spellblades' Presence is now a party buff like Prayer of Fortitude and increases all five attributes.
- New Arcane spell: Arcane Haste - a party cooldown granting 30% movement speed and haste for 12 seconds, on a 2 minute cooldown. New Arcane talent Temporal Rush shortens its cooldown.
- Blade Shatter now cleaves 3 targets and its armour shatter applies to all of them.
- Spellblades can now use the Dungeon Finder - pick your role in the LFG frame.
- Spellblades' Presence has a new red casting animation; Spellblade Strike, Arcane Ignition and Arcane Haste have new icons.
- Every race can speak and understand every language, cross-faction, from character creation.
- Each Spellblade grimoire tier has its own icon and held model.

## 2026.09.05b - Blade Shatter + talent fixes

- New Blade ability: Blade Shatter - a two-target cleave (weapon damage plus a bonus) that shatters the target's armor by 15% for 10 seconds. Trained from Instructor Vaeryn from level 6, 8 ranks. Recasting won't refresh the armor debuff until it wears off.
- Spellblade talents now actually do something - Bladed Focus, Gentle Hands and Lingering Aura were being silently ignored and now correctly boost Spellblade Strike, Touch of Light and Spellblades' Presence.

## 2026.09.05 - Spellblade balance pass

- Touch of Light (was Light Touch): duration up to 10s, now heals every 2 seconds instead of every second - same total healing.
- Arcane Ignition: added a burning wound that deals extra Arcane damage over 6 seconds on every rank.
- Arcane Ignition: direct-hit damage and mana cost rebalanced across all 8 ranks.
- Spellblade Strike: weapon-damage bonus reduced from 120% to 110%.
- Spellblade Strike: ranks 6-8 bonus damage significantly increased, and now varies within a range instead of a fixed number.

## 2026.09.04 - Legendary grimoire

- New legendary off-hand: Grimoire of the Ascendant Spellblade (item level 284).
  Bought from Instructor Vaeryn for 100 Emblems of Frost by a level-80 Spellblade -
  best-in-slot for top-end raiding.
- Spellblade starter sword now shows the correct model on the character-creation screen.
- "Spell Blade" is now written Spellblade everywhere (class name, tooltips, trainer).
- Instructor Vaeryn's spawn points no longer reset when the world data is re-applied.

## 2026.09.03 - Spellblade launch

- The Spellblade class is now playable and selectable at character creation
  (Human, Night Elf, Draenei, Undead, Troll, Blood Elf).
- Mandatory client patch: custom class tables, character-create screen, class icon,
  and the SpellBladeUI addon.
- Client renamed to RazagathWoW; windowed mode is the default on first launch.
