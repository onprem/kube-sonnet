XARGS ?= xargs
JSONNET ?= jsonnet
GOJSONTOYAML ?= gojsontoyaml

.PHONY: all
all: examples


JSONNET_SRC = $(shell find . -type f -not -path './*vendor/*' \( -name '*.libsonnet' -o -name '*.jsonnet' \))


.PHONY: examples
examples: ingress-nginx-examples
	$(MAKE) clean


.PHONY: ingress-nginx-examples
ingress-nginx-examples: $(wildcard ingress-nginx/*)
	@echo ">>>>> Generating examples for ingress-nginx"
	@for d in $(shell ls -d ingress-nginx/examples/*/); do \
		rm -r $${d}/manifests/*; \
		$(JSONNET) -J vendor -m $${d}/manifests $${d}/main.jsonnet | $(XARGS) -I{} sh -c 'cat {} | $(GOJSONTOYAML) > {}.yaml' -- {}; \
	done


.PHONY: clean
clean:
	@for d in $(shell ls -d ingress-nginx/examples/*/); do \
		find $${d}/manifests -type f ! -name '*.yaml' -delete; \
	done