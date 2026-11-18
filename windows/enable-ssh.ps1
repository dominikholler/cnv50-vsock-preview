# Make the Windows guest reachable with `virtctl ssh/scp --vsock`.
# Run in the guest as Administrator. Requires the virtio-win guest tools
# (virtio-win-gt-x64.msi): they provide the VirtIO Socket driver and the
# "Virtio Socket Transport Bridge" service (VsockTcpBridge), which hands
# incoming vsock connections to the local OpenSSH server.
$ErrorActionPreference = "Stop"

if (-not (Get-Service VsockTcpBridge -ErrorAction SilentlyContinue)) {
    throw "VsockTcpBridge service not found. Install virtio-win-gt-x64.msi from the virtio-win drivers disk first."
}

if ((Get-WindowsCapability -Online -Name "OpenSSH.Server*").State -ne "Installed") {
    Add-WindowsCapability -Online -Name "OpenSSH.Server~~~~0.0.1.0" | Out-Null
}

Set-Service sshd -StartupType Automatic
Start-Service sshd
Set-Service VsockTcpBridge -StartupType Automatic
Start-Service VsockTcpBridge

Get-Service sshd, VsockTcpBridge | Format-Table Name, Status, StartType -AutoSize
