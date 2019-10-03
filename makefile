PROJECT_NAME = skaffold-debug-go-demo
BINARY_PREFIX = ${PROJECT_NAME}
IMAGE_PREFIX = cage1016/${BINARY_PREFIX}
BUILD_DIR = build
SERVICES = addsvc
DOCKERS_CLEANBUILD = $(addprefix cleanbuild_docker_,$(SERVICES))
DOCKERS = $(addprefix dev_docker_,$(SERVICES))
DOCKERS_DEBUG = $(addprefix debug_docker_,$(SERVICES))
STAGES = dev debug prod
CGO_ENABLED ?= 0
GOOS ?= linux
DEBUG_GOGCFLAGS = -gcflags='all=-N -l'
GOGCFLAGS = -ldflags '-s -w'

define compile_service
	CGO_ENABLED=$(CGO_ENABLED) GOOS=$(GOOS) GOARCH=$(GOARCH) GOARM=$(GOARM) go build $(2) -o ${BUILD_DIR}/${BINARY_PREFIX}-$(1) cmd/$(1)/main.go
endef

define make_docker_cleanbuild
	docker build --no-cache --build-arg PROJECT_NAME=${PROJECT_NAME} --build-arg BINARY=${BINARY_PREFIX}-$(1) --tag=${IMAGE_PREFIX}-$(1) -f deployments/docker/Dockerfile.cleanbuild .
endef

define make_docker
	docker build --build-arg BINARY=${BINARY_PREFIX}-$(1) --tag=${IMAGE_PREFIX}-$(1) -f deployments/docker/$(2) ./build
endef

all: $(SERVICES)

.PHONY: all $(SERVICES) dev_dockers debug_dockers cleanbuild_dockers

cleandocker:
	# Remove skaffold-debug-go-demo containers
	docker ps -f name=${IMAGE_PREFIX}-* -aq | xargs docker rm
	# Remove old skaffold-debug-go-demo images
	docker images -q ${IMAGE_PREFIX}-* | xargs docker rmi

# Clean ghost docker images
cleanghost:
	# Remove exited containers
	docker ps -f status=dead -f status=exited -aq | xargs docker rm -v
	# Remove unused images
	docker images -f dangling=true -q | xargs docker rmi
	# Remove unused volumes
	docker volume ls -f dangling=true -q | xargs docker volume rm

install:
	cp ${BUILD_DIR}/* $(GOBIN)

test:
	go test -v -race -tags test $(shell go list ./... | grep -v 'vendor\|cmd')

PD_SOURCES:=$(shell find ./pb -type d)
proto:
	@for var in $(PD_SOURCES); do \
		if [ -f "$$var/compile.sh" ]; then \
			cd $$var && ./compile.sh; \
			echo "complie $$var/$$(basename $$var).proto"; \
			cd $(PWD); \
		fi \
	done

# Regenerates OPA data from rego files
HAVE_GO_BINDATA := $(shell command -v go-bindata 2> /dev/null)
generate:
ifndef HAVE_GO_BINDATA
	@echo "requires 'go-bindata' (go get -u github.com/kevinburke/go-bindata/go-bindata)"
	@exit 1 # fail
else
	go generate ./...
endif

$(SERVICES):
	$(call compile_service,$(@),${GOGCFLAGS})

$(DOCKERS_CLEANBUILD):
	$(call make_docker_cleanbuild,$(subst cleanbuild_docker_,,$(@)))

$(DOCKERS):
	$(call compile_service,$(subst dev_docker_,,$(@)),${GOGCFLAGS})
	$(call make_docker,$(subst dev_docker_,,$(@)),Dockerfile)

$(DOCKERS_DEBUG):
	$(call compile_service,$(subst debug_docker_,,$(@)),${DEBUG_GOGCFLAGS})
	$(call make_docker,$(subst debug_docker_,,$(@)),Dockerfile.debug)

services: $(SERVICES)

dev_dockers: $(DOCKERS)

debug_dockers: $(DOCKERS_DEBUG)

cleanbuild_dockers: $(DOCKERS_CLEANBUILD)

sum:
	curl -X "POST" "http://localhost:8020/sum" -H 'Content-Type: application/json; charset=utf-8' -d '{ "a": 3, "b": 34}'

concat:
	curl -X "POST" "http://localhost:8020/concat" -H 'Content-Type: application/json; charset=utf-8' -d '{ "a": "3", "b": "34"}'