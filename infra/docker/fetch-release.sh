#!/usr/bin/env bash
#
# fetch-release.sh VERSION ARCH OUTDIR
#
# Downloads maple-proxy for linux/ARCH from a published release, and refuses it unless it is
# genuine: SHA256SUMS must carry its checksum, and when the release is signed (SHA256SUMS.sig)
# the signature must verify against a trusted release key, exactly as the installer checks it.
# Used by the Dockerfile's build stage; it can be run by hand too.
#
# Environment:
#   MAPLE_REPO          owner/repo of the releases (default kinncj/maple-harness-dist)
#   MAPLE_RELEASE_KEYS  trusted keys, "name=base64 Ed25519 public key", comma separated
#                       (default: the keys built into the installer)
#   MAPLE_DOWNLOAD_BASE where releases are downloaded from (default https://github.com)
set -euo pipefail

VERSION="${1:?usage: fetch-release.sh VERSION ARCH OUTDIR}"
ARCH="${2:?usage: fetch-release.sh VERSION ARCH OUTDIR}"
OUT="${3:?usage: fetch-release.sh VERSION ARCH OUTDIR}"
REPO="${MAPLE_REPO:-kinncj/maple-harness-dist}"
BASE="${MAPLE_DOWNLOAD_BASE:-https://github.com}"
# Must match the installer's RELEASE_KEYS (a test checks it).
RELEASE_KEYS="${MAPLE_RELEASE_KEYS:-PLACEHOLDER-not-a-release-key=kdIYytfg0VNDBAGp4Lco4AjgX+p/7m/mdJsFcSjO5K0=}"

case "$VERSION" in v*) ;; *) VERSION="v${VERSION}" ;; esac
case "$ARCH" in amd64|arm64) ;; *) echo "fetch-release: unsupported architecture ${ARCH} (amd64 or arm64)" >&2; exit 1 ;; esac
asset="maple-proxy_linux_${ARCH}"

err() { printf 'fetch-release: %s\n' "$1" >&2; exit 1; }
fetch() { curl -fsSL --retry 3 -o "$2" "${BASE}/${REPO}/releases/download/${VERSION}/$1"; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fetch SHA256SUMS "$tmp/SHA256SUMS" || err "${VERSION} has no SHA256SUMS; refusing unverified binaries"

# The signed message is "maple-harness-release-v1\n" + tag + "\n" + the exact bytes of SHA256SUMS.
if fetch SHA256SUMS.sig "$tmp/SHA256SUMS.sig" 2>/dev/null; then
  field() { awk -F': *' -v k="$1" '$1 == k { print $2; exit }' "$tmp/SHA256SUMS.sig" | tr -d '\r'; }
  [ "$(head -n1 "$tmp/SHA256SUMS.sig" | tr -d '\r')" = "maple-harness-release-signature v1" ] || err "SHA256SUMS.sig is not a release signature"
  keyid=$(field key); tag=$(field tag); sig=$(field sig)
  [ "$tag" = "$VERSION" ] || err "the signature is for ${tag}, not ${VERSION}"
  pub=""
  for entry in $(printf '%s' "$RELEASE_KEYS" | tr ',' ' '); do
    k="${entry#*=}"
    id=$(printf '%s' "$k" | base64 -d | sha256sum | cut -c1-16)
    if [ "$id" = "$keyid" ]; then pub="$k"; fi
  done
  [ -n "$pub" ] || err "${VERSION} is signed by key ${keyid}, which is not trusted here"
  { printf 'maple-harness-release-v1\n%s\n' "$tag"; cat "$tmp/SHA256SUMS"; } > "$tmp/msg"
  printf '%s' "$sig" | base64 -d > "$tmp/sig"
  { printf '\x30\x2a\x30\x05\x06\x03\x2b\x65\x70\x03\x21\x00'; printf '%s' "$pub" | base64 -d; } > "$tmp/pub.der"
  openssl pkey -pubin -inform DER -in "$tmp/pub.der" -out "$tmp/pub.pem" 2>/dev/null || err "the release key does not read"
  openssl pkeyutl -verify -pubin -inkey "$tmp/pub.pem" -rawin -in "$tmp/msg" -sigfile "$tmp/sig" >/dev/null 2>&1 \
    || err "the signature on SHA256SUMS does NOT match: the release was altered or is not genuine"
  echo "fetch-release: SHA256SUMS signed by key ${keyid} for ${tag}"
else
  case "$RELEASE_KEYS" in
    *PLACEHOLDER-not-a-release-key*) echo "fetch-release: ${VERSION} is not signed; checking its checksums only" ;;
    *) err "${VERSION} is not signed, and a release key is trusted: refusing it" ;;
  esac
fi

fetch "$asset" "$tmp/$asset" || err "${VERSION} has no ${asset}"
want=$(awk -v a="$asset" '$2 == a || $2 == "*"a { print $1; exit }' "$tmp/SHA256SUMS")
[ -n "$want" ] || err "SHA256SUMS has no entry for ${asset}"
got=$(sha256sum "$tmp/$asset" | awk '{print $1}')
[ "$want" = "$got" ] || err "checksum mismatch for ${asset} (expected ${want}, got ${got})"

mkdir -p "$OUT/licenses"
install -m 0555 "$tmp/$asset" "$OUT/maple-proxy"
for f in LICENSE THIRD_PARTY_NOTICES.md; do
  if fetch "$f" "$tmp/$f" 2>/dev/null; then
    w=$(awk -v a="$f" '$2 == a { print $1; exit }' "$tmp/SHA256SUMS")
    if [ -n "$w" ] && [ "$w" = "$(sha256sum "$tmp/$f" | awk '{print $1}')" ]; then cp "$tmp/$f" "$OUT/licenses/$f"; fi
  fi
done
echo "fetch-release: verified ${asset} ${VERSION}"
