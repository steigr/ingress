# Copyright 2017 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

.PHONY: all
all: all-container

BUILDTAGS=

# Use the 0.0 tag for testing, it shouldn't clobber any release builds
TAG?=0.15.0
REGISTRY?=quay.io/kubernetes-ingress-controller
GOOS?=linux
DOCKER?=docker
SED_I?=sed -i
GOHOSTOS ?= $(shell go env GOHOSTOS)

# e2e settings
# Allow limiting the scope of the e2e tests. By default run everything
FOCUS?=.*
# number of parallel test
E2E_NODES?=3


ifeq ($(GOHOSTOS),darwin)
  SED_I=sed -i ''
endif

REPO_INFO=$(shell git config --get remote.origin.url)

ifndef COMMIT
  COMMIT := git-$(shell git rev-parse --short HEAD)
endif

PKG=k8s.io/ingress-nginx

ARCH ?= $(shell go env GOARCH)
GOARCH = ${ARCH}
DUMB_ARCH = ${ARCH}

ALL_ARCH = amd64 arm arm64 ppc64le s390x

QEMUVERSION=v2.12.0

BUSTED_ARGS=-v --pattern=_test

IMGNAME = nginx-ingress-controller
IMAGE = $(REGISTRY)/$(IMGNAME)
MULTI_ARCH_IMG = $(IMAGE)-$(ARCH)

# Set default base image dynamically for each arch
BASEIMAGE?=quay.io/kubernetes-ingress-controller/nginx-$(ARCH):0.49

ifeq ($(ARCH),arm)
	QEMUARCH=arm
	GOARCH=arm
	DUMB_ARCH=armhf
endif
ifeq ($(ARCH),arm64)
    QEMUARCH=aarch64
endif
ifeq ($(ARCH),ppc64le)
	QEMUARCH=ppc64le
	GOARCH=ppc64le
	DUMB_ARCH=ppc64el
endif
ifeq ($(ARCH),s390x)
    QEMUARCH=s390x
endif

TEMP_DIR := $(shell mktemp -d)

DOCKERFILE := $(TEMP_DIR)/rootfs/Dockerfile

.PHONY: image-info
image-info:
	echo -n '{"image":"$(IMAGE)","tag":"$(TAG)"}'

.PHONY: sub-container-%
sub-container-%:
	$(MAKE) ARCH=$* build container

.PHONY: sub-push-%
sub-push-%:
	$(MAKE) ARCH=$* push

.PHONY: all-container
all-container: $(addprefix sub-container-,$(ALL_ARCH))

.PHONY: all-push
all-push: $(addprefix sub-push-,$(ALL_ARCH))

.PHONY: container
container: .container-$(ARCH)

