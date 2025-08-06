export CONTAINER_RUNTIME ?= docker

.phony: validate

validate:
	$(CONTAINER_RUNTIME) run --rm \
		--volume "${PWD}:/workdir:ro,z" \
		--entrypoint /ko-app/checkconfig \
		us-docker.pkg.dev/k8s-infra-prow/images/checkconfig:v20250709-d01b8af18 \
		--config-path /workdir/config/config.yaml \
		--job-config-path /workdir/config/jobs \
		--plugin-config /workdir/config/plugins.yaml \
		--strict
