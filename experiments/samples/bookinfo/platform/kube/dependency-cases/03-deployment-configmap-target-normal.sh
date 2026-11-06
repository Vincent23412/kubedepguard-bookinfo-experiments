kubectl --context kind-kube-dep-guard --namespace bookinfo label configmap/bookinfo-service-config dependency-case=configmap-target-normal --overwrite
