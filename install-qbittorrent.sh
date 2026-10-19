#!/usr/bin/env bash
# install-qbittorrent.sh  --  qBittorrent-nox installer for Feral Hosting slots
#
# * Same mechanism as Feral's own qBittorrent installer (nginx reverse proxy at
#   /qbittorrent/, container start script, binary fetched on first start).
# * Binary is pinned to qBittorrent 5.2.4 + libtorrent 1.2.20 and is downloaded
#   from the userdocs/qbittorrent-nox-static GitHub release. Versions that are not
#   there (e.g. 4.3.9) come from the jerry048/Dedicated-Seedbox binaries, SHA-256 checked.
# * qBittorrent.conf uses the tuning profiles from jerry048/Dedicated-Seedbox
#   (https://github.com/jerry048/Dedicated-Seedbox).
#
# One-line install:
#   wget -O ~/install-qbittorrent.sh https://raw.githubusercontent.com/race-in/frealqbit1.2.20/main/install-qbittorrent.sh && bash ~/install-qbittorrent.sh
#
# Optional environment variables (put them in front of the bash command):
#   QB_VERSION          qBittorrent version, or "latest"            (default: 5.2.4)
#   LT_VERSION          libtorrent version                          (default: 1.2.20)
#   QB_PROFILE          tuning profile                              (default: 1g-ssd)
#                       1g-hdd 1g-hdd-raid0 1g-ssd 1g-nvme 1g-ceph
#                       10g-hdd 10g-hdd-raid0 10g-ssd 10g-nvme 10g-ceph
#   QB_CACHE_MIB        disk cache / working-set limit in MiB       (default: 1024)
#   QB_WEB_PORT         local WebUI port behind nginx               (default: 9001)
#   QB_INCOMING_PORT    fixed incoming peer port                    (default: qBittorrent picks one)
#   QB_MAX_CONNECTIONS  global connection limit                     (default: qBittorrent default)
#   QB_URL              full binary URL (overrides version/URL logic)
#   QB_SHA256           expected SHA-256 of the binary (verified on download)
#
# Example:
#   QB_PROFILE=1g-nvme QB_CACHE_MIB=2048 bash ~/install-qbittorrent.sh

QB_VERSION="${QB_VERSION:-5.2.4}"
LT_VERSION="${LT_VERSION:-1.2.20}"
QB_PROFILE="${QB_PROFILE:-1g-ssd}"
QB_CACHE_MIB="${QB_CACHE_MIB:-1024}"
QB_WEB_PORT="${QB_WEB_PORT:-9001}"
QB_INCOMING_PORT="${QB_INCOMING_PORT:-}"
QB_MAX_CONNECTIONS="${QB_MAX_CONNECTIONS:-}"
QB_SHA256="${QB_SHA256:-}"
REPO="userdocs/qbittorrent-nox-static"

die() { echo "ERROR: $*" >&2; exit 1; }

if [[ ! -d ~/.nginx ]]; then
    echo "This install script requires nginx on your slot. See: https://www.feralhosting.com/wiki/software/nginx"
    exit 1
fi

[[ "$QB_CACHE_MIB" =~ ^[0-9]+$ ]] || die "QB_CACHE_MIB must be a number."
[[ "$QB_WEB_PORT" =~ ^[0-9]+$ ]] || die "QB_WEB_PORT must be a number."

# ---------------------------------------------------------------- download URL
# Source 1: userdocs/qbittorrent-nox-static (recent versions).
# Source 2: binaries bundled in jerry048/Dedicated-Seedbox (older versions such as 4.3.9),
#           pinned to one commit and verified with SHA-256.
JERRY_BASE="https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/4eed056b1e25489eba462c4aa6ca2ae33a43a5a2/Torrent%20Clients/qBittorrent/x86_64"

