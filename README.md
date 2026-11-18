# Run commands in a VM without network access – preview on OpenShift Virtualization 5.0

OpenShift Virtualization 5.1 lets you open a shell, run commands, and copy files
in a VM with `virtctl ssh` / `virtctl scp`, even if the VM has no network
connection, no IP address, no Service, and no open SSH port. That's useful for
isolated or air-gapped VMs, for VMs on secondary networks only, and for fixing a
VM with broken networking.

Behind the scenes, `virtctl` reaches the guest's SSH server through the cluster
API and a virtio-vsock host-guest channel instead of the VM network. On the
command line this is the `--vsock` flag.

This guide shows how to try it on **5.0** with RHEL 8, 9, 10, Windows Server 2025 and Windows 11.

> **For testing only.** None of this is supported on 5.0. Use a test cluster.

## Limitations in 5.0

| | 5.0 | 5.1 |
|---|---|---|
| KubeVirt | 1.9 | 1.10 |
| `VSOCK` feature gate | Alpha, off. Enabling it needs the **unsupported** jsonpatch annotation | Tech Preview, on by default |
| `virtctl ssh/scp --vsock` | Not in the 5.0 `virtctl`. Use the upstream KubeVirt 1.10 `virtctl` | Included |

- **Annotation side effects:** HCO reports `TaintedConfiguration=True` while the annotation is set.
- **Version mismatch:** a 1.10 `virtctl` with a 1.9 cluster is an untested combination. It works for this feature.
- **RBAC:** non-cluster-admin users need extra permissions, even namespace admins (see step 3).
- **VM changes:** VMs need `autoattachVSOCK: true`. Adding it to an existing VM takes effect after a restart.
- **Turning the gate off:** VMs that set `autoattachVSOCK: true` won't start.

Guest support:

| Guest | What's needed |
|---|---|
| RHEL 10 | Nothing. systemd makes sshd reachable automatically. |
| RHEL 9, RHEL 8 | A systemd socket unit + an SELinux policy module so sshd can be reached. The manifests here install both with cloud-init. |
| Windows Server 2025, Windows 11 | virtio-win guest tools + OpenSSH Server running. The manifests here set both up during the unattended install; `windows/enable-ssh.ps1` does it on existing VMs. |

## Files

```
cluster/enable-vsock.sh         enable the VSOCK feature gate (jsonpatch annotation)
cluster/disable-vsock.sh        remove it again
cluster/vsock-access-role.yaml  RBAC for non-cluster-admin users
vms/rhel10-vsock.yaml           RHEL 10 VM
vms/rhel9-vsock.yaml            RHEL 9 VM, guest set up by cloud-init
vms/rhel8-vsock.yaml            RHEL 8 VM, guest set up by cloud-init
vms/windows2k25-iso.yaml        Windows Server 2025 Evaluation ISO, imported once, shared by all Windows VMs
vms/windows2k25-vsock.yaml      Windows Server 2025 VM, unattended install from that ISO
vms/windows11-iso.yaml          Windows 11 ISO, imported once, shared by all Windows 11 VMs
vms/windows11-vsock.yaml        Windows 11 Pro VM, unattended install from that ISO
guest/rhel8-rhel9/              the same guest files, plus install.sh for existing VMs
windows/enable-ssh.ps1          Windows guest setup for existing VMs
```

## 1. Enable the feature (cluster-admin)

```bash
./cluster/enable-vsock.sh
```

The script stops if the HyperConverged CR already has a different
`kubevirt.kubevirt.io/jsonpatch` annotation. In that case, add the VSOCK
operation to the existing annotation yourself.

## 2. Get a `virtctl` that supports it

Download the upstream KubeVirt 1.10 build. Use the latest v1.10.x from
<https://github.com/kubevirt/kubevirt/releases>; v1.10.0-rc.1 was tested.

```bash
curl -L -o virtctl-1.10 \
  https://github.com/kubevirt/kubevirt/releases/download/v1.10.0-rc.1/virtctl-v1.10.0-rc.1-linux-amd64
chmod +x virtctl-1.10
./virtctl-1.10 ssh --help | grep -- --vsock
```

