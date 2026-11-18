#!/bin/bash
# Remove the VSOCK operation added by enable-vsock.sh (run before upgrading OpenShift Virtualization).
# Other operations in the jsonpatch annotation are kept unchanged; the annotation
# is deleted only if the VSOCK operation was its only content. Needs: oc, bash.
# Remove autoattachVSOCK from VMs first: VMs that set it fail to start while the gate is off.
set -euo pipefail
NS=openshift-cnv
HCO=kubevirt-hyperconverged
ANN=kubevirt.kubevirt.io/jsonpatch
OP='{"op":"add","path":"/spec/configuration/developerConfiguration/featureGates/-","value":"VSOCK"}'

current=$(oc get hco -n "$NS" "$HCO" -o jsonpath="{.metadata.annotations['kubevirt\.kubevirt\.io/jsonpatch']}")
current="${current#"${current%%[![:space:]]*}"}"
current="${current%"${current##*[![:space:]]}"}"

if [ -z "$current" ]; then
  echo "$ANN is not set; nothing to change."
  exit 0
fi
if [[ "$current" != *"$OP"* ]]; then
  echo "The VSOCK operation (as written by enable-vsock.sh) is not in $ANN; nothing to change."
  echo "  $ANN=$current"
  exit 0
fi

if [ "$current" = "[$OP]" ]; then
  oc annotate -n "$NS" hco "$HCO" "$ANN-"
  echo "Removed $ANN (it only contained the VSOCK operation)."
  exit 0
fi

# Remove the operation together with its separating comma.
if [[ "$current" == *",$OP"* ]]; then
  new="${current/",$OP"/}"
else
  new="${current/"$OP,"/}"
fi
if [ "$new" = "$current" ]; then
  echo "ERROR: could not remove the VSOCK operation cleanly; not changing $ANN:" >&2
  echo "  $current" >&2
  exit 1
fi
oc annotate --overwrite -n "$NS" hco "$HCO" "$ANN=$new"
echo "Removed the VSOCK operation; kept the other operations:"
echo "  $new"
