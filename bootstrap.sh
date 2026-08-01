#!/usr/bin/env bash
# Install orchestrate-agents without cloning: fetch this branch's archive into
# a temp directory, run the real installer from it, delete the directory.
#
# Usage: curl -fsSL <raw-url>/bootstrap.sh | bash
#        curl -fsSL <raw-url>/bootstrap.sh | bash -s -- --uninstall
#
# Overrides (the second exists so the smoke suite can point at a local
# tarball -- it is the only reason the URL is not hardcoded):
#   ORCH_REF=<branch|tag>        (default main)
#   ORCH_ARCHIVE_URL=<url>       (default: this repo's tar.gz for ORCH_REF)

set -euo pipefail

REPO="milad-hub/orchestrate-agents"
REF="${ORCH_REF:-main}"
ARCHIVE="${ORCH_ARCHIVE_URL:-https://codeload.github.com/$REPO/tar.gz/refs/heads/$REF}"

# What this script itself needs, before it downloads anything. The installer
# runs its own preflight (git, python, the platform CLI) once it starts.
fetch() {
  # A local path is accepted as well as a URL: the smoke suite hands this a
  # tarball it just built, and file:// URLs are a portability trap on Windows.
  if [ -f "$1" ]; then
    cp "$1" "$2"
    return
  fi
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$1" -o "$2"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$2" "$1"
  else
    echo "Need curl or wget to download the bundle. Install one, or clone the" >&2
    echo "repo and run ./install.sh directly: https://github.com/$REPO" >&2
    exit 1
  fi
}

if ! command -v tar >/dev/null 2>&1; then
  echo "Need tar to unpack the bundle. Install it, or clone the repo and run" >&2
  echo "./install.sh directly: https://github.com/$REPO" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fetch "$ARCHIVE" "$WORK/bundle.tar.gz"
tar -xzf "$WORK/bundle.tar.gz" -C "$WORK"

# GitHub names the directory <repo>-<ref>, but a tag, a slash in a branch name
# or a locally built archive all change that -- find it instead of assuming.
DIR=""
for candidate in "$WORK"/*/; do
  if [ -f "${candidate}install.sh" ]; then DIR="${candidate%/}"; break; fi
done
if [ -z "$DIR" ]; then
  echo "The archive from $ARCHIVE has no install.sh in it." >&2
  exit 1
fi

# Piped into bash, stdin IS this script: install.sh's `read -r -p` and the
# arrow-key menus would read the remaining bytes, or EOF, instead of the user.
# Hand them the terminal. Without one (CI, ORCH_NONINTERACTIVE=1) run as-is.
# Test by opening it, not with -r: a /dev/tty that exists but has no
# controlling terminal behind it (CI, a detached shell) passes -r and then
# fails at redirect time, taking the install with it.
# Run it, never exec it: exec replaces this shell and the EXIT trap above
# never fires, leaving the downloaded bundle in the temp directory forever.
status=0
if { : < /dev/tty; } 2>/dev/null; then
  bash "$DIR/install.sh" "$@" < /dev/tty || status=$?
else
  bash "$DIR/install.sh" "$@" || status=$?
fi
exit "$status"
