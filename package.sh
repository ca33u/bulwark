#!/bin/zsh
# Builds dist/Bulwark-<version>.zip with only what the game needs:
# every file listed in Bulwark.toc, the TOC, LICENSE and the readmes.
# Unzip it into  World of Warcraft/_forever_/Interface/AddOns
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
VERSION=$(grep -m1 '^## Version:' "$SRC/Bulwark.toc" | sed 's/## Version: *//' | tr -d '\r')
STAGE="$(mktemp -d)"
mkdir -p "$STAGE/Bulwark" "$SRC/dist"
cp "$SRC/Bulwark.toc" "$SRC/LICENSE" "$SRC/README.md" "$SRC/README.ru.md" "$STAGE/Bulwark/"
mkdir -p "$STAGE/Bulwark/Media/Reminders" && cp "$SRC/Media/icon.tga" "$STAGE/Bulwark/Media/" && cp "$SRC"/Media/Reminders/*.tga "$STAGE/Bulwark/Media/Reminders/"
grep -v '^##' "$SRC/Bulwark.toc" | tr -d '\r' | sed 's/\\/\//g' | while read -r file; do
  [ -z "$file" ] && continue
  mkdir -p "$STAGE/Bulwark/$(dirname "$file")"
  cp "$SRC/$file" "$STAGE/Bulwark/$file"
done
OUT="$SRC/dist/Bulwark-$VERSION.zip"
rm -f "$OUT"
(cd "$STAGE" && zip -qr "$OUT" Bulwark -x '*.DS_Store')
rm -rf "$STAGE"
echo "$OUT"
