#!/usr/bin/env bash
# Installs or updates the tvplayer sync server in a Proxmox VE container.
# Run as root in the Proxmox host's shell. See docs/sync-server.md.
#
#   tvplayer-sync-proxmox.sh                  a menu
#   tvplayer-sync-proxmox.sh --install        install in a new container
#   tvplayer-sync-proxmox.sh --update <ctid>  update an existing container
#   ... --local <archive>                     use this server archive instead
#                                             of downloading it
#
# The ct_* functions run inside the container, through ct_run, so they can't
# use this script's variables or call each other unless ct_run sends them.
#
# Tokens are only ever kept in a local variable and printed: never in a file.
#
# shellcheck disable=SC2317,SC2329  # The ct_* functions are called through ct_run.
set -euo pipefail
umask 022

# Filled in by tool/package_release.sh. A copy that isn't filled in needs --local.
release_version='@TVPLAYER_VERSION@'
release_base=https://github.com/bbglind/tvplayer/releases/download
docs_url=https://github.com/bbglind/tvplayer/blob/main/docs/sync-server.md
ct_archive=/root/tvplayer-sync-update.tar.gz

tmp_dir=
local_archive=
archive=
stage_ct=          # The container holding files of an unfinished update.
critical_ct=       # The container whose program is being replaced right now.
health_via=

say() { printf '%s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# --- Questions ---

# ask <question> <default>: the answer goes to stdout.
ask() {
  local answer
  read -r -p "$1 [$2]: " answer \
    || die "No answer. Run this script in a terminal."
  printf '%s' "${answer:-$2}"
}

# ask_yes <question> <y|n>
ask_yes() {
  local answer hint='y/N'
  [ "$2" = y ] && hint='Y/n'
  while :; do
    read -r -p "$1 [$hint]: " answer \
      || die "No answer. Run this script in a terminal."
    answer=${answer:-$2}
    case "$answer" in
      [Yy] | [Yy][Ee][Ss]) return 0 ;;
      [Nn] | [Nn][Oo]) return 1 ;;
    esac
    say "Please answer y or n."
  done
}

# --- Code that runs inside the container ---

# Reports what a tvplayer-sync install should have and this container lacks.
ct_missing() {
  local path
  for path in /opt/tvplayer-sync/bin/tvplayer_sync_server \
      /usr/local/bin/tvplayer-sync /etc/tvplayer-sync/config.json \
      /etc/systemd/system/tvplayer-sync.service /var/backups/tvplayer-sync; do
    [ -e "$path" ] || echo "$path"
  done
  id tvplayer-sync >/dev/null 2>&1 || echo "the system user tvplayer-sync"
}

ct_version() {
  /usr/local/bin/tvplayer-sync --version
}

ct_port() {
  sed -n 's/.*"port"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' \
    /etc/tvplayer-sync/config.json | head -n 1
}

ct_data_dir() {
  sed -n 's/.*"dataDir"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    /etc/tvplayer-sync/config.json | head -n 1
}

ct_has_rollback() {
  [ -e /opt/tvplayer-sync.rollback ]
}

ct_ip() {
  local ip
  for ip in $(hostname -I 2>/dev/null); do
    case "$ip" in
      *:* | 169.254.* | 127.*) ;;
      *) echo "$ip"; return 0 ;;
    esac
  done
}

ct_booted() {
  [ -d /run/systemd/system ]
}

# Tools for checks inside the container. The server itself doesn't need them
# and needs no internet, so this may fail.
ct_install_curl() {
  export DEBIAN_FRONTEND=noninteractive
  timeout 120 apt-get -qq -o Acquire::Retries=1 update >/dev/null
  timeout 180 apt-get -qq -y install curl >/dev/null
}

ct_health() {
  command -v curl >/dev/null || return 1
  curl -fsS --noproxy '*' --connect-timeout 2 --max-time 4 \
    "http://127.0.0.1:$1/v1/health" 2>/dev/null
}