# jerry_sha256 <qb_version> <libtorrent_version>  (x86_64 builds only)
jerry_sha256() {
    case "$1_$2" in
        4.2.5_1.2.20) echo "56dee662be42f272e470236b51449c3e9ecb858280901c546f2c0aa42e071a65" ;;
        4.3.9_1.2.20) echo "3dabfe162c9177570caa0eddc97b96e82a71c34199f71346c948c97801000b5e" ;;
        4.4.5_1.2.20) echo "dab0a26c5267894c144aad41d4143d7999c5ed49e43db6d50b5113b3d6a6a21b" ;;
        4.4.5_2.0.13) echo "7734bc35651411cbebe16d0f42906c4890222712a5db464979e47535142e5b6f" ;;
        4.5.5_1.2.20) echo "4155ce524fa08a29e3e13702bd7d00ba8d2123b391524119fdec799fa6a2d204" ;;
        4.5.5_2.0.13) echo "f7faceeade0b8bd8b9ca582165ef041bc19b3af4cbdd8732334b1b730f8077f3" ;;
        4.6.7_1.2.20) echo "9f2ff7073c35da549507fc2d5024950dc3288652a3814ef732df7f2f8b6e3207" ;;
        4.6.7_2.0.13) echo "10f02dfbf4bd4649f3100d0116339f45cf3f13ce73997d8e716819e4ff0ba5fa" ;;
        5.0.5_1.2.20) echo "fe8b3e18a1855d9792b1c77e159656fde8593915880ebb897f52521001016540" ;;
        5.0.5_2.0.13) echo "78014f2ba975107dd0c217ef5c5e16a1af65c561211346c367133efb425804f9" ;;
        5.1.4_1.2.20) echo "c0c36a0bd44db9972875534af14e8165e249723138e5c54a769dcd8e3a7c72ec" ;;
        5.1.4_2.0.13) echo "fe4a0f1fe6e38e2797f5488ace2780fe96ed9916debea2b38ac41b8d18b8fda7" ;;
        5.2.2_1.2.20) echo "c4c2dcbf396f57e411a6fefe1ed092397ee3e3372ae6f680f44bcca792d2f043" ;;
        5.2.2_2.0.13) echo "8913a7cc3a30ef2ce1104165c2b8bf0eed19994bb7c0741d45376079710d84b6" ;;
        *) return 1 ;;
    esac
}

url_exists() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsIL --max-time 30 -o /dev/null "$1"
    else
        wget -q --spider --timeout=30 "$1"
    fi
}

case "$QB_VERSION" in
    4.1.*|4.0.*|3.*) die "qBittorrent $QB_VERSION is not supported by this installer (minimum 4.2)." ;;
esac

if [[ -n "${QB_URL:-}" ]]; then
    URL="$QB_URL"
elif [[ "$QB_VERSION" == "latest" ]]; then
    URL="https://github.com/$REPO/releases/latest/download/x86_64-qbittorrent-nox"
else
    URL="https://github.com/$REPO/releases/download/release-${QB_VERSION}_v${LT_VERSION}/x86_64-qbittorrent-nox"
    if ! url_exists "$URL"; then
        if jerry_sha="$(jerry_sha256 "$QB_VERSION" "$LT_VERSION")"; then
            echo "qBittorrent $QB_VERSION + libtorrent $LT_VERSION is not a userdocs release; using the jerry048/Dedicated-Seedbox build."
            URL="$JERRY_BASE/qBittorrent-${QB_VERSION}%20-%20libtorrent-v${LT_VERSION}/qbittorrent-nox"
            [[ -n "$QB_SHA256" ]] || QB_SHA256="$jerry_sha"
        else
            die "No binary found for qBittorrent $QB_VERSION + libtorrent $LT_VERSION. Check https://github.com/$REPO/releases or set QB_URL."
        fi
    fi
fi

# ---------------------------------------------------------------- tuning table
# (values taken from jerry048/Dedicated-Seedbox, lib/components/qbittorrent.bash)

