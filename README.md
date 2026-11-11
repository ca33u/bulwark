English · [Русский](README.ru.md)

# Bulwark

A Protection Paladin addon for **World of Warcraft: Forever** (Interface 16001). Made by **addicted** ([addicted.sh](https://addicted.sh)), MIT license.

Version 2.0 is a completely new core written from scratch: the buff line, cooldowns, reminders, swing timer, the readiness and stats windows, and the settings. Your old settings (`BulwarkDB` from 1.x) are picked up automatically the first time you log in.

## What it shows

- **Duration line.** Icons for short buffs (Seals, Righteous Fury, Holy Shield, Consecration, Divine Protection, Divine Shield, Blessing of Protection/Freedom, plus the Forever spells Seal of Fury, Templar's Bulwark, Iron Creed and Shieldsworn) appear at the start of the line, travel toward the red end and disappear when the buff runs out. Seconds are shown under each icon, and optionally the name; the icon flashes in the last few seconds. Seals are mutually exclusive. By default Righteous Fury only appears in its last 30 seconds. Four line styles (classic rounded, minimal flat, inset rail, luminous beveled), custom colors for the line, glow, background and ends, and presets.
- **Swing timer.** A thin rail under the line: it fills up between main-hand swings, with the seconds to the next swing on the right. Sources are `PLAYER_SWING` (if available) and your own swings from the combat log (can be turned off). Swapping weapons restarts the timer, turning off auto attack clears it. A parry speeds up your next swing by the classic rule (minus 40% of weapon speed, but not below 20%).
- **Abilities** above the line: icons show up only if you have learned the ability. On cooldown they are dimmed, with a clock sweep and seconds. Cooldowns take talents into account (Improved Judgement, Shieldsworn, Sacred Duty, Guardian's Favor, Improved Hammer of Justice, Purifying Power). While Forbearance is on you, immunities are marked as locked.
- **Reminders** in red text: "Righteous Fury missing", "Seal missing" / "Seal timer expired", "No aura active" (you have no paladin aura at all; any aura counts: Devotion, Retribution, Concentration, resistance auras); plus draggable Righteous Fury and Forbearance badges. A sound plays when Seal of Fury drops in combat. A reminder only appears when the addon is sure: a value hidden by the game never creates a reminder.
- **Tank readiness window** (`/bulwark prep`): Righteous Fury, Seal, aura, blessing, buffs from the classes in your group, Forbearance, weapon and shield, enchants, Subtlety on your cloak, food, flasks and elixirs, defense. Green means good, yellow means it couldn't be read or it's a tip, red means something is missing.
- **Mitigation stats window** (`/bulwark mitig`): miss, dodge, parry, avoidance, block, chance to be crit (and how much defense you need to be immune), crushing blows (and how much you're short of 102.4%), block value, armor and its damage reduction, effective health, spell power, hit, against a raid boss (or a level you choose).
- **Aggro list** (`Aggro.lua`). A panel listing the mobs in combat around you, based on enemy nameplates (they must be turned on, V key). Gold: hitting you; orange: about to switch to someone else; red: "loose", in combat with your group but not hitting you (the right side shows who it is on). Loose mobs are listed at the top. If the client hides a mob's threat, the row is grey.
- **Rank upgrades** (`Ranks.lua`). When you learn a new rank, every button on your action bars with the previous highest rank is replaced with the new one. Downranked spells are left alone. In combat the swap waits until combat ends.
- **Nameplate coloring** (`Plates.lua`) by threat: green, you have it; orange, you're losing it; red, it's gone.
- **Group blessings** (`Blessings.lua`). Small icons of paladin blessings to the right of the party frames, with the minutes left under each icon. Gold border: yours; grey: someone else's; red cross: no blessing.
- **Low mana in group** (`PartyMana.lua`). The mana bar of a party member below the threshold (30% by default) gets a pulsing red overlay.

Every read of a value that WoW Forever hides in combat (secret values) goes through guards: a hidden value doesn't break the addon, it keeps the last value that was read. Blizzard frames are never touched; forbidden frames are not even read.

On other classes the paladin parts are hidden, while the modules (aggro, nameplates, ranks, blessings, mana) keep working.

## Installation

Download `Bulwark-2.2.0.zip` and unzip it into `World of Warcraft/_forever_/Interface/AddOns`.

From source (`~/Develop/Bulwark`):

```
~/Develop/Bulwark/install.sh
```

Then `/reload` in game. If the addon isn't in the list, go back to character select and log in again. `./package.sh` builds a zip in `dist/`.

## Commands

`/bulwark` or `/bul`

| Command | What it does |
|---|---|
| `/bulwark` | list of commands |
| `/bulwark unlock` (`move`) | unlock: the line, the ability group, the reminder text and the badges can be dragged with the mouse |
| `/bulwark lock` | lock them again |
| `/bulwark options` | settings window (tabs Bar, Abilities, Warnings, Swing, Mitigation, About); also opened by right-clicking the unlocked line, the minimap button or the addon list |
| `/bulwark scale 1.2` | line scale (0.6–2) |
| `/bulwark width 500` | line length (200–800) |
| `/bulwark thick 8` | line thickness (2–24) |
| `/bulwark readysize 32` | ability icon size (12–64) |
| `/bulwark readyx 0`, `/bulwark readyy 50` | offset of the ability group from the line |
| `/bulwark readygap 4` | spacing between icons (0–24) |
| `/bulwark timers` | seconds under icons on/off |
| `/bulwark names` | names under icons on/off |
| `/bulwark swing` | show/hide the swing timer |
| `/bulwark swingheight 5` | swing timer rail thickness (2–12) |
| `/bulwark swinggap 6` | gap between the rail and the line (0–60) |
| `/bulwark swinglog` | turn the combat log source on/off |
| `/bulwark swingdebug` | what feeds the auto attack timer: whether swing events arrive, what weapon speed is used |
| `/bulwark warnings` | turn all reminders on/off at once |
| `/bulwark combat` | show everything only in combat |
| `/bulwark test` | test icons, reminders and swing timer for 12 seconds |
| `/bulwark reset` | restore default positions and sizes |
| `/bulwark prep` | tank readiness window |
| `/bulwark mitig` | mitigation stats window |
| `/bulwark spellcheck` | why reminders are firing: whether the addon sees Devotion Aura, Righteous Fury and Seals by ID and in the spellbook |
| `/bulwark debug` | what is being tracked right now |
| `/bulwark aggro` | show/hide the aggro list |
| `/bulwark aggrocombat` | aggro list only in combat (on by default) |
| `/bulwark plates` | nameplate threat coloring on/off |
| `/bulwark platesreset` | reset nameplate settings to defaults |
| `/bulwark blessings` | group blessings on/off entirely |
| `/bulwark blessingsframes` | icons next to the party frames (on by default) |
| `/bulwark blessingspanel` | a separate panel with rows (off by default) |
| `/bulwark blessingssolo` | show blessings even without a group |
| `/bulwark classicons` | class icon in front of the blessings next to the party frames (on by default); if a blessing is missing, the one that's needed is shown in grey: Might for warriors and rogues, Wisdom for everyone else |
| `/bulwark blessingsdebug` | which party frames the addon found |
| `/bulwark lowmana` | low mana highlight for the group on/off |
| `/bulwark lowmana 25` | highlight threshold in percent (5–90) |
| `/bulwark ranks` | replace all lower ranks on your bars with the highest ones right now |
| `/bulwark autoranks` | automatic rank replacement on/off |
| `/bulwark rankscheck` | which ranked spells are on your bars and which rank they should be |
| `/bulwark keepdownranks` | leave lower ranks you placed on purpose alone (for healers) |

Unlocked line: mouse wheel changes scale, Shift+wheel changes length, Alt+wheel changes thickness, right-click opens settings. Ability group: mouse wheel changes icon size, Shift+wheel changes spacing.

## How it works

- `Locales/`: translations (English is the source, plus ruRU, deDE, frFR, esES/esMX, ptBR, koKR, zhTW).
- `Core/`: the core, split into sections: `Init` (events, `Bulwark.SetLocked`, slash), `Guards` (secret values, forbidden frames), `DB` (settings and migration from 1.x), `Spells` (catalog, spellbook, talents), `Auras`, `Line`, `Swing`, `Abilities`, `Reminders`, `Prep`, `Mitigation`, `Options`, `Minimap`, `Movers`, `Slash`, `Boot`.
- `Aggro.lua`, `Ranks.lua`, `Plates.lua`, `Blessings.lua`, `PartyMana.lua`: modules.
- The line, glow and rail are drawn with plain textures, no custom images; the icon is the built-in `INV_Shield_06`.
- `tests/run.sh`: tests in plain Lua (`brew install lua`).

Spells are recognized by ID, then by name. The addon learns the IDs of Forever spells (Seal of Fury, Holy Strike, Templar's Bulwark…) by itself, from the spellbook, your casts and auras (`BulwarkDB.learnedIDs`).

---

© 2026 addicted · [addicted.sh](https://addicted.sh). MIT license, see `LICENSE`.
