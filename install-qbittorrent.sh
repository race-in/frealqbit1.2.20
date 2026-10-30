#!/usr/bin/env bash
# install-qbittorrent.sh  --  qBittorrent-nox installer for Feral Hosting slots
#
# * Same mechanism as Feral's own qBittorrent installer (nginx reverse proxy at
#   /qbittorrent/, container start script, binary fetched on first start).
# * Default: qBittorrent 5.3.0 + libtorrent 1.2.20, RACING-PATCHED.
#   Binary source order:
#     1. the verified release mirrored by this repo from Jerry's SHA-256 manifest
#     2. commit-pinned prebuilt binaries in jerry048/Dedicated-Seedbox (SHA-256 checked)
#     3. only with QB_ALLOW_UNPATCHED=1: the stock userdocs/qbittorrent-nox-static build
# * qBittorrent.conf uses the tuning profiles from jerry048/Dedicated-Seedbox
#   (https://github.com/jerry048/Dedicated-Seedbox) plus a racing overlay (QB_RACING=1).
#
# One-line install:
#   wget -O ~/install-qbittorrent.sh https://raw.githubusercontent.com/race-in/frealqbit1.2.20/main/install-qbittorrent.sh && bash ~/install-qbittorrent.sh
#
# Optional environment variables (put them in front of the bash command):
#   QB_VERSION          qBittorrent version, or newest for selected libtorrent (default: 5.3.0)
#   LT_VERSION          libtorrent version                          (default: 1.2.20)
#   QB_PROFILE          tuning profile                              (default: 1g-ssd)
#                       1g-hdd 1g-hdd-raid0 1g-ssd 1g-nvme 1g-ceph
#                       over1g-hdd over1g-hdd-raid0 over1g-ssd over1g-nvme over1g-ceph (10g aliases)
#   QB_CACHE_MIB        disk cache / working-set limit in MiB       (default: 1024)
#   QB_WEB_PORT         local WebUI port behind nginx               (default: 9001)
#   QB_INCOMING_PORT    fixed incoming peer port                    (default: qBittorrent picks one)
#   QB_MAX_CONNECTIONS  global connection limit                     (default: unlimited with QB_RACING=1)
#   QB_RACING           1 = racing overlay in qBittorrent.conf      (default: 1)
#                       (DHT/LSD/PeX off, TCP only, no connection/upload limits, announce to all trackers)
#   QB_PATCHED_REPO     GitHub repo holding your patched releases   (default: race-in/frealqbit1.2.20)
#   QB_ALLOW_UNPATCHED  1 = allow the stock userdocs build if no patched build exists   (default: 0)
#   QB_URL              full binary URL (overrides version/URL logic)
#   QB_SHA256           expected SHA-256 of the binary (verified on download)
#
# Example:
#   QB_PROFILE=1g-nvme QB_CACHE_MIB=2048 bash ~/install-qbittorrent.sh

