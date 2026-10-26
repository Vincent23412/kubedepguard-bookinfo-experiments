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
- `ratings-v2` reads ratings from the internal `mongodb` Service. The MongoDB
  data volume is intentionally ephemeral for this demo.

## Suggested workflow

Keep upstream-oriented files in `base/`. Add or change manifests in this
directory for project-specific Kubernetes experiments.

The Ingress-only Bookinfo architecture diagram is at
`samples/bookinfo/bookinfo-k8s-architecture.puml` and the compiled PNG sits
beside it.
