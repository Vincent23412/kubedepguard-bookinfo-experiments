#!/usr/bin/env bash
# Verify that dependency modes have the expected admission and monitoring
# behaviour without changing the Bookinfo namespace.
set -uo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
KUBECTL=${KUBECTL:-kubectl}
KUBE_CONTEXT=${KUBE_CONTEXT:-kind-kube-dep-guard}
RESULTS_DIR=${RESULTS_DIR:-"$SCRIPT_DIR/runs"}
EVENT_WAIT_SECONDS=${EVENT_WAIT_SECONDS:-30}
EVENT_REASON_REGEX=${EVENT_REASON_REGEX:-'.*'}

MODE_FILTER=""
RELATION_FILTER=""
OPERATION_FILTER=""
RUN_ID=$(date '+%Y%m%dT%H%M%S%z')
RUN_TOKEN="$(date '+%Y%m%d%H%M%S')-$$-$RANDOM"
RUN_DIR="$RESULTS_DIR/$RUN_ID"
SUMMARY_FILE="$RUN_DIR/summary.tsv"

relations=(
  deployment-configmap
  deployment-secret
  deployment-pvc
  ingress-service
  service-pod
  networkpolicy-pod
)
modes=(enforce warn)
operations=(source-conflict target-delete)

usage() {
  cat <<'EOF'
Usage: run-mode-cases.sh [options]

Runs 24 isolated mode tests: six dependency relationships, each with source
creation and target deletion violations in both enforce and warn mode.

Options:
  --mode enforce|warn
  --relation deployment-configmap|deployment-secret|deployment-pvc|ingress-service|service-pod|networkpolicy-pod
  --operation source-conflict|target-delete
  -h, --help

Environment:
  KUBECTL             kubectl binary (default: kubectl)
  KUBE_CONTEXT        target context (default: kind-kube-dep-guard)
  RESULTS_DIR         parent directory for logs (default: mode-cases/runs)
  EVENT_WAIT_SECONDS  maximum wait for a Warning Event (default: 30)
  EVENT_REASON_REGEX  regex required for an Event reason (default: .*)
EOF
}

contains() {
  local expected=$1
  shift
  local value
  for value in "$@"; do
    [[ $value == "$expected" ]] && return 0
  done
  return 1
}

while (( $# > 0 )); do
  case "$1" in
    --mode)
      MODE_FILTER=${2:?"--mode requires a value"}
      shift 2
      ;;
    --relation)
      RELATION_FILTER=${2:?"--relation requires a value"}
      shift 2
      ;;
    --operation)
      OPERATION_FILTER=${2:?"--operation requires a value"}
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -n $MODE_FILTER ]] && ! contains "$MODE_FILTER" "${modes[@]}"; then
  echo "Unsupported mode: $MODE_FILTER" >&2
  exit 2
fi
if [[ -n $RELATION_FILTER ]] && ! contains "$RELATION_FILTER" "${relations[@]}"; then
  echo "Unsupported relation: $RELATION_FILTER" >&2
  exit 2
fi
if [[ -n $OPERATION_FILTER ]] && ! contains "$OPERATION_FILTER" "${operations[@]}"; then
  echo "Unsupported operation: $OPERATION_FILTER" >&2
  exit 2
fi

kubectl_cmd=("$KUBECTL" --context "$KUBE_CONTEXT")

target_kind_for() {
  case "$1" in
    deployment-configmap) printf '%s\n' configmap ;;
    deployment-secret) printf '%s\n' secret ;;
    deployment-pvc) printf '%s\n' persistentvolumeclaim ;;
    ingress-service) printf '%s\n' service ;;
    service-pod|networkpolicy-pod) printf '%s\n' pod ;;
  esac
}

event_uids() {
  "${kubectl_cmd[@]}" --namespace "$1" get events -o jsonpath='{range .items[*]}{.metadata.uid}{" "}{end}' 2>/dev/null || true
}

wait_for_warning_event() {
  local namespace=$1
  local previous_uids=" $2 "
  local source_name=$3
  local target_name=$4
  local deadline=$((SECONDS + EVENT_WAIT_SECONDS))
  local uid object_name reason message

  while (( SECONDS < deadline )); do
    while IFS=$'\t' read -r uid object_name reason message; do
      [[ -z $uid || $previous_uids == *" $uid "* ]] && continue
      [[ $object_name != "$source_name" && $object_name != "$target_name" ]] && continue
      [[ $reason =~ $EVENT_REASON_REGEX ]] || continue
      printf 'Warning Event: reason=%s object=%s message=%s\n' "$reason" "$object_name" "$message"
      return 0
    done < <("${kubectl_cmd[@]}" --namespace "$namespace" get events \
      --field-selector type=Warning \
      -o jsonpath='{range .items[*]}{.metadata.uid}{"\t"}{.involvedObject.name}{"\t"}{.reason}{"\t"}{.message}{"\n"}{end}' 2>/dev/null)
    sleep 1
  done

  echo "No new matching Warning Event appeared within ${EVENT_WAIT_SECONDS}s."
  return 1
}

