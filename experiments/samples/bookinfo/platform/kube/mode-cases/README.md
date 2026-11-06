# Dependency mode cases

`run-mode-cases.sh` tests the source-resource annotation
`dependency.kubedepguard.io/mode` without modifying the `bookinfo` namespace.
Every case creates a fresh, temporary namespace and removes it when finished.

The suite runs 24 cases: six dependency relationships, each with a missing
target while creating the source and a deletion of an existing target, in both
`enforce` and `warn` modes.

Deployment fixtures use zero replicas. The dependency remains present in the
Deployment spec, while no Pod mounts the test PVC; this keeps Kubernetes PVC
protection from obscuring the target-deletion assertion.

| Mode | Expected API result | Expected state | Expected Event |
| --- | --- | --- | --- |
| `enforce` | Request rejected | Invalid source is absent; referenced target remains | None required |
| `warn` | Request accepted | Invalid source is present; referenced target is deleted | A new `Warning` Event |

Run the full suite:

```sh
./run-mode-cases.sh
```

Run a focused case:

```sh
./run-mode-cases.sh --relation deployment-configmap --operation source-conflict --mode warn
```

Each run writes a per-case command log and `summary.tsv` under `runs/`. The
runner exits non-zero if any assertion fails. Warning Events are asynchronous,
so each warn case waits up to 30 seconds by default. Set
`EVENT_WAIT_SECONDS` to change that value. Set `EVENT_REASON_REGEX` if the
monitor's Event reason should be constrained further.
