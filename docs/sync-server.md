# The tvplayer sync server

tvplayer can keep watch progress, favourites and settings the same on your
devices (see the user guide, Settings › Sync). It does that through a small
server **of your own**: one program and one database file, for one user.
This page explains how to install it, keep it up to date and back it up.
It assumes no Linux experience; every command can be copied as it is,
except the values in `<angle brackets>`, which you fill in yourself.

Contents:

1. [How it fits together](#1-how-it-fits-together)
2. [Build the server (on your computer)](#2-build-the-server-on-your-computer)
3. [Create the container](#3-create-the-container)
4. [Copy the server into the container](#4-copy-the-server-into-the-container)
5. [Install it](#5-install-it)
6. [Create a token per device](#6-create-a-token-per-device)
7. [Check that it runs](#7-check-that-it-runs)
8. [A reverse proxy with HTTPS (optional)](#8-a-reverse-proxy-with-https-optional)
9. [Set up the app](#9-set-up-the-app)
10. [Update the server](#10-update-the-server)
11. [Backups and restoring](#11-backups-and-restoring)
12. [Everyday commands](#12-everyday-commands)
13. [Troubleshooting](#13-troubleshooting)

---

## 1. How it fits together

```
 laptop app ─┐                          ┌──────────────────────────────┐
             ├─ http://192.0.2.10:8787 ─▶ sync server (Debian 13 LXC)  │
 phone app ──┘   (home network)         │  /opt/tvplayer-sync          │
      │                                 │  /var/lib/tvplayer-sync/     │
      └─ https://sync.example.com ──▶ reverse proxy ─▶ (same server)  │
         (at home or from outside)      └──────────────────────────────┘
```

- The server is a normal service in its own small **Debian 13** container
  (an unprivileged LXC on Proxmox in this guide; any Debian 13 machine
  works the same). No Docker.
- It listens on **plain HTTP**, port **8787**, on your home network.
  That is fine at home. For HTTPS, and for reaching it from outside, put
  a **reverse proxy** in front (for example Nginx Proxy Manager, section
  8). How you reach the proxy from outside is up to you; a VPN such as
  Tailscale on the proxy machine is one way. The sync server itself needs
  no VPN and no internet access.
- The app accepts both `http://` and `https://` addresses.
- **One user.** Each device logs in with its own **token**, made on the
  server. Only a hash of each token is stored.
- **What the server stores**: watch progress and marks, favourites and
  your category settings, and the synced settings, per provider account
  under an id that doesn't reveal the account. **Never**: your provider's
  address or login, stream links, service keys or downloaded files. It
  does hold names (of your favourite items and categories, and of the next
  episode of a series), so keep it on your own network or behind HTTPS.
- **Request size**: the app sends at most 256 KB per request and the
  server takes at most 1 MB. nginx, and so Nginx Proxy Manager, accept
  1 MB by default, so a proxy needs **no** extra size setting.

You need about 20 MB of disk for the program, a few MB for the database,
and 128 MB of memory.

## 2. Build the server (on your computer)

The server is built on your Linux computer (the one with the tvplayer
source and Flutter or the Dart SDK), then copied into the container. The
build includes the SQLite library it needs, so nothing else has to be
installed in the container.

In a terminal, in the tvplayer source folder:

```sh
cd packages/tvplayer_sync_server
dart pub get
dart build cli
cp -r deploy config.example.json build/cli/linux_x64/bundle/
tar -czf ~/tvplayer-sync.tar.gz -C build/cli/linux_x64 bundle
ls -lh ~/tvplayer-sync.tar.gz
```

The last line shows the file to copy: `~/tvplayer-sync.tar.gz` (about
4 MB). The program needs glibc 2.34 or newer; Debian 13 has 2.41.

## 3. Create the container

In the Proxmox web interface, create a container (**Create CT**):

- **Template**: Debian 13 (download it under the storage's **CT
  Templates** › **Templates** if it isn't there).
- **Unprivileged container**: yes (the default). Under **Options** ›
  **Features**, **Nesting** must be on (the default for new unprivileged
  containers): the service uses systemd's sandboxing, which needs it.
- **Disk**: 2 GB is plenty. **CPU**: 1 core. **Memory**: 256 MB, swap
  256 MB.
- **Network**: a fixed address on your home network, e.g.
  `192.0.2.10/24` with your router as gateway (or DHCP with a fixed lease
  in your router).

Start it. Note its **CT ID** (e.g. 105) and **IP address**: they are
`<CTID>` and `<LXC-IP>` below. `<Proxmox-host>` is the address of the
Proxmox machine itself.

## 4. Copy the server into the container

The simplest way needs nothing in the container: copy the file to the
Proxmox host, then push it into the container with `pct push`.

On your computer:

```sh
scp ~/tvplayer-sync.tar.gz root@<Proxmox-host>:/root/
```

Then log in to the Proxmox host (with `ssh root@<Proxmox-host>`, or the
host's **Shell** in the web interface) and run:

```sh
pct push <CTID> /root/tvplayer-sync.tar.gz /root/tvplayer-sync.tar.gz
pct enter <CTID>
```

`pct enter` opens a root shell **inside** the container; the rest of the
installation happens there. (`exit` leaves it again.)

## 5. Install it

Inside the container, as root:

```sh
apt update
apt install -y curl

# A system user that runs the server and owns its data.
useradd --system --home-dir /var/lib/tvplayer-sync --shell /usr/sbin/nologin tvplayer-sync

# The program.
mkdir -p /opt/tvplayer-sync
tar -xzf /root/tvplayer-sync.tar.gz -C /opt/tvplayer-sync --strip-components=1 --no-same-owner

# Data and backup folders, readable only by the service user.
install -d -o tvplayer-sync -g tvplayer-sync -m 700 /var/lib/tvplayer-sync /var/backups/tvplayer-sync

# The config file.
install -d -m 755 /etc/tvplayer-sync
install -m 644 /opt/tvplayer-sync/config.example.json /etc/tvplayer-sync/config.json

# The service, the daily backup and the tvplayer-sync command.
cp /opt/tvplayer-sync/deploy/tvplayer-sync.service /opt/tvplayer-sync/deploy/tvplayer-sync-backup.service /opt/tvplayer-sync/deploy/tvplayer-sync-backup.timer /etc/systemd/system/
install -m 755 /opt/tvplayer-sync/deploy/tvplayer-sync /usr/local/bin/tvplayer-sync
ln -sf /usr/local/bin/tvplayer-sync /usr/bin/tvplayer-sync
systemctl daemon-reload
systemctl enable --now tvplayer-sync.service tvplayer-sync-backup.timer
```

The link in `/usr/bin` is there because a `pct enter` shell may not look in
`/usr/local/bin`; with it, `tvplayer-sync` works in every shell.

The config file `/etc/tvplayer-sync/config.json` holds:

```json
{
  "host": "0.0.0.0",
  "port": 8787,
  "dataDir": "/var/lib/tvplayer-sync"
}
```

`0.0.0.0` means "on every network interface". To use another port, change
it with `nano /etc/tvplayer-sync/config.json` and run `systemctl restart
tvplayer-sync`.

## 6. Create a token per device

Still inside the container:

```sh
tvplayer-sync token create --name laptop
tvplayer-sync token create --name pixel
```

Each command prints a token starting with `tvps_`, **only once**. Copy each
token to its device (e.g. in a password manager); you enter it in the app
in section 9. Lost one? Revoke it and create a new one (section 12).

## 7. Check that it runs

Inside the container:

```sh
systemctl status tvplayer-sync --no-pager
curl http://127.0.0.1:8787/v1/health
```

The status shows `active (running)`, and `curl` answers
`{"service":"tvplayer-sync","api":1}`.

Then on your computer (on the home network):

```sh
curl http://<LXC-IP>:8787/v1/health
```

It should answer the same. If it doesn't, see section 13.

## 8. A reverse proxy with HTTPS (optional)

With only a home network, you can skip this and use
`http://<LXC-IP>:8787` in the app. With a reverse proxy you get HTTPS and
one name that works at home and, through however you reach the proxy,
away from home.

**Nginx Proxy Manager** (NPM): **Hosts** › **Proxy Hosts** › **Add Proxy
Host**.

*Details* tab:

| Field | Value |
|---|---|
| Domain Names | `<your sync domain>`, e.g. `sync.example.com` |
| Scheme | `http` |
| Forward Hostname / IP | `<LXC-IP>`, e.g. `192.0.2.10` |
| Forward Port | `8787` |
| Cache Assets | off |
| Block Common Exploits | on |
| Websockets Support | off (not needed) |

*SSL* tab:

| Field | Value |
|---|---|
| SSL Certificate | your certificate for the domain (Let's Encrypt or your own) |
| Force SSL | on |
| HTTP/2 Support | on |
| HSTS Enabled | as for your other hosts |

Nothing goes in the *Advanced* tab: the default body size limit (1 MB) is
enough.

Make the name point to the proxy, e.g. a local DNS entry
`<your sync domain>` → the proxy's address in your router or DNS server,
the same as for your other proxied services. Then on your computer:

```sh
curl https://<your sync domain>/v1/health
```

It answers `{"service":"tvplayer-sync","api":1}`.

Any other reverse proxy works the same: forward `https://<your sync
domain>/` to `http://<LXC-IP>:8787/`. The server can also live under a
path (e.g. `https://example.com/sync` forwarded to the server's `/`); use
the full address with the path in the app.

## 9. Set up the app

**Sync the device whose settings you want to keep first.** The first
device to sync sets the synced settings for all the others; watch history
and favourites of all devices are merged either way. In this guide: the
laptop first, then the phone.

On each device, in **Settings › Sync**:

1. Turn on **"Sync"**.
2. **"Server address"** › **"Edit…"**: `https://<your sync domain>`, or at
   home `http://<LXC-IP>:8787`.
3. **"Token"** › **"Enter token…"**: this device's token.
4. **"Test connection"** should answer "Connected to the sync server.".
5. The app syncs straight away; "Last sync: Today …" shows when.

Before its first sync, each device saves a copy of its own data in the
app's data folder under `sync_backup/`.

## 10. Update the server

Build and copy the new version as in sections 2 and 4. Then inside the
container:

```sh
systemctl stop tvplayer-sync
tvplayer-sync backup /var/backups/tvplayer-sync/before-update-$(date +%Y%m%d-%H%M%S).sqlite
rm -rf /opt/tvplayer-sync
mkdir -p /opt/tvplayer-sync
tar -xzf /root/tvplayer-sync.tar.gz -C /opt/tvplayer-sync --strip-components=1 --no-same-owner
cp /opt/tvplayer-sync/deploy/tvplayer-sync.service /opt/tvplayer-sync/deploy/tvplayer-sync-backup.service /opt/tvplayer-sync/deploy/tvplayer-sync-backup.timer /etc/systemd/system/
install -m 755 /opt/tvplayer-sync/deploy/tvplayer-sync /usr/local/bin/tvplayer-sync
ln -sf /usr/local/bin/tvplayer-sync /usr/bin/tvplayer-sync
systemctl daemon-reload
systemctl start tvplayer-sync
/opt/tvplayer-sync/bin/tvplayer_sync_server --version
curl http://127.0.0.1:8787/v1/health
```

Your data and config stay where they are. A new version updates the
database by itself when it starts; an older version refuses a database
from a newer one (to go back, restore the `before-update-…` backup,
section 11). The devices need nothing: they sync on as before.

## 11. Backups and restoring

**Automatic**: every night around 03:30 a copy of the database goes to
`/var/backups/tvplayer-sync/sync-<date>-<time>.sqlite`; the newest 14 are
kept. Check the timer and the copies:

```sh
systemctl list-timers tvplayer-sync-backup.timer --no-pager
ls -lh /var/backups/tvplayer-sync/
```

**By hand**, also while the server runs:

```sh
tvplayer-sync backup /var/backups/tvplayer-sync/manual-$(date +%Y%m%d-%H%M%S).sqlite
```

**Off the machine**: Proxmox backups of the container (**Backup** in the
container's menu, or a backup job under **Datacenter** › **Backup**)
include everything: program, config, database and the copies. To copy
one database copy to the Proxmox host, run there:

```sh
pct pull <CTID> /var/backups/tvplayer-sync/<file>.sqlite /root/<file>.sqlite
```

**Restoring** a copy, inside the container:

```sh
systemctl stop tvplayer-sync
cp /var/lib/tvplayer-sync/sync.sqlite /root/sync-before-restore.sqlite
rm -f /var/lib/tvplayer-sync/sync.sqlite-wal /var/lib/tvplayer-sync/sync.sqlite-shm
install -o tvplayer-sync -g tvplayer-sync -m 600 /var/backups/tvplayer-sync/<file>.sqlite /var/lib/tvplayer-sync/sync.sqlite
systemctl start tvplayer-sync
```

The devices notice that the server went back in time and send it what it
is missing on their next sync, so after a restore nothing that is still
on a device is lost. Tokens are part of the database: a restored copy has
the tokens it had then.

The data on each device has its own backup from before its first sync
(`sync_backup/` in the app's data folder).

## 12. Everyday commands

Inside the container (`pct enter <CTID>` on the Proxmox host):

| Command | Does |
|---|---|
| `tvplayer-sync token list` | The tokens by name, with when each was last used |
| `tvplayer-sync token create --name <name>` | A new token (shown once) |
| `tvplayer-sync token revoke <name>` | Deletes a token: that device can't sync any more |
| `tvplayer-sync status` | How many records each space holds |
| `tvplayer-sync backup <file>` | A copy of the database |
| `systemctl restart tvplayer-sync` | Restarts the server |
| `journalctl -u tvplayer-sync -n 50 --no-pager` | The last 50 log lines |

The log has one line per request, e.g.
`POST /spaces/:space/records 200 · 12 records · 4 ms`: never tokens,
names or other data.

## 13. Troubleshooting

| The app says | Check |
|---|---|
| "Couldn't reach the sync server. …" | The address (http or https, port); `curl …/v1/health` from another machine; that the container runs (`systemctl status tvplayer-sync`); away from home, that you can reach the proxy |
| "The sync server didn't accept the token. …" | The token was copied whole, and isn't revoked (`tvplayer-sync token list`) |
| "That address isn't a tvplayer sync server." | The address points somewhere else, e.g. the proxy's own page: check the proxy host's forward address and port |
| "The sync server didn't respond in time." | The container's load, or the network |
| "The sync server had a problem (HTTP 502). …" | 502/504 come from the proxy: the server is down or the forward address is wrong. Others: `journalctl -u tvplayer-sync` |
| "This device's clock is far off. …" | The device's date and time (use automatic time) |

If the status shows `status=226/NAMESPACE`, the container lacks
**Nesting**: on the Proxmox host, `pct set <CTID> --features nesting=1`,
then restart the container (`pct reboot <CTID>`).

If `systemctl status tvplayer-sync` shows it isn't running, the log
(`journalctl -u tvplayer-sync -n 50 --no-pager`) says why, e.g. a typo in
`/etc/tvplayer-sync/config.json` ("…is not valid JSON") or a port that is
already taken.

If `tvplayer-sync` answers "command not found" inside the container (for
example on a server installed before this link was part of section 5), run
this once:

```sh
ln -sf /usr/local/bin/tvplayer-sync /usr/bin/tvplayer-sync
```