# The same steps as "Install it" in docs/sync-server.md.
ct_install() {
  local archive=$1
  id tvplayer-sync >/dev/null 2>&1 \
    || useradd --system --home-dir /var/lib/tvplayer-sync \
      --shell /usr/sbin/nologin tvplayer-sync
  mkdir -p /opt/tvplayer-sync
  tar -xzf "$archive" -C /opt/tvplayer-sync --strip-components=1 --no-same-owner
  install -d -o tvplayer-sync -g tvplayer-sync -m 700 \
    /var/lib/tvplayer-sync /var/backups/tvplayer-sync
  install -d -m 755 /etc/tvplayer-sync
  install -m 644 /opt/tvplayer-sync/config.example.json \
    /etc/tvplayer-sync/config.json
  cp /opt/tvplayer-sync/deploy/tvplayer-sync.service \
    /opt/tvplayer-sync/deploy/tvplayer-sync-backup.service \
    /opt/tvplayer-sync/deploy/tvplayer-sync-backup.timer /etc/systemd/system/
  install -m 755 /opt/tvplayer-sync/deploy/tvplayer-sync /usr/local/bin/tvplayer-sync
  ln -sf /usr/local/bin/tvplayer-sync /usr/bin/tvplayer-sync
  systemctl daemon-reload
  systemctl enable --now tvplayer-sync.service tvplayer-sync-backup.timer
  rm -f "$archive"
}

# Unpacks the new program next to the old one and prints its version.
ct_stage() {
  local archive=$1 new=/opt/tvplayer-sync.new file
  rm -rf "$new"
  mkdir -p "$new"
  tar -xzf "$archive" -C "$new" --strip-components=1 --no-same-owner
  for file in bin/tvplayer_sync_server deploy/tvplayer-sync \
      deploy/tvplayer-sync.service deploy/tvplayer-sync-backup.service \
      deploy/tvplayer-sync-backup.timer; do
    [ -e "$new/$file" ] || { echo "The archive has no $file." >&2; return 1; }
  done
  runuser -u tvplayer-sync -- "$new/bin/tvplayer_sync_server" --version
}

ct_unstage() {
  rm -rf /opt/tvplayer-sync.new
  rm -f "$1"
}

# A copy of the database, also while the server runs. Prints the file's name.
ct_backup() {
  local file
  file=/var/backups/tvplayer-sync/before-update-$(date +%Y%m%d-%H%M%S).sqlite
  /usr/local/bin/tvplayer-sync backup "$file" >/dev/null
  [ -s "$file" ] || { echo "The backup $file is empty." >&2; return 1; }
  echo "$file"
}

# Replaces the program, units, wrapper and link. Config and data aren't touched.
ct_swap() {
  local keep=/opt/tvplayer-sync.rollback unit
  local units='tvplayer-sync.service tvplayer-sync-backup.service tvplayer-sync-backup.timer'
  systemctl stop tvplayer-sync
  mkdir -p "$keep/system"
  for unit in $units; do
    if [ -e "/etc/systemd/system/$unit" ]; then
      cp -a "/etc/systemd/system/$unit" "$keep/system/"
    fi
  done
  cp -a /usr/local/bin/tvplayer-sync "$keep/system/wrapper"
  if [ -L /usr/bin/tvplayer-sync ]; then touch "$keep/had-link"; fi
  touch "$keep/saved"
  mv /opt/tvplayer-sync "$keep/program"
  mv /opt/tvplayer-sync.new /opt/tvplayer-sync
  for unit in $units; do
    cp "/opt/tvplayer-sync/deploy/$unit" /etc/systemd/system/
  done
  install -m 755 /opt/tvplayer-sync/deploy/tvplayer-sync /usr/local/bin/tvplayer-sync
  ln -sf /usr/local/bin/tvplayer-sync /usr/bin/tvplayer-sync
  systemctl daemon-reload
  systemctl try-restart tvplayer-sync-backup.timer
  systemctl start tvplayer-sync
}

