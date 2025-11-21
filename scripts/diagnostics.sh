#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run as root" >&2
  exit 1
fi

printf '\n=== testparm output ===\n'
testparm -s

printf '\n=== smb.conf summary ===\n'
grep -Ev '^\s*#' /etc/samba/smb.conf

printf '\n=== Recent smbd log ===\n'
journalctl -u smbd -n 100 --no-pager