## 3. Grant access (skip for cluster-admin)

```bash
oc apply -n <namespace> -f cluster/vsock-access-role.yaml
oc create rolebinding vsock-access -n <namespace> --role=vsock-access --user=<user>
```

## 4. Create the RHEL VMs

Use an **ed25519** key. The cloud-init data is limited to 2048 bytes, and the
RHEL 8/9 manifests don't leave room for a 4096-bit RSA key.

```bash
ssh-keygen -t ed25519 -f ~/.ssh/vsock_test -N ''
KEY=$(cat ~/.ssh/vsock_test.pub)
NS=<namespace>
for v in 8 9 10; do
  sed "s|REPLACE_WITH_YOUR_SSH_PUBLIC_KEY|$KEY|" vms/rhel$v-vsock.yaml | oc apply -n $NS -f -
done
oc wait vm -n $NS rhel8-vsock rhel9-vsock rhel10-vsock --for=condition=Ready --timeout=10m
```

The manifests clone the default `rhel8`, `rhel9` and `rhel10` boot sources from
`openshift-virtualization-os-images`. Give cloud-init about a minute after the VM is `Ready`.

## 5. Run commands in the VMs

```bash
for v in 8 9 10; do
  ./virtctl-1.10 ssh --vsock -i ~/.ssh/vsock_test \
    -c 'cat /etc/redhat-release; echo $SSH_CONNECTION' cloud-user@vmi/rhel$v-vsock/$NS
done
```

Leave out `-c ...` to get an interactive shell. `SSH_CONNECTION=UNKNOWN 65535 ...`
shows that the connection didn't use the VM network (over the network you'd see
an IP address).

Copy files, or forward the guest's SSH port to your workstation for other SSH tools:

```bash
./virtctl-1.10 scp --vsock -i ~/.ssh/vsock_test ./file cloud-user@vmi/rhel9-vsock/$NS:/tmp/
./virtctl-1.10 port-forward --vsock --vsock-tls=false vmi/rhel9-vsock/$NS 2222:22   # then: ssh -p 2222 cloud-user@127.0.0.1
```

`--vsock-tls=false` is required for SSH. `virtctl ssh/scp` set it automatically.

## Existing RHEL 8/9 VMs

1. Add `spec.template.spec.domain.devices.autoattachVSOCK: true` to the VM and restart it.
2. Copy `guest/rhel8-rhel9/` into the guest and run `sudo ./install.sh`.
3. To undo: `sudo ./uninstall.sh`.

The SELinux module (`sshd_vsock.cil`) allows only what systemd and sshd need on the vsock socket:

```lisp
(allow init_t sshd_t (vsock_socket (create bind listen accept getattr setopt)))
(allow sshd_t self (vsock_socket (read write getattr)))
(allow sshd_net_t sshd_t (vsock_socket (read write)))
```

## Windows Server 2025 and Windows 11

| | ISO (once, cluster-admin) | VM |
|---|---|---|
| Windows Server 2025 (Evaluation) | `vms/windows2k25-iso.yaml` → `windows2k25-iso` | `vms/windows2k25-vsock.yaml` → `windows2k25-vsock` |
| Windows 11 Pro | `vms/windows11-iso.yaml` → `windows11-iso` | `vms/windows11-vsock.yaml` → `windows11-vsock` |

### New VM

Windows Server 2025 shown; for Windows 11, use the `windows11` files and names.

1. Import the ISO once (cluster-admin). All VMs clone it, so it's downloaded only once:
   ```bash
   oc apply -f vms/windows2k25-iso.yaml
   oc wait dv windows2k25-iso -n openshift-virtualization-os-images --for=condition=Ready --timeout=30m
   ```
2. Create the VM (same SSH key as for RHEL):
   ```bash
   sed "s|REPLACE_WITH_YOUR_SSH_PUBLIC_KEY|$KEY|" vms/windows2k25-vsock.yaml | oc apply -n $NS -f -
   ```
