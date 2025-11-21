# CNC File Server Specification

## Goals
- Provide a single shared directory (`/srv/CNC`) on a Raspberry Pi 4/5.
- Expose the directory twice: once via SMB2+/SMB3 for modern clients and once via SMB1 (NT1) for legacy DOS clients.
- Allow both guest access and authenticated access using the hard-coded credentials `piserver / piserver`.
- Keep the deployment reproducible via a single automation script suitable for a fresh Raspberry Pi OS Lite install.

## Platform Assumptions
- Raspberry Pi OS Lite (Debian Bookworm or newer) running on a Pi 4 or Pi 5.
- Headless configuration with SSH access and `sudo` privileges.
- The Pi is located on an isolated/captive network where the reduced security posture is acceptable.

## Directory Layout
- `/srv/CNC` is the authoritative storage location.
- The repository includes:
  - `scripts/setup.sh` — orchestrates package installs, user/group creation, Samba config deployment, and service enablement.
  - `config/smb.conf` — template Samba configuration with a placeholder (`@NETBIOS_NAME@`) for the server name.
  - `README.md` — operator instructions.
  - `spec.md` — this document.

## Automation Flow (`scripts/setup.sh`)
1. **Environment checks** — enforces root execution; exposes overrides through environment variables (`SERVER_NAME`, `SHARE_PATH`, `SMB_USER`, `SMB_PASS`, `SHARE_GROUP`).
2. **Package install** — `samba`, `samba-common-bin`, and `gettext-base` (for template substitution) via `apt-get`.
3. **User/Group provisioning**
   - Creates/ensures the `cncshare` group.
   - Creates/ensures the `piserver` system user with home pointed to `/srv/CNC`, shell `/usr/sbin/nologin`, and membership in `cncshare`.
   - Sets the Unix password (even though the shell is disabled) to keep credentials aligned with Samba.
4. **Directory prep** — creates `/srv/CNC`, sets owner to `piserver:cncshare`, and applies `2775` permissions so files inherit the group.
5. **Samba configuration**
   - Backs up the previous `/etc/samba/smb.conf` with a timestamp suffix.
   - Uses `sed` to inject the desired NetBIOS name into `config/smb.conf`.
   - Validates the resulting config with `testparm`.
6. **Credentials sync** — pipes the fixed password into `smbpasswd -s -a` and enables the account.
7. **Service enablement** — enables and restarts `smbd` and `nmbd` via `systemctl`, leaving them persistent across reboots.

## Samba Configuration Details
- **Global**
  - `server min protocol = SMB2`, `server max protocol = SMB3` to keep modern clients on secure dialects.
  - `ntlm auth = yes` and `lanman auth = yes` are turned on to satisfy DOS SMB1 clients; `map to guest = Bad User` plus `guest account = piserver` ensure bad/blank credentials drop to the guest identity mapped to the service user.
  - Character sets set to `UTF-8` (Unix) and `CP437` (DOS) for compatibility.
- **Modern share `[CNC]`**
  - Accessible at `\\SERVER\CNC`.
  - Still allows guest connections but supports authenticated sessions with `piserver / piserver`.
  - Forces ownership to `piserver:cncshare`, inherits permissions, and relies on client-side dialect selection (SMB2+/SMB3 preferred even though SMB1 remains globally enabled).
- **Legacy share `[CNCSMB1]`**
  - Accessible at `\\SERVER\CNCSMB1` (hyphen removed for stricter DOS stacks).
  - Shares the same backing directory while relying on the server-wide `server min protocol = NT1` so DOS clients can negotiate.
  - Disables opportunistic locks (`oplocks`, `level2 oplocks`) and enables `strict locking` to avoid DOS file corruption scenarios.

## Security Considerations
- SMB1, NTLM, LANMAN, and plaintext/weak credential fallbacks are insecure by modern standards; isolate this Pi on a trusted VLAN/subnet without Internet exposure.
- Guest write access is enabled by default; disable `guest ok` in `config/smb.conf` if the environment changes.
- The fixed credentials should be updated (`SMB_PASS=... ./scripts/setup.sh`) if threat models evolve.

## Validation & Testing
- `testparm -s /etc/samba/smb.conf` runs automatically during setup to catch syntax issues (ensure `server min protocol = NT1`, LANMAN, and plaintext auth allowances are present so DOS can negotiate).
- After deployment, validate from:
  - Windows/macOS: `smb://<SERVER_NAME>/CNC` or `\\<SERVER_NAME>\CNC`.
  - Linux: `smbclient -L //<SERVER_NAME> -U piserver%piserver`.
  - DOS: use existing SMB1-capable client to mount `\\<SERVER_NAME>\CNCSMB1`.

## Future Enhancements
- Optionally add an rsync/backup script for the `/srv/CNC` directory.
- Add Ansible playbooks or a systemd oneshot unit for unattended provisioning.
- Integrate health checks/monitoring (e.g., using `monit` or `prometheus-node-exporter`).
