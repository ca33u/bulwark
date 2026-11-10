#!/bin/zsh
# Runs every test suite with a plain Lua interpreter (brew install lua) from
# the repo root. Syntax-checks every Lua file first. Exits non-zero on any failure.
cd "$(dirname "$0")/.."
fail=0

echo "== syntax (luac -p)"
for f in Locales/*.lua Core/*.lua *.lua tests/*.lua; do
  if ! luac -p "$f"; then
    echo "SYNTAX ERROR: $f"
    fail=1
  fi
done

for suite in tests/core_test.lua tests/toc_test.lua tests/modules_test.lua tests/plates_test.lua \
             tests/blessings_test.lua tests/partymana_test.lua; do
  echo "== $suite"
  out=$(lua "$suite" 2>&1)
  code=$?
  echo "$out" | grep -E '^FAIL' 
  echo "$out" | tail -1
  if [ $code -ne 0 ]; then
    echo "SUITE FAILED: $suite (exit $code)"
    fail=1
  fi
done

if [ $fail -ne 0 ]; then
  echo "== FAILED"
  exit 1
fi
echo "== all green"
