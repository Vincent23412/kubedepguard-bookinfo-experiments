#!/usr/bin/env bash
# Return the Bookinfo dependency-case environment to its declared baseline.
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPOSITORY_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)
KUBECTL=${KUBECTL:-kubectl}
KUBE_CONTEXT=${KUBE_CONTEXT:-kind-kube-dep-guard}
NAMESPACE=${NAMESPACE:-bookinfo}
DEPENDENCY_MODE=${DEPENDENCY_MODE:-}

kubectl_cmd=("$KUBECTL" --context "$KUBE_CONTEXT" --namespace "$NAMESPACE")

remove_label() {
  local resource_args=("$@")

  if "${kubectl_cmd[@]}" get "${resource_args[@]}" >/dev/null 2>&1; then
    "${kubectl_cmd[@]}" label "${resource_args[@]}" dependency-case- >/dev/null
  fi
}

echo "Removing temporary dependency-case resources..."
"${kubectl_cmd[@]}" delete --ignore-not-found -f "$SCRIPT_DIR/resources"

if [[ -n $DEPENDENCY_MODE ]]; then
  case "$DEPENDENCY_MODE" in
    enforce|warn) ;;
    *)
      echo "Unsupported DEPENDENCY_MODE: $DEPENDENCY_MODE" >&2
      exit 2
      ;;
  esac
  echo "Reapplying and verifying the '$DEPENDENCY_MODE' Bookinfo profile..."
  KUBECTL="$KUBECTL" KUBE_CONTEXT="$KUBE_CONTEXT" NAMESPACE="$NAMESPACE" \
    "$SCRIPT_DIR/../mode-profiles/$DEPENDENCY_MODE/deploy.sh"
else
  echo "Reapplying and verifying the declared Bookinfo baseline..."
  make --no-print-directory -C "$REPOSITORY_ROOT" deploy \
    KUBECTL="$KUBECTL" \
    KUBE_CONTEXT="$KUBE_CONTEXT" \
    NAMESPACE="$NAMESPACE"
fi

echo "Removing dependency-case labels..."
remove_label configmap/bookinfo-service-config
remove_label secret/bookinfo-service-credentials
remove_label pvc/mongodb-data
remove_label service/productpage
remove_label pods -l app=productpage,version=v1
remove_label pods -l app=reviews,version=v3

echo "Bookinfo baseline restored."
