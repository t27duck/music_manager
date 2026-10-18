#!/usr/bin/env bash
# The app version lives in several files that must agree.
#   scripts/version.sh bump X.Y.Z   set it everywhere
#   scripts/version.sh check [X.Y.Z] fail unless every file agrees (and equals X.Y.Z, if given)
set -euo pipefail
cd "$(dirname "$0")/.."

current() {
  row() { printf '%-28s %s\n' "$1" "$2"; }
  row package.json "$(node -p "require('./package.json').version")"
  row package-lock.json "$(node -p "require('./package-lock.json').version")"
  row 'package-lock.json ("")' "$(node -p "require('./package-lock.json').packages[''].version")"
  row src-tauri/tauri.conf.json "$(node -p "require('./src-tauri/tauri.conf.json').version")"
  row src-tauri/Cargo.toml "$(sed -n 's/^version = "\(.*\)"$/\1/p' src-tauri/Cargo.toml | head -1)"
  row src-tauri/Cargo.lock "$(sed -n '/^name = "music-manager"$/{n;s/^version = "\(.*\)"$/\1/p}' src-tauri/Cargo.lock)"
  row packaging/arch/PKGBUILD "$(sed -n 's/^pkgver=//p' packaging/arch/PKGBUILD)"
}

check() {
  local versions
  versions=$(current)
  echo "$versions"
  local distinct
  distinct=$(awk '{print $NF}' <<<"$versions" | sort -u)
  if [ "$(wc -l <<<"$distinct")" -ne 1 ]; then
    echo "error: versions differ; run scripts/version.sh bump X.Y.Z" >&2
    exit 1
  fi
  if [ -n "${1:-}" ] && [ "$distinct" != "$1" ]; then
    echo "error: version is $distinct, expected $1" >&2
    exit 1
  fi
}

bump() {
  local v=$1
  [[ $v =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: '$v' is not X.Y.Z" >&2; exit 1; }
  # Top-level keys are the only ones indented by two spaces.
  sed -i "s/^  \"version\": \"[^\"]*\"/  \"version\": \"$v\"/" package.json src-tauri/tauri.conf.json
  sed -i -e "0,/^  \"version\": /s/^  \"version\": \"[^\"]*\"/  \"version\": \"$v\"/" \
    -e "/^    \"\": {$/,/\"version\"/s/\"version\": \"[^\"]*\"/\"version\": \"$v\"/" package-lock.json
  sed -i "0,/^version = /s/^version = \".*\"/version = \"$v\"/" src-tauri/Cargo.toml
  sed -i "/^name = \"music-manager\"$/{n;s/^version = \".*\"/version = \"$v\"/}" src-tauri/Cargo.lock
  sed -i -e "s/^pkgver=.*/pkgver=$v/" -e "s/^pkgrel=.*/pkgrel=1/" packaging/arch/PKGBUILD
  check "$v"
  scripts/release-notes.sh "$v" >/dev/null 2>&1 ||
    echo "Next: add a '# MusicManager $v' section to RELEASE_NOTES.md"
}

case "${1:-}" in
  bump) [ -n "${2:-}" ] || { echo "usage: $0 bump X.Y.Z" >&2; exit 1; }; bump "$2" ;;
  check) check "${2:-}" ;;
  *) echo "usage: $0 bump X.Y.Z | check [X.Y.Z]" >&2; exit 1 ;;
esac
