#!/usr/bin/env bash
# Run dependency cases one at a time, restore Bookinfo after each one, and
# keep a complete command/output log plus a machine-readable summary.
set -uo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
RESTORE_SCRIPT="$SCRIPT_DIR/restore-environment.sh"
RUNS_DIR=${RUNS_DIR:-"$SCRIPT_DIR/runs"}
KUBECTL=${KUBECTL:-kubectl}
KUBE_CONTEXT=${KUBE_CONTEXT:-kind-kube-dep-guard}
NAMESPACE=${NAMESPACE:-bookinfo}
WARN_EVENT_WAIT_SECONDS=${WARN_EVENT_WAIT_SECONDS:-30}
WARN_EVENT_REASON_REGEX=${WARN_EVENT_REASON_REGEX:-'.*'}
MODE=""
RUN_ID=$(date '+%Y%m%dT%H%M%S%z')
RUN_DIR="$RUNS_DIR/$RUN_ID"
SUMMARY_FILE="$RUN_DIR/summary.tsv"

usage() {
  cat <<'EOF'
Usage: run-cases.sh [--mode enforce|warn] [case-script ...]

Run all 24 dependency cases when no case script is given. A supplied case may
be either its filename (for example, 01-deployment-configmap-source-normal.sh)
or a path to a case script. Each case is followed by environment restoration.

With --mode, the matching Bookinfo profile is deployed before the first case.
Conflict cases then treat an enforce rejection as a passing result, while warn
cases require an accepted request and a new Warning Event.

Environment:
  RUNS_DIR                 Directory for timestamped logs (default: dependency-cases/runs)
  WARN_EVENT_WAIT_SECONDS  Maximum wait for a warn Event (default: 30)
  WARN_EVENT_REASON_REGEX  Regex required for a warn Event reason (default: .*)
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --mode)
      MODE=${2:?"--mode requires a value"}
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

if [[ -n $MODE && $MODE != enforce && $MODE != warn ]]; then
  echo "Unsupported mode: $MODE" >&2
  exit 2
fi