# Puts back what ct_swap saved, from wherever it got to. Never touches the data.
ct_rollback() {
  local keep=/opt/tvplayer-sync.rollback unit
  systemctl stop tvplayer-sync || true
  if [ -d "$keep/program" ]; then
    rm -rf /opt/tvplayer-sync
    mv "$keep/program" /opt/tvplayer-sync
  fi
  if [ -e "$keep/saved" ]; then
    for unit in tvplayer-sync.service tvplayer-sync-backup.service tvplayer-sync-backup.timer; do
      if [ -e "$keep/system/$unit" ]; then
        cp -a "$keep/system/$unit" /etc/systemd/system/
      else
        rm -f "/etc/systemd/system/$unit"
      fi
    done
    cp -a "$keep/system/wrapper" /usr/local/bin/tvplayer-sync
    if [ ! -e "$keep/had-link" ]; then rm -f /usr/bin/tvplayer-sync; fi
  fi
  rm -rf "$keep" /opt/tvplayer-sync.new
  systemctl daemon-reload
  systemctl start tvplayer-sync
}

ct_finish() {
  rm -rf /opt/tvplayer-sync.rollback
  rm -f "$1"
}

# ct_run <ctid> <function> <args...>
ct_run() {
  local id=$1 fn=$2
  shift 2
  pct exec "$id" -- bash -c \
    "set -euo pipefail; umask 022; export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
$(declare -f "$fn")
$fn \"\$@\"" tvplayer-sync "$@" </dev/null
}

# --- Cleaning up ---

roll_back() {
  local id=$1
  step "Restoring the previous program"
  critical_ct=
  ct_run "$id" ct_rollback
}

on_exit() {
  local status=$?
  if [ -n "$stage_ct" ]; then
    ct_run "$stage_ct" ct_unstage "$ct_archive" || true
  fi
  if [ -n "$tmp_dir" ]; then rm -rf "$tmp_dir"; fi
  exit "$status"
}

on_signal() {
  trap '' INT TERM HUP
  say
  if [ -n "$critical_ct" ]; then
    say "Interrupted during the update."
    roll_back "$critical_ct" || warn "Restoring failed. Run this script again to retry."
  fi
  exit 130
}

trap on_exit EXIT
trap on_signal INT TERM HUP

# --- Checks ---

preflight() {
  local tool major
  [ "$(id -u)" = 0 ] || die "Run this as root, in the Proxmox host's shell."
  command -v pveversion >/dev/null \
    || die "This isn't a Proxmox VE host (pveversion is missing). Run it in the host's shell, not in a container."
  [ "$(uname -m)" = x86_64 ] || die "Only amd64 is supported, this is $(uname -m)."
  for tool in pct pveam pvesh pvesm curl sha256sum tar; do
    command -v "$tool" >/dev/null || die "$tool is missing on this host."
  done
  major=$(pveversion | sed -n 's|^pve-manager/\([0-9]*\)\..*|\1|p')
  case "$major" in
    8 | 9) ;;
    '') warn "Couldn't read the Proxmox VE version." ;;
    [0-7]) die "This needs Proxmox VE 8 or 9, this is version $major." ;;
    *)
      warn "This script was written for Proxmox VE 8 and 9, this is version $major."
      ask_yes "Continue anyway?" n || exit 1
      ;;
  esac
}

# --- The archive ---

verify_sum() { # <folder> <sums file> <archive name>
  local line
  line=$(awk -v name="$3" '$2 == name || $2 == "*" name' "$2")
  [ -n "$line" ] || return 2
  (cd "$1" && printf '%s\n' "$line" | sha256sum -c --quiet - >/dev/null 2>&1)
}

