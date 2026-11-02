#!/usr/bin/env bash
# Tests tvplayer-sync-proxmox.sh without Proxmox. The "container" is a bwrap
# sandbox with the real paths (/opt, /etc, /var/lib...) and the real server
# binary; pct, pveam, pvesh, pvesm, systemctl, runuser and the like are stubs.
# It can't prove what real pct, pveam and systemd do, only the script's logic.
#
#   tool/proxmox/test_installer.sh [server archive]
#
# Without an archive it builds the server. Needs bwrap and script (util-linux),
# no root.
set -euo pipefail
umask 022

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
script=$root/tool/proxmox/tvplayer-sync-proxmox.sh
work=$(mktemp -d)
sb=
failures=0

cleanup() { stop_server; rm -rf "$work"; }
stop_server() {
  if [ -n "$sb" ] && [ -f "$sb/run/server.pid" ]; then
    kill "$(cat "$sb/run/server.pid")" 2>/dev/null || true
    rm -f "$sb/run/server.pid"
  fi
}
trap cleanup EXIT

pass() { echo "  ok: $1"; }
fail() {
  echo "  FAILED: $1"
  failures=$((failures + 1))
  tail -n 8 "$work/out" 2>/dev/null | sed 's/^/    | /'
}
check() { # <description> <command...>
  local what=$1
  shift
  if "$@"; then pass "$what"; else fail "$what"; fi
}
log_has() { grep -qF -- "$1" "$work/out"; }
log_lacks() { ! grep -qF -- "$1" "$work/out"; }
log_count() { grep -oF -- "$1" "$work/out" | wc -l; }

# --- Fixtures ---

if [ $# -ge 1 ]; then
  good=$(realpath "$1")
else
  echo "Building the server..."
  (cd "$root/packages/tvplayer_sync_server" && dart pub get >/dev/null && dart build cli >/dev/null)
  bundle=$root/packages/tvplayer_sync_server/build/cli/linux_x64/bundle
  cp -r "$root/packages/tvplayer_sync_server/deploy" \
    "$root/packages/tvplayer_sync_server/config.example.json" "$bundle/"
  good=$work/release/tvplayer-sync-server_test_linux-amd64.tar.gz
  mkdir -p "$work/release"
  tar -czf "$good" -C "$(dirname "$bundle")" bundle
fi
new_version=$(tar -xzOf "$good" bundle/deploy/tvplayer-sync >/dev/null; mkdir -p "$work/x"; \
  tar -xzf "$good" -C "$work/x"; "$work/x/bundle/bin/tvplayer_sync_server" --version)

# An archive whose program reports a version but can't serve.
broken=$work/broken/tvplayer-sync-server_broken_linux-amd64.tar.gz
mkdir -p "$work/broken"
cp -r "$work/x/bundle" "$work/broken/bundle"
cat > "$work/broken/bundle/bin/tvplayer_sync_server" <<'EOF'
#!/bin/sh
case "$*" in *--version*) echo 9.9.9; exit 0 ;; esac
exit 1
EOF
tar -czf "$broken" -C "$work/broken" bundle

# The commands the script finds on the host.
host_stubs=$work/host-stubs
mkdir -p "$host_stubs"
stub() { cat > "$host_stubs/$1"; chmod +x "$host_stubs/$1"; }

stub pveversion <<'EOF'
#!/bin/sh
echo "pve-manager/${FAKE_PVE:-8.4.1}/0000 (running kernel: 6.8)"
EOF
stub id <<'EOF'
#!/bin/sh
echo 0
EOF
stub sleep <<'EOF'
#!/bin/sh
exec /usr/bin/sleep 0.3
EOF
stub pvesh <<'EOF'
#!/bin/sh
case "$*" in *--vmid\ 999*) exit 1 ;; esac
echo 200
EOF
stub pvesm <<'EOF'
#!/bin/sh
echo "Name Type Status Total Used Available %"
case "$*" in
  *vztmpl*) echo "local dir active 1 1 1 1%" ;;
  *) echo "local dir active 1 1 1 1%"; echo "local-lvm lvmthin active 1 1 1 1%" ;;
esac
EOF
stub pveam <<'EOF'
#!/bin/sh
case "$1" in
  update) exit 0 ;;
  list) cat "$FAKE_SB/templates" 2>/dev/null; exit 0 ;;
  available)
    echo "system debian-12-standard_12.7-1_amd64.tar.zst"
    if [ -z "${FAKE_NO_D13:-}" ]; then echo "system debian-13-standard_13.1-1_amd64.tar.zst"; fi ;;
  download) echo "local:vztmpl/$3 1MB" >> "$FAKE_SB/templates" ;;
