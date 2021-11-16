export CONTAINER_RUNTIME ?= docker

.phony: update-config update-plugins update-labels validate

update-config:
	kubectl create configmap config -n prow --from-file=config.yaml=config/config.yaml --dry-run=client -o yaml | kubectl replace configmap -n prow config -f -

update-plugins:
	kubectl create configmap plugins -n prow --from-file=plugins.yaml=config/plugins.yaml --dry-run=client -o yaml | kubectl replace configmap -n prow plugins -f -

update-labels:
	kubectl create configmap label-config --from-file=labels.yaml=config/labels.yaml --dry-run=client -o yaml | kubectl replace configmap label-config -f -

validate:
	$(CONTAINER_RUNTIME) run --rm \
		--volume "${PWD}:/workdir:ro,z" \
		--entrypoint /checkconfig \
		gcr.io/k8s-prow/checkconfig:v20210916-3c87dfedd5 \
		--config-path /workdir/config/config.yaml \
		--plugin-config /workdir/config/plugins.yaml \
		--strict
