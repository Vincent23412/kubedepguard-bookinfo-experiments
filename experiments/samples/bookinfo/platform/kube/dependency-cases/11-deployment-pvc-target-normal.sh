kubectl --context kind-kube-dep-guard --namespace bookinfo label pvc/mongodb-data dependency-case=pvc-target-normal --overwrite
