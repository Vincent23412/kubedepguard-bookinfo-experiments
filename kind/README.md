# kind development environment

This directory contains optional kind-only helpers. It is separate from
KubeDepGuard's application deployment and can be moved to the repository that
owns local cluster infrastructure.

```sh
./tools/kind/create-cluster.sh kube-dep-guard
IMAGE_TAG=dev ./tools/kind/load-kubedepguard-images.sh kube-dep-guard
```

For a non-kind cluster, provide the KubeDepGuard images through the cluster
project's normal image-delivery process, then run `make deploy` against that
cluster's current context.
