export CONTAINER_RUNTIME ?= docker

.phony: validate

validate:
	$(CONTAINER_RUNTIME) run --rm \
		--volume "${PWD}:/workdir:ro,z" \
		--entrypoint /checkconfig \
		gcr.io/k8s-prow/checkconfig:v20210916-3c87dfedd5 \
		--config-path /workdir/manifests/overlays/metal3/config.yaml \
		--plugin-config /workdir/manifests/overlays/metal3/plugins.yaml \
		--strict
