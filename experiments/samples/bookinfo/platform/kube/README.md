# Kubernetes Bookinfo experiment

This experiment exposes Bookinfo through one standard Kubernetes `Ingress`.
The application and MongoDB Services stay internal (`ClusterIP`); do not create a
NodePort, LoadBalancer, Istio Gateway, Gateway API route, or external Service
for them.

## Directory guide

| Path | Purpose |
| --- | --- |
| `kustomization.yaml` and `bookinfo-*.yaml` | The declared Bookinfo baseline, applied together. |
| `dependency-break-tests.sh` | Manually break one relationship, inspect it, then restore. |
| [`mode-profiles/`](mode-profiles/README.md) | Ordered Bookinfo deployment profiles for `enforce` and `warn`. |
| [`dependency-cases/`](dependency-cases/README.md) | 24 single-command cases against the real `bookinfo` namespace; the runner restores Bookinfo after every case. |
| [`mode-cases/`](mode-cases/README.md) | 24 isolated `enforce`/`warn` assertions; each case uses and removes its own temporary namespace. |

## Prerequisites

Install an NGINX Ingress controller and ensure it is registered as the `nginx`
IngressClass. A default StorageClass is also required for the `mongodb-data`
PersistentVolumeClaim.

## Deploy

From the repository root, the standard workflow is:

```sh
make deploy
make status
```

`make deploy` creates the namespace if needed, applies this Kustomization,
waits for the workloads, and runs an in-cluster Productpage smoke test. Open
`http://localhost/productpage` when using the configured kind cluster.

To apply this directory directly to another configured cluster, run:

```sh
kubectl --namespace bookinfo apply -k .
```

If a previous version of this experiment created an Ingress named `gateway`,
remove that obsolete resource first:

```sh
kubectl delete ingress gateway
```

The database-backed configuration supersedes `ratings-v1` and the reviews v1
and v2 variants. Remove those obsolete deployments when upgrading an existing
installation:

```sh
kubectl delete deployment ratings-v1 reviews-v1 reviews-v2 --ignore-not-found
```

Open `http://<ingress-address>/productpage`.
The Ingress also routes the application's `/static/`, `/login`, `/logout`, and
`/api/v1/products` paths to the `productpage` Service on port 9080.

`reviews-v3` calls `ratings-v2`, which reads the seeded ratings from MongoDB.
MongoDB persists data through the `mongodb-data` PersistentVolumeClaim.

## Dependency relationships in Bookinfo

The Bookinfo resources are split by responsibility and deployed together by
`kustomization.yaml`:

| File | Contents |
| --- | --- |
| `bookinfo.yaml` | Core Services, ServiceAccounts, and Deployments |
| `bookinfo-configuration.yaml` | ConfigMaps and Secrets |
| `bookinfo-storage.yaml` | PersistentVolumeClaims |
| `bookinfo-ingress.yaml` | NGINX Ingress |
| `bookinfo-networkpolicy.yaml` | Reviews access-control policy |

The resulting Bookinfo deployment contains these relationships:

| Relationship | Resources |
| --- | --- |
| Deployment → ConfigMap | `productpage-v1` → `bookinfo-service-config` (`DETAILS_HOSTNAME`) |
| Deployment → ConfigMap | `reviews-v3` → `reviews-service-config` (`RATINGS_SERVICE_PORT`) |
| Deployment → Secret | `productpage-v1` → `bookinfo-service-credentials` (`REVIEWS_HOSTNAME`) |
| Deployment → Secret | `reviews-v3` → `reviews-service-credentials` (`RATINGS_HOSTNAME`) |
| Deployment → Secret | `ratings-v2` → `ratings-db-credentials` (`MONGO_DB_URL`) |
| Deployment → PVC | `productpage-v1` → `productpage-workspace` |
| Deployment → PVC | `reviews-v3` → `reviews-logs` |
| Deployment → PVC | `mongodb-v1` → `mongodb-data` |
| Ingress → Service | `bookinfo` → `productpage` |
| Service → Pod | `productpage` → `productpage-v1` |
| NetworkPolicy → Pod | `reviews-from-productpage` → `reviews-v3` Pods |

The ConfigMap and Secret set Productpage's actual Details and Reviews service
hostnames, Reviews' Ratings endpoint, and the Ratings MongoDB connection.
`reviews-from-productpage` permits the normal Productpage → Reviews request on
port 9080 and denies other source Pods. The Reviews `wlp-output` volume remains
an `emptyDir`; it is Pod-local scratch space, not a PersistentVolume or PVC.

## Dependency experiments

| Goal | Command | Scope |
| --- | --- | --- |
| Explore one relationship interactively | `./dependency-break-tests.sh --namespace bookinfo break <relation>` | Changes Bookinfo until `restore` is run. |
| Restore after a manual break | `./dependency-break-tests.sh --namespace bookinfo restore` | Reapplies this Kustomization. |
| Run the dependency command matrix | `./dependency-cases/run-cases.sh` | Restores Bookinfo after every case. |
| Run the matrix with enforcement | `./dependency-cases/run-cases.sh --mode enforce` | Deploys the ordered enforce profile and treats expected rejections as success. |
| Run the matrix with warnings | `./dependency-cases/run-cases.sh --mode warn` | Deploys the warn profile and requires Warning Events for conflict cases. |
| Assert annotation modes | `./mode-cases/run-mode-cases.sh` | Uses a fresh temporary namespace per case. |

`dependency-break-tests.sh` supports `configmap`, `secret`, `pvc`, `ingress`,
`service`, and `networkpolicy`; use `--help` for the expected application or
Kubernetes failure in each case.

The `dependency-cases` and `mode-cases` directories keep per-run stdout/stderr
logs and a `summary.tsv` in their ignored `runs/` directories.
