.phony: update-config update-plugins validate

update-config:
	kubectl create configmap config --from-file=config.yaml=config/config.yaml --dry-run=client -o yaml | kubectl replace configmap config -f -

update-plugins:
	kubectl create configmap plugins --from-file=plugins.yaml=config/plugins.yaml --dry-run=client -o yaml | kubectl replace configmap plugins -f -

update-labels:
	kubectl create configmap labels-config --from-file=labels.yaml=config/labels.yaml --dry-run=client -o yaml | kubectl replace configmap labels-config -f -

validate:
	podman run --rm \
		--volume "${PWD}:/workdir:ro,z" \
		--entrypoint /checkconfig \
		gcr.io/k8s-prow/checkconfig:v20210409-985ef5e721 \
		--config-path /workdir/config/config.yaml \
		--plugin-config /workdir/config/plugins.yaml \
		--strict
