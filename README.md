# qbittorrent-seedbox-installer

Rootless one-file installer for **qBittorrent-nox** on seedboxes / shared Linux hosts (no `sudo` required).

- Downloads a static qBittorrent-nox build (x86_64 / aarch64 / armv7) from [userdocs/qbittorrent-nox-static](https://github.com/userdocs/qbittorrent-nox-static)
- Installs to `~/.local/bin`
- Picks a random free WebUI port
- Starts it in the background and adds an `@reboot` cron entry
- Prints the WebUI URL and temporary password

## Install

```bash
wget -O ~/install-qbittorrent.sh https://raw.githubusercontent.com/<YOUR_USER>/<YOUR_REPO>/main/install-qbittorrent.sh && bash ~/install-qbittorrent.sh
```

## Options

| Env var      | Meaning                                   | Default            |
|--------------|-------------------------------------------|--------------------|
| `QB_VERSION` | qBittorrent version, or `latest`          | `5.2.4`            |
| `LT_VERSION` | libtorrent version (`1.2.20`, `2.0.13`)   | `1.2.20`           |
| `QB_PORT`    | WebUI port                                | random 20000-60000 |
| `QB_URL`     | Direct URL of a qbittorrent-nox binary    | built from the above |
| `QB_BIN_DIR` | Install directory                         | `~/.local/bin`     |

Examples:

```bash
# default: qBittorrent 5.2.4 + libtorrent 1.2.20
bash install-qbittorrent.sh

# another combination
QB_VERSION=5.2.3 LT_VERSION=2.0.13 bash install-qbittorrent.sh

# newest release of the repo (whatever libtorrent it ships)
QB_VERSION=latest bash install-qbittorrent.sh

# fixed port
QB_PORT=31337 bash install-qbittorrent.sh
```

Available combinations are the release tags (`release-<qbt>_v<libtorrent>`) at
<https://github.com/userdocs/qbittorrent-nox-static/releases>.

## Uninstall

```bash
bash install-qbittorrent.sh --uninstall
```

Config and downloads are kept in `~/.qbittorrent`.

## Notes

- Log in as `admin` with the temporary password shown at the end (also in `~/.qbittorrent/qbittorrent.log`), then change it immediately.
- Use only for legal content.
- Some hosts restrict which ports you may use; set `QB_PORT` accordingly.

## License

MIT