if (( $# == 0 )); then
  case_scripts=("$SCRIPT_DIR"/[0-9][0-9]-*.sh)
else
  case_scripts=()
  for requested_case in "$@"; do
    if [[ $requested_case == */* ]]; then
      case_scripts+=("$requested_case")
    else
      case_scripts+=("$SCRIPT_DIR/$requested_case")
    fi
  done
fi

event_uids() {
  "$KUBECTL" --context "$KUBE_CONTEXT" --namespace "$NAMESPACE" get events \
    -o jsonpath='{range .items[*]}{.metadata.uid}{" "}{end}' 2>/dev/null || true
}

event_object_for_case() {
  case "$1" in
    *source-conflict.sh)
      local without_number=${1#??-}
      local relation=${without_number%-source-conflict.sh}
      printf 'case-%s-conflict\n' "$relation"
      ;;
    *deployment-configmap-target-conflict.sh|*deployment-secret-target-conflict.sh)
      printf 'productpage-v1\n'
      ;;
    *deployment-pvc-target-conflict.sh)
      printf 'mongodb-v1\n'
      ;;
    *ingress-service-target-conflict.sh)
      printf 'bookinfo\n'
      ;;
    *service-pod-target-conflict.sh)
      printf 'productpage\n'
      ;;
    *networkpolicy-pod-target-conflict.sh)
      printf 'reviews-from-productpage\n'
      ;;
  esac
}

wait_for_warning_event() {
  local previous_uids=" $1 "
  local expected_object=$2
  local deadline=$((SECONDS + WARN_EVENT_WAIT_SECONDS))
  local uid object_name reason message

  while (( SECONDS < deadline )); do
    while IFS=$'\t' read -r uid object_name reason message; do
      [[ -z $uid || $previous_uids == *" $uid "* ]] && continue
      [[ $object_name == "$expected_object" ]] || continue
      [[ $reason =~ $WARN_EVENT_REASON_REGEX ]] || continue
      printf 'Warning Event: reason=%s object=%s message=%s\n' "$reason" "$object_name" "$message"
      return 0
    done < <("$KUBECTL" --context "$KUBE_CONTEXT" --namespace "$NAMESPACE" get events \
      --field-selector type=Warning \
      -o jsonpath='{range .items[*]}{.metadata.uid}{"\t"}{.involvedObject.name}{"\t"}{.reason}{"\t"}{.message}{"\n"}{end}' 2>/dev/null)
    sleep 1
  done

  echo "No new matching Warning Event appeared within ${WARN_EVENT_WAIT_SECONDS}s."
  return 1
}

expected_api_for_case() {
  local case_name=$1

  if [[ -n $MODE && $MODE == enforce && $case_name == *-conflict.sh ]]; then
    printf 'rejected\n'
  else
    printf 'accepted\n'
  fi
}

expected_event_for_case() {
  local case_name=$1

  if [[ $MODE == warn && $case_name == *-conflict.sh ]]; then
    printf 'warning\n'
  else
    printf 'none\n'
  fi
}

mkdir -p "$RUN_DIR"
printf 'case\tmode\texpected_api\tactual_api\texpected_event\tactual_event\trestore_exit\tsuccess\tlog\n' >"$SUMMARY_FILE"

if [[ -n $MODE ]]; then
  profile_script="$SCRIPT_DIR/../mode-profiles/$MODE/deploy.sh"
  if ! KUBECTL="$KUBECTL" KUBE_CONTEXT="$KUBE_CONTEXT" NAMESPACE="$NAMESPACE" "$profile_script"; then
    echo "Could not deploy the '$MODE' profile; no cases were run." >&2
    exit 1
  fi
fi

overall_status=0
for case_script in "${case_scripts[@]}"; do
  case_name=$(basename "$case_script")
  case_log="$RUN_DIR/${case_name%.sh}.log"
  command_status=127
  restore_status=127
  expected_api=$(expected_api_for_case "$case_name")
  expected_event=$(expected_event_for_case "$case_name")
  actual_api=not-run
  actual_event=none
  event_before=""

  if [[ $expected_event == warning ]]; then
    event_before=$(event_uids)
  fi

  if [[ -f $case_script ]]; then
    echo "=== Running $case_name ==="
    {
      printf 'Case: %s\nMode: %s\nStarted: %s\n\n' "${case_name}" "${MODE:-none}" "$(date '+%Y-%m-%dT%H:%M:%S%z')"
      printf '%s\n' '--- Command output ---'
      (
        cd "$SCRIPT_DIR"
        DEPENDENCY_MODE="$MODE" KUBECTL="$KUBECTL" KUBE_CONTEXT="$KUBE_CONTEXT" NAMESPACE="$NAMESPACE" \
          bash -x "$case_script"
      )
    } >"$case_log" 2>&1
    command_status=$?
  else
    printf 'Case script not found: %s\n' "$case_script" >"$case_log"
  fi

  if (( command_status == 0 )); then
    actual_api=accepted
  else
    actual_api=rejected
  fi

  if [[ $expected_event == warning ]]; then
    {
      printf '\n%s\n' '--- Warning Event assertion ---'
      if wait_for_warning_event "$event_before" "$(event_object_for_case "$case_name")"; then
        actual_event=warning
      else
        actual_event=missing
      fi
    } >>"$case_log" 2>&1
  fi

  {
    printf '\n%s\n' '--- Restore output ---'
    DEPENDENCY_MODE="$MODE" KUBECTL="$KUBECTL" KUBE_CONTEXT="$KUBE_CONTEXT" NAMESPACE="$NAMESPACE" \
      "$RESTORE_SCRIPT"
  } >>"$case_log" 2>&1
  restore_status=$?

  success=false
  if [[ $actual_api == "$expected_api" && $actual_event == "$expected_event" && $restore_status == 0 ]]; then
    success=true
  fi
  if [[ $success != true ]]; then
    overall_status=1
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$case_name" "${MODE:-none}" "$expected_api" "$actual_api" "$expected_event" \
    "$actual_event" "$restore_status" "$success" "$case_log" >>"$SUMMARY_FILE"
  printf '%s: expected_api=%s actual_api=%s expected_event=%s actual_event=%s restore=%s success=%s\n' \
    "$case_name" "$expected_api" "$actual_api" "$expected_event" "$actual_event" "$restore_status" "$success"
done

printf '\nSummary: %s\n' "$SUMMARY_FILE"
exit "$overall_status"