QB_VERSION="${QB_VERSION:-5.3.0}"
LT_VERSION="${LT_VERSION:-1.2.20}"
LT_VERSION="${LT_VERSION#libtorrent-}"
LT_VERSION="${LT_VERSION#v}"
[[ "$LT_VERSION" == "1_1_14" ]] && LT_VERSION="1.1.14"
[[ "$LT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "ERROR: invalid LT_VERSION: $LT_VERSION" >&2; exit 1; }
QB_PROFILE="${QB_PROFILE:-1g-ssd}"
case "$QB_PROFILE" in 10g-*) QB_PROFILE="over1g-${QB_PROFILE#10g-}" ;; esac
QB_CACHE_MIB="${QB_CACHE_MIB:-1024}"
QB_WEB_PORT="${QB_WEB_PORT:-9001}"
QB_INCOMING_PORT="${QB_INCOMING_PORT:-}"
QB_MAX_CONNECTIONS="${QB_MAX_CONNECTIONS:-}"
QB_SHA256="${QB_SHA256:-}"
QB_RACING="${QB_RACING:-1}"
PATCHED_REPO="${QB_PATCHED_REPO:-race-in/frealqbit1.2.20}"
ALLOW_UNPATCHED="${QB_ALLOW_UNPATCHED:-0}"
REPO="userdocs/qbittorrent-nox-static"

die() { echo "ERROR: $*" >&2; exit 1; }

if [[ ! -d ~/.nginx ]]; then
    echo "This install script requires nginx on your slot. See: https://www.feralhosting.com/wiki/software/nginx"
    exit 1
fi

[[ "$QB_CACHE_MIB" =~ ^[0-9]+$ ]] || die "QB_CACHE_MIB must be a non-negative integer."
(( QB_CACHE_MIB > 0 )) || die "QB_CACHE_MIB must be greater than zero."
if [[ ! "$QB_WEB_PORT" =~ ^[0-9]+$ ]] || (( QB_WEB_PORT < 1 || QB_WEB_PORT > 65535 )); then
    die "QB_WEB_PORT must be between 1 and 65535."
fi
if [[ -n "$QB_INCOMING_PORT" ]]; then
    if [[ ! "$QB_INCOMING_PORT" =~ ^[0-9]+$ ]] || (( QB_INCOMING_PORT < 1 || QB_INCOMING_PORT > 65535 )); then
        die "QB_INCOMING_PORT must be between 1 and 65535."
    fi
fi
if [[ -n "$QB_MAX_CONNECTIONS" ]]; then
    if [[ ! "$QB_MAX_CONNECTIONS" =~ ^[0-9]+$ ]] || (( QB_MAX_CONNECTIONS < 1 )); then
        die "QB_MAX_CONNECTIONS must be a positive integer."
    fi
fi
[[ "$QB_RACING" == "0" || "$QB_RACING" == "1" ]] || die "QB_RACING must be 0 or 1."
[[ "$ALLOW_UNPATCHED" == "0" || "$ALLOW_UNPATCHED" == "1" ]] || die "QB_ALLOW_UNPATCHED must be 0 or 1."
# Validate dependencies before changing any running service or configuration.
if ! command -v python3 >/dev/null 2>&1 && ! command -v php >/dev/null 2>&1; then
    die "Need python3 or php to hash the WebUI password; install one before running this installer."
fi

# ---------------------------------------------------------------- download source
# Jerry's TSV manifest is authoritative for static versions, pinned URLs and hashes.
JERRY_MANIFEST_URL="https://raw.githubusercontent.com/jerry048/Dedicated-Seedbox/main/manifests/qbittorrent.tsv"

url_exists() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsIL --max-time 30 -o /dev/null "$1"
    else
        wget -q --spider --timeout=30 "$1"
    fi
}

fetch_text() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --max-time 30 "$1" 2>/dev/null
    else
        wget -qO- --timeout=30 "$1" 2>/dev/null
    fi
}

# Resolve "latest" as the highest qBittorrent version available for the
# selected libtorrent pair, rather than relying on the newest GitHub release tag.
jerry_latest_version() {
    local lt="$1" lt_field tmp latest
    case "$lt" in
        1.1.14) lt_field="1_1_14" ;;
        *) lt_field="v$lt" ;;
    esac
    tmp="$(mktemp)" || return 1
    if ! fetch_text "$JERRY_MANIFEST_URL" >"$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    latest="$(awk -F '\t' -v lt="$lt_field" '
        $0 ~ /^#/ || NF < 7 { next }
        $2 == lt && $3 == "amd64" && $4 == "static" { print $1 }
    ' "$tmp" | sort -Vu | tail -n1)"
    rm -f "$tmp"
    [[ -n "$latest" ]] || return 1
    printf '%s\n' "$latest"
}

