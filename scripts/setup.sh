#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "[!] Please run this script as root (e.g. sudo ./scripts/setup.sh)" >&2
  exit 1
fi

SERVER_NAME=${SERVER_NAME:-CNCPI}
SHARE_PATH=${SHARE_PATH:-/srv/CNC}
SMB_USER=${SMB_USER:-piserver}
SMB_PASS=${SMB_PASS:-piserver}
SHARE_GROUP=${SHARE_GROUP:-cncshare}
SMB_CONF_TEMPLATE="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)/config/smb.conf"
SMB_CONF_DEST=/etc/samba/smb.conf
BACKUP_SUFFIX=$(date +%Y%m%d-%H%M%S)

info() { printf "[+] %s\n" "$*"; }
run() { info "$*"; eval "$@"; }

ensure_packages() {
  info "Updating apt sources and installing Samba"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y samba samba-common-bin gettext-base
}

ensure_group() {
  if ! getent group "$SHARE_GROUP" >/dev/null; then
    info "Creating group $SHARE_GROUP"
    groupadd --system "$SHARE_GROUP"
  else
    info "Group $SHARE_GROUP already exists"
  fi
}

ensure_user() {
  if ! id -u "$SMB_USER" >/dev/null 2>&1; then
    info "Creating user $SMB_USER"
    useradd --system --home "$SHARE_PATH" --shell /usr/sbin/nologin \
      --gid "$SHARE_GROUP" --no-create-home "$SMB_USER"
  else
    info "User $SMB_USER already exists"
    usermod -g "$SHARE_GROUP" "$SMB_USER" >/dev/null
  fi
  usermod -d "$SHARE_PATH" "$SMB_USER" >/dev/null
  usermod -a -G "$SHARE_GROUP" "$SMB_USER" >/dev/null
  echo "$SMB_USER:$SMB_PASS" | chpasswd >/dev/null 2>&1 || true
}

prepare_share() {
  info "Preparing share directory at $SHARE_PATH"
  mkdir -p "$SHARE_PATH"
  chown -R "$SMB_USER:$SHARE_GROUP" "$SHARE_PATH"
  chmod 2775 "$SHARE_PATH"
}

configure_samba() {
  info "Configuring Samba"
  if [[ ! -f "$SMB_CONF_TEMPLATE" ]]; then
    echo "Missing template: $SMB_CONF_TEMPLATE" >&2
    exit 1
  fi
  if [[ -f "$SMB_CONF_DEST" ]]; then
    cp "$SMB_CONF_DEST" "${SMB_CONF_DEST}.${BACKUP_SUFFIX}.bak"
    info "Existing smb.conf backed up to ${SMB_CONF_DEST}.${BACKUP_SUFFIX}.bak"
  fi
  escaped_name=$(printf '%s' "$SERVER_NAME" | sed -e 's/[&/]/\\&/g')
  sed "s/@NETBIOS_NAME@/${escaped_name}/g" "$SMB_CONF_TEMPLATE" > "$SMB_CONF_DEST"
  printf '\n[debug] Final Samba config:\n' >&2
  testparm -s "$SMB_CONF_DEST" >/dev/null
}

configure_credentials() {
  info "Syncing Samba password for $SMB_USER"
  (printf '%s\n' "$SMB_PASS"; printf '%s\n' "$SMB_PASS") | smbpasswd -s -a "$SMB_USER"
  smbpasswd -e "$SMB_USER" >/dev/null
}

enable_services() {
  info "Enabling and restarting Samba daemons"
  systemctl enable --now smbd nmbd
  systemctl restart smbd nmbd
  systemctl status smbd --no-pager --lines=5 || true
}

main() {
  ensure_packages
  ensure_group
  prepare_share
  ensure_user
  configure_samba
  configure_credentials
  enable_services
  info "DONE! CNC share available as //${SERVER_NAME}/CNC and //${SERVER_NAME}/CNC-SMB1"
  info "Connect with username '$SMB_USER' and password '$SMB_PASS' or use guest access."
}

main "$@"
