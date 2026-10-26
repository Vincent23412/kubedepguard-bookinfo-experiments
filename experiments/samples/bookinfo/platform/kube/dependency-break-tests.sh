#!/usr/bin/env bash
# Intentionally break one Bookinfo dependency to observe its effect, then use
# restore to return to the manifests in this directory.
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
NAMESPACE=""
ACTION=""
RELATION=""

usage() {
  cat <<'EOF'
Usage:
  dependency-break-tests.sh --namespace <namespace> break <relation>
  dependency-break-tests.sh --namespace <namespace> restore
  dependency-break-tests.sh --namespace <namespace> status

Relations:
  configmap      Deployment -> ConfigMap; Productpage replacement Pod waits
                 with CreateContainerConfigError.
  secret         Deployment -> Secret; Productpage replacement Pod waits with
                 CreateContainerConfigError.
  pvc            Deployment -> PVC; MongoDB replacement Pod cannot mount its
                 missing claim and ratings requests fail.
  ingress        Ingress -> Service; /productpage receives an Ingress backend
                 error because the referenced Service does not exist.
  service        Service -> Pod; Productpage has no selected endpoints, so the
                 Ingress backend cannot serve requests.
  networkpolicy  NetworkPolicy -> Pod; Reviews still selects its Pods, but its
                 allowed source selector is broken, so Productpage cannot call
                 Reviews and the product page displays a review error.

restore reapplies kustomization.yaml, then restarts the affected Deployments.
status prints the resources and endpoints to inspect.
EOF
}

while test "$#" -gt 0; do
  case "$1" in
    --namespace|-n)
      NAMESPACE=${2:?"--namespace requires a value"}
      shift 2
      ;;
    break|restore|status)
      ACTION=$1
      shift
      if test "$ACTION" = break; then
        RELATION=${1:?"break requires a relation"}
        shift
      fi
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

if test -z "$NAMESPACE" || test -z "$ACTION" || test "$#" -ne 0; then
  usage >&2
  exit 2
fi

kubectl_cmd() {
  kubectl --namespace "$NAMESPACE" "$@"
}

case "$ACTION" in
  break)
    case "$RELATION" in
      configmap)
        kubectl_cmd delete configmap bookinfo-service-config
        kubectl_cmd rollout restart deployment/productpage-v1
        ;;
      secret)
        kubectl_cmd delete secret bookinfo-service-credentials
        kubectl_cmd rollout restart deployment/productpage-v1
        ;;
      pvc)
        kubectl_cmd patch deployment mongodb-v1 --type merge \
          -p '{"spec":{"template":{"spec":{"volumes":[{"name":"data-db","persistentVolumeClaim":{"claimName":"mongodb-data-broken"}}]}}}}'
        ;;
      ingress)
        kubectl_cmd patch ingress bookinfo --type json \
          -p '[{"op":"replace","path":"/spec/rules/0/http/paths/0/backend/service/name","value":"productpage-broken"}]'
        ;;
      service)
        kubectl_cmd patch service productpage --type merge \
          -p '{"spec":{"selector":{"app":"productpage-broken"}}}'
        ;;
      networkpolicy)
        kubectl_cmd patch networkpolicy reviews-from-productpage --type json \
          -p '[{"op":"replace","path":"/spec/ingress/0/from/0/podSelector/matchLabels/app","value":"productpage-broken"}]'
        ;;
      *)
        usage >&2
        exit 2
        ;;
    esac
    ;;
  restore)
    kubectl_cmd apply -k "$SCRIPT_DIR"
    kubectl_cmd rollout restart deployment/productpage-v1 deployment/mongodb-v1
    ;;
  status)
    kubectl_cmd get pods,services,ingress,networkpolicy,pvc
    kubectl_cmd get endpointslice -l kubernetes.io/service-name=productpage
    ;;
esac