check_archive() {
  local list file
  list=$(tar -tzf "$archive" 2>/dev/null) || die "$archive isn't a readable archive."
  for file in bin/tvplayer_sync_server deploy/tvplayer-sync \
      deploy/tvplayer-sync.service config.example.json; do
    grep -qx "bundle/$file" <<<"$list" \
      || die "$archive isn't a tvplayer sync server archive (no bundle/$file)."
  done
  if grep -qE '^/|(^|/)\.\.(/|$)' <<<"$list"; then
    die "$archive has unsafe paths in it."
  fi
}

get_archive() {
  local name status=0 dir
  if [ -n "$local_archive" ]; then
    archive=$local_archive
    [ -f "$archive" ] || die "$archive doesn't exist."
    dir=$(dirname "$archive")
    name=$(basename "$archive")
    step "Using the local archive $archive"
    if [ -f "$dir/SHA256SUMS" ]; then
      verify_sum "$dir" "$dir/SHA256SUMS" "$name" || status=$?
      case "$status" in
        0) say "The checksum matches SHA256SUMS." ;;
        2) warn "SHA256SUMS doesn't list $name, so the archive isn't verified." ;;
        *) die "The checksum of $name doesn't match SHA256SUMS. The file is damaged or isn't the right one." ;;
      esac
    else
      warn "No SHA256SUMS next to the archive, so it isn't verified."
    fi
  else
    [[ $release_version != @* ]] || die "This copy of the script has no release \
version in it. Use the one from a release, or give an archive with --local."
    name=tvplayer-sync-server_${release_version}_linux-amd64.tar.gz
    tmp_dir=$(mktemp -d)
    step "Downloading version $release_version"
    curl -fsSL --retry 2 -o "$tmp_dir/SHA256SUMS" \
      "$release_base/v$release_version/SHA256SUMS" \
      || die "Couldn't download SHA256SUMS of release v$release_version."
    curl -fsSL --retry 2 -o "$tmp_dir/$name" \
      "$release_base/v$release_version/$name" \
      || die "Couldn't download $name."
    verify_sum "$tmp_dir" "$tmp_dir/SHA256SUMS" "$name" || status=$?
    case "$status" in
      0) say "The checksum matches SHA256SUMS." ;;
      2) die "SHA256SUMS doesn't list $name." ;;
      *) die "The checksum of $name doesn't match SHA256SUMS. Nothing was changed." ;;
    esac
    archive=$tmp_dir/$name
  fi
  check_archive
}

# --- Health check ---

# health_matches <json> <version, or empty for any>
health_matches() {
  grep -q '"service":"tvplayer-sync"' <<<"$1" || return 1
  [ -z "$2" ] || grep -qF "\"version\":\"$2\"" <<<"$1"
}

# wait_health <ctid> <ip> <port> <version, or empty for any>: sets health_via.
wait_health() {
  local id=$1 ip=$2 port=$3 want=$4 body try
  for try in $(seq 1 15); do
    if [ -n "$ip" ]; then
      body=$(curl -fsS --noproxy '*' --connect-timeout 2 --max-time 4 \
        "http://$ip:$port/v1/health" 2>/dev/null || true)
      if health_matches "$body" "$want"; then
        health_via=host
        return 0
      fi
    fi
    body=$(ct_run "$id" ct_health "$port" 2>/dev/null || true)
    if health_matches "$body" "$want"; then
      health_via=container
      return 0
    fi
    [ "$try" = 15 ] || sleep 3
  done
  return 1
}

report_health_via() {
  if [ "$health_via" = container ]; then
    warn "The server answers inside the container, but not from this host. \
Check the firewall and the network, and \"host\" in /etc/tvplayer-sync/config.json."
  fi
}

# --- Install ---

active_storages() { # <content type>
  pvesm status --content "$1" 2>/dev/null | awk 'NR > 1 && $3 == "active" { print $1 }'
}

