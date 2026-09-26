#!/usr/bin/env bash
#
# Remote bootstrap for Maple Harness.
#
#   curl -fsSL https://raw.githubusercontent.com/kinncj/maple-harness-dist/main/bootstrap.sh | bash
#
# Clones (or updates) the repository into a stable on-disk location, then
# hands off to its install.sh, which installs the release binaries.
# Extra arguments are forwarded to the installer:
#
#   ... | bash -s -- --install-location ~/.local/bin
#   ... | bash -s -- --quiet
#
# The default repository is the public binaries repository, which carries
# install.sh at its root and needs no credential. The owner can point this
# at the private source repository instead (its installer lives in
# scripts/), which needs git access — gh auth login, an SSH key, or a token
# in the URL — and a token for the release download:
#
#   MAPLE_REPO=kinncj/maple-harness GITHUB_TOKEN=... bash bootstrap.sh
#
# This needs a published repository to clone. Until one is, build from
# source (`make build`). Knobs, via env:
#
#   MAPLE_REPO   owner/repo or a full git URL   (default: kinncj/maple-harness-dist)
#   MAPLE_REF    branch, tag or commit          (default: main)
#   MAPLE_DIR    clone destination              (default: ~/.local/share/maple-harness)
#
# When MAPLE_REF is a release tag (vX.Y.Z), that release is installed;
# otherwise the latest release is, and MAPLE_REF only selects which copy
# of the installer runs.
set -euo pipefail

MAPLE_REPO="${MAPLE_REPO:-kinncj/maple-harness-dist}"
MAPLE_REF="${MAPLE_REF:-main}"
MAPLE_DIR="${MAPLE_DIR:-$HOME/.local/share/maple-harness}"

case "$MAPLE_REPO" in
  http://*|https://*|ssh://*|git://*|file://*|git@*) REPO_URL="$MAPLE_REPO" ;;
  */*) REPO_URL="https://github.com/${MAPLE_REPO}.git" ;;
  *) echo "MAPLE_REPO must be owner/repo or a full git URL" >&2; exit 2 ;;
esac

for dep in git bash; do
  command -v "$dep" >/dev/null 2>&1 || { echo "missing required dependency: $dep" >&2; exit 1; }
done

if [ -d "$MAPLE_DIR/.git" ]; then
  echo "→ updating $MAPLE_DIR"
  git -C "$MAPLE_DIR" remote set-url origin "$REPO_URL"
  git -C "$MAPLE_DIR" fetch --tags --prune --quiet origin
else
  echo "→ cloning $REPO_URL into $MAPLE_DIR"
  mkdir -p "$(dirname "$MAPLE_DIR")"
  git clone --quiet "$REPO_URL" "$MAPLE_DIR"
  git -C "$MAPLE_DIR" fetch --tags --quiet origin
fi

# A branch tracks the remote tip; a tag or commit is checked out detached.
if git -C "$MAPLE_DIR" rev-parse --verify --quiet "refs/remotes/origin/${MAPLE_REF}" >/dev/null; then
  git -C "$MAPLE_DIR" checkout --quiet -B "$MAPLE_REF" "origin/${MAPLE_REF}"
else
  git -C "$MAPLE_DIR" checkout --quiet --detach "$MAPLE_REF"
fi

if [[ "$MAPLE_REF" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  export MAPLEHARNESS_VERSION="${MAPLEHARNESS_VERSION:-$MAPLE_REF}"
fi
export MAPLEHARNESS_REPO="${MAPLEHARNESS_REPO:-${MAPLE_REPO#https://github.com/}}"
MAPLEHARNESS_REPO="${MAPLEHARNESS_REPO%.git}"

# The binaries repository keeps the installer at its root; the source
# repository keeps it under scripts/. Either works.
for candidate in "$MAPLE_DIR/install.sh" "$MAPLE_DIR/scripts/install.sh"; do
  if [ -f "$candidate" ]; then
    exec bash "$candidate" "$@"
  fi
done
echo "no install.sh found in $MAPLE_DIR (looked in the root and in scripts/)" >&2
exit 1
