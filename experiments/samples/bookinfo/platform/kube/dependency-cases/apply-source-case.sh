#!/usr/bin/env bash
# Apply a source fixture, adding the selected dependency mode before admission.
set -euo pipefail

MANIFEST=${1:?"usage: apply-source-case.sh <manifest>"}
MODE=${DEPENDENCY_MODE:-}
KUBECTL=${KUBECTL:-kubectl}
KUBE_CONTEXT=${KUBE_CONTEXT:-kind-kube-dep-guard}
NAMESPACE=${NAMESPACE:-bookinfo}

kubectl_cmd=("$KUBECTL" --context "$KUBE_CONTEXT" --namespace "$NAMESPACE")

if [[ -z $MODE ]]; then
  exec "${kubectl_cmd[@]}" apply -f "$MANIFEST"
fi

case "$MODE" in
  enforce|warn) ;;
  *)
    echo "Unsupported DEPENDENCY_MODE: $MODE" >&2
    exit 2
    ;;
esac

"${kubectl_cmd[@]}" annotate --local -f "$MANIFEST" \
  dependency.kubedepguard.io/mode="$MODE" -o yaml | \
  "${kubectl_cmd[@]}" apply -f -
