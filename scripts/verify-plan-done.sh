#!/bin/zsh
# Rerun from the repo root. Exit 0 only when the four done-when checks pass.
set -euo pipefail

ROOT="${1:-$(pwd)}"
cd "$ROOT"

fail=0
say() { print -- "$1" }

say "== README fence =="
if rg -q "Cadence never uploads audio" README.md && rg -q "Compare Lab can call Wispr only if you paste a key" README.md
then
  say "PASS README fence"
else
  say "FAIL README fence"
  fail=1
fi

say "== git add -A home path =="
if git add -An 2>/dev/null | rg -q '/Users/|Documents/Projects'
then
  say "FAIL git add would stage a home path"
  git add -An 2>/dev/null | rg '/Users/|Documents/Projects' || true
  fail=1
else
  say "PASS git add -An has no home path"
fi

say "== Studio live =="
if ! pgrep -q -f '/Applications/Cadence.app/Contents/MacOS/Cadence'
then
  say "FAIL Cadence is not running from /Applications"
  fail=1
else
  ax="$(perl -e 'alarm 16; exec @ARGV' osascript <<'EOS'
tell application "System Events"
  tell process "Cadence"
    set frontmost to true
    delay 0.4
    if (count of windows) is 0 then
      click menu bar item 1 of menu bar 2
      delay 0.35
      click menu item "Open Cadence" of menu 1 of menu bar item 1 of menu bar 2
      delay 0.8
    end if
    set sz to size of window "Cadence"
    set elems to entire contents of window "Cadence"
    set names to ""
    repeat with i from 1 to count of elems
      set e to item i of elems
      set nm to ""
      try
        set nm to (name of e) as string
      end try
      if nm is not "missing value" and nm is not "" then
        set names to names & nm & linefeed
      end if
    end repeat
    click button 1 of toolbar 1 of window "Cadence"
    delay 0.6
    set opened to count of windows
    try
      click (first button of window "Hotkeys" whose description is "close button")
    end try
    delay 0.3
    click (first button of window "Cadence" whose description is "close button")
    delay 0.4
    set afterClose to count of windows
    click menu bar item 1 of menu bar 2
    delay 0.3
    click menu item "Open Cadence" of menu 1 of menu bar item 1 of menu bar 2
    delay 0.7
    return "size=" & (item 1 of sz as string) & "x" & (item 2 of sz as string) & " settingsOpen=" & opened & " afterClose=" & afterClose & " afterOpen=" & (count of windows) & linefeed & names
  end tell
end tell
EOS
)" || ax="osascript_failed"
  print -- "$ax"
  if print -- "$ax" | rg -q 'settingsOpen=2' \
    && print -- "$ax" | rg -q 'afterClose=0' \
    && print -- "$ax" | rg -q 'afterOpen=1' \
    && print -- "$ax" | rg -q 'Recent takes' \
    && print -- "$ax" | rg -q 'size=360x'
  then
    take_lines="$(print -- "$ax" | rg -c '^[0-9]' || true)"
    say "PASS Studio close/settings and recent-takes heading (clock lines=$take_lines)"
  else
    say "FAIL Studio live AX"
    fail=1
  fi
fi

if (( fail == 0 ))
then
  say "== ALL FOUR DONE-WHEN CHECKS PASSED =="
  exit 0
fi
say "== FAILED =="
exit 1
