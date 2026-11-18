#!/bin/bash
# Enable the KubeVirt VSOCK feature gate on OpenShift Virtualization 5.0.
# UNSUPPORTED: uses the HyperConverged jsonpatch annotation.
set -euo pipefail
NS=openshift-cnv
HCO=kubevirt-hyperconverged
ANN=kubevirt.kubevirt.io/jsonpatch
PATCH='[{"op":"add","path":"/spec/configuration/developerConfiguration/featureGates/-","value":"VSOCK"}]'

current=$(oc get hco -n "$NS" "$HCO" -o jsonpath="{.metadata.annotations['kubevirt\.kubevirt\.io/jsonpatch']}")
if [ -n "$current" ] && [ "$current" != "$PATCH" ]; then
  echo "ERROR: $ANN is already set on the HyperConverged CR:" >&2
  echo "  $current" >&2
  echo "Merge the VSOCK operation into it manually instead of overwriting it." >&2
  exit 1
fi

oc annotate --overwrite -n "$NS" hco "$HCO" "$ANN=$PATCH"
echo "Waiting for the VSOCK gate to show up in the KubeVirt CR ..."
for _ in $(seq 1 24); do
  oc get kubevirt -n "$NS" kubevirt-kubevirt-hyperconverged \
    -o jsonpath='{.spec.configuration.developerConfiguration.featureGates}' | grep -q '"VSOCK"' && break
  sleep 5
done
oc get kubevirt -n "$NS" kubevirt-kubevirt-hyperconverged \
  -o jsonpath='{.spec.configuration.developerConfiguration.featureGates}{"\n"}'
oc wait hco -n "$NS" "$HCO" --for=condition=Available --timeout=600s
