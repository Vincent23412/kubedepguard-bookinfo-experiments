# Bookinfo on Kubernetes with Ingress

This experiment exposes Bookinfo through one standard Kubernetes `Ingress`.
The application and MongoDB Services stay internal (`ClusterIP`); do not create a
NodePort, LoadBalancer, Istio Gateway, Gateway API route, or external Service
for them.

## Prerequisite

Install an NGINX Ingress controller and ensure it is registered as the `nginx`
IngressClass. A default StorageClass is also required for the `mongodb-data`
PersistentVolumeClaim.

## Deploy

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

```sh
kubectl apply -k .
```

Open `http://<ingress-address>/productpage`. The Ingress also routes the
application's `/static/`, `/login`, `/logout`, and `/api/v1/products` paths to
the `productpage` Service on port 9080.

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

## Dependency break experiments

Use `dependency-break-tests.sh` to intentionally sever one relationship, view
the resulting Kubernetes or application failure, then restore the declared
Bookinfo state. The script reapplies `kustomization.yaml`, requires an explicit
relation and namespace, and documents its options with `--help`.