# "<AsyncIOThreads> <SendBufferLowWatermark> <SendBufferWatermark> <SendBufferWatermarkFactor>"
profile_common() {
    case "$1" in
        1g-hdd)        echo "4 1024 4096 150" ;;
        1g-hdd-raid0)  echo "8 1024 8192 150" ;;
        1g-ssd)        echo "12 1024 8192 200" ;;
        1g-nvme)       echo "16 1024 16384 200" ;;
        1g-ceph)       echo "8 1024 16384 200" ;;
        10g-hdd)       echo "4 1024 16384 150" ;;
        10g-hdd-raid0) echo "8 1024 16384 150" ;;
        10g-ssd)       echo "16 2048 32768 200" ;;
        10g-nvme)      echo "32 2048 32768 200" ;;
        10g-ceph)      echo "16 2048 32768 200" ;;
        *) return 1 ;;
    esac
}

# libtorrent 2.x only: "<HashingThreads> <DiskIOType>"
profile_lt2() {
    case "$1" in
        1g-hdd)        echo "1 Default" ;;
        1g-hdd-raid0)  echo "2 Default" ;;
        1g-ssd)        echo "4 Default" ;;
        1g-nvme)       echo "8 MMap" ;;
        1g-ceph)       echo "2 SimplePreadPwrite" ;;
        10g-hdd)       echo "1 Default" ;;
        10g-hdd-raid0) echo "2 Default" ;;
        10g-ssd)       echo "8 Default" ;;
        10g-nvme)      echo "16 MMap" ;;
        10g-ceph)      echo "4 SimplePreadPwrite" ;;
        *) return 1 ;;
    esac
}

# qBittorrent >= 4.5.5: "<DiskQueueSize MiB> <RequestQueueSize>"
profile_qb455() {
    case "$1" in
        1g-hdd)        echo "16 1000" ;;
        1g-hdd-raid0)  echo "64 2000" ;;
        1g-ssd)        echo "128 2000" ;;
        1g-nvme)       echo "256 4000" ;;
        1g-ceph)       echo "64 2000" ;;
        10g-hdd)       echo "32 1000" ;;
        10g-hdd-raid0) echo "128 2000" ;;
        10g-ssd)       echo "256 4000" ;;
        10g-nvme)      echo "512 8000" ;;
        10g-ceph)      echo "256 4000" ;;
        *) return 1 ;;
    esac
}

# version_ge A B  ->  true if A >= B
version_ge() { [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" == "$2" ]]; }

common="$(profile_common "$QB_PROFILE")" || die "Unknown QB_PROFILE '$QB_PROFILE'. See the list at the top of this script."
read -r AIO LOW_BUF BUF BUF_FACTOR <<<"$common"

TUNE_VERSION="$QB_VERSION"
[[ "$TUNE_VERSION" == "latest" ]] && TUNE_VERSION="99.0.0"

session_extra=()
lt_major="${LT_VERSION#v}"; lt_major="${lt_major%%.*}"
if [[ "$QB_VERSION" != "latest" && "$lt_major" == "2" ]]; then
    read -r HASHING DISKIO <<<"$(profile_lt2 "$QB_PROFILE")"
    if [[ "$DISKIO" == "SimplePreadPwrite" ]] && ! version_ge "$TUNE_VERSION" "5.0.1"; then
        DISKIO="Posix"
    fi
    session_extra+=("Session\\HashingThreadsCount=$HASHING" "Session\\DiskIOType=$DISKIO")
fi
if version_ge "$TUNE_VERSION" "4.4.5"; then
    session_extra+=("Session\\ConnectionSpeed=500")
fi
if version_ge "$TUNE_VERSION" "4.5.5"; then
    read -r DQ_MIB REQ_Q <<<"$(profile_qb455 "$QB_PROFILE")"
    session_extra+=("Session\\DiskQueueSize=$((DQ_MIB * 1024 * 1024))" "Session\\RequestQueueSize=$REQ_Q")
fi
if version_ge "$TUNE_VERSION" "4.6.7"; then
    session_extra+=("Session\\SocketSendBufferSize=0" "Session\\SocketReceiveBufferSize=0")
fi
# qBittorrent 4.2.x / 4.3.x use the "classic" config layout, 4.4+ the "modern" one.
case "$QB_VERSION" in
    4.2.*|4.3.*) CONF_FAMILY="classic" ;;
    *)           CONF_FAMILY="modern" ;;