.PHONY: .container-$(ARCH)
.container-$(ARCH):
	cp -RP ./* $(TEMP_DIR)
	$(SED_I) "s|BASEIMAGE|$(BASEIMAGE)|g" $(DOCKERFILE)
	$(SED_I) "s|QEMUARCH|$(QEMUARCH)|g" $(DOCKERFILE)
	$(SED_I) "s|DUMB_ARCH|$(DUMB_ARCH)|g" $(DOCKERFILE)

ifeq ($(ARCH),amd64)
	# When building "normally" for amd64, remove the whole line, it has no part in the amd64 image
	$(SED_I) "/CROSS_BUILD_/d" $(DOCKERFILE)
else
	# When cross-building, only the placeholder "CROSS_BUILD_" should be removed
	curl -sSL https://github.com/multiarch/qemu-user-static/releases/download/$(QEMUVERSION)/x86_64_qemu-$(QEMUARCH)-static.tar.gz | tar -xz -C $(TEMP_DIR)/rootfs
	$(SED_I) "s/CROSS_BUILD_//g" $(DOCKERFILE)
endif

	$(DOCKER) build -t $(MULTI_ARCH_IMG):$(TAG) $(TEMP_DIR)/rootfs

ifeq ($(ARCH), amd64)
	# This is for maintaining backward compatibility
	$(DOCKER) tag $(MULTI_ARCH_IMG):$(TAG) $(IMAGE):$(TAG)
endif

.PHONY: register-qemu
register-qemu:
	# Register /usr/bin/qemu-ARCH-static as the handler for binaries in multiple platforms
	$(DOCKER) run --rm --privileged multiarch/qemu-user-static:register --reset

.PHONY: push
push: .push-$(ARCH)

.PHONY: .push-$(ARCH)
.push-$(ARCH):
	$(DOCKER) push $(MULTI_ARCH_IMG):$(TAG)
ifeq ($(ARCH), amd64)
	$(DOCKER) push $(IMAGE):$(TAG)
endif

.PHONY: clean
clean:
	$(DOCKER) rmi -f $(MULTI_ARCH_IMG):$(TAG) || true

.PHONY: build
build: clean
	CGO_ENABLED=0 GOOS=${GOOS} GOARCH=${GOARCH} go build -a -installsuffix cgo \
		-ldflags "-s -w -X ${PKG}/version.RELEASE=${TAG} -X ${PKG}/version.COMMIT=${COMMIT} -X ${PKG}/version.REPO=${REPO_INFO}" \
		-o ${TEMP_DIR}/rootfs/nginx-ingress-controller ${PKG}/cmd/nginx

.PHONY: verify-all
verify-all:
	@./hack/verify-all.sh

.PHONY: test
test:
	@go test -v -race -tags "$(BUILDTAGS) cgo" $(shell go list ${PKG}/... | grep -v vendor | grep -v '/test/e2e')

.PHONY: lua-test
lua-test:
	@busted $(BUSTED_ARGS) ./rootfs/etc/nginx/lua/test;

.PHONY: e2e-test
e2e-test:
	@ginkgo version || go get -u github.com/onsi/ginkgo/ginkgo
	@ginkgo build ./test/e2e
	@KUBECONFIG=${HOME}/.kube/config ginkgo \
		-randomizeSuites \
		-randomizeAllSpecs \
		-flakeAttempts=2 \
		--focus=$(FOCUS) \
		-p \
		-trace \
		-nodes=$(E2E_NODES) \
		./test/e2e/e2e.test

.PHONY: cover
cover:
	@rm -rf coverage.txt
	@for d in `go list ./... | grep -v vendor | grep -v '/test/e2e' | grep -v 'images/grpc-fortune-teller'`; do \
		t=$$(date +%s); \
		go test -coverprofile=cover.out -covermode=atomic $$d || exit 1; \
		echo "Coverage test $$d took $$(($$(date +%s)-t)) seconds"; \
		if [ -f cover.out ]; then \
			cat cover.out >> coverage.txt; \
			rm cover.out; \
		fi; \
	done
	@echo "Uploading coverage results..."
	@curl -s https://codecov.io/bash | bash

.PHONY: vet
vet:
	@go vet $(shell go list ${PKG}/... | grep -v vendor)

.PHONY: luacheck
luacheck:
	luacheck -q ./rootfs/etc/nginx/lua/

.PHONY: release
release: all-container all-push
	echo "done"

.PHONY: docker-build
docker-build: all-container

.PHONY: docker-push
docker-push: all-push

.PHONY: check_dead_links
check_dead_links:
	docker run -t -v $$PWD:/tmp aledbf/awesome_bot:0.1 --allow-dupe --allow-redirect $(shell find $$PWD -mindepth 1 -name "*.md" -printf '%P\n' | grep -v vendor | grep -v Changelog.md)

.PHONY: dep-ensure
dep-ensure:
	dep version || go get -u github.com/golang/dep/cmd/dep
	dep ensure -v
	dep prune -v
	find vendor -name '*_test.go' -delete

.PHONY: dev-env
dev-env:
	@./hack/build-dev-env.sh

.PHONY: live-docs
live-docs:
	@docker run --rm -it -p 3000:3000 -v ${PWD}:/docs aledbf/mkdocs:0.1

.PHONY: build-docs
build-docs:
	@docker run --rm -it -v ${PWD}:/docs aledbf/mkdocs:0.1 build
