# qBittorrent for Feral Hosting: racing-tuned, Jerry-patched builds

Feral Hosting slot-এর জন্য qBittorrent-nox installer, tuned configuration এবং safe binary-only updater।

- Jerry's prebuilt static binaries from [jerry048/Dedicated-Seedbox](https://github.com/jerry048/Dedicated-Seedbox)
- Racing patches from [jerry048/Patch](https://github.com/jerry048/Patch)
- Jerry's current TSV manifest থেকে exact version, pinned source URL, config family এবং SHA-256 নেওয়া হয়
- GitHub Actions সব supported **amd64** pair mirror করে; Qt/qBittorrent locally compile করে না
- Feral-এর nginx reverse proxy at `/qbittorrent/`, slot container manager দিয়ে start হয়

## Supported version matrix

এই তালিকা Jerry's `manifests/qbittorrent.tsv` থেকে নেওয়া। Feral mirror workflow শুধু `amd64` artifacts publish করে; Jerry-এর repository-তে ARM64 builds-ও আছে।

| qBittorrent | libtorrent |
|---|---|
| 4.1.9.1 | 1.1.14 |
| 4.2.5, 4.3.9 | 1.2.20 |
| 4.4.5, 4.5.5, 4.6.7, 5.0.5, 5.1.4 | 1.2.20, 2.0.15 |
| 5.2.4 | 1.2.20, 2.0.15 |
| 5.3.0 | 1.2.20, 2.1.2 |

Jerry manifest: [qbittorrent.tsv](https://github.com/jerry048/Dedicated-Seedbox/blob/main/manifests/qbittorrent.tsv).

## Repository files

```
install-qbittorrent.sh
upgrade-qbittorrent-binary.sh
README.md
.github/workflows/build-qbittorrent.yml
.github/workflows/installer-checks.yml
```

## 1. Mirror Jerry's verified binaries

The workflow reads the manifest, validates commit-pinned URLs and SHA-256 values, checks the binary's qBittorrent version, and publishes the release assets:

- `x86_64-qbittorrent-nox`
- `x86_64-qbittorrent-nox.sha256`
- `patches-used.txt`

It checks daily and mirrors every supported amd64 version pair when the upstream checksum changes. You can also run it manually for one exact qBittorrent/libtorrent pair, or leave both inputs empty to check all pairs.

Current known release: [qBittorrent 5.3.0 + libtorrent 1.2.20](https://github.com/race-in/frealqbit1.2.20/releases/tag/release-5.3.0_v1.2.20).

## 2A. Update an existing Feral install — binary only

Use this for an update within the same qBittorrent config family. The updater keeps the current WebUI credentials, port, config, nginx proxy, Feral start script, torrent state and download data. It saves a timestamped binary backup under `~/qbittorrent-backup/`, verifies SHA-256 and `--version`, then atomically replaces only the binary.

Example:

```bash
wget -O ~/upgrade-qbittorrent-binary.sh \
  https://raw.githubusercontent.com/race-in/frealqbit1.2.20/main/upgrade-qbittorrent-binary.sh

QB_VERSION=5.3.0 LT_VERSION=1.2.20 \
  bash ~/upgrade-qbittorrent-binary.sh
```

The updater first tries this repository's mirrored release, then resolves Jerry's current commit-pinned manifest entry if the mirror is missing. It refuses a config-family change. In particular, qBittorrent 5.3 moved WebUI keys from `[Preferences]` to `[WebUI]`; moving between 5.3+ and older qB versions needs a full config migration and cannot be done by swapping only the binary.

Supported binary-only config families:

- qBittorrent 4.1.x: legacy HA1 credentials
- qBittorrent 4.2.x–4.3.x: classic PBKDF2 config
- qBittorrent 4.4.x–5.2.x: modern `[Preferences]` WebUI settings
- qBittorrent 5.3.x and newer: modern `[WebUI]` section

Do not use the binary-only updater to downgrade from qB 5.3 to 5.2/4.x. It will stop before replacing the binary if the config family differs.

## 2B. Fresh install or deliberate full reconfiguration

Enable nginx on your slot first: <https://www.feralhosting.com/wiki/software/nginx>

```bash
wget -O ~/install-qbittorrent.sh \
  https://raw.githubusercontent.com/race-in/frealqbit1.2.20/main/install-qbittorrent.sh
bash ~/install-qbittorrent.sh
```

Examples:

```bash
# Jerry's qBittorrent 4.3.9 + libtorrent 1.2.20 build
QB_VERSION=4.3.9 LT_VERSION=1.2.20 \
  bash ~/install-qbittorrent.sh

# qBittorrent 5.3.0 + libtorrent 2.1.2 on an over-1-Gbps NVMe profile
QB_VERSION=5.3.0 LT_VERSION=2.1.2 QB_PROFILE=over1g-nvme \
  bash ~/install-qbittorrent.sh
```

The full installer backs up the existing `qBittorrent.conf`, but regenerates its contents and creates a new random WebUI password. It also recreates the Feral container/start configuration and nginx proxy. **Do not rerun it just to change the binary**; use Step 2A where the config family matches.

At the end, the installer prints the WebUI URL, username, password, selected profile and build source. Save the password; it is not stored in plain text.

## Options

Set variables before the `bash` command.

| Variable | Meaning | Default |
|---|---|---|
| `QB_VERSION` | qBittorrent version, or `latest` for the newest upstream build matching `LT_VERSION` | `5.3.0` |
| `LT_VERSION` | libtorrent version | `1.2.20` |
| `QB_PROFILE` | `<1g\|over1g\|10g>-<hdd\|hdd-raid0\|ssd\|nvme\|ceph>`; `10g` is an alias for `over1g` | `1g-ssd` |
| `QB_CACHE_MIB` | disk cache / memory working set in MiB | `1024` |
| `QB_WEB_PORT` | local WebUI port behind nginx | `9001` |
| `QB_INCOMING_PORT` | fixed incoming peer port | qBittorrent picks one |
| `QB_MAX_CONNECTIONS` | global connection limit | unlimited |
| `QB_RACING` | `1` enable racing overlay, `0` disable | `1` |
| `QB_PATCHED_REPO` | repo that holds mirrored patched releases | `race-in/frealqbit1.2.20` |
| `QB_ALLOW_UNPATCHED` | `1` allow stock userdocs build if no patched binary exists | `0` |
| `QB_URL`, `QB_SHA256` | custom binary URL and its SHA-256 | unset |

### Tuning profiles

`1g-*` profiles use the standard 1-Gbps tier. `over1g-*` profiles use Jerry's higher-throughput buffer settings. `10g-*` remains accepted as a compatibility alias for `over1g-*`.

The Feral version keeps disk/request queues explicitly bounded instead of sizing them from host-wide RAM. On a shared slot, host memory totals can represent the physical host rather than the slot's actual resource limit.

## What "racing" does

Compile-time (jerry048 patches, built into the binary): predictive piece announce, increased connection/request queues, faster request and piece timeouts, quicker reconnects, enlarged send buffers, uTP disabled, and fastest-upload seed choking.

Config overlay (`QB_RACING=1`): DHT, LSD and PeX disabled, TCP only, no configured connection/upload limits, multiple connections per IP, upload suggestions, announce to all trackers and tiers, queueing disabled. The selected profile tunes asynchronous I/O and send buffers for the storage/network tier.

Important considerations:

- Set `QB_INCOMING_PORT` to a port that is reachable from your slot; otherwise upload can be limited by inbound connectivity.
- Select the profile that matches your actual storage and network, not just the advertised peak speed.
- No setting guarantees constant upload; tracker, swarm and peer conditions still matter.
- DHT/LSD/PeX off is suitable for private trackers, not public swarms.
- Jerry's supplied patches disable WebUI CSRF protection by default. This is a security trade-off; review the WebUI CSRF setting for your deployment.

## Important paths

| Path | Purpose |
|---|---|
| `~/.config/qBittorrent/qBittorrent.conf` | qBittorrent configuration |
| `~/.nginx/conf.d/000-default-server.d/qbittorrent.conf` | nginx reverse proxy |
| `~/.config/feral/ns/containers/docs-qbittorrent/` | Feral container start script and binary |
| `~/private/qbittorrent/data` | default download directory |
| `~/qbittorrent-backup/` | binary-only updater backups |

## Credits

- Patches: [jerry048/Patch](https://github.com/jerry048/Patch)
- Static builds and tuning profiles: [jerry048/Dedicated-Seedbox](https://github.com/jerry048/Dedicated-Seedbox)
- Build chain: [userdocs/qbittorrent-nox-static](https://github.com/userdocs/qbittorrent-nox-static)
- Feral container/nginx layout follows Feral Hosting's own qBittorrent installer.

Use only for legal content. MIT licence applies to this repository's own scripts; credited projects retain their own licences and terms.
