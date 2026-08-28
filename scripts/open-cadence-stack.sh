#!/bin/zsh
# Create the PR-clean / PR-docs / PR-recent stack when git identity and gh exist.
# Does not write git config. Does not invent LICENSE text.
# Usage: scripts/open-cadence-stack.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! /opt/homebrew/bin/gh auth status >/dev/null 2>&1
then
  print -- "BLOCKED gh is not logged in. Run: gh auth login"
  /opt/homebrew/bin/gh auth status 2>&1 | head -5 || true
  exit 2
fi

if [[ -z "$(git config user.name || true)" || -z "$(git config user.email || true)" ]]
then
  login="$(/opt/homebrew/bin/gh api user --jq .login)"
  export GIT_AUTHOR_NAME="${login}"
  export GIT_AUTHOR_EMAIL="${login}@users.noreply.github.com"
  export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
  export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
  print -- "Using gh login $login as commit author via env, not git config"
fi

if git rev-parse --verify HEAD >/dev/null 2>&1
then
  print -- "BLOCKED repo already has commits. Split by hand from HEAD."
  exit 3
fi

print -- "Ready to open the stack. Re-run with apply after reviewing pathspecs in this script."
print -- "This copy stops before git add so a first commit cannot leak by accident."
exit 4
