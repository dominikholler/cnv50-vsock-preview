#!/bin/bash
# Remove the VSOCK jsonpatch annotation again (run before upgrading to 5.1).
# Remove autoattachVSOCK from VMs first: VMs that set it fail to start while the gate is off.
set -euo pipefail
oc annotate -n openshift-cnv hco kubevirt-hyperconverged kubevirt.kubevirt.io/jsonpatch-