# pick_storage <question> <list> <preferred...>
pick_storage() {
  local question=$1 list=$2 default preferred answer
  shift 2
  default=$(head -n 1 <<<"$list")
  for preferred in "$@"; do
    if grep -qx "$preferred" <<<"$list"; then default=$preferred; break; fi
  done
  while :; do
    answer=$(ask "$question ($(paste -sd ' ' <<<"$list"))" "$default")
    if grep -qxF -- "$answer" <<<"$list"; then
      printf '%s' "$answer"
      return 0
    fi
    say "That isn't one of the listed storages." >&2
  done
}

template_on_storage() { # <storage> <debian version>
  pveam list "$1" 2>/dev/null \
    | grep -oE "debian-$2-standard_[^ ]*_amd64\.tar\.[a-z]+" | sort -V | tail -n 1 || true
}

template_available() { # <debian version>
  pveam available --section system 2>/dev/null | awk '{ print $2 }' \
    | grep -E "^debian-$1-standard_" | sort -V | tail -n 1 || true
}

find_template() { # <storage> <debian version>
  local name
  name=$(template_on_storage "$1" "$2")
  [ -n "$name" ] || name=$(template_available "$2")
  printf '%s' "$name"
}

ensure_template() { # <storage> <name>
  if [ -z "$(pveam list "$1" 2>/dev/null | grep -F "$2" || true)" ]; then
    step "Downloading the template $2"
    pveam download "$1" "$2" || die "Couldn't download the template $2."
  fi
}

