#!/usr/bin/env bash
# Prints the RELEASE_NOTES.md section for a version, without its heading.
#   scripts/release-notes.sh X.Y.Z
# Each release is a `# MusicManager X.Y.Z` section; fails if there's none (or it's empty).
set -euo pipefail
cd "$(dirname "$0")/.."

[ -n "${1:-}" ] || { echo "usage: $0 X.Y.Z" >&2; exit 1; }

# A section runs until the next top-level heading outside a code fence. Blank lines at either
# end are trimmed.
notes=$(awk -v heading="# MusicManager $1" '
  /^```/ { fence = !fence }
  !fence && $0 == heading { found = 1; next }
  !fence && found && /^# / { exit }
  found { lines[++n] = $0 }
  END {
    first = 1; while (first <= n && lines[first] ~ /^[[:space:]]*$/) first++
    last = n; while (last >= first && lines[last] ~ /^[[:space:]]*$/) last--
    for (i = first; i <= last; i++) print lines[i]
  }' RELEASE_NOTES.md)

if [ -z "$notes" ]; then
  echo "error: RELEASE_NOTES.md has no '# MusicManager $1' section, or it's empty" >&2
  exit 1
fi
echo "$notes"
