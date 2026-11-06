KUBECTL ?= kubectl
KIND ?= kind
KIND_CLUSTER ?= kube-dep-guard
KUBE_CONTEXT ?= kind-$(KIND_CLUSTER)
NAMESPACE ?= bookinfo
MANIFEST_DIR := experiments/samples/bookinfo/platform/kube
DEPLOYMENTS := details-v1 productpage-v1 reviews-v3 ratings-v2 mongodb-v1
INGRESS_NGINX_VERSION ?= controller-v1.15.1
INGRESS_NGINX_MANIFEST := https://raw.githubusercontent.com/kubernetes/ingress-nginx/$(INGRESS_NGINX_VERSION)/deploy/static/provider/kind/deploy.yaml

.DEFAULT_GOAL := help
.PHONY: help create-cluster recreate-cluster render deploy status verify smoke-test install-ingress ingress-status ingress-forward delete

help: ## Show available commands.
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "%-10s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

create-cluster: ## Create the configured kind cluster and install NGINX Ingress.
	$(KIND) create cluster --name $(KIND_CLUSTER) --config kind/cluster.yaml
	$(KUBECTL) --context $(KUBE_CONTEXT) label node $(KIND_CLUSTER)-control-plane ingress-ready=true
	@$(MAKE) --no-print-directory install-ingress

recreate-cluster: ## Replace the legacy kind cluster with the configured cluster.
	$(KIND) delete cluster --name kind
	@$(MAKE) --no-print-directory create-cluster

render: ## Render the Bookinfo manifests with Kustomize.
	$(KUBECTL) --context $(KUBE_CONTEXT) kustomize $(MANIFEST_DIR)

deploy: ## Create NAMESPACE if needed and deploy Bookinfo.
	@$(KUBECTL) --context $(KUBE_CONTEXT) get namespace $(NAMESPACE) >/dev/null 2>&1 || $(KUBECTL) --context $(KUBE_CONTEXT) create namespace $(NAMESPACE)
	$(KUBECTL) --context $(KUBE_CONTEXT) apply --namespace $(NAMESPACE) -k $(MANIFEST_DIR)
	@$(MAKE) --no-print-directory verify
	@$(MAKE) --no-print-directory smoke-test

status: ## Show Bookinfo workload and networking resources.
	$(KUBECTL) --context $(KUBE_CONTEXT) --namespace $(NAMESPACE) get deployments,pods,services,ingress,networkpolicy,pvc

verify: ## Wait for all Deployments to become available and show their status.
	@set -e; for deployment in $(DEPLOYMENTS); do \
		$(KUBECTL) --context $(KUBE_CONTEXT) --namespace $(NAMESPACE) rollout status deployment/$$deployment --timeout=180s; \
	done
	@$(MAKE) --no-print-directory status

smoke-test: ## Request Productpage from inside the cluster and require HTTP 200.
	$(KUBECTL) --context $(KUBE_CONTEXT) --namespace $(NAMESPACE) exec deployment/productpage-v1 -- python -c "import urllib.request; response = urllib.request.urlopen('http://productpage:9080/productpage', timeout=10); print('Productpage HTTP', response.status); assert response.status == 200"

install-ingress: ## Install the pinned official NGINX Ingress Controller and wait for it.
	$(KUBECTL) --context $(KUBE_CONTEXT) apply -f $(INGRESS_NGINX_MANIFEST)
	$(KUBECTL) --context $(KUBE_CONTEXT) --namespace ingress-nginx wait --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=180s

ingress-status: ## Confirm that the cluster has the required NGINX IngressClass.
	$(KUBECTL) --context $(KUBE_CONTEXT) get ingressclass nginx
	$(KUBECTL) --context $(KUBE_CONTEXT) --namespace $(NAMESPACE) get ingress bookinfo

ingress-forward: ## Forward localhost:8080 to the NGINX Ingress Controller.
	$(KUBECTL) --context $(KUBE_CONTEXT) --namespace ingress-nginx port-forward service/ingress-nginx-controller 8080:80

delete: ## Remove the Bookinfo resources, preserving the namespace itself.
	$(KUBECTL) --context $(KUBE_CONTEXT) delete --ignore-not-found --namespace $(NAMESPACE) -k $(MANIFEST_DIR)
