export CONTAINER_RUNTIME ?= docker

.phony: validate

validate:
	$(CONTAINER_RUNTIME) run --rm \
		--volume "${PWD}:/workdir:ro,z" \
		--entrypoint /ko-app/checkconfig \
		us-docker.pkg.dev/k8s-infra-prow/images/checkconfig:v20250626-3e50f2237 \
		--config-path /workdir/config/config.yaml \
		--job-config-path /workdir/config/jobs \
		--plugin-config /workdir/config/plugins.yaml \
		--strict
