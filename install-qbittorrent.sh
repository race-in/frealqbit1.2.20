#!/usr/bin/env bash
# install-qbittorrent.sh
# Rootless qBittorrent-nox installer for seedbox / shared hosts (no sudo needed).
# Installs a static qBittorrent-nox build into ~/.local/bin and starts it
# with a randomly chosen free WebUI port.
#
# Usage:
#   bash install-qbittorrent.sh              # install + start
#   bash install-qbittorrent.sh --uninstall  # stop + remove binary (keeps config & downloads)
#
#   # another version (qBittorrent + libtorrent):
#   QB_VERSION=5.2.3 LT_VERSION=2.0.13 bash install-qbittorrent.sh
#   # newest release of the repo, whatever libtorrent it ships with:
#   QB_VERSION=latest bash install-qbittorrent.sh
#
# Optional env vars:
#   QB_VERSION  qBittorrent version, or "latest"   (default: 5.2.4)
#   LT_VERSION  libtorrent version, e.g. 1.2.20 or 2.0.13 (default: 1.2.20)
#   QB_URL      direct URL of a qbittorrent-nox binary (overrides everything above)
#   QB_PORT     WebUI port (default: random free port 20000-60000)
#   QB_BIN_DIR  install dir (default: ~/.local/bin)
#
# Release tags in the source repo look like: release-<QB_VERSION>_v<LT_VERSION>
# Browse them: https://github.com/userdocs/qbittorrent-nox-static/releases

set -euo pipefail

REPO="userdocs/qbittorrent-nox-static"
BIN_DIR="${QB_BIN_DIR:-$HOME/.local/bin}"
BIN="$BIN_DIR/qbittorrent-nox"
PROFILE="$HOME/.qbittorrent"          # --profile dir (config lives in $PROFILE/qBittorrent/config)
LOG="$PROFILE/qbittorrent.log"
PIDFILE="$PROFILE/qbittorrent.pid"
PORT_FILE="$PROFILE/webui.port"

info()  { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()   { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed."; }

stop_qb() {
  if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    kill "$(cat "$PIDFILE")" && info "Stopped running qBittorrent."
    sleep 2
  fi
  rm -f "$PIDFILE"
}

if [[ "${1:-}" == "--uninstall" ]]; then
  stop_qb
  rm -f "$BIN"
  crontab -l 2>/dev/null | grep -v 'qbittorrent-nox' | crontab - 2>/dev/null || true
  info "Removed binary and @reboot cron entry. Config kept in $PROFILE"
  exit 0
fi

need uname
if command -v curl >/dev/null 2>&1; then
  dl() { curl -fL --retry 3 -o "$2" "$1"; }
elif command -v wget >/dev/null 2>&1; then
  dl() { wget -q -O "$2" "$1"; }
else
  die "Need curl or wget."
fi

# ---- pick architecture ----
case "$(uname -m)" in
  x86_64|amd64)  ARCH="x86_64"  ;;
  aarch64|arm64) ARCH="aarch64" ;;
  armv7l)        ARCH="armv7"   ;;
  *) die "Unsupported architecture: $(uname -m)" ;;
esac

if [[ -n "${QB_URL:-}" ]]; then
  URL="$QB_URL"
elif [[ "${QB_VERSION:-5.2.4}" == "latest" ]]; then
  URL="https://github.com/$REPO/releases/latest/download/${ARCH}-qbittorrent-nox"
  info "Using the repo's latest release."
else
  QB_VERSION="${QB_VERSION:-5.2.4}"
  LT_VERSION="${LT_VERSION:-1.2.20}"
  TAG="release-${QB_VERSION}_v${LT_VERSION}"
  URL="https://github.com/$REPO/releases/download/${TAG}/${ARCH}-qbittorrent-nox"
  info "Version: qBittorrent $QB_VERSION + libtorrent $LT_VERSION (tag $TAG)"
fi

# ---- pick a free port ----
port_free() {
  ! (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}
pick_port() {
  local p
  for _ in $(seq 1 50); do
    p=$(( (RANDOM % 40000) + 20000 ))
    if port_free "$p"; then echo "$p"; return; fi
  done
  die "Could not find a free port."
}
PORT="${QB_PORT:-$(pick_port)}"

# ---- install ----
mkdir -p "$BIN_DIR" "$PROFILE"
stop_qb

info "Downloading qbittorrent-nox ($ARCH)..."
TMP="$(mktemp)"
dl "$URL" "$TMP" || die "Download failed: $URL
    Check that this version/libtorrent combo exists: https://github.com/$REPO/releases"
chmod +x "$TMP"
"$TMP" --version >/dev/null 2>&1 || die "Downloaded binary does not run on this system."
mv "$TMP" "$BIN"
info "Installed: $BIN ($("$BIN" --version))"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) warn "$BIN_DIR is not in PATH. Add this to ~/.bashrc:  export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac

# ---- start ----
echo "$PORT" > "$PORT_FILE"
: > "$LOG"
info "Starting qBittorrent on port $PORT..."
nohup "$BIN" --profile="$PROFILE" --webui-port="$PORT" --confirm-legal-notice \
  >>"$LOG" 2>&1 &
echo $! > "$PIDFILE"
sleep 4
kill -0 "$(cat "$PIDFILE")" 2>/dev/null || { cat "$LOG"; die "qBittorrent failed to start."; }

# ---- autostart on reboot (cron) ----
CRON_LINE="@reboot $BIN --profile=$PROFILE --webui-port=$PORT --confirm-legal-notice >>$LOG 2>&1 &"
if command -v crontab >/dev/null 2>&1; then
  ( crontab -l 2>/dev/null | grep -v 'qbittorrent-nox' || true; echo "$CRON_LINE" ) | crontab -
  info "Added @reboot cron entry."
else
  warn "crontab not found; qBittorrent will not auto-start after reboot."
fi

# ---- login info ----
PASS="$(grep -oE 'temporary password[^:]*: *[A-Za-z0-9]+' "$LOG" | tail -n1 | sed 's/.*: *//' || true)"
echo
info "Done!"
echo "  WebUI : http://<your-server-ip>:$PORT"
echo "  User  : admin"
if [[ -n "$PASS" ]]; then
  echo "  Pass  : $PASS   (temporary - change it in Options > WebUI)"
else
  echo "  Pass  : see $LOG (qBittorrent >= 4.6.1 prints a temporary password there)"
fi
echo "  Log   : $LOG"
