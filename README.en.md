# Bulwark

A Protection Paladin toolkit for **World of Warcraft: Forever** (Interface 16001). Made by **addicted**. MIT license.

## Features

- **Duration line.** Short buffs ride a horizontal line: the icon appears at the start, travels to the red end as the buff runs out and disappears when it ends. Seals, Righteous Fury (last 30 seconds by default), Holy Shield, Consecration, Divine Protection, Divine Shield, Blessing of Protection and Freedom, plus the Forever spells Seal of Fury, Templar's Bulwark, Iron Creed and Shieldsworn. Seconds and optional names under the icons, flashing at the end. Four styles (classic rounded, minimal flat, inset rail, luminous beveled), custom colors and presets.
- **Swing timer.** A thin rail under the line fills between main-hand swings and shows the seconds to the next one. Parry haste follows the classic rule. Weapon swaps restart it.
- **Ability icons** with cooldowns, adjusted for talents. Shown only for abilities you know. Immunities are marked as locked while Forbearance is on you.
- **Reminders**: Righteous Fury missing, Seal missing or expired, No aura active (no paladin aura at all; any aura counts), plus draggable Righteous Fury and Forbearance badges. A sound plays when Seal of Fury drops in combat.
- **Tank readiness window** (`/bulwark prep`): buffs, blessings, group class buffs, Forbearance, weapon and shield, enchants, Subtlety, food, flask, elixirs, defense.
- **Mitigation window** (`/bulwark mitig`): miss, dodge, parry, block, crit and crush chance against a raid boss, armor reduction, effective health and more.
- **Modules**: aggro list from nameplates, threat-colored nameplates, automatic spell rank upgrades on your bars, party blessing icons next to the party frames, and a low-mana highlight for party members.

All game reads are guarded against the "secret values" WoW Forever returns in combat. A hidden value never shows up as missing, and it never creates a reminder. Bulwark never touches Blizzard frames and never reads forbidden ones.

On other classes the paladin parts stay hidden. The modules still work.

## Install

Unzip `Bulwark-2.0.0.zip` into `World of Warcraft/_forever_/Interface/AddOns`, then `/reload`.

## Commands

`/bulwark` (or `/bul`) lists every command. The main ones:

- `unlock` / `lock`: move things. On the line, the wheel changes scale, Shift+wheel changes width, Alt+wheel changes thickness and right-click opens options.
- `options`: the settings window. The minimap button and the addon list open it too.
- `test`: a 12-second preview.
- `reset`: default positions and sizes.
- `prep`, `mitig`: the two windows.
- `combat`: show everything only in combat.
- `warnings`, `swing`, `swinglog`, `timers`, `names`: on/off toggles.
- `width`, `thick`, `scale`, `swingheight`, `swinggap`, `readysize`, `readyx`, `readyy`, `readygap`: sizes and offsets.
- `spellcheck`: shows why reminders fire. `debug`: shows what is being tracked.
- Modules: `aggro`, `aggrocombat`, `plates`, `platesreset`, `ranks`, `autoranks`, `rankscheck`, `keepdownranks`, `blessings`, `blessingsframes`, `blessingspanel`, `blessingssolo`, `blessingsdebug`, `lowmana [percent]`.

## Languages

English, Russian, German, French, Spanish (Spain and Mexico), Brazilian Portuguese, Korean and Traditional Chinese.

## License

MIT. Copyright (c) 2026 addicted. See `LICENSE`.
