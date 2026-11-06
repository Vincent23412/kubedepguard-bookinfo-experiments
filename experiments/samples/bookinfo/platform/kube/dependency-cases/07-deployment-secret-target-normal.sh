kubectl --context kind-kube-dep-guard --namespace bookinfo label secret/bookinfo-service-credentials dependency-case=secret-target-normal --overwrite