esac
if [[ "$CONF_FAMILY" == "modern" ]]; then
    [[ -n "$QB_INCOMING_PORT" ]]   && session_extra+=("Session\\Port=$QB_INCOMING_PORT")
    [[ -n "$QB_MAX_CONNECTIONS" ]] && session_extra+=("Session\\MaxConnections=$QB_MAX_CONNECTIONS")
fi

# ------------------------------------------------------- stop existing processes
rm -rf ~/.config/feral/ns/containers/docs-qbittorrent 2>/dev/null || true
rm ~/.config/feral/user-container.d/wiki-qbittorrent 2>/dev/null || true
pkill -x qbittorrent-nox 2>/dev/null || true
sleep 3
pkill -9 -x qbittorrent-nox 2>/dev/null || true

# ------------------------------------------------------------------- password
pass="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 15; echo '')"
salt="$(head -c 16 /dev/urandom | base64)"
if command -v python3 >/dev/null 2>&1; then
    hmac="$(QB_PASS="$pass" QB_SALT="$salt" python3 -c 'import base64, hashlib, os
print(base64.b64encode(hashlib.pbkdf2_hmac("sha512", os.environ["QB_PASS"].encode(), base64.b64decode(os.environ["QB_SALT"]), 100000)).decode())')"
elif command -v php >/dev/null 2>&1; then
    hmac="$(QB_PASS="$pass" QB_SALT="$salt" php -r 'echo base64_encode(hash_pbkdf2("sha512", getenv("QB_PASS"), base64_decode(getenv("QB_SALT")), 100000, 0, true));')"
else
    die "Need python3 or php to hash the WebUI password."
fi
[[ -n "$hmac" ]] || die "Could not generate the password hash."

# --------------------------------------------------------------- qBittorrent.conf
mkdir -p ~/.config/qBittorrent
conf=~/.config/qBittorrent/qBittorrent.conf
if [[ -f "$conf" ]]; then
    cp -f "$conf" "$conf.bak.$(date +%Y%m%d-%H%M%S)"
fi
(
    umask 077
    if [[ "$CONF_FAMILY" == "modern" ]]; then
        {
            echo "[Application]"
            echo "MemoryWorkingSetLimit=$QB_CACHE_MIB"
            echo
            echo "[BitTorrent]"
            echo "Session\\AsyncIOThreadsCount=$AIO"
            echo "Session\\DefaultSavePath=$HOME/private/qbittorrent/data/"
            echo "Session\\DiskCacheSize=$QB_CACHE_MIB"
            echo "Session\\QueueingSystemEnabled=false"
            echo "Session\\SendBufferLowWatermark=$LOW_BUF"
            echo "Session\\SendBufferWatermark=$BUF"
            echo "Session\\SendBufferWatermarkFactor=$BUF_FACTOR"
            for line in "${session_extra[@]}"; do echo "$line"; done
            echo
            echo "[LegalNotice]"
            echo "Accepted=true"
            echo
            echo "[Network]"
            echo "Cookies=@Invalid()"
            echo
            echo "[Preferences]"
            echo "WebUI\\Username=$(whoami)"
            echo "WebUI\\Password_PBKDF2=\"@ByteArray($salt:$hmac)\""
            echo "WebUI\\Port=$QB_WEB_PORT"
            echo "WebUI\\MaxAuthenticationFailCount=60"
        } >"$conf"
    else
        {
            echo "[BitTorrent]"
            echo "Session\\AsyncIOThreadsCount=$AIO"
            echo "Session\\SendBufferLowWatermark=$LOW_BUF"
            echo "Session\\SendBufferWatermark=$BUF"
            echo "Session\\SendBufferWatermarkFactor=$BUF_FACTOR"
            for line in "${session_extra[@]}"; do echo "$line"; done
            echo
            echo "[LegalNotice]"
            echo "Accepted=true"
            echo
            echo "[Network]"
            echo "Cookies=@Invalid()"
            echo
            echo "[Preferences]"
            [[ -n "$QB_INCOMING_PORT" ]]   && echo "Connection\\PortRangeMin=$QB_INCOMING_PORT"
            [[ -n "$QB_MAX_CONNECTIONS" ]] && echo "Bittorrent\\MaxConnecs=$QB_MAX_CONNECTIONS"
            echo "Downloads\\DiskWriteCacheSize=$QB_CACHE_MIB"
            echo "Downloads\\SavePath=$HOME/private/qbittorrent/data/"
            echo "Queueing\\QueueingEnabled=false"
            echo "WebUI\\Username=$(whoami)"
            echo "WebUI\\Password_PBKDF2=\"@ByteArray($salt:$hmac)\""
            echo "WebUI\\Port=$QB_WEB_PORT"
            echo "WebUI\\MaxAuthenticationFailCount=60"
        } >"$conf"
    fi
)
mkdir -p ~/private/qbittorrent/data

