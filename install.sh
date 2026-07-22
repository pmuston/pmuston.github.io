#!/bin/sh
# install.sh — download and install a pmuston CLI tool from its GitHub release.
#
#   curl -fsSL https://pmuston.github.io/install.sh | sh -s <tool>
#
# Works on Linux and macOS (amd64/arm64). It reuses the same release tarballs
# the Homebrew tap serves, so there is nothing extra to host but this script and
# a small tool->repo manifest. No auto-update: re-run to upgrade.
#
# Env overrides:
#   VERSION   pin a version, e.g. v0.1.2   (default: latest release)
#   BIN_DIR   where the binary goes        (default: ~/.local/bin)
#   MAN_DIR   where the man page goes       (default: <BIN_DIR>/../share/man/man1)
#   OWNER     GitHub owner                  (default: pmuston, or manifest)
#   REPO      release repo                  (default: looked up in the manifest)
set -eu

OWNER="${OWNER:-pmuston}"
MANIFEST_URL="${MANIFEST_URL:-https://pmuston.github.io/tools.json}"

TOOL="${1:-${TOOL:-}}"
[ -n "$TOOL" ] || { echo "usage: install.sh <tool>" >&2; exit 2; }

have() { command -v "$1" >/dev/null 2>&1; }
fetch()    { if have curl; then curl -fsSL "$1"; elif have wget; then wget -qO- "$1"; else echo "need curl or wget" >&2; exit 1; fi; }
fetch_to() { if have curl; then curl -fsSL -o "$2" "$1"; elif have wget; then wget -qO "$2" "$1"; else echo "need curl or wget" >&2; exit 1; fi; }
final_url(){ curl -fsSLI -o /dev/null -w '%{url_effective}' "$1"; }
sha256()   { if have sha256sum; then sha256sum "$1" | awk '{print $1}'; elif have shasum; then shasum -a 256 "$1" | awk '{print $1}'; fi; }

# Resolve the release repo for this tool from the manifest (unless REPO is set).
# The manifest is flat JSON: { "tool": { "owner": "..", "repo": ".." }, ... }
if [ -z "${REPO:-}" ]; then
  entry="$(fetch "$MANIFEST_URL" | tr -d ' \n' | sed -n "s/.*\"$TOOL\":{\([^}]*\)}.*/\1/p")"
  [ -n "$entry" ] || { echo "error: '$TOOL' not found in $MANIFEST_URL (or set REPO=)" >&2; exit 1; }
  REPO="$(printf '%s' "$entry" | sed -n 's/.*"repo":"\([^"]*\)".*/\1/p')"
  eowner="$(printf '%s' "$entry" | sed -n 's/.*"owner":"\([^"]*\)".*/\1/p')"
  [ -n "$eowner" ] && OWNER="$eowner"
fi
[ -n "${REPO:-}" ] || { echo "error: no repo resolved for '$TOOL'" >&2; exit 1; }

# OS / arch, mapped to the release asset naming.
os="$(uname -s)"; arch="$(uname -m)"
case "$os"   in Linux) os=linux;; Darwin) os=darwin;; *) echo "error: unsupported OS $os" >&2; exit 1;; esac
case "$arch" in x86_64|amd64) arch=amd64;; aarch64|arm64) arch=arm64;; *) echo "error: unsupported arch $arch" >&2; exit 1;; esac

# Latest version via the /releases/latest redirect (no API, no rate limit).
if [ -z "${VERSION:-}" ]; then
  VERSION="$(final_url "https://github.com/$OWNER/$REPO/releases/latest")"
  VERSION="${VERSION##*/}"
fi
case "$VERSION" in v*) ;; *) VERSION="v$VERSION";; esac
[ "$VERSION" != "v" ] && [ "${VERSION#v}" != "latest" ] || { echo "error: could not resolve version (set VERSION=)" >&2; exit 1; }

asset="$TOOL-$VERSION-$os-$arch.tar.gz"
base="https://github.com/$OWNER/$REPO/releases/download/$VERSION"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "Downloading $asset ..." >&2
fetch_to "$base/$asset" "$tmp/$asset"

# Verify against the release's checksums.txt when both sides are available.
if fetch_to "$base/checksums.txt" "$tmp/checksums.txt" 2>/dev/null; then
  want="$(grep " $asset\$" "$tmp/checksums.txt" 2>/dev/null | awk '{print $1}' || true)"
  got="$(sha256 "$tmp/$asset")"
  if [ -n "$want" ] && [ -n "$got" ]; then
    [ "$want" = "$got" ] || { echo "error: checksum mismatch for $asset" >&2; exit 1; }
    echo "Checksum OK" >&2
  else
    echo "warning: could not verify checksum" >&2
  fi
fi

tar -xzf "$tmp/$asset" -C "$tmp"
dir="$tmp/${asset%.tar.gz}"
[ -f "$dir/$TOOL" ] || { echo "error: '$TOOL' not found inside $asset" >&2; exit 1; }

BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
MAN_DIR="${MAN_DIR:-${BIN_DIR%/bin}/share/man/man1}"

mkdir -p "$BIN_DIR"
if have install; then install -m 0755 "$dir/$TOOL" "$BIN_DIR/$TOOL"
else cp "$dir/$TOOL" "$BIN_DIR/$TOOL" && chmod 0755 "$BIN_DIR/$TOOL"; fi
echo "Installed $TOOL $VERSION -> $BIN_DIR/$TOOL" >&2

if [ -f "$dir/$TOOL.1" ]; then
  mkdir -p "$MAN_DIR"
  cp "$dir/$TOOL.1" "$MAN_DIR/$TOOL.1"
  echo "Installed man page -> $MAN_DIR/$TOOL.1" >&2
fi

# man-db derives its search path from PATH ($dir/bin -> $dir/share/man), so a
# BIN_DIR on PATH makes `man $TOOL` work with no extra config.
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "note: $BIN_DIR is not on your PATH — add:  export PATH=\"$BIN_DIR:\$PATH\"" >&2;;
esac