# Resolve an exact amd64 artifact from Jerry's manifest.
# Returns: commit-pinned URL<TAB>SHA-256<TAB>config-family.
jerry_manifest_entry() {
    local qb="$1" lt="$2" lt_field tmp row version manifest_lt arch source url sha family
    case "$lt" in
        1.1.14) lt_field="1_1_14" ;;
        *) lt_field="v$lt" ;;
    esac
    tmp="$(mktemp)" || return 1
    if ! fetch_text "$JERRY_MANIFEST_URL" >"$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    row="$(awk -F '\t' -v qb="$qb" -v lt="$lt_field" '
        $0 ~ /^#/ || NF < 7 { next }
        $1 == qb && $2 == lt && $3 == "amd64" && $4 == "static" { print; exit }
    ' "$tmp")"
    rm -f "$tmp"
    [[ -n "$row" ]] || return 1
    IFS=$'\t' read -r version manifest_lt arch source url sha family <<<"$row"
    [[ "$version" == "$qb" && "$manifest_lt" == "$lt_field" && "$arch" == "amd64" && "$source" == "static" ]] || return 1
    [[ "$url" =~ ^https://raw\.githubusercontent\.com/jerry048/Dedicated-Seedbox/[0-9a-f]{40}/ ]] || return 1
    [[ "$sha" =~ ^[0-9a-fA-F]{64}$ ]] || return 1
    case "$family" in classic_pbkdf2|modern_pbkdf2|legacy_41) ;; *) return 1 ;; esac
    printf '%s\t%s\t%s\n' "$url" "${sha,,}" "$family"
}

if [[ "$QB_VERSION" == "latest" ]]; then
    QB_VERSION="$(jerry_latest_version "$LT_VERSION")" ||
        die "No Jerry qBittorrent build is available for libtorrent $LT_VERSION."
fi
[[ "$QB_VERSION" =~ ^[0-9]+(\.[0-9]+){2,3}$ ]] ||
    die "Invalid or unsupported QB_VERSION: $QB_VERSION"
case "$QB_VERSION" in
    4.0.*|3.*) die "qBittorrent $QB_VERSION is not supported by Jerry's patched static builds." ;;
esac

BUILD_STATE=""
if [[ -n "${QB_URL:-}" ]]; then
    URL="$QB_URL"
    [[ "$QB_SHA256" =~ ^[0-9a-fA-F]{64}$ ]] || die "QB_URL requires QB_SHA256 (64 hexadecimal characters); refusing to install an unverified binary."
    QB_SHA256="${QB_SHA256,,}"
    BUILD_STATE="custom binary (QB_URL), patch state unknown"
else
    if [[ "$QB_VERSION" == "latest" ]]; then
        OWN_URL="https://github.com/$PATCHED_REPO/releases/latest/download/x86_64-qbittorrent-nox"
    else
        OWN_URL="https://github.com/$PATCHED_REPO/releases/download/release-${QB_VERSION}_v${LT_VERSION}/x86_64-qbittorrent-nox"
    fi

    if url_exists "$OWN_URL"; then
        URL="$OWN_URL"
        BUILD_STATE="PATCHED (jerry048/Patch, built in $PATCHED_REPO)"
        if [[ -z "$QB_SHA256" ]]; then
            sum="$(fetch_text "$OWN_URL.sha256" | awk 'NR==1 {print $1}')"
            if [[ "$sum" =~ ^[0-9a-f]{64}$ ]]; then
                QB_SHA256="$sum"
            else
                die "Patched release has no valid .sha256 checksum. Publish x86_64-qbittorrent-nox.sha256 or provide QB_SHA256; refusing an unverified binary."
            fi
        fi
    elif [[ "$QB_VERSION" != "latest" ]] && JERRY_ENTRY="$(jerry_manifest_entry "$QB_VERSION" "$LT_VERSION")"; then
        IFS=$'\t' read -r JERRY_BINARY_URL JERRY_EXPECTED_SHA JERRY_CONFIG_FAMILY <<<"$JERRY_ENTRY"
        echo "No release for qBittorrent $QB_VERSION + libtorrent $LT_VERSION in $PATCHED_REPO; using Jerry's verified manifest entry."
        URL="$JERRY_BINARY_URL"
        [[ -n "$QB_SHA256" ]] || QB_SHA256="$JERRY_EXPECTED_SHA"
        BUILD_STATE="PATCHED (Jerry prebuilt; commit-pinned manifest SHA-256 verified)"
    elif [[ "$ALLOW_UNPATCHED" == "1" ]]; then
        if [[ "$QB_VERSION" == "latest" ]]; then
            URL="https://github.com/$REPO/releases/latest/download/x86_64-qbittorrent-nox"
        else
            URL="https://github.com/$REPO/releases/download/release-${QB_VERSION}_v${LT_VERSION}/x86_64-qbittorrent-nox"
        fi
        url_exists "$URL" || die "No binary found for qBittorrent $QB_VERSION + libtorrent $LT_VERSION. Check https://github.com/$REPO/releases or set QB_URL."
        if [[ -z "$QB_SHA256" ]]; then
            sum="$(fetch_text "$URL.sha256" | awk 'NR==1 {print $1}')"
            [[ "$sum" =~ ^[0-9a-fA-F]{64}$ ]] || die "Stock release has no valid .sha256 checksum. Set QB_SHA256 explicitly; refusing an unverified binary."
            QB_SHA256="${sum,,}"
        fi
        BUILD_STATE="NOT PATCHED (stock userdocs build, QB_ALLOW_UNPATCHED=1)"
        echo "WARNING: installing the stock, unpatched build."
    else
        die "No verified PATCHED binary is available for qBittorrent $QB_VERSION + libtorrent $LT_VERSION.
  This workflow mirrors binaries already published in jerry048/Dedicated-Seedbox; it does not compile new versions.
  Choose a version pair listed in https://github.com/jerry048/Dedicated-Seedbox/tree/main/Torrent%20Clients/qBittorrent
  or explicitly allow the stock build by setting QB_ALLOW_UNPATCHED=1."
    fi