valid_ipv4() {
  local IFS=. part
  # shellcheck disable=SC2086  # Split on the dots.
  set -- $1
  [ $# = 4 ] || return 1
  for part in "$@"; do
    [[ $part =~ ^[0-9]{1,3}$ ]] && [ "$part" -le 255 ] || return 1
  done
}

create_tokens() { # <ctid>
  local id=$1 name output
  say
  say "A device needs its own token. Each is shown only once (the server keeps"
  say "only a hash): copy it now, e.g. into a password manager."
  while :; do
    read -r -p "Device name for a new token (Enter to finish): " name || break
    [ -n "$name" ] || break
    if ! [[ $name =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]]; then
      say "Use letters, digits, dot, dash or underscore, e.g. laptop."
      continue
    fi
    if output=$(pct exec "$id" -- /usr/local/bin/tvplayer-sync token create --name "$name" </dev/null); then
      say "  $name: ${output%%$'\n'*}"
    else
      say "No token made for $name."
    fi
  done
}

do_install() {
  local id hostname template_storage rootfs_storage disk memory cores bridge
  local network address gateway net0 onboot version storages template debian
  local onboot_text ip

  get_archive
  if [ -n "$local_archive" ]; then
    version="from $(basename "$local_archive")"
  else
    version=$release_version
  fi

  step "Questions (press Enter to accept the value in brackets)"
  id=$(pvesh get /cluster/nextid | tr -dc 0-9)
  while :; do
    id=$(ask "Container ID" "$id")
    if [[ $id =~ ^[0-9]+$ ]] && pvesh get /cluster/nextid --vmid "$id" >/dev/null 2>&1; then
      break
    fi
    say "That ID is taken or not valid."
    id=$(pvesh get /cluster/nextid | tr -dc 0-9)
  done
  while :; do
    hostname=$(ask "Hostname" tvplayer-sync)
    [[ $hostname =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] && break
    say "Use letters, digits and dashes."
  done

  storages=$(active_storages vztmpl)
  [ -n "$storages" ] || die "No active storage can hold container templates."
  template_storage=$(pick_storage "Storage for the template" "$storages" local)
  storages=$(active_storages rootdir)
  [ -n "$storages" ] || die "No active storage can hold containers."
  rootfs_storage=$(pick_storage "Storage for the container's disk" "$storages" local-lvm local-zfs)

  while :; do
    disk=$(ask "Disk size in GB" 2)
    [[ $disk =~ ^[1-9][0-9]*$ ]] && break
    say "Give a whole number."
  done
  while :; do
    memory=$(ask "Memory in MB" 256)
    [[ $memory =~ ^[1-9][0-9]*$ ]] && break
    say "Give a whole number."
  done
  while :; do
    cores=$(ask "CPU cores" 1)
    [[ $cores =~ ^[1-9][0-9]*$ ]] && break
    say "Give a whole number."
  done
  while :; do
    bridge=$(ask "Network bridge" vmbr0)
    [ -e "/sys/class/net/$bridge/bridge" ] && break
    say "This host has no bridge called $bridge."
  done
  while :; do
    network=$(ask "IP address: dhcp or static" dhcp)
    case "$network" in dhcp | static) break ;; esac
    say "Answer dhcp or static."
  done
  if [ "$network" = static ]; then
    while :; do
      address=$(ask "Address with prefix length" 192.0.2.10/24)
      if [[ $address == */* ]] && valid_ipv4 "${address%/*}" \
        && [[ ${address#*/} =~ ^[0-9]{1,2}$ ]] && [ "${address#*/}" -le 32 ]; then
        break
      fi
      say "Write it like 192.0.2.10/24."
    done
    while :; do
      gateway=$(ask "Gateway (your router)" 192.0.2.1)
      valid_ipv4 "$gateway" && break
      say "Write it like 192.0.2.1."
    done
    net0="name=eth0,bridge=$bridge,ip=$address,gw=$gateway"
  else
    address=dhcp
    gateway=
    net0="name=eth0,bridge=$bridge,ip=dhcp"
  fi
  if ask_yes "Start the container when the host boots?" y; then
    onboot=1
    onboot_text=yes
  else
    onboot=0
    onboot_text=no
  fi

  step "Looking for the Debian template"
  pveam update >/dev/null 2>&1 || warn "Couldn't refresh the template list; using what's known."
  debian=13
  template=$(find_template "$template_storage" 13)
  if [ -z "$template" ]; then
    debian=12
    template=$(find_template "$template_storage" 12)
    [ -n "$template" ] || die "No Debian 13 or 12 template found. Check the host's internet connection."
    say "No Debian 13 template here, so using Debian 12."
  fi

  step "Summary"
  cat <<EOF
  Container ID:   $id
  Hostname:       $hostname (unprivileged, nesting on)
  Template:       $template on $template_storage
  Disk:           $disk GB on $rootfs_storage
  Memory / swap:  $memory MB / 256 MB
  CPU cores:      $cores
  Network:        $bridge, $address${gateway:+, gateway $gateway}
  Start on boot:  $onboot_text
  Server version: $version
EOF
  ask_yes "Create this container?" y || { say "Nothing was created."; exit 0; }

  ensure_template "$template_storage" "$template"
  step "Creating container $id"
  while ! pct create "$id" "$template_storage:vztmpl/$template" \
      --hostname "$hostname" --unprivileged 1 --features nesting=1 \
      --cores "$cores" --memory "$memory" --swap 256 \
      --rootfs "$rootfs_storage:$disk" --net0 "$net0" \
      --onboot "$onboot" --timezone host; do
    # An older Proxmox VE 8 can list Debian 13 and still refuse to create it.
    [ "$debian" = 13 ] || die "Creating the container failed. See the message above."
    template=$(find_template "$template_storage" 12)
    [ -n "$template" ] || die "Creating the container failed, and there is no Debian 12 template to try."
    ask_yes "That failed, perhaps because this Proxmox VE doesn't know Debian 13 yet. Try $template?" y \
      || die "Creating the container failed."
    debian=12
    ensure_template "$template_storage" "$template"
  done

  local keep_hint="The container $id stays as it is, to look into. To delete it: pct stop $id; pct destroy $id"
  step "Starting it"
  pct start "$id" || die "It didn't start. $keep_hint"
  wait_for_boot "$id" || die "It didn't finish starting. $keep_hint"
  ip=$(wait_for_ip "$id" || true)
  [ -n "$ip" ] || warn "The container has no IPv4 address yet. Check the bridge and your DHCP server."

  step "Installing the server"
  pct push "$id" "$archive" "$ct_archive" || die "Couldn't copy the archive into the container. $keep_hint"
  ct_run "$id" ct_install_curl \
    || warn "Couldn't install curl (no internet in the container?). The server doesn't need it."
  ct_run "$id" ct_install "$ct_archive" || die "The installation failed. $keep_hint"

  step "Checking that it answers"
  wait_health "$id" "$ip" 8787 "" \
    || die "The server doesn't answer. See its log: pct exec $id -- journalctl -u tvplayer-sync -n 50 --no-pager. $keep_hint"
  report_health_via

  local shown_ip=${ip:-<container address>}
  step "The sync server runs"
  cat <<EOF
Address for the app (Settings › Sync › "Server address") on the home network:

  http://$shown_ip:8787

EOF
  if [ "$network" = dhcp ]; then
    say "This address came from DHCP. Give it a fixed lease in your router, so it stays the same."
    say
  fi
  cat <<EOF
Create a token for each device, in the container:

  pct enter $id
  tvplayer-sync token create --name <device name>
  exit

HTTPS through a reverse proxy, and reaching the server from outside the
home network: see $docs_url
EOF
  if ask_yes "Create tokens now?" y; then create_tokens "$id"; fi
}

