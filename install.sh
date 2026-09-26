#!/usr/bin/env bash
#
# Install the MapleHarness binaries from GitHub Releases.
#
#   curl -fsSL https://raw.githubusercontent.com/kinncj/maple-harness-dist/main/install.sh | bash
#
#   ... | bash -s -- --install-location ~/.local/bin
#
# Release-based install needs a published repository with releases. If
# there is none yet, build from source instead: `make build` or
# `make dist/app` (see docs/install.md).
#
# No credential is needed for a public release repository, which is what
# the default is. A private one — or one with no release yet — answers 404
# to an anonymous request, which is indistinguishable from "no such
# release"; when a download fails and there is no credential, the error
# says so and names the two ways forward.
#
# An authenticated `gh` is used when present (it resolves release assets by
# name); GITHUB_TOKEN or GH_TOKEN is the alternative, parsed with python3
# rather than by hand, since a release payload's nested "uploader" object
# has URL templates containing braces that a sed-based parser can silently
# choke on.
#
# Every release is signed. The installer checks SHA256SUMS against the
# project's Ed25519 release key (built into this script, and into the
# binaries) before it trusts a single hash in it, and refuses to install
# when it cannot. It needs OpenSSL 3 for that; without it, an already
# installed maple-harness can do the check; with neither, it stops and says
# how to proceed. See docs/supply-chain.md.
#
# Environment overrides:
#   MAPLEHARNESS_VERSION   release tag to install (default: latest)
#   MAPLEHARNESS_BIN_DIR   install directory (default: /usr/local/bin)
#   MAPLEHARNESS_REPO      release owner/repo (default: kinncj/maple-harness-dist)
#   GITHUB_TOKEN           optional (or GH_TOKEN, or an authenticated `gh`): only for a private fork
#
# Windows: use scripts/install.ps1.
#
set -euo pipefail

REPO="${MAPLEHARNESS_REPO:-kinncj/maple-harness-dist}"
VERSION="${MAPLEHARNESS_VERSION:-latest}"
BINARIES=("maple-proxy" "maple-harness")

# The keys releases are signed with, "name=base64 Ed25519 public key", one
# per line. Must match common/pkg/selfupdate/keys.go (a test enforces it).
# The placeholder is a real key whose private half does not exist: until the
# project's release key replaces it, no release can verify, so this script
# refuses to install one — which is the point.
RELEASE_KEYS="${MAPLEHARNESS_RELEASE_KEYS:-PLACEHOLDER-not-a-release-key=kdIYytfg0VNDBAGp4Lco4AjgX+p/7m/mdJsFcSjO5K0=}"

# Releases API base and public-download base. Overridable for one reason
# only: this script's own tests drive both paths against a local stub, and
# no test in this repository is allowed to touch the network. Test-only —
# deliberately absent from --help.
API="${MAPLEHARNESS_API:-https://api.github.com}"
PUBLIC_BASE="${MAPLEHARNESS_PUBLIC_BASE:-https://github.com}"

# --------------------------------------------------------------------------
# Output
# --------------------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'; RESET=$'\033[0m'
else
  BOLD=''; DIM=''; RED=''; GREEN=''; RESET=''
fi

info() { printf '  %s\n' "$*"; }
step() { printf '%s→%s %s\n' "$BOLD" "$RESET" "$*"; }
err()  { printf '\n%serror:%s %s\n' "$RED" "$RESET" "$1" >&2; exit "${2:-1}"; }
need() { command -v "$1" >/dev/null 2>&1 || err "'$1' is required but was not found on PATH."; }

usage() {
  cat <<EOF
Install the MapleHarness binaries.

  --install-location DIR   where to put the binaries (default: /usr/local/bin)
  --no-herdr               skip the herdr integration entirely
  --quiet                  suppress the logo
  --skip-verify            install even if the release signature cannot be checked
                           (the checksums are still enforced). Not recommended.
  -h, --help               this message

Environment:
  MAPLEHARNESS_VERSION   release tag (default: latest)
  MAPLEHARNESS_BIN_DIR   install directory
  MAPLEHARNESS_REPO      owner/repo to install from
  GITHUB_TOKEN           optional (avoids rate limits, or needed for a private fork)
  MAPLEHARNESS_RELEASE_KEYS  trusted release keys (name=base64 public key, comma
                         separated) instead of the ones built into this script
EOF
}