fi

# ---------------------------------------------------------------- tuning table
# (values taken from jerry048/Dedicated-Seedbox, lib/components/qbittorrent.bash)

# Jerry's current 1g / over1g storage tuning values.
# "<AsyncIOThreads> <SendBufferLowWatermark> <SendBufferWatermark> <Factor>"
profile_common() {
    case "$1" in
        1g-hdd)           echo "4 3072 10240 150" ;;
        1g-hdd-raid0)     echo "8 3072 16384 150" ;;
        1g-ssd)           echo "12 5120 20480 200" ;;
        1g-nvme)          echo "16 5120 20480 200" ;;
        1g-ceph)          echo "8 5120 20480 200" ;;
        over1g-hdd)       echo "4 3072 16384 250" ;;
        over1g-hdd-raid0) echo "8 3072 16384 250" ;;
        over1g-ssd)       echo "16 5120 32768 300" ;;
        over1g-nvme)      echo "32 5120 32768 300" ;;
        over1g-ceph)      echo "16 5120 32768 250" ;;
        *) return 1 ;;
    esac
}

# libtorrent 2.x only: "<HashingThreads> <DiskIOType>"
profile_lt2() {
    case "$1" in
        1g-hdd)           echo "1 Default" ;;
        1g-hdd-raid0)     echo "2 Default" ;;
        1g-ssd)           echo "4 Default" ;;
        1g-nvme)          echo "8 MMap" ;;
        1g-ceph)          echo "2 SimplePreadPwrite" ;;
        over1g-hdd)       echo "1 Default" ;;
        over1g-hdd-raid0) echo "2 Default" ;;
        over1g-ssd)       echo "8 Default" ;;
        over1g-nvme)      echo "16 MMap" ;;
        over1g-ceph)      echo "4 SimplePreadPwrite" ;;
        *) return 1 ;;
    esac
}

# Feral is a shared slot: keep disk/request queues bounded instead of
# sizing them from host-wide MemTotal as Jerry does for dedicated hosts.
profile_qb455() {
    case "$1" in
        1g-hdd)           echo "16 1000" ;;
        1g-hdd-raid0)     echo "64 2000" ;;
        1g-ssd)           echo "128 2000" ;;
        1g-nvme)          echo "256 4000" ;;
        1g-ceph)          echo "64 2000" ;;
        over1g-hdd)       echo "32 1000" ;;
        over1g-hdd-raid0) echo "128 2000" ;;
        over1g-ssd)       echo "256 4000" ;;
        over1g-nvme)      echo "512 8000" ;;
        over1g-ceph)      echo "256 4000" ;;
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
# Match Jerry's configuration compatibility families.
case "$QB_VERSION" in
    4.1.*)       CONF_FAMILY="legacy_41" ;;
    4.2.*|4.3.*) CONF_FAMILY="classic_pbkdf2" ;;
    *)           CONF_FAMILY="modern_pbkdf2" ;;