wait_for_boot() {
  local try
  for try in $(seq 1 30); do
    if ct_run "$1" ct_booted 2>/dev/null; then return 0; fi
    [ "$try" = 30 ] || sleep 2
  done
  return 1
}

wait_for_ip() {
  local try ip
  for try in $(seq 1 30); do
    ip=$(ct_run "$1" ct_ip 2>/dev/null || true)
    if [ -n "$ip" ]; then printf '%s' "$ip"; return 0; fi
    [ "$try" = 30 ] || sleep 2
  done
  return 1
}

# --- Update ---

do_update() {
  local id=$1 missing current new port ip data_dir backup status line
  status=$(pct status "$id" 2>/dev/null) \
    || die "There is no container $id on this Proxmox node."
  if [ "$status" != "status: running" ]; then
    say "Container $id isn't running."
    ask_yes "Start it?" y || die "The update needs it running. Nothing was changed."
    pct start "$id" || die "Container $id didn't start."
    wait_for_boot "$id" || die "Container $id didn't finish starting."
  fi

  if ct_run "$id" ct_has_rollback; then
    say "An earlier update of container $id was interrupted."
    ask_yes "Restore the previous program now?" y \
      || die "Not updating until that is sorted out. Nothing was changed."
    ct_run "$id" ct_rollback || die "Restoring failed. See: pct exec $id -- journalctl -u tvplayer-sync -n 50 --no-pager"
    say "Restored. Run this script again to update."
    exit 0
  fi

  missing=$(ct_run "$id" ct_missing) \
    || die "Couldn't look inside container $id."
  if [ -n "$missing" ]; then
    say "Container $id doesn't look like a tvplayer-sync install. It lacks:" >&2
    while IFS= read -r line; do say "  $line" >&2; done <<<"$missing"
    die "Nothing was changed."
  fi
  current=$(ct_run "$id" ct_version) \
    || die "The installed server doesn't report its version. Nothing was changed."
  data_dir=$(ct_run "$id" ct_data_dir)
  case "$data_dir" in
    /opt/tvplayer-sync | /opt/tvplayer-sync/*)
      die "The data folder $data_dir is inside the program folder, which an update replaces. Move it first. Nothing was changed." ;;
  esac
  port=$(ct_run "$id" ct_port)
  port=${port:-8787}
  ip=$(ct_run "$id" ct_ip || true)

  get_archive
  step "Preparing the new version"
  stage_ct=$id
  pct push "$id" "$archive" "$ct_archive" || die "Couldn't copy the archive into the container. Nothing was changed."
  new=$(ct_run "$id" ct_stage "$ct_archive") \
    || die "The new program doesn't run in this container. Nothing was changed."

  step "Update of container $id"
  say "  Current version: $current"
  say "  New version:     $new"
  if [ "$current" = 1.0.0 ]; then
    say "  (Servers before 0.1.1 called themselves 1.0.0, so this is an update.)"
  elif [ "$current" = "$new" ]; then
    say "  (The same version: this replaces the program with a fresh copy.)"
  fi
  say "  Config and data stay as they are; the database is backed up first."
  ask_yes "Update?" y || { say "Nothing was changed."; exit 0; }

  step "Backing up the database"
  backup=$(ct_run "$id" ct_backup) || die "The backup failed. Nothing was changed."
  say "Saved $backup"

  step "Replacing the program"
  critical_ct=$id
  if ct_run "$id" ct_swap; then
    step "Checking that it answers"
    if wait_health "$id" "$ip" "$port" "$new"; then
      critical_ct=
      stage_ct=
      report_health_via
      ct_run "$id" ct_finish "$ct_archive" \
        || warn "Couldn't clean up /opt/tvplayer-sync.rollback in the container."
      step "Updated to version $new"
      say "Devices need nothing: they sync on as before. The database copy is at $backup"
      return 0
    fi
    say "The new version doesn't answer its health check."
  else
    say "Replacing the program failed."
  fi

  if roll_back "$id" && wait_health "$id" "$ip" "$port" ""; then
    die "The update FAILED and was undone: version $current runs again, with your \
data as it was. The database copy is at $backup. What went wrong may be in the \
log: pct exec $id -- journalctl -u tvplayer-sync -n 100 --no-pager"
  fi
  die "The update FAILED and the server does NOT answer after restoring version \
$current. No data was deleted, and the database copy is at $backup. See the log: \
pct exec $id -- journalctl -u tvplayer-sync -n 100 --no-pager, and \"Backups and \
restoring\" in $docs_url"
}

# --- Start ---

usage() {
  cat <<EOF
Installs or updates the tvplayer sync server in a Proxmox VE container.
Run as root on the Proxmox host.

  --install          Install in a new container
  --update <ctid>    Update an existing container
  --local <archive>  Use this server archive instead of downloading it
  --help             Show this text

With neither --install nor --update it shows a menu.
EOF
}

main() {
  local mode='' update_id='' choice
  while [ $# -gt 0 ]; do
    case "$1" in
      --install) mode=install; shift ;;
      --update)
        if [ $# -lt 2 ] || ! [[ $2 =~ ^[0-9]+$ ]]; then
          die "--update needs a container ID, e.g. --update 105."
        fi
        mode=update
        update_id=$2
        shift 2
        ;;
      --local)
        [ $# -ge 2 ] || die "--local needs the archive's path."
        local_archive=$2
        shift 2
        ;;
      -h | --help) usage; exit 0 ;;
      *) usage >&2; die "Unknown option: $1" ;;
    esac
  done

  # With "curl ... | bash", stdin is this script, so questions would eat it.
  if [ ! -t 0 ] && [ ! -f "$0" ]; then
    die "This script asks questions. Run it as: bash -c \"\$(curl -fsSL <address>)\""
  fi

  preflight

  if [ -z "$mode" ]; then
    say "tvplayer sync server on Proxmox VE"
    say "  1) Install in a new container"
    say "  2) Update an existing container"
    say "  q) Quit"
    choice=$(ask "Your choice" 1)
    case "$choice" in
      1) mode=install ;;
      2)
        mode=update
        update_id=$(ask "Container ID to update" "")
        [[ $update_id =~ ^[0-9]+$ ]] || die "That isn't a container ID."
        ;;
      *) exit 0 ;;
    esac
  fi

  case "$mode" in
    install) do_install ;;
    update) do_update "$update_id" ;;
  esac
}

main "$@"