# --------------------------------------------------------------------------
# Banner — same ANSI Shadow mark as the README logo and the TUI splash
# --------------------------------------------------------------------------
banner() {
  [ -n "${QUIET:-}" ] && return 0
  local c="" r=""
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then c=$'\033[38;5;202m'; r=$'\033[0m'; fi
  printf '%s\n' "${c}"
  cat <<'LOGO'
███╗   ███╗ █████╗ ██████╗ ██╗     ███████╗
████╗ ████║██╔══██╗██╔══██╗██║     ██╔════╝
██╔████╔██║███████║██████╔╝██║     █████╗  
██║╚██╔╝██║██╔══██║██╔═══╝ ██║     ██╔══╝  
██║ ╚═╝ ██║██║  ██║██║     ███████╗███████╗
╚═╝     ╚═╝╚═╝  ╚═╝╚═╝     ╚══════╝╚══════╝
            H A R N E S S
LOGO
  printf '%s\n' "${r}"
}

# --------------------------------------------------------------------------
# Arguments
# --------------------------------------------------------------------------
INSTALL_LOCATION=""
# The harness reports to herdr under its own name and needs nothing
# installed for it — see install_herdr_shim. --no-herdr is kept so the
# detection can be skipped entirely.
NO_HERDR=""
QUIET=""
SKIP_VERIFY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --install-location) INSTALL_LOCATION="${2:-}"; shift 2 ;;
    --install-location=*) INSTALL_LOCATION="${1#*=}"; shift ;;
    --no-herdr) NO_HERDR=1; shift ;;
    --quiet) QUIET=1; shift ;;
    --skip-verify) SKIP_VERIFY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) err "unknown option: $1" ;;
  esac
done

banner

need curl
need uname

# --------------------------------------------------------------------------
# Platform
# --------------------------------------------------------------------------
os=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$os" in
  linux|darwin) ;;
  *) err "unsupported OS: $os (Windows users: use scripts/install.ps1)" ;;
esac

arch=$(uname -m)
case "$arch" in
  x86_64|amd64) arch=amd64 ;;
  arm64|aarch64) arch=arm64 ;;
  *) err "unsupported architecture: $arch" ;;
esac

if [ "$os" = "darwin" ]; then
  BINARIES+=("maple-sidecar")
fi

# --------------------------------------------------------------------------
# Auth — optional
# --------------------------------------------------------------------------
# An authenticated gh, or a token, is used when present and never demanded:
# the default repository is public. What a missing credential costs is
# explained where it matters — at the failed download — because GitHub
# answers 404 for a private repository and for a release that does not
# exist alike, and the two need different answers.
USE_GH=""
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  USE_GH=1
fi
: "${GITHUB_TOKEN:=${GH_TOKEN:-}}"

