kubectl --context kind-kube-dep-guard --namespace bookinfo label service/productpage dependency-case=ingress-service-target-normal --overwrite
