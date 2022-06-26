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
	@for d in $(shell ls ingress-nginx/examples); do \
		rm -r ingress-nginx/examples/$${d}/manifests/*; \
		$(JSONNET) -J vendor -m ingress-nginx/examples/$${d}/manifests ingress-nginx/examples/$${d}/main.jsonnet | $(XARGS) -I{} sh -c 'cat {} | $(GOJSONTOYAML) > {}.yaml' -- {}; \
	done


.PHONY: clean
clean:
	@for d in $(shell ls ingress-nginx/examples); do \
		find ingress-nginx/examples/$${d}/manifests -type f ! -name '*.yaml' -delete; \
	done
