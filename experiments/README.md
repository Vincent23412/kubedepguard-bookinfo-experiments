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