# no_credential_hint is appended to a failed download when nothing was
# signed in, since that is the one case where 404 is ambiguous.
no_credential_hint() {
  if [ -z "$USE_GH" ] && [ -z "${GITHUB_TOKEN:-}" ]; then
    printf '%s' "

  GitHub answers 404 both for a release that does not exist and for a
  private repository you cannot see. If ${REPO} is private, sign in with
  'gh auth login' or set GITHUB_TOKEN and run this again. If no release has
  been published yet, build from source instead: make build (or make dist/app)."
  fi
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# fetch <asset-name> <dest> — download one release asset; fails if it is
# absent. Falls back to an unauthenticated request when neither gh nor
# GITHUB_TOKEN is available, which is the normal case for a public repo.
fetch() {
  if [ -n "$USE_GH" ]; then
    if [ "$VERSION" = "latest" ]; then
      gh release download --repo "$REPO" --pattern "$1" --output "$2" --clobber 2>/dev/null && return 0
    else
      gh release download "$VERSION" --repo "$REPO" --pattern "$1" --output "$2" --clobber 2>/dev/null && return 0
    fi
  fi

  if [ "$VERSION" = "latest" ]; then
    dl_url="${PUBLIC_BASE}/${REPO}/releases/latest/download/$1"
  else
    dl_url="${PUBLIC_BASE}/${REPO}/releases/download/${VERSION}/$1"
  fi
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN}" -o "$2" "$dl_url" 2>/dev/null && return 0
  else
    curl -fsSL -o "$2" "$dl_url" 2>/dev/null && return 0
  fi

  # Private-repo fallback: browser_download_url 404s without a session, so
  # the asset id + API endpoint is the only path that honors a token.
  [ -n "${GITHUB_TOKEN:-}" ] || return 1
  need python3
  rel_url="${API}/repos/${REPO}/releases/latest"
  [ "$VERSION" = "latest" ] || rel_url="${API}/repos/${REPO}/releases/tags/${VERSION}"
  id=$(curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" \
         -H "Accept: application/vnd.github+json" "$rel_url" \
       | python3 -c "import json,sys; rel=json.load(sys.stdin); m=[a['id'] for a in rel['assets'] if a['name']=='$1']; print(m[0] if m else '')")
  [ -n "$id" ] || return 1
  curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/octet-stream" \
    -o "$2" "${API}/repos/${REPO}/releases/assets/${id}"
}

printf '\n%sMapleHarness%s\n' "$BOLD" "$RESET"
printf '%s%s %s (%s/%s)%s\n\n' "$DIM" "$REPO" "$VERSION" "$os" "$arch" "$RESET"

# --------------------------------------------------------------------------
# Download
# --------------------------------------------------------------------------
for bin in "${BINARIES[@]}"; do
  asset="${bin}_${os}_${arch}"
  step "Downloading ${asset}"
  fetch "$asset" "${tmp}/${asset}" \
    || err "no asset named ${asset} in release ${VERSION} of ${REPO}.

  Either the release predates this installer's binary names, or the release is
  still publishing. List what it does have:

    gh release view ${VERSION} --repo ${REPO}$(no_credential_hint)"
done

# --------------------------------------------------------------------------
# Where things go (needed by verification, which may use an installed copy)
# --------------------------------------------------------------------------
if [ -n "$INSTALL_LOCATION" ]; then
  bindir="$INSTALL_LOCATION"
else
  bindir="${MAPLEHARNESS_BIN_DIR:-/usr/local/bin}"
fi
case "$bindir" in "~"/*) bindir="${HOME}/${bindir#"~"/}" ;; esac

# --------------------------------------------------------------------------
# Verify the signature on SHA256SUMS
# --------------------------------------------------------------------------
# Checksums only prove the download matches the checksum file, and an
# attacker who can replace the binary can replace that file too. The
# signature is what ties the file to the project.
#
# The signed message is  "maple-harness-release-v1\n" + tag + "\n" + the
# exact bytes of SHA256SUMS, so a signature cannot be moved to another
# release or another file.

# openssl_ed25519 prints the openssl that can verify Ed25519 with raw input,
# or nothing. macOS ships LibreSSL, which cannot; Homebrew's OpenSSL can.
openssl_ed25519() {
  local cand
  for cand in "${MAPLEHARNESS_OPENSSL:-openssl}" /opt/homebrew/opt/openssl/bin/openssl /usr/local/opt/openssl/bin/openssl; do
    command -v "$cand" >/dev/null 2>&1 || continue
    # Prove it, rather than trusting a version string: sign and verify.
    local d; d=$(mktemp -d) || continue
    if "$cand" genpkey -algorithm ed25519 -out "$d/k.pem" >/dev/null 2>&1 \
       && printf x > "$d/m" \
       && "$cand" pkeyutl -sign -inkey "$d/k.pem" -rawin -in "$d/m" -out "$d/s" >/dev/null 2>&1 \
       && "$cand" pkeyutl -verify -inkey "$d/k.pem" -rawin -in "$d/m" -sigfile "$d/s" >/dev/null 2>&1; then
      rm -rf "$d"; printf '%s' "$cand"; return 0
    fi
    rm -rf "$d"
  done
  return 1
}

# key_id <base64 public key> — first 8 bytes of its SHA-256, in hex: the id a
# signature file carries.
key_id() {
  local d; d=$(mktemp -d)
  printf '%s' "$1" | base64 -d > "$d/raw" 2>/dev/null || { rm -rf "$d"; return 1; }
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$d/raw" | cut -c1-16
  else shasum -a 256 "$d/raw" | cut -c1-16; fi
  rm -rf "$d"
}

sig_field() { awk -F': *' -v k="$2" '$1 == k { print $2; exit }' "$1" | tr -d '\r'; }

# verify_signature <SHA256SUMS> <sigfile> — sets SIGNED_BY and SIGNED_TAG, or
# exits with an explanation.
verify_signature() {
  local sums="$1" sigf="$2" header keyid tag sigb64 line name pub id ossl d found=""
  header=$(head -n1 "$sigf" | tr -d '\r')
  [ "$header" = "maple-harness-release-signature v1" ] || err "SHA256SUMS.sig is not a release signature (unexpected header). Nothing has been installed."
  keyid=$(sig_field "$sigf" key); tag=$(sig_field "$sigf" tag); sigb64=$(sig_field "$sigf" sig)
  [ -n "$keyid" ] && [ -n "$tag" ] && [ -n "$sigb64" ] || err "SHA256SUMS.sig is incomplete. Nothing has been installed."
  if [ "$VERSION" != "latest" ] && [ "$tag" != "$VERSION" ]; then
    err "the signature is for release ${tag}, not ${VERSION}: it was moved from another release. Nothing has been installed."
  fi

  # Which trusted key made it?
  while IFS= read -r line; do
    line=$(printf '%s' "$line" | tr -d ' \r'); [ -n "$line" ] || continue
    case "$line" in *=*) name="${line%%=*}"; pub="${line#*=}" ;; *) name="key"; pub="$line" ;; esac
    id=$(key_id "$pub") || continue
    if [ "$id" = "$keyid" ]; then found=1; SIGNED_BY="$name"; SIGNED_PUB="$pub"; break; fi
  done <<KEYS
$(printf '%s' "$RELEASE_KEYS" | tr ',' '\n')
KEYS
  if [ -z "$found" ]; then
    case "$RELEASE_KEYS" in *PLACEHOLDER-not-a-release-key*)
      err "this installer has no release key yet (it carries a placeholder), so it cannot verify anything.

  This is a build of the installer that predates the project's first signed
  release. Get the installer from the release you are installing, or see
  docs/supply-chain.md. Nothing has been installed." ;;
    esac
    err "this release is signed by key ${keyid}, which this installer does not trust.

  If the project rotated its key, get a newer installer. If you did not expect
  this, do not install: the download may have been tampered with.
  Nothing has been installed."
  fi
  SIGNED_TAG="$tag"

  d=$(mktemp -d)
  printf 'maple-harness-release-v1\n%s\n' "$tag" > "$d/msg"; cat "$sums" >> "$d/msg"
  printf '%s' "$sigb64" | base64 -d > "$d/sig" 2>/dev/null || err "the signature is not valid base64. Nothing has been installed."

  if ossl=$(openssl_ed25519); then
    # An Ed25519 public key in DER is a fixed 12-byte prefix and the 32 raw bytes.
    { printf '\x30\x2a\x30\x05\x06\x03\x2b\x65\x70\x03\x21\x00'; printf '%s' "$SIGNED_PUB" | base64 -d; } > "$d/pub.der"
    { echo '-----BEGIN PUBLIC KEY-----'; base64 < "$d/pub.der" | tr -d '\n' | fold -w 64; echo; echo '-----END PUBLIC KEY-----'; } > "$d/pub.pem"
    if "$ossl" pkeyutl -verify -pubin -inkey "$d/pub.pem" -rawin -in "$d/msg" -sigfile "$d/sig" >/dev/null 2>&1; then
      rm -rf "$d"; return 0
    fi
    rm -rf "$d"
    err "the signature on SHA256SUMS does NOT match. The release was altered after it was signed, or is not genuine.

  Nothing has been installed. Do not use these files."
  fi

  # No usable OpenSSL. An installed maple-harness carries the same keys and
  # can check it — but only one that was installed before this download:
  # the downloaded binary cannot vouch for itself.
  if [ -x "${bindir}/maple-harness" ]; then
    if "${bindir}/maple-harness" update --verify-release "$sums" --sig "$sigf" --version "$tag" >/dev/null 2>&1; then
      rm -rf "$d"; SIGNED_BY="${SIGNED_BY} (via the installed maple-harness)"; return 0
    fi
    rm -rf "$d"
    err "the installed maple-harness rejected the signature on SHA256SUMS. Nothing has been installed."
  fi
  rm -rf "$d"
  return 2
}

SIGNED_BY=""; SIGNED_TAG=""; SIGNED_PUB=""
if ! fetch "SHA256SUMS" "${tmp}/SHA256SUMS" 2>/dev/null; then
  err "this release publishes no SHA256SUMS; refusing to install unverified binaries."
fi
step "Verifying the release signature"
if fetch "SHA256SUMS.sig" "${tmp}/SHA256SUMS.sig" 2>/dev/null; then
  verify_signature "${tmp}/SHA256SUMS" "${tmp}/SHA256SUMS.sig" && vrc=0 || vrc=$?
  if [ "$vrc" -eq 0 ]; then
    info "${GREEN}✓${RESET} SHA256SUMS is signed by ${SIGNED_BY} for ${SIGNED_TAG}"
  elif [ -n "$SKIP_VERIFY" ]; then
    printf '%s!%s %s\n' "$RED" "$RESET" "the signature could not be checked here; continuing because of --skip-verify. The checksums still apply, but nothing proves they came from the project."
  else
    err "cannot check the release signature: this machine has no OpenSSL 3 (macOS's built-in one is too old),
  and no maple-harness is installed yet to do it.

  Either:
    - install OpenSSL 3 (brew install openssl) and run this again, or
    - verify by hand as docs/supply-chain.md describes, then re-run with --skip-verify.

  Nothing has been installed."
  fi
else
  if [ -z "$SKIP_VERIFY" ] && [ -z "${MAPLEHARNESS_RELEASE_KEYS:-}" ] && case "$RELEASE_KEYS" in *PLACEHOLDER-not-a-release-key*) true ;; *) false ;; esac; then
    # No release key is embedded: this project does not sign, and the
    # checksums below are what is verified. (With a key embedded, an
    # unsigned release is refused, so stripping a signature does nothing.)
    info "this release is not signed; verifying its checksums only"
  elif [ -n "$SKIP_VERIFY" ]; then
    printf '%s!%s %s\n' "$RED" "$RESET" "this release has no signature (SHA256SUMS.sig); continuing because of --skip-verify. Nothing proves it came from the project."
  else
    err "this release is not signed (no SHA256SUMS.sig), so its authenticity cannot be checked.

  Nothing has been installed. If you are sure about where you got it,
  --skip-verify installs anyway (checksums are still enforced)."
  fi
fi

if command -v sha256sum >/dev/null 2>&1; then
  sha256_of() { sha256sum "$1" | awk '{print $1}'; }
else
  need shasum
  sha256_of() { shasum -a 256 "$1" | awk '{print $1}'; }
fi

for bin in "${BINARIES[@]}"; do
  asset="${bin}_${os}_${arch}"
  want=$(awk -v a="$asset" '$2 == a || $2 == "*"a { print $1; exit }' "${tmp}/SHA256SUMS")
  [ -n "$want" ] || err "SHA256SUMS has no entry for ${asset}; refusing to install an unverified binary."
  got=$(sha256_of "${tmp}/${asset}")
  [ "$want" = "$got" ] || err "checksum mismatch for ${asset}.

    expected: ${want}
    actual:   ${got}

  The download was corrupted or tampered with. Nothing has been installed."
  info "${GREEN}✓${RESET} verified ${asset}"
done

# --------------------------------------------------------------------------
# Install, elevating only when the target is not writable
# --------------------------------------------------------------------------
SUDO=""
if [ ! -d "$bindir" ]; then
  if ! mkdir -p "$bindir" 2>/dev/null; then
    command -v sudo >/dev/null 2>&1 || err "cannot create ${bindir} and sudo is unavailable (use --install-location)"
    SUDO="sudo"
    $SUDO mkdir -p "$bindir" || err "cannot create ${bindir} (use --install-location)"
  fi
fi
if [ -z "$SUDO" ] && [ ! -w "$bindir" ]; then
  command -v sudo >/dev/null 2>&1 || err "${bindir} is not writable and sudo is unavailable (use --install-location)"
  SUDO="sudo"
fi

step "Installing to ${bindir}"
for bin in "${BINARIES[@]}"; do
  asset="${bin}_${os}_${arch}"
  chmod +x "${tmp}/${asset}"
  $SUDO mv "${tmp}/${asset}" "${bindir}/${bin}" || err "failed to install ${bindir}/${bin}"
  info "installed ${bindir}/${bin}"
done

# --------------------------------------------------------------------------
# Short aliases
# --------------------------------------------------------------------------
# The full names are what releases, self-update and the docs use; these are
# for typing. Symlinks rather than copies so `cch update` updates the one
# real binary, and a stale alias can't diverge from it.
link_alias() {
  alias_name="$1"
  target="$2"
  [ -x "${bindir}/${target}" ] || return 0
  if ln -sf "${target}" "${bindir}/${alias_name}" 2>/dev/null; then
    info "linked ${bindir}/${alias_name} -> ${target}"
  else
    info "note: could not create the ${alias_name} alias in ${bindir}"
  fi
}
link_alias cch maple-harness
link_alias ccp maple-proxy

# --------------------------------------------------------------------------
# Licence and third-party notices
# --------------------------------------------------------------------------
# The binaries contain other people's code, whose licences require their
# notices to travel with it. They are also inside the binary
# (`maple-harness licenses`); these are the readable copies, covered by the
# same signed checksums. A release that predates them just lacks them.
case "$(basename "$bindir")" in
  bin) sharedir="$(dirname "$bindir")/share/maple-harness" ;;
  *)   sharedir="${bindir}/maple-harness-licenses" ;;
esac
notice_files=()
for f in LICENSE THIRD_PARTY_NOTICES.md; do
  if fetch "$f" "${tmp}/$f" 2>/dev/null; then
    want=$(awk -v a="$f" '$2 == a || $2 == "*"a { print $1; exit }' "${tmp}/SHA256SUMS")
    if [ -z "$want" ] || [ "$want" != "$(sha256_of "${tmp}/$f")" ]; then
      printf '%s!%s %s\n' "$RED" "$RESET" "skipping ${f}: it is not covered by the signed checksums."
      continue
    fi
    notice_files+=("$f")
  fi
done
if [ "${#notice_files[@]}" -gt 0 ]; then
  if $SUDO mkdir -p "$sharedir" 2>/dev/null; then
    for f in "${notice_files[@]}"; do $SUDO cp "${tmp}/$f" "${sharedir}/$f" 2>/dev/null; done
    info "licences: ${sharedir}"
  else
    info "note: could not create ${sharedir}; the licences are also available with: maple-harness licenses"
  fi
fi

# herdr needs nothing installed.
#
# It used to need two things: `herdr integration install <id>`, and a
# symlink putting a borrowed agent name on PATH. The symlink existed
# because herdr's hook script only runs for an agent herdr launched
# itself, and launching means `herdr agent start --kind <k>` where the
# kind is the executable name herdr types into the pane.
#
# The harness reports to herdr directly now
# (app/harness/internal/herdr): it finds the socket at its fixed path,
# works out which pane it is in by walking its own process ancestry
# against `pane.process_info`, and calls `pane.report_agent` under its
# own name. Verified on herdr 0.9.0 — an unknown agent id is accepted
# for *reporting*, even though detection manifests reject one, which is
# the distinction the old advice missed.
#
# So there is no integration to install, no id to borrow, no shim on
# PATH, and nothing for this installer to do. Start the harness in a
# herdr pane however you like and the pane labels itself.
install_herdr_shim() {
  command -v herdr >/dev/null 2>&1 || return 0
  info "herdr: detected — the harness reports its state directly, nothing to install."
  return 0
}

[ -n "$NO_HERDR" ] || install_herdr_shim

# --------------------------------------------------------------------------
# Report
# --------------------------------------------------------------------------
printf '\n%sInstalled%s\n' "$BOLD" "$RESET"
for bin in "${BINARIES[@]}"; do
  if [ -x "${bindir}/${bin}" ]; then
    printf '  %-32s %s\n' "$bin" "$("${bindir}/${bin}" version 2>/dev/null | head -n1 || echo 'installed')"
  fi
done

case ":${PATH}:" in
  *":${bindir}:"*)
    # shellcheck disable=SC2016  # backticks here are prose, not a subshell
    printf '\n%sRun `maple-harness` (or `cch`) to get started.%s\n\n' "$DIM" "$RESET"
    ;;
  *)
    printf '\n%s!%s %s is not on your PATH. Add it:\n\n' "$RED" "$RESET" "$bindir"
    # shellcheck disable=SC2016  # $PATH must stay literal: this is advice to paste, not to run
    printf '    echo '\''export PATH="%s:$PATH"'\'' >> ~/.zshrc && exec zsh\n\n' "$bindir"
    ;;
esac

# Optional: the bash sandbox needs bubblewrap on Linux (macOS has its own).
optional_sandbox_hint() {
  [ "$(uname -s)" = "Linux" ] || return 0
  [ -n "${MAPLE_TEST_HAVE_BWRAP:-}" ] && return 0
  if [ -z "${MAPLE_TEST_OS_RELEASE:-}" ]; then
    command -v bwrap >/dev/null 2>&1 && return 0
  fi
  local rel="${MAPLE_TEST_OS_RELEASE:-/etc/os-release}" ids="" cmd
  [ -r "$rel" ] && ids="$(grep -E '^(ID|ID_LIKE)=' "$rel" | tr -d '"' | cut -d= -f2 | tr '\n' ' ')"
  case " $ids " in
    *" arch "*|*" manjaro "*)     cmd="sudo pacman -S bubblewrap" ;;
    *" debian "*|*" ubuntu "*)    cmd="sudo apt install bubblewrap" ;;
    *" fedora "*|*" rhel "*)      cmd="sudo dnf install bubblewrap" ;;
    *" opensuse "*|*" suse "*)    cmd="sudo zypper install bubblewrap" ;;
    *" alpine "*)                 cmd="sudo apk add bubblewrap" ;;
    *) cmd="" ;;
  esac
  printf '%sOptional:%s bubblewrap lets the harness contain bash commands (/sandbox).\n' "$BOLD" "$RESET"
  if [ -n "$cmd" ]; then
    printf '  %s\n\n' "$cmd"
  else
    printf '  Arch: sudo pacman -S bubblewrap | Debian/Ubuntu: sudo apt install bubblewrap | Fedora: sudo dnf install bubblewrap\n\n'
  fi
}
optional_sandbox_hint

printf '%sUpdate later with:  maple-harness update%s\n\n' "$DIM" "$RESET"
