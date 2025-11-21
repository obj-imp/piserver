# Raspberry Pi CNC File Server

This repo contains everything needed to turn a Raspberry Pi 4/5 (headless) into a dual-stack file server for legacy DOS CNC machines and modern Windows/macOS clients. A single directory named `CNC` is exposed twice through Samba:

- `\\<SERVER_NAME>\CNC` — modern SMB2+/SMB3 share for Windows/macOS/Linux
- `\\<SERVER_NAME>\CNCSMB1` — legacy SMB1 share for DOS systems that require NT1 (hyphen removed for compatibility)

Both shares write to the same `/srv/CNC` directory and allow read/write access either as the guest account or with the hard-coded credentials `piserver / piserver` (per the requested captive-environment setup).

## Prerequisites

- Raspberry Pi OS Lite (Bookworm or newer) on a Pi 4/5
- SSH access with a sudo-capable user
- Network connectivity to the CNC subnet
- (Optional) `git` if cloning directly onto the Pi

## Setup

1. Copy this repo to the Pi (via `git clone`, `scp`, or removable media) and `cd` into it.
2. Run the automated installer as root:

   ```bash
   sudo ./scripts/setup.sh
   ```

   Environment variables can override defaults without editing files:

   | Variable      | Default  | Purpose                              |
   |---------------|----------|--------------------------------------|
   | `SERVER_NAME` | `CNCPI`  | NetBIOS name advertised over SMB     |
   | `SHARE_PATH`  | `/srv/CNC` | Filesystem path for the shared data |
   | `SMB_USER`    | `piserver` | Linux/Samba service account         |
   | `SMB_PASS`    | `piserver` | Password for both Linux + Samba     |
   | `SHARE_GROUP` | `cncshare` | Owning group for the share          |

   Example: `sudo SERVER_NAME=CNCCTRL ./scripts/setup.sh`

3. Once the script finishes, the services `smbd` and `nmbd` are enabled and started automatically. The CNC directory lives at `/srv/CNC`.

## Connecting from Clients

- **Modern Windows/macOS/Linux**
  - Map the share `\\<SERVER_NAME>\CNC`
  - Authenticate with `piserver / piserver` or connect as a guest
- **DOS CNC machines**
  - Use the SMB1-only share `\\<SERVER_NAME>\CNCSMB1`
  - Guest access is enabled for ease of use; credentials also work if supported

## Common Maintenance Tasks

- View service status: `sudo systemctl status smbd nmbd`
- Review Samba logs: `sudo tail -f /var/log/samba/log.smbd`
- Regenerate config after editing `config/smb.conf`: re-run `sudo ./scripts/setup.sh`
- Populate CNC files directly on the Pi: `sudo cp <file> /srv/CNC/`

## Security Notes

- SMB1/NT1 plus LANMAN/NTLM and even plaintext fallback auth are enabled globally so DOS clients can negotiate. Modern OSes still pick SMB2/3 automatically, but the Pi should stay on an isolated, trusted network segment.
- The `piserver` credentials are intentionally weak per requirements. Change `SMB_PASS` (and rerun the script) if conditions change.

## Repository Contents

- `scripts/setup.sh` — end-to-end installer/configurator
- `scripts/diagnostics.sh` — quick helper to dump Samba config/log info
- `config/smb.conf` — Samba configuration template applied by the script
- `spec.md` — architecture and implementation details

## Next Steps

- Initialize a git repo when ready: `git init && git add . && git commit -m "Initial CNC server"`
- Push to GitHub or mirror per your deployment workflow.
