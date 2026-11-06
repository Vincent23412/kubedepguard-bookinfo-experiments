#!/usr/bin/env bash
# Deploy the Bookinfo baseline first, then enable a dependency mode only after
# every referenced target already exists.
set -euo pipefail

MODE=${1:?"usage: deploy-profile.sh <enforce|warn>"}
case "$MODE" in
  enforce|warn) ;;
  *)
    echo "Unsupported dependency mode: $MODE" >&2
    exit 2
    ;;
esac

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPOSITORY_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)
KUBECTL=${KUBECTL:-kubectl}
KUBE_CONTEXT=${KUBE_CONTEXT:-kind-kube-dep-guard}
NAMESPACE=${NAMESPACE:-bookinfo}

# First deploy the unannotated baseline. Its ConfigMaps, Secrets, PVCs,
# Services, and Pods are present before the corresponding source annotations
# are enabled below.
make --no-print-directory -C "$REPOSITORY_ROOT" deploy \
  KUBECTL="$KUBECTL" \
  KUBE_CONTEXT="$KUBE_CONTEXT" \
  NAMESPACE="$NAMESPACE"

kubectl_cmd=("$KUBECTL" --context "$KUBE_CONTEXT" --namespace "$NAMESPACE")
sources=(
  deployment/productpage-v1
  deployment/reviews-v3
  deployment/ratings-v2
  deployment/mongodb-v1
  service/productpage
  ingress/bookinfo
  networkpolicy/reviews-from-productpage
)

echo "Setting dependency mode '$MODE' on Bookinfo source resources..."
"${kubectl_cmd[@]}" annotate --overwrite "${sources[@]}" \
  dependency.kubedepguard.io/mode="$MODE"

echo "Bookinfo '$MODE' profile is ready."