apply_target() {
  local namespace=$1
  local relation=$2
  local target_name=$3

  case "$relation" in
    deployment-configmap)
      "${kubectl_cmd[@]}" --namespace "$namespace" create configmap "$target_name" --from-literal=key=value
      ;;
    deployment-secret)
      "${kubectl_cmd[@]}" --namespace "$namespace" create secret generic "$target_name" --from-literal=key=value
      ;;
    deployment-pvc)
      "${kubectl_cmd[@]}" --namespace "$namespace" apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $target_name
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 16Mi
EOF
      ;;
    ingress-service)
      "${kubectl_cmd[@]}" --namespace "$namespace" apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: backend-pod
  labels:
    app: $target_name
spec:
  containers:
  - name: sleeper
    image: busybox:1.36.1
    command: ["sh", "-c", "sleep 600"]
---
apiVersion: v1
kind: Service
metadata:
  name: $target_name
spec:
  selector:
    app: $target_name
  ports:
  - port: 8080
    targetPort: 8080
EOF
      ;;
    service-pod|networkpolicy-pod)
      "${kubectl_cmd[@]}" --namespace "$namespace" apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $target_name
  labels:
    app: $target_name
spec:
  containers:
  - name: sleeper
    image: busybox:1.36.1
    command: ["sh", "-c", "sleep 600"]
EOF
      ;;
  esac
}

apply_source() {
  local namespace=$1
  local relation=$2
  local source_name=$3
  local target_name=$4
  local mode=$5

  case "$relation" in
    deployment-configmap)
      "${kubectl_cmd[@]}" --namespace "$namespace" apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $source_name
  annotations:
    dependency.kubedepguard.io/mode: $mode
spec:
  replicas: 0
  selector:
    matchLabels: {app: $source_name}
  template:
    metadata:
      labels: {app: $source_name}
    spec:
      containers:
      - name: sleeper
        image: busybox:1.36.1
        command: ["sh", "-c", "sleep 600"]
        envFrom:
        - configMapRef: {name: $target_name}
EOF
      ;;
    deployment-secret)
      "${kubectl_cmd[@]}" --namespace "$namespace" apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $source_name
  annotations:
    dependency.kubedepguard.io/mode: $mode
spec:
  replicas: 0
  selector:
    matchLabels: {app: $source_name}
  template:
    metadata:
      labels: {app: $source_name}
    spec:
      containers:
      - name: sleeper
        image: busybox:1.36.1
        command: ["sh", "-c", "sleep 600"]
        env:
        - name: VALUE
          valueFrom:
            secretKeyRef: {name: $target_name, key: key}
EOF
      ;;
    deployment-pvc)
      "${kubectl_cmd[@]}" --namespace "$namespace" apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $source_name
  annotations:
    dependency.kubedepguard.io/mode: $mode
spec:
  replicas: 0
  selector:
    matchLabels: {app: $source_name}
  template:
    metadata:
      labels: {app: $source_name}
    spec:
      containers:
      - name: sleeper
        image: busybox:1.36.1
        command: ["sh", "-c", "sleep 600"]
        volumeMounts: [{name: data, mountPath: /data}]
      volumes:
      - name: data
        persistentVolumeClaim: {claimName: $target_name}
EOF
      ;;
    ingress-service)
      "${kubectl_cmd[@]}" --namespace "$namespace" apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: $source_name
  annotations:
    dependency.kubedepguard.io/mode: $mode
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service: {name: $target_name, port: {number: 8080}}
EOF
      ;;
    service-pod)
      "${kubectl_cmd[@]}" --namespace "$namespace" apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: $source_name
  annotations:
    dependency.kubedepguard.io/mode: $mode
spec:
  selector: {app: $target_name}
  ports:
  - port: 8080
    targetPort: 8080
EOF
      ;;
    networkpolicy-pod)
      "${kubectl_cmd[@]}" --namespace "$namespace" apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: $source_name
  annotations:
    dependency.kubedepguard.io/mode: $mode
spec:
  podSelector:
    matchLabels: {app: $target_name}
  policyTypes: [Ingress]
  ingress: [{}]
EOF
      ;;
  esac
}

case_index=0
overall_status=0
mkdir -p "$RUN_DIR"
printf 'case\tmode\toperation\texpected_api\tactual_api\texpected_event\tactual_event\tsuccess\tlog\n' >"$SUMMARY_FILE"

