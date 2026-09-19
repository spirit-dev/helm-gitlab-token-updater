.ONESHELL:

# Service
NAMESPACE = gitlab-next
RELEASE_NAME = gitlab-token-updater-turingpi
# ENV ?= ### Specify the env to use
ENV = turingpi
pod := $$(kubectl get pods -n ${NAMESPACE} |  grep -m1 ${RELEASE_NAME} | cut -d' ' -f1)

# Current dir
CURRENT_DIR = $(shell pwd)
HELM_CHART_DIR = ${CURRENT_DIR}/helm

# HELM
HELM_BIN ?= helm
FORCE ?=
ifeq ($(strip ${FORCE}),true)
SET_FORCE := --force
else
SET_FORCE :=
endif

help:
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make \033[36m<command> <option>\033[0m\n"} /^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
	@printf "\033[1mVariables\033[0m\n"
	@grep -E '^[a-zA-Z0-9_-]+.*?### .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?### "}; {printf "  \033[36m%-21s\033[0m %s\n", $$1, $$2}'
	@# Use ##@ <section> to define a section
	@# Use ## <comment> aside of the target to get it shown in the helper
	@# Use ### <comment> to comment a variable

##@ Installation part
warning: ## A warning to make you warned
	@echo -e "$$(cat ARGOCD-OWNED)\n"
	@exit 1
template: ## Helm template
	@${HELM_BIN} template --dependency-update ${RELEASE_NAME} ${HELM_CHART_DIR} --namespace ${NAMESPACE} -f ${HELM_CHART_DIR}/values.${ENV}.yaml
dry-run: template warning ## Template plus dry-run of the helm chart
	@${HELM_BIN} upgrade --dry-run ${SET_FORCE} --install --namespace ${NAMESPACE} -f ${HELM_CHART_DIR}/values.${ENV}.yaml ${RELEASE_NAME} ${HELM_CHART_DIR}
install: warning ## Helm intallation
	@${HELM_BIN} upgrade ${SET_FORCE} --install --namespace ${NAMESPACE} --create-namespace -f ${HELM_CHART_DIR}/values.${ENV}.yaml ${RELEASE_NAME} ${HELM_CHART_DIR}
logs: ## Get pod logs
	@kubectl logs --since=1h -f -n ${NAMESPACE} $(pod)