esac
if [[ -n "${JERRY_CONFIG_FAMILY:-}" && "$JERRY_CONFIG_FAMILY" != "$CONF_FAMILY" ]]; then
    die "Jerry manifest config family ($JERRY_CONFIG_FAMILY) does not match qBittorrent $QB_VERSION ($CONF_FAMILY)."
fi
classic_extra=()
if [[ "$CONF_FAMILY" == "modern_pbkdf2" ]]; then
    [[ -n "$QB_INCOMING_PORT" ]]   && session_extra+=("Session\\Port=$QB_INCOMING_PORT")
    [[ -n "$QB_MAX_CONNECTIONS" ]] && session_extra+=("Session\\MaxConnections=$QB_MAX_CONNECTIONS")
    # Racing overlay: private-tracker settings, no limits, TCP only.
    if [[ "$QB_RACING" == "1" ]]; then
        session_extra+=(
            "Session\\DHTEnabled=false" "Session\\LSDEnabled=false" "Session\\PeXEnabled=false"
            "Session\\BTProtocol=TCP" "Session\\uTPRateLimited=false"
            "Session\\MaxConnectionsPerTorrent=-1" "Session\\MaxUploads=-1" "Session\\MaxUploadsPerTorrent=-1"
            "Session\\MultiConnectionsPerIp=true" "Session\\SuggestMode=true"
            "Session\\AnnounceToAllTrackers=true" "Session\\AnnounceToAllTiers=true"
            "Session\\SeedChokingAlgorithm=FastestUpload"
        )
        [[ -z "$QB_MAX_CONNECTIONS" ]] && session_extra+=("Session\\MaxConnections=-1")
    fi
else
    [[ -n "$QB_INCOMING_PORT" ]]   && classic_extra+=("Connection\\PortRangeMin=$QB_INCOMING_PORT")
    [[ -n "$QB_MAX_CONNECTIONS" ]] && classic_extra+=("Bittorrent\\MaxConnecs=$QB_MAX_CONNECTIONS")
    if [[ "$QB_RACING" == "1" ]]; then
        classic_extra+=("Bittorrent\\DHT=false" "Bittorrent\\LSD=false" "Bittorrent\\PeX=false"
                        "Bittorrent\\MaxConnecsPerTorrent=-1" "Bittorrent\\MaxUploads=-1" "Bittorrent\\MaxUploadsPerTorrent=-1")
        [[ -z "$QB_MAX_CONNECTIONS" ]] && classic_extra+=("Bittorrent\\MaxConnecs=-1")
    fi
fi

# ------------------------------------------------------- stop existing processes
rm -rf ~/.config/feral/ns/containers/docs-qbittorrent 2>/dev/null || true
rm ~/.config/feral/user-container.d/wiki-qbittorrent 2>/dev/null || true
# Stop only the qBittorrent instance launched from this installer-managed container.
# Never kill unrelated qBittorrent instances owned by the same account.
for pid in $(pgrep -x qbittorrent-nox 2>/dev/null || true); do
    cmdline="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
    if [[ "$cmdline" == *"docs-qbittorrent"* || "$cmdline" == *"$HOME/.config/feral/ns/containers/docs-qbittorrent"* ]]; then
        kill "$pid" 2>/dev/null || true
        for _ in {1..10}; do
            kill -0 "$pid" 2>/dev/null || break
            sleep 1
        done
        if kill -0 "$pid" 2>/dev/null; then
            echo "WARNING: managed qBittorrent PID $pid did not stop; leaving it running rather than force-killing it." >&2
        fi
    fi
done

# ------------------------------------------------------------------- password
pass="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 15; echo '')"
salt=""
hmac=""
if [[ "$CONF_FAMILY" == "legacy_41" ]]; then
    password_ha1="$(printf '%s' "$pass" | md5sum | awk '{print $1}')" ||
        die "Could not generate the legacy WebUI password hash."
    [[ "$password_ha1" =~ ^[0-9a-fA-F]{32}$ ]] || die "Invalid legacy WebUI password hash."
    PASSWORD_CONFIG_LINE="WebUI\\Password_ha1=@ByteArray($password_ha1)"