3. Open the VNC console (web console or `./virtctl-1.10 vnc windows2k25-vsock -n $NS`) and
   **press a key at "Press any key to boot from CD or DVD"**. If you miss it, restart
   the VM, or press a key and select the first `UEFI QEMU DVD-ROM` in the Boot Manager.
4. The rest is unattended, about 30–45 minutes. Windows installs, then sets up the
   virtio-win guest tools, OpenSSH Server and your SSH key.
   Windows 11 downloads OpenSSH Server from Windows Update, so the VM needs internet access during setup.
5. Run commands:
   ```bash
   ./virtctl-1.10 ssh --vsock -i ~/.ssh/vsock_test -c 'hostname & ver' Administrator@vmi/windows2k25-vsock/$NS
   ./virtctl-1.10 scp --vsock -i ~/.ssh/vsock_test ./file Administrator@vmi/windows2k25-vsock/$NS:C:/Windows/Temp/
   ```

The Administrator password is `123456`, used for console login only. Change it in
the answer file inside the manifest. For more VMs in one namespace, rename every
`windows2k25-vsock` (or `windows11-vsock`) in the manifest.

### Existing VM

The VM needs the virtio-win guest tools (`virtio-win-gt-x64.msi` from the virtio-win drivers disk).

1. Add the vsock device and restart the VM:
   ```bash
   oc patch vm <windows-vm> -n $NS --type merge \
     -p '{"spec":{"template":{"spec":{"domain":{"devices":{"autoattachVSOCK":true}}}}}}'
   ./virtctl-1.10 restart <windows-vm> -n $NS
   ```
2. In the guest, run `windows/enable-ssh.ps1` in an Administrator PowerShell.
   It enables and starts OpenSSH Server (`sshd`) and the virtio-win
   "Virtio Socket Transport Bridge" service (`VsockTcpBridge`).
3. Run commands. Windows OpenSSH uses password login unless you add a key to
   `C:\ProgramData\ssh\administrators_authorized_keys`:
   ```bash
   ./virtctl-1.10 ssh --vsock -c 'hostname & ver' Administrator@vmi/<windows-vm>/$NS
   ```

Windows needs no firewall rule, because the connection doesn't use the VM network.

## Clean up

```bash
oc delete vm -n $NS rhel8-vsock rhel9-vsock rhel10-vsock windows2k25-vsock windows11-vsock
oc delete cm -n $NS windows2k25-vsock-sysprep windows11-vsock-sysprep
oc delete -f vms/windows2k25-iso.yaml -f vms/windows11-iso.yaml
oc patch vm <windows-vm> -n $NS --type json \
  -p '[{"op":"remove","path":"/spec/template/spec/domain/devices/autoattachVSOCK"}]'
./cluster/disable-vsock.sh
```

Before upgrading to 5.1, run `./cluster/disable-vsock.sh`. In 5.1, VSOCK is on
by default and the 5.1 `virtctl` includes `--vsock`.

## Tested

OpenShift Virtualization 5.0.0 (KubeVirt v1.9.0), `virtctl` v1.10.0-rc.1, SELinux enforcing:

| Guest | Result |
|---|---|
| RHEL 10.3 | ✅ |
| RHEL 9.9 | ✅ |
| RHEL 8.10 | ✅ |
| Windows Server 2025 (26100), existing VM + `enable-ssh.ps1` | ✅ |
| Windows Server 2025 (26100), `vms/windows2k25-vsock.yaml`, SSH key login | ✅ |
| Windows 11 Pro 25H2 (26200), `vms/windows11-vsock.yaml`, SSH key login | ✅ |

Also tested without working networking. `virtctl ssh/scp --vsock` work in all of these cases:

| Case | Guest |
|---|---|
| No network interface (`autoattachPodInterface: false`), only loopback in the guest | RHEL 10, Windows Server 2025 |
| Network adapter disabled inside the guest (no IP, no internet); regular `virtctl ssh` fails | Windows Server 2025 |