# --------------------------------------------------------------- reverse proxy
echo "location /qbittorrent/ {
    proxy_pass http://127.0.0.1:$QB_WEB_PORT/;
    proxy_http_version 1.1;
    proxy_set_header Host              \$http_x_host;
    proxy_set_header X-Forwarded-Host  \$http_x_host;
    proxy_set_header X-Real-IP         \$remote_addr;
    proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$http_x_forwarded_proto;
}" >~/.nginx/conf.d/000-default-server.d/qbittorrent.conf
rm ~/.nginx/conf.d/000-default-server.d/wiki-qbittorrent.conf 2>/dev/null || true
/usr/sbin/nginx -s reload -c ~/.nginx/nginx.conf 2>/dev/null

# --------------------------------------------------------------- launch script
mkdir -p ~/.config/feral/ns/containers/docs-qbittorrent
pushd ~/.config/feral/ns/containers/docs-qbittorrent >/dev/null
rm -f qbittorrent-nox
echo debian-trixie >root

cat >start <<'EOF_START'
#!/usr/bin/env bash
set -eux -o pipefail

pushd "$FERAL_SLOTNS_PATH"
# Download the binary if it is missing
if [[ ! -f qbittorrent-nox ]]; then
    wget --no-verbose -O qbittorrent-nox.part "@QB_URL@"
    if [[ -n "@QB_SHA256@" ]]; then
        echo "@QB_SHA256@  qbittorrent-nox.part" | sha256sum -c -
    fi
    chmod +x qbittorrent-nox.part
    mv -f qbittorrent-nox.part qbittorrent-nox
    # Trigger restart
    pkill -x qbittorrent-nox || true
fi
popd

# Start
cd "$HOME"
export TMPDIR="$FERAL_SLOTNS_PATH/tmp"
mkdir -p "$TMPDIR"
[[ "$(pgrep -x 'qbittorrent-nox')" ]] || exec "$FERAL_SLOTNS_PATH/qbittorrent-nox"
EOF_START
sed -i -e "s|@QB_URL@|$URL|g" -e "s|@QB_SHA256@|$QB_SHA256|g" start
chmod +x start
popd >/dev/null

# ---------------------------------------------------------------------- report
if [[ "$QB_VERSION" == "latest" ]]; then
    echo "qBittorrent (latest release) has been successfully installed. Tuning profile: $QB_PROFILE."
else
    echo "qBittorrent $QB_VERSION (libtorrent $LT_VERSION) has been successfully installed. Tuning profile: $QB_PROFILE."
fi
echo "It will be running in five minutes."
echo
echo "URL: https://$(whoami).$(hostname -f)/qbittorrent/"
echo "Username: $(whoami)"
echo "Password: $pass"
echo
echo "Save this password now; it is not stored anywhere in plain text."
