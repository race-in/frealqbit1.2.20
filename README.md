# qBittorrent for Feral Hosting: racing-tuned, patched build

Installer for **qBittorrent-nox** on a [Feral Hosting](https://www.feralhosting.com/) slot, built for racing:

- Uses Jerry's existing, prebuilt static binaries from [jerry048/Dedicated-Seedbox](https://github.com/jerry048/Dedicated-Seedbox), with racing patches from [jerry048/Patch](https://github.com/jerry048/Patch)
- A GitHub Actions workflow downloads Jerry's binary from his SHA-256 manifest, verifies it, and mirrors it as a release here; it does not rebuild Qt or qBittorrent
- The installer downloads that release (SHA-256 checked) and writes a tuned `qBittorrent.conf`
  (profiles from [jerry048/Dedicated-Seedbox](https://github.com/jerry048/Dedicated-Seedbox) plus a racing overlay)
- Same setup Feral uses for its own qBittorrent: nginx reverse proxy at `/qbittorrent/`, started by Feral's container manager

## Repo layout

```
install-qbittorrent.sh
upgrade-qbittorrent-binary.sh
README.md
.github/workflows/build-qbittorrent.yml
.github/workflows/installer-checks.yml
```

The workflow automatically checks Jerry's published manifest daily and mirrors an updated binary only when its SHA-256 changes. It can also be triggered manually for a version pair already present in Jerry's manifest. A separate installer-check workflow runs Bash syntax validation and ShellCheck.

## Step 1: mirror Jerry's prebuilt binary (automatic)

Jerry already provides compiled static binaries, including **qBittorrent 5.3.0 + libtorrent 1.2.20**. This repository does not need to compile Qt or qBittorrent again.

The workflow checks `manifests/qbittorrent.tsv` from Jerry's repository, downloads the commit-pinned x86_64 binary, validates its SHA-256 and qBittorrent version, then publishes:

- `x86_64-qbittorrent-nox`
- `x86_64-qbittorrent-nox.sha256`
- `patches-used.txt`

It runs automatically when this workflow is updated and checks for upstream binary changes daily. It only republishes when Jerry's published manifest points to a different binary checksum. The current release is [qBittorrent 5.3.0 + libtorrent 1.2.20](https://github.com/race-in/frealqbit1.2.20/releases/tag/release-5.3.0_v1.2.20).

## Step 2A: safely update an existing Feral install (recommended)

If qBittorrent is already running and you want to keep its current WebUI password, port, configuration, nginx proxy, Feral start script, and torrent state, **do not rerun the full installer**. The binary-only updater first checks this repository's verified release; if the release is unavailable, it can use the commit-pinned Jerry binary with its known SHA-256 for the supported version pair.

```bash
wget -O ~/upgrade-qbittorrent-binary.sh https://raw.githubusercontent.com/race-in/frealqbit1.2.20/main/upgrade-qbittorrent-binary.sh
QB_VERSION=5.3.0 LT_VERSION=1.2.20 bash ~/upgrade-qbittorrent-binary.sh
```

The updater verifies the binary checksum and qBittorrent version, saves a timestamped backup under `~/qbittorrent-backup/`, and replaces only the binary. It does **not** rewrite `qBittorrent.conf`, change WebUI credentials/port, alter nginx, remove the Feral container directory, or modify torrent/download data. It sends a graceful TERM only to a process matching the Feral binary path; Feral should auto-restart qBittorrent within about five minutes. If the release and the pinned fallback are unavailable, invalid or unsupported, the script exits before replacing the current binary.

## Step 2B: fresh install or full reconfiguration

nginx must be enabled on your slot first: <https://www.feralhosting.com/wiki/software/nginx>

```bash
wget -O ~/install-qbittorrent.sh https://raw.githubusercontent.com/race-in/frealqbit1.2.20/main/install-qbittorrent.sh && bash ~/install-qbittorrent.sh
```

With options, for example qBittorrent 4.3.9 on a 10G NVMe slot:

```bash
wget -O ~/install-qbittorrent.sh https://raw.githubusercontent.com/race-in/frealqbit1.2.20/main/install-qbittorrent.sh && QB_VERSION=5.3.0 LT_VERSION=1.2.20 QB_PROFILE=10g-nvme bash ~/install-qbittorrent.sh
```

At the end it prints the WebUI URL, username and a random password. **Save the password**, it is shown once. A full installer run regenerates the configuration and WebUI password, so use Step 2A for a binary-only update. qBittorrent starts within about five minutes.

### Where the binary comes from

1. the verified release mirrored from Jerry's manifest (`race-in/frealqbit1.2.20`)
2. the commit-pinned patched binaries bundled in jerry048/Dedicated-Seedbox (including 5.2.4/5.3.0 where supported), SHA-256 checked
3. only with `QB_ALLOW_UNPATCHED=1`: the stock [userdocs](https://github.com/userdocs/qbittorrent-nox-static) build

If neither verified patched source is available the installer stops, instead of silently installing an unpatched build.
The installer prints `Build: PATCHED ...` or `Build: NOT PATCHED ...` at the end.

## Options

Put variables in front of the `bash` command.

| Variable | Meaning | Default |
|---|---|---|
| `QB_VERSION` | qBittorrent version, or `latest` (newest release of your repo) | `5.3.0` |
| `LT_VERSION` | libtorrent version | `1.2.20` |
| `QB_PROFILE` | tuning profile, `<1g\|10g>-<hdd\|hdd-raid0\|ssd\|nvme\|ceph>` | `1g-ssd` |
| `QB_CACHE_MIB` | disk cache / memory limit in MiB | `1024` |
| `QB_WEB_PORT` | local WebUI port behind nginx | `9001` |
| `QB_INCOMING_PORT` | fixed incoming peer port | qBittorrent picks one |
| `QB_MAX_CONNECTIONS` | global connection limit | unlimited |
| `QB_RACING` | `1` racing overlay in `qBittorrent.conf`, `0` off | `1` |
| `QB_PATCHED_REPO` | repo that holds your patched releases | `race-in/frealqbit1.2.20` |
| `QB_ALLOW_UNPATCHED` | `1` allows the stock build when no patched one exists | `0` |
| `QB_URL`, `QB_SHA256` | full binary URL and its SHA-256 | unset |

## What "racing" does

Compile-time (jerry048 patches, built into the binary): `predictive_piece_announce` so pieces are announced before they are
fully hashed, unlimited unchoke slots and connections, `connection_speed` 500 and `torrent_connect_boost` 100, 100 ms engine tick,
short request and piece timeouts, fast reconnects, large request queues and send buffers, uTP off, `fastest_upload` seed choker.

Config overlay (`QB_RACING=1`, written to `qBittorrent.conf`): DHT, LSD and PeX off, TCP only, no connection or upload limits,
multiple connections per IP, upload suggestions, announce to all trackers and tiers, queueing off. The tuning profile adds disk
and buffer sizes for your network and storage.

Things that matter as much as any setting:

- **Open a fixed incoming port.** Set `QB_INCOMING_PORT` to a port that is reachable on your slot. If peers cannot connect to you, upload drops a lot.
- Pick the `QB_PROFILE` that matches your slot's real network and disk.
- Bursts depend on the tracker, the swarm and the other peers. No setting guarantees constant upload.
- DHT/LSD/PeX off is right for private trackers but not for public ones.

The patches also turn the WebUI CSRF protection off by default. That is a security trade-off. If you want it on, enable CSRF protection
in the WebUI options (behind Feral's nginx proxy it may need the Host header handling in the proxy config).

## Uninstall / reinstall

The full installer is intended for a fresh install or deliberate full reconfiguration. It backs up `qBittorrent.conf`, but regenerates its contents and creates a **new** WebUI password. Use the binary-only updater above if you want to preserve existing settings.

| Path | What |
|---|---|
| `~/.config/qBittorrent/qBittorrent.conf` | config |
| `~/.nginx/conf.d/000-default-server.d/qbittorrent.conf` | reverse proxy |
| `~/.config/feral/ns/containers/docs-qbittorrent/` | container start script and binary |
| `~/private/qbittorrent/data` | default download directory |

## Credits

Patches: [jerry048/Patch](https://github.com/jerry048/Patch). Tuning profiles: [jerry048/Dedicated-Seedbox](https://github.com/jerry048/Dedicated-Seedbox).
Jerry's prebuilt-binary build chain uses [userdocs/qbittorrent-nox-static](https://github.com/userdocs/qbittorrent-nox-static).
Container / nginx layout follows Feral Hosting's own qBittorrent installer.

Use only for legal content. MIT licence for this repo's own scripts; the credited projects have their own terms.
