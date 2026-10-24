# Bookinfo base

This directory is a focused subset of Istio's
[Bookinfo sample](https://github.com/istio/istio/tree/master/samples/bookinfo?utm_source=chatgpt.com).
It is kept as the upstream-oriented baseline for this repository. The upstream
license is retained in [LICENSE](LICENSE).

## Included material

- `samples/bookinfo/src/` — source code and build configuration for the
  Productpage, Details, Reviews, Ratings, MongoDB, and MySQL example images.
- `samples/bookinfo/platform/kube/bookinfo.yaml` — the standard Kubernetes
  Services, ServiceAccounts, and Deployments.
- `samples/bookinfo/platform/kube/bookinfo-ingress.yaml` — the upstream Istio
  Ingress example.
- `samples/bookinfo/bookinfo-k8s-architecture.puml` and `.png` — the local
  Kubernetes architecture diagram.

For custom Kubernetes resources and a standard NGINX Ingress configuration,
work in [`../experiments/`](../experiments/README.md) rather than changing this
baseline.
