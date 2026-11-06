#!/usr/bin/env bash
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "$SCRIPT_DIR/apply-source-case.sh" "$SCRIPT_DIR/resources/deployment-configmap-normal.yaml"
