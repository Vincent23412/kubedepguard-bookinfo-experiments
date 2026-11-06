# Dependency cases

Each case targets the active `kind-kube-dep-guard` cluster and its `bookinfo`
namespace.

| Relationship | Source | Target |
| --- | --- | --- |
| Deployment → ConfigMap | `deployment/productpage-v1` | `configmap/bookinfo-service-config` |
| Deployment → Secret | `deployment/productpage-v1` | `secret/bookinfo-service-credentials` |
| Deployment → PVC | `deployment/mongodb-v1` | `pvc/mongodb-data` |
| Ingress → Service | `ingress/bookinfo` | `service/productpage` |
| Service → Pod | `service/productpage` | Productpage Pods |
| NetworkPolicy → Pod | `networkpolicy/reviews-from-productpage` | Reviews Pods |

`*-source-normal.sh` creates a new source resource that references an existing
target. `*-source-conflict.sh` creates the same kind of source resource but
references a target that does not exist.

`*-target-normal.sh` adds a label to the current target while its Bookinfo
source still exists. `*-target-conflict.sh` deletes a target that is still
referenced by its source.
For the Pod relationships, it deletes the selected Productpage or Reviews Pod.

## Run with automatic restoration and logs

Use `run-cases.sh` to run every case. It restores the environment after every
case, including a case whose command fails, so the next case starts from the
declared Bookinfo baseline.

```sh
./run-cases.sh
```

Run the same matrix under a dependency mode profile:

```sh
./run-cases.sh --mode enforce
./run-cases.sh --mode warn
```

The profile is deployed before the first case and reapplied after every case.
For conflict cases, an `enforce` rejection is recorded as success. A `warn`
case must be accepted and produce a new Warning Event on the source resource.

To run selected cases, pass their filenames:

```sh
./run-cases.sh 01-deployment-configmap-source-normal.sh 04-deployment-configmap-target-conflict.sh
```

Each run writes timestamped per-case logs and a `summary.tsv` under `runs/`
(or under `$RUNS_DIR` when set). The summary records the expected and actual
API result, Event result, restoration exit status, and success state. The log
contains the traced `kubectl` command plus its standard output and error output.

Use `restore-environment.sh` alone to manually reset the Bookinfo environment.
It removes `case-*` resources, reapplies and verifies the declared Bookinfo
manifests, and removes the temporary `dependency-case` labels. The temporary
PVC source case mounts `mongodb-data`; run it only when a second consumer of
that claim is acceptable.