else
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
    PASSWORD_CONFIG_LINE="WebUI\\Password_PBKDF2=\"@ByteArray($salt:$hmac)\""
fi

# --------------------------------------------------------------- qBittorrent.conf
mkdir -p ~/.config/qBittorrent
conf=~/.config/qBittorrent/qBittorrent.conf
if [[ -f "$conf" ]]; then
    cp -f "$conf" "$conf.bak.$(date +%Y%m%d-%H%M%S)"
fi
(
    umask 077
    if [[ "$CONF_FAMILY" == "modern_pbkdf2" ]]; then
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
            if version_ge "$QB_VERSION" "5.3.0"; then
                echo "[WebUI]"
                echo "${PASSWORD_CONFIG_LINE#WebUI\\}"
                echo "Port=$QB_WEB_PORT"
                echo "Username=$(whoami)"
            else
                echo "[Preferences]"
                echo "WebUI\\Username=$(whoami)"
                echo "$PASSWORD_CONFIG_LINE"
                echo "WebUI\\Port=$QB_WEB_PORT"
                echo "WebUI\\MaxAuthenticationFailCount=60"
            fi
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
            for line in "${classic_extra[@]}"; do echo "$line"; done
            echo "Downloads\\DiskWriteCacheSize=$QB_CACHE_MIB"
            echo "Downloads\\SavePath=$HOME/private/qbittorrent/data/"
            echo "Queueing\\QueueingEnabled=false"
            echo "WebUI\\Username=$(whoami)"
            echo "$PASSWORD_CONFIG_LINE"
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
pushd ~/.config/feral/ns/containers/docs-qbittorrent >/dev/null || die "Could not enter the qBittorrent container directory."
rm -f qbittorrent-nox
echo debian-trixie >root

cat >start <<'EOF_START'
#!/usr/bin/env bash
set -eux -o pipefail

pushd "$FERAL_SLOTNS_PATH" || exit 1
# Download the binary if it is missing
if [[ ! -f qbittorrent-nox ]]; then
    wget --no-verbose -O qbittorrent-nox.part "@QB_URL@"
    [[ "@QB_SHA256@" =~ ^[0-9a-f]{64}$ ]] || { echo "ERROR: missing or invalid expected SHA-256; refusing to install binary." >&2; rm -f qbittorrent-nox.part; exit 1; }
    echo "@QB_SHA256@  qbittorrent-nox.part" | sha256sum -c -
    chmod +x qbittorrent-nox.part
    mv -f qbittorrent-nox.part qbittorrent-nox
    # Trigger restart
    pkill -x qbittorrent-nox || true
fi
popd || exit 1

# Start
cd "$HOME"
export TMPDIR="$FERAL_SLOTNS_PATH/tmp"
mkdir -p "$TMPDIR"
[[ "$(pgrep -x 'qbittorrent-nox')" ]] || exec "$FERAL_SLOTNS_PATH/qbittorrent-nox"
EOF_START
sed -i -e "s|@QB_URL@|$URL|g" -e "s|@QB_SHA256@|$QB_SHA256|g" start
chmod +x start
popd >/dev/null || die "Could not leave the qBittorrent container directory."

# ---------------------------------------------------------------------- report
if [[ "$QB_VERSION" == "latest" ]]; then
    echo "qBittorrent (latest release) has been successfully installed. Tuning profile: $QB_PROFILE."
else
    echo "qBittorrent $QB_VERSION (libtorrent $LT_VERSION) has been successfully installed. Tuning profile: $QB_PROFILE."
fi
echo "Build: $BUILD_STATE"
[[ "$QB_RACING" == "1" ]] && echo "Racing overlay: on"
echo "It will be running in five minutes."
echo
echo "URL: https://$(whoami).$(hostname -f)/qbittorrent/"
echo "Username: $(whoami)"
echo "Password: $pass"
echo
echo "Save this password now; it is not stored anywhere in plain text."