run_case() {
  local relation=$1
  local mode=$2
  local operation=$3
  local namespace="kubedepguard-mode-${RUN_TOKEN}-${case_index}"
  local source_name="source"
  local target_name="target"
  local target_kind
  local command_status=127
  local expected_api
  local actual_api=failed
  local actual_event=not-required
  local success=false
  local event_before

  target_kind=$(target_kind_for "$relation")
  ((case_index += 1))

  echo "Namespace: $namespace"
  if ! "${kubectl_cmd[@]}" create namespace "$namespace"; then
    echo "Could not create test namespace."
    return 1
  fi

  if [[ $operation == target-delete ]]; then
    if ! apply_target "$namespace" "$relation" "$target_name"; then
      echo "Could not create target fixture."
      "${kubectl_cmd[@]}" delete namespace "$namespace" --ignore-not-found --wait=false
      return 1
    fi
    if ! apply_source "$namespace" "$relation" "$source_name" "$target_name" "$mode"; then
      echo "Could not create valid annotated source fixture."
      "${kubectl_cmd[@]}" delete namespace "$namespace" --ignore-not-found --wait=false
      return 1
    fi
  fi

  event_before=$(event_uids "$namespace")
  if [[ $operation == source-conflict ]]; then
    apply_source "$namespace" "$relation" "$source_name" "$target_name" "$mode"
    command_status=$?
  else
    "${kubectl_cmd[@]}" --namespace "$namespace" delete "$target_kind/$target_name"
    command_status=$?
  fi

  if (( command_status == 0 )); then
    actual_api=accepted
  else
    actual_api=rejected
  fi

  if [[ $mode == enforce ]]; then
    expected_api=rejected
    if [[ $operation == source-conflict ]]; then
      if (( command_status != 0 )) && ! "${kubectl_cmd[@]}" --namespace "$namespace" get deployment "$source_name" >/dev/null 2>&1; then
        success=true
      fi
    elif (( command_status != 0 )) && "${kubectl_cmd[@]}" --namespace "$namespace" get "$target_kind/$target_name" >/dev/null 2>&1; then
      success=true
    fi
  else
    expected_api=accepted
    if (( command_status == 0 )); then
      if [[ $operation == source-conflict ]] && "${kubectl_cmd[@]}" --namespace "$namespace" get deployment "$source_name" >/dev/null 2>&1; then
        :
      elif [[ $operation == target-delete ]] && ! "${kubectl_cmd[@]}" --namespace "$namespace" get "$target_kind/$target_name" >/dev/null 2>&1; then
        :
      else
        echo "Accepted request did not produce the expected resource state."
        command_status=1
      fi
    fi
    if (( command_status == 0 )) && wait_for_warning_event "$namespace" "$event_before" "$source_name" "$target_name"; then
      actual_event=warning
      success=true
    else
      actual_event=missing
    fi
  fi

  "${kubectl_cmd[@]}" delete namespace "$namespace" --ignore-not-found --wait=false
  printf 'Result: expected_api=%s actual_api=%s actual_event=%s success=%s\n' \
    "$expected_api" "$actual_api" "$actual_event" "$success"
  [[ $success == true ]]
}

for relation in "${relations[@]}"; do
  [[ -n $RELATION_FILTER && $RELATION_FILTER != "$relation" ]] && continue
  for mode in "${modes[@]}"; do
    [[ -n $MODE_FILTER && $MODE_FILTER != "$mode" ]] && continue
    for operation in "${operations[@]}"; do
      [[ -n $OPERATION_FILTER && $OPERATION_FILTER != "$operation" ]] && continue

      case_name="${relation}-${operation}-${mode}"
      case_log="$RUN_DIR/${case_name}.log"
      echo "=== Running $case_name ==="
      if { run_case "$relation" "$mode" "$operation"; } >"$case_log" 2>&1; then
        success=true
      else
        success=false
        overall_status=1
      fi

      expected_api=$([[ $mode == enforce ]] && printf rejected || printf accepted)
      actual_api=$(awk -F '[ =]' '/^Result:/ {for (i = 1; i <= NF; i++) if ($i == "actual_api") print $(i + 1)}' "$case_log" | tail -n 1)
      actual_event=$(awk -F '[ =]' '/^Result:/ {for (i = 1; i <= NF; i++) if ($i == "actual_event") print $(i + 1)}' "$case_log" | tail -n 1)
      [[ -n $actual_api ]] || actual_api=setup-failed
      [[ -n $actual_event ]] || actual_event=not-recorded
      expected_event=$([[ $mode == warn ]] && printf warning || printf none)
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$case_name" "$mode" "$operation" "$expected_api" "$actual_api" \
        "$expected_event" "$actual_event" "$success" "$case_log" >>"$SUMMARY_FILE"
      printf '%s: success=%s\n' "$case_name" "$success"
    done
  done
done

printf '\nSummary: %s\n' "$SUMMARY_FILE"
exit "$overall_status"
