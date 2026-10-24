# Bookinfo experiments

This directory began as a copy of [`../base/`](../base/README.md), the trimmed
Istio [Bookinfo sample](https://github.com/istio/istio/tree/master/samples/bookinfo?utm_source=chatgpt.com).
Use it for project-specific Kubernetes experiments and additional resources.

## Current differences from `base/`

- `samples/bookinfo/platform/kube/bookinfo-ingress.yaml` uses
  `ingressClassName: nginx`, so it works with a standard NGINX Ingress
  controller instead of the upstream Istio Ingress example.

## Suggested workflow

Keep upstream-oriented files in `base/`. Add or change manifests in this
directory for experiments such as PersistentVolumeClaims, databases, traffic
policies, observability, or deployment variants.

The Bookinfo architecture diagram is retained at
`samples/bookinfo/bookinfo-k8s-architecture.puml` and the compiled PNG sits
beside it.
