# Bookinfo on Kubernetes with Ingress

This experiment exposes Bookinfo through one standard Kubernetes `Ingress`.
The application and MongoDB Services stay internal (`ClusterIP`); do not create a
NodePort, LoadBalancer, Istio Gateway, Gateway API route, or external Service
for them.

## Prerequisite

Install an NGINX Ingress controller and ensure it is registered as the `nginx`
IngressClass.

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
kubectl apply -f bookinfo.yaml
kubectl apply -f bookinfo-ingress.yaml
```

Open `http://<ingress-address>/productpage`. The Ingress also routes the
application's `/static/`, `/login`, `/logout`, and `/api/v1/products` paths to
the `productpage` Service on port 9080.

`reviews-v3` calls `ratings-v2`, which reads the seeded ratings from MongoDB.
MongoDB uses `emptyDir`, so its data resets if its Pod is replaced; it is for
the Bookinfo demonstration, not persistent application data.
