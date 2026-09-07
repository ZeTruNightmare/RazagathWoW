# RazagathWoW - Changelog

The launcher reads the machine-readable copy of this from `manifest.json`
(`changelog[]`). Keep the newest entry at the top; keep notes short and player-facing.

---

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
