# qBittorrent for Feral Hosting: racing-tuned, patched build

Installer for **qBittorrent-nox** on a [Feral Hosting](https://www.feralhosting.com/) slot, built for racing:

- **Any qBittorrent version + libtorrent 1.2.20**, compiled with the racing patches from
  [jerry048/Patch](https://github.com/jerry048/Patch) (both the qBittorrent and the libtorrent patch)
- A GitHub Actions workflow in this repo builds the binary for the version you pick and publishes it as a release
- The installer downloads that release (SHA-256 checked) and writes a tuned `qBittorrent.conf`
  (profiles from [jerry048/Dedicated-Seedbox](https://github.com/jerry048/Dedicated-Seedbox) plus a racing overlay)
- Same setup Feral uses for its own qBittorrent: nginx reverse proxy at `/qbittorrent/`, started by Feral's container manager

## Repo layout

```
install-qbittorrent.sh
README.md
.github/workflows/build-qbittorrent.yml
.github/workflows/installer-checks.yml
```

The repository must be **public** (the free ARM build runner is only free for public repositories). The build workflow is stored in `.github/workflows/build-qbittorrent.yml`, where GitHub Actions discovers it. A separate installer-check workflow runs Bash syntax validation and ShellCheck.

## Step 1: build the patched binary (once per version)

1. GitHub: **Actions** tab, **Build patched qBittorrent-nox**, **Run workflow**
2. Enter `qb_version` (for example `5.3.0`), leave the rest as it is, and run it
3. When it finishes (a full static build takes a long time, often 1 to 3 hours) the release
   `release-<version>_v1.2.20` appears under **Releases** with `x86_64-qbittorrent-nox`, a `.sha256` file and `patches-used.txt`

The workflow refuses to build an unpatched binary: if no jerry048 patch applies cleanly to the requested version, or a patch
is not applied during the build, the run fails.

Patches: qBittorrent uses the patch for the exact version if jerry048 has one, otherwise the newest earlier patch of the
same major version that applies cleanly (for example, a previous same-major patch is used only if it applies cleanly; `patches-used.txt` records the exact patch version). `patches-used.txt` says which.

## Step 2: install on Feral

nginx must be enabled on your slot first: <https://www.feralhosting.com/wiki/software/nginx>

```bash
wget -O ~/install-qbittorrent.sh https://raw.githubusercontent.com/race-in/frealqbit1.2.20/main/install-qbittorrent.sh && bash ~/install-qbittorrent.sh
```

With options, for example qBittorrent 4.3.9 on a 10G NVMe slot:

```bash
wget -O ~/install-qbittorrent.sh https://raw.githubusercontent.com/race-in/frealqbit1.2.20/main/install-qbittorrent.sh && QB_VERSION=5.3.0 LT_VERSION=1.2.20 QB_PROFILE=10g-nvme bash ~/install-qbittorrent.sh
```

At the end it prints the WebUI URL, username and a random password. **Save the password**, it is shown once.
qBittorrent starts within about five minutes.

### Where the binary comes from

1. your own patched release (`race-in/frealqbit1.2.20`, built in step 1)
2. the patched binaries bundled in jerry048/Dedicated-Seedbox (4.2.5 to 5.2.2), SHA-256 checked
3. only with `QB_ALLOW_UNPATCHED=1`: the stock [userdocs](https://github.com/userdocs/qbittorrent-nox-static) build

If none of the first two exist the installer stops and tells you to run step 1, instead of silently installing an unpatched build.
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

Run the installer again with new variables: it stops qBittorrent, backs up `qBittorrent.conf`
(`qBittorrent.conf.bak.<date>`), and generates a **new** WebUI password. Torrents and downloads are not touched.

| Path | What |
|---|---|
| `~/.config/qBittorrent/qBittorrent.conf` | config |
| `~/.nginx/conf.d/000-default-server.d/qbittorrent.conf` | reverse proxy |
| `~/.config/feral/ns/containers/docs-qbittorrent/` | container start script and binary |
| `~/private/qbittorrent/data` | default download directory |

## Credits

Patches: [jerry048/Patch](https://github.com/jerry048/Patch). Tuning profiles: [jerry048/Dedicated-Seedbox](https://github.com/jerry048/Dedicated-Seedbox).
Build script: [userdocs/qbittorrent-nox-static](https://github.com/userdocs/qbittorrent-nox-static).
Container / nginx layout follows Feral Hosting's own qBittorrent installer.

Use only for legal content. MIT licence for this repo's own scripts; the credited projects have their own terms.