esac
EOF
# Addresses of the fake container reach the real server on this machine, and
# release downloads come from a folder.
stub curl <<'EOF'
#!/bin/bash
args=()
for a in "$@"; do
  if [ -n "${FAKE_HOST_BLOCKED:-}" ] && [[ $a == http://192.0.2.10:* ]]; then
    echo "curl: (7) Failed to connect to 192.0.2.10: Connection timed out" >&2
    exit 7
  fi
  a=${a/http:\/\/192.0.2.10:/http://127.0.0.1:}
  a=${a/https:\/\/github.com\/bbglind\/tvplayer\/releases\/download\/v*\//file://$FAKE_RELEASE/}
  args+=("$a")
done
exec /usr/bin/curl "${args[@]}"
EOF
stub pct <<'EOF'
#!/bin/bash
sb=$FAKE_SB
incontainer() {
  /usr/bin/bwrap --unshare-user --uid 0 --gid 0 --ro-bind /usr /usr --ro-bind /usr /host-usr \
    --bind "$sb/usrbin" /usr/bin --bind "$sb/localbin" /usr/local/bin \
    --bind "$sb/localsbin" /usr/local/sbin \
    --symlink usr/lib /lib --symlink usr/lib64 /lib64 --symlink usr/bin /bin --symlink usr/sbin /sbin \
    --dev /dev --proc /proc --tmpfs /tmp --bind "$sb/etc" /etc --bind "$sb/opt" /opt \
    --bind "$sb/root" /root --bind "$sb/run" /run --bind "$sb/varlib" /var/lib \
    --bind "$sb/backups" /var/backups "$@"
}
cmd=$1; shift
case "$cmd" in
  status)
    [ -f "$sb/exists" ] || exit 2
    cat "$sb/status" ;;
  start) echo "status: running" > "$sb/status" ;;
  create)
    if [ -n "${FAKE_REFUSE_D13:-}" ] && [[ $2 == *debian-13* ]]; then
      echo "unsupported debian version '13'" >&2; exit 1
    fi
    echo "$*" > "$sb/created"; touch "$sb/exists"; echo "status: stopped" > "$sb/status"
    ;;
  push) cp "$2" "$sb/root/$(basename "$3")" ;;
  exec)
    shift 2  # the id and --
    # A real pct exec takes a second or two.
    [ -z "${FAKE_PCT_DELAY:-}" ] || /usr/bin/sleep "$FAKE_PCT_DELAY"
    if [ -n "${FAKE_TOKEN_FAIL:-}" ] && [[ "$*" == *"token create"* ]]; then
      echo "pct stub: can't run that" >&2; exit 1
    fi
    incontainer "$@"
    ;;
  *) echo "pct stub: $cmd" >&2; exit 1 ;;
esac
EOF

