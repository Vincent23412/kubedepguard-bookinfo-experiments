# Kubedepguard Bookinfo Experiments

This repository contains a focused Bookinfo baseline and a separate workspace
for Kubernetes experiments.

- [`base/`](base/README.md) is a trimmed, source-preserving subset of Istio's
  [Bookinfo sample](https://github.com/istio/istio/tree/master/samples/bookinfo?utm_source=chatgpt.com).
- [`experiments/`](experiments/README.md) is copied from `base/` and is the
  place for additional Kubernetes resources and configuration changes.

The `base/` directory should remain close to the selected upstream Bookinfo
baseline. Put experiment-specific manifests, storage, traffic rules, or other
custom resources under `experiments/`.
