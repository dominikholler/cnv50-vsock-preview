#!/bin/bash
# Enable the KubeVirt VSOCK feature gate on OpenShift Virtualization 5.0.
# UNSUPPORTED: uses the HyperConverged jsonpatch annotation.
# If the annotation already holds other operations, the VSOCK operation is
# appended and the other operations are kept unchanged. Needs: oc, bash.
set -euo pipefail
NS=openshift-cnv
HCO=kubevirt-hyperconverged
ANN=kubevirt.kubevirt.io/jsonpatch
OP='{"op":"add","path":"/spec/configuration/developerConfiguration/featureGates/-","value":"VSOCK"}'

current=$(oc get hco -n "$NS" "$HCO" -o jsonpath="{.metadata.annotations['kubevirt\.kubevirt\.io/jsonpatch']}")
# trim surrounding whitespace
current="${current#"${current%%[![:space:]]*}"}"
current="${current%"${current##*[![:space:]]}"}"

if [[ "$current" == *"$OP"* ]]; then
  echo "The VSOCK operation is already in $ANN; nothing to change."
else
  if [ -z "$current" ]; then
    new="[$OP]"
  elif [[ "$current" != \[*\] ]]; then
    echo "ERROR: $ANN is not a JSON array; not changing it:" >&2
    echo "  $current" >&2
    exit 1
  else
    inner="${current#[}"; inner="${inner%]}"
    if [[ -z "${inner//[[:space:]]/}" ]]; then
      new="[$OP]"
    else
      echo "Keeping the existing operations in $ANN and adding VSOCK."
      new="${current%]},$OP]"
    fi
  fi
  oc annotate --overwrite -n "$NS" hco "$HCO" "$ANN=$new"
fi

echo "Waiting for the VSOCK gate to show up in the KubeVirt CR ..."
for _ in $(seq 1 24); do
  oc get kubevirt -n "$NS" kubevirt-kubevirt-hyperconverged \
    -o jsonpath='{.spec.configuration.developerConfiguration.featureGates}' | grep -q '"VSOCK"' && break
  sleep 5
done
oc get kubevirt -n "$NS" kubevirt-kubevirt-hyperconverged \
  -o jsonpath='{.spec.configuration.developerConfiguration.featureGates}{"\n"}'
oc wait hco -n "$NS" "$HCO" --for=condition=Available --timeout=600s
