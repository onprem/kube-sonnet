XARGS ?= xargs
JSONNET ?= jsonnet
GOJSONTOYAML ?= gojsontoyaml

.PHONY: all
all: examples


JSONNET_SRC = $(shell find . -type f -not -path './*vendor/*' \( -name '*.libsonnet' -o -name '*.jsonnet' \))


.PHONY: examples
examples: $(wildcard ingress-nginx/*) $(wildcard nats/*)
	@echo ">>>>> Generating example manifests"
	@for d in $(shell ls -d {ingress-nginx,nats}/examples/*/); do \
		rm -r $${d}/manifests/* || true; \
		$(JSONNET) -J vendor -m $${d}/manifests $${d}/main.jsonnet | $(XARGS) -I{} sh -c 'cat {} | $(GOJSONTOYAML) > {}.yaml' -- {}; \
	done
	$(MAKE) clean


.PHONY: clean
clean:
	@for d in $(shell ls -d {ingress-nginx,nats}/examples/*/); do \
		find $${d}/manifests -type f ! -name '*.yaml' -delete; \
	done
