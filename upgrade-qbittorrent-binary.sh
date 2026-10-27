#!/usr/bin/env bash
# Safely replace the qBittorrent binary in an existing Feral Hosting slot.
# Does not rewrite qBittorrent.conf, the nginx proxy, or Feral's container start script.
set -Eeuo pipefail
umask 077

QB_VERSION="${QB_VERSION:-5.3.0}"
LT_VERSION="${LT_VERSION:-1.2.20}"
PATCHED_REPO="${QB_PATCHED_REPO:-race-in/frealqbit1.2.20}"
BIN="${HOME}/.config/feral/ns/containers/docs-qbittorrent/qbittorrent-nox"
CONTAINER_DIR="${HOME}/.config/feral/ns/containers/docs-qbittorrent"
BACKUP_DIR="${HOME}/qbittorrent-backup"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
note() { printf '\n==> %s\n' "$*"; }

[[ "$QB_VERSION" =~ ^[0-9]+(\.[0-9]+){2,3}$ ]] || die "Invalid QB_VERSION: $QB_VERSION"
[[ "$LT_VERSION" =~ ^1\.2\.[0-9]+$ ]] || die "Only libtorrent 1.2.x is supported: $LT_VERSION"
[[ -x "$BIN" ]] || die "Existing Feral binary not found/executable: $BIN"
[[ -d "$CONTAINER_DIR" ]] || die "Feral container directory not found: $CONTAINER_DIR"
command -v curl >/dev/null 2>&1 || die "curl is required."
command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required."
command -v pgrep >/dev/null 2>&1 || die "pgrep is required."

BASE="https://github.com/${PATCHED_REPO}/releases/download/release-${QB_VERSION}_v${LT_VERSION}"
BINARY_URL="${BASE}/x86_64-qbittorrent-nox"
SUM_URL="${BINARY_URL}.sha256"
PATCHES_URL="${BASE}/patches-used.txt"
TMP="$(mktemp "${CONTAINER_DIR}/.qbittorrent-nox.new.XXXXXX")"
SUM_TMP="${TMP}.sha256"
PATCHES_TMP="${TMP}.patches-used"
cleanup() { rm -f "$TMP" "$SUM_TMP" "$PATCHES_TMP"; }
trap cleanup EXIT

note "Checking release metadata for qBittorrent $QB_VERSION + libtorrent $LT_VERSION"
curl -fsSL --retry 3 --connect-timeout 20 "$PATCHES_URL" -o "$PATCHES_TMP" ||
  die "Release metadata unavailable. Build and publish the patched release first."
grep -Fq "qBittorrent $QB_VERSION + libtorrent $LT_VERSION" "$PATCHES_TMP" ||
  die "Release metadata does not match the requested versions."
grep -Fq "jerry048/Patch" "$PATCHES_TMP" ||
  die "Release metadata does not identify jerry048/Patch."
grep -Fq "patches/libtorrent/$LT_VERSION" "$PATCHES_TMP" ||
  die "Release metadata does not confirm the requested libtorrent patch."
grep -Fq "applied cleanly to $QB_VERSION" "$PATCHES_TMP" ||
  die "Release metadata does not confirm a compatible qBittorrent patch."

note "Downloading binary and published SHA-256"
curl -fsSL --retry 3 --connect-timeout 20 "$BINARY_URL" -o "$TMP" ||
  die "Could not download patched binary."
curl -fsSL --retry 3 --connect-timeout 20 "$SUM_URL" -o "$SUM_TMP" ||
  die "Could not download the published checksum."
EXPECTED="$(awk 'NR==1 {print $1}' "$SUM_TMP")"
[[ "$EXPECTED" =~ ^[0-9a-fA-F]{64}$ ]] || die "Invalid SHA-256 file from release."
printf '%s  %s\n' "$EXPECTED" "$TMP" | sha256sum -c - ||
  die "Binary checksum verification failed."
chmod 700 "$TMP"

VERSION_OUTPUT="$("$TMP" --version 2>&1)" || die "Downloaded binary failed its --version check."
printf '%s\n' "$VERSION_OUTPUT"
grep -Fq "qBittorrent v$QB_VERSION" <<<"$VERSION_OUTPUT" ||
  die "Downloaded binary version does not match qBittorrent $QB_VERSION."

note "Saving a timestamped backup of the current binary"
mkdir -p "$BACKUP_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${BACKUP_DIR}/qbittorrent-nox.${STAMP}.original"
cp -p "$BIN" "$BACKUP"
printf 'Backup: %s\n' "$BACKUP"
printf 'Backup SHA-256: '
sha256sum "$BACKUP"

note "Atomically replacing the binary (configuration and Feral startup files are untouched)"
mv -f "$TMP" "$BIN"
chmod 700 "$BIN"

note "Stopping only qBittorrent processes launched from this Feral binary"
MATCHED=0
STOPPED=0
for pid in $(pgrep -x qbittorrent-nox 2>/dev/null || true); do
  [[ -r "/proc/$pid/cmdline" ]] || continue
  cmdline="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
  exe="$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)"
  if [[ "$cmdline" == *"$BIN"* || "$exe" == "$BIN" || "$exe" == "$BIN (deleted)" ]]; then
    MATCHED=1
    printf 'Sending TERM to PID %s\n' "$pid"
    kill -TERM "$pid" 2>/dev/null || true
    for _ in {1..20}; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 1
    done
    if kill -0 "$pid" 2>/dev/null; then
      printf 'WARNING: PID %s is still running. Not force-killing it.\n' "$pid" >&2
    else
      STOPPED=1
    fi
  fi
done

printf '\nInstalled binary: %s\n' "$BIN"
printf 'Version: '
"$BIN" --version
printf 'SHA-256: '
sha256sum "$BIN"

if [[ "$MATCHED" == "1" && "$STOPPED" == "0" ]]; then
  printf '\nWARNING: The old process may still be running. Stop it gracefully from your Feral slot controls; do not use pkill -9.\n' >&2
elif [[ "$MATCHED" == "1" ]]; then
  printf '\nqBittorrent was stopped. Feral should auto-restart it within about five minutes.\n'
else
  printf '\nNo matching qBittorrent process was found. Feral should start the new binary on its next cycle.\n'
fi
printf 'The qBittorrent configuration, WebUI credentials, port, torrent state, nginx proxy and Feral start script were not edited.\n'
