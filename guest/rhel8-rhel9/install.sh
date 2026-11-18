#!/bin/bash
# Enable SSH over VSOCK on an existing RHEL 8 or RHEL 9 guest. Run as root
# from this directory. RHEL 10 does not need this.
set -euo pipefail
cd "$(dirname "$0")"
install -m 0644 sshd-vsock.socket /etc/systemd/system/sshd-vsock.socket
install -m 0644 sshd-vsock@.service /etc/systemd/system/sshd-vsock@.service
restorecon /etc/systemd/system/sshd-vsock.socket /etc/systemd/system/sshd-vsock@.service
semodule -i sshd_vsock.cil
systemctl daemon-reload
systemctl enable --now sshd-vsock.socket
ss -l --vsock
