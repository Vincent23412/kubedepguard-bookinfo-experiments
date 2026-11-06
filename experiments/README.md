# Bookinfo experiments

This directory began as a copy of [`../base/`](../base/README.md), the trimmed
Istio [Bookinfo sample](https://github.com/istio/istio/tree/master/samples/bookinfo?utm_source=chatgpt.com).
Use it for project-specific Kubernetes experiments and additional resources.

## Current differences from `base/`

- Bookinfo has one external entry point: the `bookinfo` Kubernetes Ingress in
  `samples/bookinfo/platform/kube/bookinfo-ingress.yaml`. It targets an NGINX
  Ingress controller (`ingressClassName: nginx`) and routes only to the
  internal `productpage` Service.
- The architecture does not include Istio Gateway, Gateway API,
  VirtualService, DestinationRule, sidecars, or NodePort/LoadBalancer
  application Services.
- `ratings-v2` reads ratings from the internal `mongodb` Service, which stores
  data through the `mongodb-data` PersistentVolumeClaim.

## Suggested workflow

Keep upstream-oriented files in `base/`. Add or change manifests in this
directory for project-specific Kubernetes experiments.

The Makefile targets the `kube-dep-guard` cluster (`kind-kube-dep-guard`
context) by default. Its [kind configuration](../kind/cluster.yaml) creates
one control-plane and two worker nodes, and maps host ports 80 and 443 to the
control-plane for NGINX Ingress. Create a new cluster, if needed, with:

```sh
make create-cluster
```

To replace a legacy cluster named `kind`, use `make recreate-cluster`; this
deletes that cluster and all of its workloads.

Then deploy the experiment from the repository root:

```sh
make deploy
```

This creates the `bookinfo` namespace if necessary, applies the Kustomization,
waits for all five Deployments, and performs an in-cluster Productpage smoke
test. Use `make status`, `make render`, or set a different namespace with
`make deploy NAMESPACE=my-bookinfo`.

`make create-cluster` installs the pinned NGINX Ingress Controller; check it
with `make ingress-status`. With the kind port mappings, open
`http://localhost/productpage` directly; `make ingress-forward` remains
available for a local port-forward on 8080.

The Ingress-only Bookinfo architecture diagram is at
`samples/bookinfo/bookinfo-k8s-architecture.puml` and the compiled PNG sits
beside it.

The Bookinfo manifests themselves also include Deployment → ConfigMap,
Deployment → Secret, Deployment → PVC, Ingress → Service, Service → Pod, and
NetworkPolicy → Pod relationships. Those relationships drive Productpage's
Details/Reviews calls, MongoDB storage, and Reviews access control; they can
be intentionally broken and restored with the platform-kube experiment script.
See its
[architecture diagram](samples/bookinfo/bookinfo-k8s-architecture.png).
