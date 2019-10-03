.PHONY: all default confirm

all: default

default:
	./sync_labels.sh

confirm:
	export LABEL_SYNC_CONFIRM="--confirm"
	./sync_labels.sh
