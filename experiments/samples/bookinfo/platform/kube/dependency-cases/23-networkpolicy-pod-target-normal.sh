kubectl --context kind-kube-dep-guard --namespace bookinfo label pod -l app=reviews,version=v3 dependency-case=networkpolicy-pod-target-normal --overwrite
