#!/bin/bash
# Undo install.sh. Run as root.
set -uo pipefail
systemctl disable --now sshd-vsock.socket
rm -f /etc/systemd/system/sshd-vsock.socket /etc/systemd/system/sshd-vsock@.service
systemctl daemon-reload
semodule -r sshd_vsock
