# qBittorrent installer for Feral Hosting

One-command installer for **qBittorrent-nox** on a [Feral Hosting](https://www.feralhosting.com/) slot.

- **qBittorrent 5.2.4 + libtorrent 1.2.20** by default (any other version via env variables)
- Static binary downloaded from the [userdocs/qbittorrent-nox-static](https://github.com/userdocs/qbittorrent-nox-static) GitHub release
- Tuned `qBittorrent.conf` using the profiles from [jerry048/Dedicated-Seedbox](https://github.com/jerry048/Dedicated-Seedbox)
- Same setup Feral uses for its own qBittorrent install: nginx reverse proxy at `/qbittorrent/`, started and kept alive by Feral's container manager

## Requirements

nginx must be enabled on your slot first: <https://www.feralhosting.com/wiki/software/nginx>

## Install

```bash
wget -O ~/install-qbittorrent.sh https://raw.githubusercontent.com/race-in/frealqbit1.2.20/main/install-qbittorrent.sh && bash ~/install-qbittorrent.sh
```

When it finishes it prints the WebUI URL, username and a random password. **Save the password**; it is shown only once. qBittorrent starts within about five minutes.

## Options

Put variables in front of the `bash` command, for example:

```bash
QB_PROFILE=1g-nvme QB_CACHE_MIB=2048 bash ~/install-qbittorrent.sh
```

| Variable | Meaning | Default |
|---|---|---|
| `QB_VERSION` | qBittorrent version, or `latest` | `5.2.4` |
| `LT_VERSION` | libtorrent version (`1.2.20`, `2.0.13`, ...) | `1.2.20` |
| `QB_PROFILE` | tuning profile (see below) | `1g-ssd` |
| `QB_CACHE_MIB` | disk cache / memory working-set limit in MiB | `1024` |
| `QB_WEB_PORT` | local WebUI port behind nginx | `9001` |
| `QB_INCOMING_PORT` | fixed incoming peer port | qBittorrent picks one |
| `QB_MAX_CONNECTIONS` | global connection limit | qBittorrent default |
| `QB_URL` | full binary URL (overrides version logic) | built from the version |
| `QB_SHA256` | expected SHA-256 of the binary | not checked |

Binaries come from two places, picked automatically:

1. [userdocs/qbittorrent-nox-static](https://github.com/userdocs/qbittorrent-nox-static/releases) release tags (`release-<qbt>_v<libtorrent>`), e.g. 5.2.4 + 1.2.20
2. If the pair is not there, the builds bundled in [jerry048/Dedicated-Seedbox](https://github.com/jerry048/Dedicated-Seedbox), verified with SHA-256:
   4.2.5, 4.3.9, 4.4.5, 4.5.5, 4.6.7 (libtorrent 1.2.20; 4.4.5 to 4.6.7 also 2.0.13), 5.0.5, 5.1.4, 5.2.2 (libtorrent 1.2.20 and 2.0.13)

qBittorrent 4.2.x / 4.3.x get the older config layout automatically. Versions below 4.2 are not supported.

Example, qBittorrent 4.3.9 + libtorrent 1.2.20 on a 10G NVMe slot:

```bash
QB_VERSION=4.3.9 LT_VERSION=1.2.20 QB_PROFILE=10g-nvme bash ~/install-qbittorrent.sh
```

### Tuning profiles

`QB_PROFILE` is `<network>-<storage>`: network `1g` or `10g`, storage `hdd`, `hdd-raid0`, `ssd`, `nvme` or `ceph`
(`1g-hdd`, `1g-hdd-raid0`, `1g-ssd`, `1g-nvme`, `1g-ceph`, `10g-hdd`, `10g-hdd-raid0`, `10g-ssd`, `10g-nvme`, `10g-ceph`).
A profile sets async I/O threads, send-buffer watermarks and, depending on the qBittorrent / libtorrent version,
connection speed, disk and request queue sizes and socket buffers. Pick the one that matches your slot's network and disk.

## Re-installing / changing version

Just run the installer again with the new variables. It stops qBittorrent, backs up the old `qBittorrent.conf`
(as `qBittorrent.conf.bak.<date>`), downloads the binary again on the next start, and generates a **new** WebUI password.
Your torrents and downloads are not touched.

## Files it creates

| Path | What |
|---|---|
| `~/.config/qBittorrent/qBittorrent.conf` | tuned config |
| `~/.nginx/conf.d/000-default-server.d/qbittorrent.conf` | reverse proxy |
| `~/.config/feral/ns/containers/docs-qbittorrent/` | container start script and binary |
| `~/private/qbittorrent/data` | default download directory |

## Credits

Tuning values come from [jerry048/Dedicated-Seedbox](https://github.com/jerry048/Dedicated-Seedbox). The container / nginx
layout follows Feral Hosting's own qBittorrent installer. Binaries are built by [userdocs](https://github.com/userdocs/qbittorrent-nox-static).

Use only for legal content.

## License

MIT (applies to this script; the credited projects have their own terms)
