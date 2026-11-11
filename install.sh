#!/bin/zsh
# Copies the addon into the WoW Forever AddOns directory: every file listed in
# Bulwark.toc (keeping its folder) plus the license and readmes.
# Run after every edit, then /reload in game.
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
DST="/Applications/World of Warcraft/_forever_/Interface/AddOns/Bulwark"
mkdir -p "$DST"
cp "$SRC/Bulwark.toc" "$SRC/LICENSE" "$SRC/README.md" "$SRC/README.en.md" "$DST/"
mkdir -p "$DST/Media/Reminders" && cp "$SRC/Media/icon.png" "$DST/Media/" && cp "$SRC"/Media/Reminders/*.tga "$DST/Media/Reminders/"
grep -v '^##' "$SRC/Bulwark.toc" | tr -d '\r' | sed 's/\\/\//g' | while read -r file; do
  [ -z "$file" ] && continue
  mkdir -p "$DST/$(dirname "$file")"
  cp "$SRC/$file" "$DST/$file"
done
echo "Bulwark installed to $DST. Type /reload in the game."
