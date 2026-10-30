#!/usr/bin/env bash
# Safely replace only the qBittorrent binary in an existing Feral slot.
# Configuration, credentials, torrent state, nginx and Feral startup files stay untouched.
set -Eeuo pipefail
umask 077

QB_VERSION="${QB_VERSION:-5.3.0}"
LT_VERSION="${LT_VERSION:-1.2.20}"
LT_VERSION="${LT_VERSION#libtorrent-}"
LT_VERSION="${LT_VERSION#v}"
[[ "$LT_VERSION" == "1_1_14" ]] && LT_VERSION="1.1.14"
PATCHED_REPO="${QB_PATCHED_REPO:-race-in/frealqbit1.2.20}"
MANIFEST_URL="https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/manifests/qbittorrent.tsv"
BIN="$HOME/.config/feral/ns/containers/docs-qbittorrent/qbittorrent-nox"
CONTAINER_DIR="$HOME/.config/feral/ns/containers/docs-qbittorrent"
BACKUP_DIR="$HOME/qbittorrent-backup"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
note() { printf '\n==> %s\n' "$*"; }
version_ge() { [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" == "$2" ]]; }
config_family() {
  local v="$1"
  if version_ge "$v" "5.3.0"; then printf 'modern_webui\n'
  elif version_ge "$v" "4.4.0"; then printf 'modern_preferences\n'
  elif version_ge "$v" "4.2.0"; then printf 'classic_pbkdf2\n'
  elif version_ge "$v" "4.1.0"; then printf 'legacy_41\n'
  else return 1; fi
}

manifest_family() {
  local v="$1"
  if version_ge "$v" "4.4.0"; then printf 'modern_pbkdf2\n'
  elif version_ge "$v" "4.2.0"; then printf 'classic_pbkdf2\\n'
  elif version_ge "$v" "4.1.0"; then printf 'legacy_41\\n'
  else return 1; fi
}
fetch_text() { curl -fsSL --retry 3 --connect-timeout 20 "$1"; }

[[ "$QB_VERSION" =~ ^[0-9]+(\.[0-9]+){2,3}$ ]] || die "Invalid QB_VERSION: $QB_VERSION"
[[ "$LT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Invalid LT_VERSION: $LT_VERSION"
[[ -x "$BIN" ]] || die "Existing Feral binary not found/executable: $BIN"
[[ -d "$CONTAINER_DIR" ]] || die "Feral container directory not found: $CONTAINER_DIR"
for cmd in curl sha256sum pgrep sort sed awk; do command -v "$cmd" >/dev/null 2>&1 || die "$cmd is required."; done

CURRENT_OUTPUT="$("$BIN" --version 2>&1)" || die "Could not read the current qBittorrent version."
CURRENT_VERSION="$(sed -nE 's/.*qBittorrent v([0-9]+(\.[0-9]+){2,3}).*/\1/p' <<<"$CURRENT_OUTPUT" | head -n1)"
[[ -n "$CURRENT_VERSION" ]] || die "Could not parse current binary version: $CURRENT_OUTPUT"
CURRENT_FAMILY="$(config_family "$CURRENT_VERSION")" || die "Unsupported current config family: $CURRENT_VERSION"
TARGET_FAMILY="$(config_family "$QB_VERSION")" || die "Unsupported target config family: $QB_VERSION"
TARGET_MANIFEST_FAMILY="$(manifest_family "$QB_VERSION")" || die "Unsupported target manifest family: $QB_VERSION"

# A binary-only operation must not cross a qBittorrent configuration schema boundary.
# qB 5.3 moved the WebUI keys from [Preferences] to [WebUI].
[[ "$CURRENT_FAMILY" == "$TARGET_FAMILY" ]] ||
  die "Refusing binary-only change from $CURRENT_VERSION ($CURRENT_FAMILY) to $QB_VERSION ($TARGET_FAMILY). Config migration is required; back up and use the full installer."

BASE="https://github.com/$PATCHED_REPO/releases/download/release-${QB_VERSION}_v${LT_VERSION}"
BINARY_URL="$BASE/x86_64-qbittorrent-nox"
SUM_URL="$BINARY_URL.sha256"
PATCHES_URL="$BASE/patches-used.txt"
EXPECTED=""
PATCHES_TMP=""
MANIFEST_TMP=""
TMP=""
SUM_TMP=""
cleanup() { [[ -z "$PATCHES_TMP" ]] || rm -f "$PATCHES_TMP"; [[ -z "$MANIFEST_TMP" ]] || rm -f "$MANIFEST_TMP"; [[ -z "$TMP" ]] || rm -f "$TMP"; [[ -z "$SUM_TMP" ]] || rm -f "$SUM_TMP"; }
trap cleanup EXIT

# Prefer this repository's mirrored release, which also carries patch metadata.
if curl -fsSL --retry 1 --connect-timeout 10 "$PATCHES_URL" -o /dev/null 2>/dev/null; then
  note "Using mirrored release for qBittorrent $QB_VERSION + libtorrent $LT_VERSION"
  PATCHES_TMP="$(mktemp)"
  fetch_text "$PATCHES_URL" >"$PATCHES_TMP" || die "Could not read release metadata."
  grep -Fq "qBittorrent $QB_VERSION + libtorrent $LT_VERSION" "$PATCHES_TMP" || die "Release metadata version mismatch."
  grep -Fq "jerry048/Patch" "$PATCHES_TMP" || die "Release metadata does not identify jerry048/Patch."
  grep -Fq "patches/libtorrent/$LT_VERSION" "$PATCHES_TMP" || die "Release metadata libtorrent patch mismatch."
  grep -Fq "applied cleanly to $QB_VERSION" "$PATCHES_TMP" || die "Release metadata qBittorrent patch mismatch."
else
  note "Mirror release unavailable; resolving Jerry's current manifest"
  [[ "$LT_VERSION" == "1.1.14" ]] && LT_FIELD="1_1_14" || LT_FIELD="v$LT_VERSION"
  MANIFEST_TMP="$(mktemp)"
  fetch_text "$MANIFEST_URL" >"$MANIFEST_TMP" || die "Could not download Jerry's qBittorrent manifest."
  ROW="$(awk -F '\t' -v qb="$QB_VERSION" -v lt="$LT_FIELD" '
    $0 ~ /^#/ || NF < 7 { next }
    $1 == qb && $2 == lt && $3 == "amd64" && $4 == "static" { print; exit }
  ' "$MANIFEST_TMP")"
  [[ -n "$ROW" ]] || die "Jerry's manifest has no static amd64 build for $QB_VERSION + libtorrent $LT_VERSION."
  IFS=$'\t' read -r M_QB M_LT M_ARCH M_SOURCE BINARY_URL EXPECTED M_FAMILY <<<"$ROW"
  [[ "$M_QB" == "$QB_VERSION" && "$M_LT" == "$LT_FIELD" && "$M_ARCH" == "amd64" && "$M_SOURCE" == "static" ]] || die "Manifest row identity check failed."
  [[ "$BINARY_URL" =~ ^https://raw\.githubusercontent\.com/jerry048/Dedicated-Seedbox/[0-9a-f]{40}/ ]] || die "Manifest URL is not commit-pinned."
  [[ "$EXPECTED" =~ ^[0-9a-fA-F]{64}$ ]] || die "Manifest SHA-256 is invalid."
  case "$M_FAMILY" in legacy_41|classic_pbkdf2|modern_pbkdf2) ;; *) die "Unknown manifest config family: $M_FAMILY" ;; esac
  [[ "$M_FAMILY" == "$TARGET_MANIFEST_FAMILY" ]] || die "Manifest config family does not match the requested qBittorrent version."
  SUM_URL=""
fi

TMP="$(mktemp "$CONTAINER_DIR/.qbittorrent-nox.new.XXXXXX")"
SUM_TMP="$TMP.sha256"
if [[ -n "$SUM_URL" ]]; then
  fetch_text "$SUM_URL" >"$SUM_TMP" || die "Could not download published SHA-256."
  EXPECTED="$(awk 'NR==1 {print $1}' "$SUM_TMP")"
fi
[[ "$EXPECTED" =~ ^[0-9a-fA-F]{64}$ ]] || die "No valid trusted SHA-256 for the requested binary."

note "Downloading qBittorrent $QB_VERSION + libtorrent $LT_VERSION"
fetch_text "$BINARY_URL" >"$TMP" || die "Could not download qBittorrent binary."
printf '%s  %s\n' "$EXPECTED" "$TMP" | sha256sum -c - || die "Binary checksum verification failed."
chmod 700 "$TMP"
VERSION_OUTPUT="$("$TMP" --version 2>&1)" || die "Downloaded binary failed its --version check."
printf '%s\n' "$VERSION_OUTPUT"
grep -Fq "qBittorrent v$QB_VERSION" <<<"$VERSION_OUTPUT" || die "Downloaded binary version mismatch."

note "Saving timestamped backup"
mkdir -p "$BACKUP_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$BACKUP_DIR/qbittorrent-nox.$STAMP.original"
cp -p "$BIN" "$BACKUP"
printf 'Backup: %s\nBackup SHA-256: ' "$BACKUP"
sha256sum "$BACKUP"

note "Atomically replacing the binary (configuration and Feral startup files are untouched)"
mv -f "$TMP" "$BIN"
TMP=""
chmod 700 "$BIN"

note "Stopping only qBittorrent processes launched from this Feral binary"
MATCHED=0
STOPPED=0
for pid in $(pgrep -x qbittorrent-nox 2>/dev/null || true); do
  [[ -r "/proc/$pid/cmdline" ]] || continue
  cmdline="$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null || true)"
  exe="$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)"
  if [[ "$cmdline" == *"$BIN"* || "$exe" == "$BIN" || "$exe" == "$BIN (deleted)" ]]; then
    MATCHED=1
    printf 'Sending TERM to PID %s\n' "$pid"
    kill -TERM "$pid" 2>/dev/null || true
    for _ in {1..20}; do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
    if kill -0 "$pid" 2>/dev/null; then
      printf 'WARNING: PID %s is still running. Not force-killing it.\n' "$pid" >&2
    else
      STOPPED=1
    fi
  fi
done

printf '\nInstalled binary: %s\nVersion: ' "$BIN"
"$BIN" --version
printf 'SHA-256: '
sha256sum "$BIN"
if [[ "$MATCHED" == "1" && "$STOPPED" == "0" ]]; then
  printf '\nWARNING: The old process may still be running. Stop it gracefully from Feral controls; do not use pkill -9.\n' >&2
elif [[ "$MATCHED" == "1" ]]; then
  printf '\nqBittorrent was stopped. Feral should auto-restart within about five minutes.\n'
else
  printf '\nNo matching process found. Feral should start the new binary on its next cycle.\n'
fi
printf 'Configuration, WebUI credentials, port, torrent state, nginx proxy and Feral start script were not edited.\n'
