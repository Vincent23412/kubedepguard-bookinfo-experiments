kubectl --context kind-kube-dep-guard --namespace bookinfo label pod -l app=productpage,version=v1 dependency-case=service-pod-target-normal --overwrite