new_sandbox() {
  stop_server
  sb=$work/sb-$1
  mkdir -p "$sb"/{usrbin,localbin,localsbin,etc/systemd/system,opt,root,run/systemd/system,varlib,backups,net/vmbr0/bridge}
  : > "$sb/etc/passwd"
  echo 'root:x:0:0:root:/root:/bin/sh' > "$sb/etc/passwd"
  echo 'root:x:0:' > "$sb/etc/group"
  local f
  for f in /usr/bin/*; do ln -s "/host-usr/bin/$(basename "$f")" "$sb/usrbin/"; done
  for f in systemctl runuser useradd install hostname apt-get; do rm -f "$sb/usrbin/$f"; done
  cat > "$sb/localsbin/systemctl" <<'EOF'
#!/bin/bash
start() {
  grep -q ExecStart=/opt/tvplayer-sync/bin /etc/systemd/system/tvplayer-sync.service || exit 1
  # A real server isn't listening yet when systemctl returns.
  setsid sh -c "/usr/bin/sleep $(cat /run/start-delay 2>/dev/null || echo 0); exec /opt/tvplayer-sync/bin/tvplayer_sync_server --config /etc/tvplayer-sync/config.json serve" \
    </dev/null >>/run/server.log 2>&1 &
  echo $! > /run/server.pid
}
case "$1" in
  start) start ;;
  enable) start ;;
  stop)
    if [ -f /run/server.pid ]; then kill "$(cat /run/server.pid)" 2>/dev/null; rm -f /run/server.pid; /usr/bin/sleep 0.3; fi ;;
esac
exit 0
EOF
  cat > "$sb/localsbin/runuser" <<'EOF'
#!/bin/sh
shift 3
exec "$@"
EOF
  cat > "$sb/localsbin/useradd" <<'EOF'
#!/bin/sh
for last; do :; done
echo "$last:x:999:999::/var/lib/$last:/usr/sbin/nologin" >> /etc/passwd
echo "$last:x:999:" >> /etc/group
EOF
  cat > "$sb/localsbin/install" <<'EOF'
#!/bin/bash
args=()
while [ $# -gt 0 ]; do
  case "$1" in -o | -g) shift 2 ;; *) args+=("$1"); shift ;; esac
done
exec /host-usr/bin/install "${args[@]}"
EOF
  cat > "$sb/localsbin/hostname" <<'EOF'
#!/bin/sh
echo "fe80::1 192.0.2.10"
EOF
  cat > "$sb/localsbin/apt-get" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "$sb"/localsbin/*
}

copy_script() {
  copy=$work/script.sh
  sed "s|/sys/class/net|$sb/net|" "$script" > "$copy"
  [ -z "${PIN:-}" ] || sed -i "s|@TVPLAYER_VERSION@|$PIN|" "$copy"
}

# Runs the script, with the answers on stdin. Sets $status; output in $work/out.
# Questions don't show: read prints its prompt only on a terminal. LIMIT stops a
# script that keeps asking after its input ended.
run() { # <answers> <args...>
  local answers=$1 copy
  shift
  copy_script
  status=0
  printf '%b' "$answers" | PATH="$host_stubs:$PATH" FAKE_SB="$sb" FAKE_RELEASE="${RELEASE_DIR:-}" \
    timeout "${LIMIT:-600}" bash "$copy" "$@" > "$work/out" 2>&1 || status=$?
}

# The same on a terminal, so the output has the questions, and the answers too.
run_tty() { # <answers> <args...>
  local answers=$1 copy command
  shift
  copy_script
  printf -v command '%q ' bash "$copy" "$@"
  status=0
  printf '%b' "$answers" | PATH="$host_stubs:$PATH" FAKE_SB="$sb" FAKE_RELEASE="${RELEASE_DIR:-}" \
    script -qfec "$command" /dev/null > "$work/out" 2>&1 || status=$?
}

ct() { PATH="$host_stubs:$PATH" FAKE_SB="$sb" pct exec 1 -- "$@" </dev/null; }

# A container set up by hand from docs/sync-server.md: the old server, which
# calls itself 1.0.0 and has no version in /v1/health, on a changed port.
hand_install() {
  local old=$sb/opt/tvplayer-sync
  mkdir -p "$old"
  cp -r "$work/x/bundle/." "$old/"
  mv "$old/bin/tvplayer_sync_server" "$old/bin/real"
  cat > "$old/bin/tvplayer_sync_server" <<'EOF'
#!/bin/sh
case "$*" in *--version*) echo 1.0.0; exit 0 ;; esac
exec /opt/tvplayer-sync/bin/real "$@"
EOF
  chmod +x "$old/bin/tvplayer_sync_server"
  echo 'tvplayer-sync:x:999:999::/var/lib/tvplayer-sync:/usr/sbin/nologin' >> "$sb/etc/passwd"
  mkdir -p "$sb/etc/tvplayer-sync" "$sb/varlib/tvplayer-sync" "$sb/backups/tvplayer-sync"
  sed 's/8787/18787/' "$work/x/bundle/config.example.json" > "$sb/etc/tvplayer-sync/config.json"
  cp "$old"/deploy/*.service "$old"/deploy/*.timer "$sb/etc/systemd/system/"
  # The wrapper as it was then, without a umask of its own.
  cat > "$old/deploy/tvplayer-sync" <<'EOF2'
#!/bin/sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
exec runuser -u tvplayer-sync -- /opt/tvplayer-sync/bin/tvplayer_sync_server \
  --config /etc/tvplayer-sync/config.json "$@"
EOF2
  install -m 755 "$old/deploy/tvplayer-sync" "$sb/localbin/tvplayer-sync"
  ln -s /usr/local/bin/tvplayer-sync "$sb/usrbin/tvplayer-sync"
  touch "$sb/exists"
  echo "status: running" > "$sb/status"
  ct /usr/local/bin/tvplayer-sync token create --name laptop >/dev/null
  ct systemctl start tvplayer-sync
  /usr/bin/sleep 0.5
}

backup_made() { compgen -G "$sb/backups/tvplayer-sync/before-update-*.sqlite" >/dev/null; }
backup_count() { compgen -G "$sb/backups/tvplayer-sync/before-update-*.sqlite" | wc -l; }
backups_private() {
  local file
  for file in "$sb"/backups/tvplayer-sync/*.sqlite; do
    [ "$(stat -c %a "$file")" = 600 ] || return 1
  done
}
config_sum() { sha256sum < "$sb/etc/tvplayer-sync/config.json"; }
health() { /usr/bin/curl -fsS --noproxy '*' --max-time 3 "http://127.0.0.1:$1/v1/health"; }
health_is() { health "$1" | grep -qF "$2"; }
token_kept() { ct /usr/local/bin/tvplayer-sync token list | grep -q '^laptop'; }
no_token_in_files() {
  ! grep -rlE 'tvps_[A-Za-z0-9_-]{20}' "$sb/root" "$sb/run/server.log" "$sb/backups" "$work/script.sh" 2>/dev/null \
    | grep -q .
}

# --- Scenarios ---

echo "Fresh install, defaults, one token"
new_sandbox install
run '\n\n\n\n\n\n\n\n\n\ny\ny\nlaptop\n\n' --install --local "$good"
check "exits 0" [ "$status" = 0 ]
check "Debian 13 chosen" log_has "debian-13-standard"
check "created unprivileged, with nesting" grep -q -- '--unprivileged 1 --features nesting=1' "$sb/created"
check "rootfs on local-lvm, 2 GB" grep -q -- '--rootfs local-lvm:2' "$sb/created"
check "program in place" [ -x "$sb/opt/tvplayer-sync/bin/tvplayer_sync_server" ]
check "wrapper in place" [ -x "$sb/localbin/tvplayer-sync" ]
check "symlink in place" [ -L "$sb/usrbin/tvplayer-sync" ]
check "config in place" [ -f "$sb/etc/tvplayer-sync/config.json" ]
check "units in place" [ -f "$sb/etc/systemd/system/tvplayer-sync-backup.timer" ]
check "health answers" health_is 8787 "\"version\":\"$new_version\""
check "address shown" log_has "http://192.0.2.10:8787"
check "token printed" log_has "laptop: tvps_"
check "pushed archive removed" [ ! -e "$sb/root/tvplayer-sync-update.tar.gz" ]
check "token in no file" no_token_in_files
check "explains one token per device" log_has "Each device that syncs needs its own token, e.g. one for the laptop and one for the phone."
check "explains it is shown once" log_has "Each token is shown only once: copy it now, e.g. into a password manager."
check "exactly one token" [ "$(log_count ": tvps_")" = 1 ]
check "the old way to stop is gone" log_lacks "empty line"
ct /usr/local/bin/tvplayer-sync backup /var/backups/tvplayer-sync/manual.sqlite >/dev/null
check "a manual backup is private" backups_private

echo "Tokens on a terminal: empty, invalid and taken names ask again"
new_sandbox tokens
run_tty '\n\n\n\n\n\n\n\n\n\ny\ny\n\nbad name\nlaptop\ny\nlaptop\nphone\n\n' --install --local "$good"
check "exits 0" [ "$status" = 0 ]
check "asks once whether to start" [ "$(log_count "Create a token now? [Y/n]: ")" = 1 ]
check "asks for a name five times" [ "$(log_count "Device name for a new token: ")" = 5 ]
check "asks for another after each token" [ "$(log_count "Create another token? [y/N]: ")" = 2 ]
check "says which names work" [ "$(log_count "Use letters, digits, dot, dash or underscore")" = 2 ]
check "says the name is taken" log_has "A token with this name exists"
check "asks for another name" log_has "Choose another name."
check "the first token shown once" [ "$(log_count "laptop: tvps_")" = 1 ]
check "the second token shown once" [ "$(log_count "phone: tvps_")" = 1 ]
check "both tokens exist" [ "$(ct /usr/local/bin/tvplayer-sync token list | grep -cE '^(laptop|phone)')" = 2 ]
check "token in no file" no_token_in_files

echo "Tokens: the input ends at each question"
new_sandbox eofnow
LIMIT=60 run '\n\n\n\n\n\n\n\n\n\ny\n' --install --local "$good"
check "at the first question, exits 0" [ "$status" = 0 ]
new_sandbox eofname
LIMIT=60 run '\n\n\n\n\n\n\n\n\n\ny\ny\n' --install --local "$good"
check "at the name, exits 0" [ "$status" = 0 ]
new_sandbox eofanother
LIMIT=60 run '\n\n\n\n\n\n\n\n\n\ny\ny\nlaptop\n' --install --local "$good"
check "at another token, exits 0" [ "$status" = 0 ]
check "the token was shown" log_has "laptop: tvps_"
check "no error" log_lacks "No answer"

echo "Tokens: creating one really fails"
new_sandbox tokenfail
FAKE_TOKEN_FAIL=1 LIMIT=60 run '\n\n\n\n\n\n\n\n\n\ny\ny\nlaptop\nphone\n' --install --local "$good"
check "exits 0, the server is fine" [ "$status" = 0 ]
check "says so" log_has "No token made for laptop."
check "says how to do it later" log_has "Make it later, in the container"
check "doesn't ask again" log_lacks "No token made for phone."

echo "Fresh install, declined at the summary"
new_sandbox decline
run '\n\n\n\n\n\n\n\n\n\nn\n' --install --local "$good"
check "exits 0" [ "$status" = 0 ]
check "nothing created" [ ! -e "$sb/created" ]

echo "Fresh install, no Debian 13 template"
new_sandbox d12
FAKE_NO_D13=1 run '\n\n\n\n\n\n\n\n\n\ny\nn\n' --install --local "$good"
check "falls back to Debian 12" log_has "debian-12-standard"

echo "Fresh install, Debian 13 refused at create"
new_sandbox refuse
FAKE_REFUSE_D13=1 run '\n\n\n\n\n\n\n\n\n\ny\ny\nn\n' --install --local "$good"
check "exits 0" [ "$status" = 0 ]
check "created with Debian 12" grep -q debian-12 "$sb/created"

echo "Update of a hand-made install on another port"
new_sandbox update
hand_install
before=$(config_sum)
run 'y\n' --update 1 --local "$good"
check "exits 0" [ "$status" = 0 ]
check "shows the current version" log_has "Current version: 1.0.0"
check "shows the new version" log_has "New version:     $new_version"
check "new version answers on the configured port" health_is 18787 "\"version\":\"$new_version\""
check "config untouched" [ "$before" = "$(config_sum)" ]
check "token kept" token_kept
check "database backed up" backup_made
check "no rollback folder left" [ ! -e "$sb/opt/tvplayer-sync.rollback" ]
check "no staging folder left" [ ! -e "$sb/opt/tvplayer-sync.new" ]
check "pushed archive removed" [ ! -e "$sb/root/tvplayer-sync-update.tar.gz" ]
check "the backup is private" backups_private

echo "Update again, on the same version"
/usr/bin/sleep 1.1
run 'y\n' --update 1 --local "$good"
check "exits 0" [ "$status" = 0 ]
check "shows the same version twice" log_has "Current version: $new_version"
check "says it is the same version" log_has "The same version"
check "new version answers" health_is 18787 "\"version\":\"$new_version\""
check "config untouched" [ "$before" = "$(config_sum)" ]
check "token kept" token_kept
check "a second backup" [ "$(backup_count)" = 2 ]
check "both backups private" backups_private

echo "Update when the server needs a moment to start"
new_sandbox slowupdate
hand_install
echo 0.7 > "$sb/run/start-delay"
FAKE_PCT_DELAY=1.5 run 'y\n' --update 1 --local "$good"
check "exits 0" [ "$status" = 0 ]
check "no false warning" log_lacks "not from this host"

echo "Install when the server needs a moment to start"
new_sandbox slowinstall
echo 0.7 > "$sb/run/start-delay"
FAKE_PCT_DELAY=1.5 run '\n\n\n\n\n\n\n\n\n\ny\nn\n' --install --local "$good"
check "exits 0" [ "$status" = 0 ]
check "no false warning" log_lacks "not from this host"

echo "Update when the host really can't reach the container"
new_sandbox blocked
hand_install
FAKE_HOST_BLOCKED=1 run 'y\n' --update 1 --local "$good"
check "exits 0, the server is fine" [ "$status" = 0 ]
check "warns" log_has "not from this host"
check "with the address it tried" log_has "http://192.0.2.10:18787"
check "and curl's own error" log_has "Connection timed out"

echo "Update that fails its health check"
new_sandbox rollback
hand_install
before=$(config_sum)
wrapper_before=$(sha256sum < "$sb/localbin/tvplayer-sync")
run 'y\n' --update 1 --local "$broken"
check "exits non-zero" [ "$status" != 0 ]
check "says it failed and was undone" log_has "FAILED and was undone"
check "old version answers again" health_is 18787 '"service":"tvplayer-sync"'
check "old program back" [ -x "$sb/opt/tvplayer-sync/bin/real" ]
check "wrapper as before" [ "$wrapper_before" = "$(sha256sum < "$sb/localbin/tvplayer-sync")" ]
check "config untouched" [ "$before" = "$(config_sum)" ]
check "token kept" token_kept
check "database still there" [ -s "$sb/varlib/tvplayer-sync/sync.sqlite" ]
check "backup still there" backup_made
check "no rollback folder left" [ ! -e "$sb/opt/tvplayer-sync.rollback" ]

echo "Update declined"
new_sandbox updecline
hand_install
run 'n\n' --update 1 --local "$good"
check "exits 0" [ "$status" = 0 ]
check "old program still there" [ -x "$sb/opt/tvplayer-sync/bin/real" ]
check "no backup made" [ -z "$(ls "$sb/backups/tvplayer-sync")" ]
check "staging removed" [ ! -e "$sb/opt/tvplayer-sync.new" ]
check "pushed archive removed" [ ! -e "$sb/root/tvplayer-sync-update.tar.gz" ]

echo "Update of a container that isn't a tvplayer-sync install"
new_sandbox notours
touch "$sb/exists"
echo "status: running" > "$sb/status"
run '' --update 1 --local "$good"
check "exits non-zero" [ "$status" != 0 ]
check "says what is missing" log_has "/opt/tvplayer-sync/bin/tvplayer_sync_server"
check "nothing unpacked" [ -z "$(ls "$sb/opt")" ]

echo "Update of a container that doesn't exist"
new_sandbox none
run '' --update 1 --local "$good"
check "exits non-zero" [ "$status" != 0 ]
check "says so" log_has "no container 1"

echo "An interrupted update is restored"
new_sandbox interrupted
hand_install
ct systemctl stop tvplayer-sync
mkdir -p "$sb/opt/tvplayer-sync.rollback/system"
for u in tvplayer-sync.service tvplayer-sync-backup.service tvplayer-sync-backup.timer; do
  cp "$sb/etc/systemd/system/$u" "$sb/opt/tvplayer-sync.rollback/system/"
done
cp "$sb/localbin/tvplayer-sync" "$sb/opt/tvplayer-sync.rollback/system/wrapper"
touch "$sb/opt/tvplayer-sync.rollback/had-link" "$sb/opt/tvplayer-sync.rollback/saved"
mv "$sb/opt/tvplayer-sync" "$sb/opt/tvplayer-sync.rollback/program"
run 'y\n' --update 1 --local "$good"
check "exits 0" [ "$status" = 0 ]
check "old program back" [ -x "$sb/opt/tvplayer-sync/bin/real" ]
check "rollback folder gone" [ ! -e "$sb/opt/tvplayer-sync.rollback" ]
/usr/bin/sleep 0.5
check "old version answers" health_is 18787 '"service":"tvplayer-sync"'

echo "Download: checksums"
new_sandbox download
RELEASE_DIR=$work/rel
mkdir -p "$RELEASE_DIR"
name=tvplayer-sync-server_${new_version}_linux-amd64.tar.gz
cp "$good" "$RELEASE_DIR/$name"
(cd "$RELEASE_DIR" && sha256sum "$name" > SHA256SUMS)
PIN=$new_version run '\n\n\n\n\n\n\n\n\n\nn\n' --install
check "a good archive is accepted" log_has "The checksum matches SHA256SUMS."
check "ends at the summary" log_has "Nothing was created."
echo x >> "$RELEASE_DIR/$name"
PIN=$new_version run '' --install
check "a damaged archive stops" [ "$status" != 0 ]
check "says it doesn't match" log_has "doesn't match SHA256SUMS"
RELEASE_DIR=

echo "Refusals"
new_sandbox refusals
run '' --install
check "an unpinned copy needs --local" log_has "no release version"
run '' --install --local "$work/nonexistent.tar.gz"
check "a missing archive stops" log_has "doesn't exist"
FAKE_PVE=7.4-1 run '' --install --local "$good"
check "Proxmox VE 7 is refused" log_has "needs Proxmox VE 8 or 9"
run 'y\n' --bogus
check "an unknown option stops" log_has "Unknown option"

stop_server
echo
if [ "$failures" = 0 ]; then
  echo "All passed."
else
  echo "$failures FAILED."
  exit 1
fi
