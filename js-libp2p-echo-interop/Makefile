# Makefile for JS-libp2p Echo Interoperability Tests
# Follows libp2p/test-plans conventions for container builds and caching

# Configuration
PROJECT_NAME := js-libp2p-echo-interop
DOCKER_REGISTRY ?= 
IMAGE_TAG ?= latest
BUILD_DATE := $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_COMMIT := $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")

# Image names
JS_SERVER_IMAGE := js-libp2p-echo-server
PY_CLIENT_IMAGE := py-test-harness

# Build arguments
DOCKER_BUILD_ARGS := --build-arg BUILD_DATE=$(BUILD_DATE) \
                     --build-arg GIT_COMMIT=$(GIT_COMMIT)

# Cache configuration
CACHE_FROM_JS := 
CACHE_FROM_PY := 
CACHE_TO_JS := 
CACHE_TO_PY := 

# Multi-architecture support
PLATFORMS ?= linux/amd64,linux/arm64
BUILDX_BUILDER ?= multiarch

# Test configuration
TEST_TIMEOUT ?= 300
COMPOSE_FILE ?= docker-compose.yml

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
NC := \033[0m

# Default target
.PHONY: all
all: build

# Help target
.PHONY: help
help: ## Show this help message
	@echo "JS-libp2p Echo Interoperability Tests - Makefile"
	@echo ""
	@echo "Usage: make [target] [options]"
	@echo ""
	@echo "Targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(BLUE)%-20s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "Options:"
	@echo "  $(BLUE)IMAGE_TAG$(NC)        Docker image tag (default: latest)"
	@echo "  $(BLUE)DOCKER_REGISTRY$(NC)  Docker registry prefix"
	@echo "  $(BLUE)PLATFORMS$(NC)        Target platforms for multi-arch builds"
	@echo "  $(BLUE)TEST_TIMEOUT$(NC)     Test timeout in seconds (default: 300)"
	@echo ""
	@echo "Examples:"
	@echo "  make build                    # Build all images"
	@echo "  make build-js                 # Build JS server only"
	@echo "  make test                     # Run all tests"
	@echo "  make push IMAGE_TAG=v1.0.0    # Build and push with tag"

# Build targets
.PHONY: build
build: build-js build-py ## Build all Docker images

.PHONY: build-js
build-js: ## Build JS Echo Server image
	@echo "$(BLUE)[BUILD]$(NC) Building JS Echo Server image..."
	@cd images/js-echo-server && \
	docker build \
		$(DOCKER_BUILD_ARGS) \
		$(if $(CACHE_FROM_JS),--cache-from $(CACHE_FROM_JS)) \
		$(if $(CACHE_TO_JS),--cache-to $(CACHE_TO_JS)) \
		-t $(JS_SERVER_IMAGE):$(IMAGE_TAG) \
		$(if $(DOCKER_REGISTRY),-t $(DOCKER_REGISTRY)/$(JS_SERVER_IMAGE):$(IMAGE_TAG)) \
		.
	@echo "$(GREEN)[SUCCESS]$(NC) JS Echo Server image built successfully"

.PHONY: build-py
build-py: ## Build Python Test Harness image
	@echo "$(BLUE)[BUILD]$(NC) Building Python Test Harness image..."
	@cd images/py-test-harness && \
	docker build \
		$(DOCKER_BUILD_ARGS) \
		$(if $(CACHE_FROM_PY),--cache-from $(CACHE_FROM_PY)) \
		$(if $(CACHE_TO_PY),--cache-to $(CACHE_TO_PY)) \
		-t $(PY_CLIENT_IMAGE):$(IMAGE_TAG) \
		$(if $(DOCKER_REGISTRY),-t $(DOCKER_REGISTRY)/$(PY_CLIENT_IMAGE):$(IMAGE_TAG)) \
		.
	@echo "$(GREEN)[SUCCESS]$(NC) Python Test Harness image built successfully"

# Multi-architecture build targets
.PHONY: buildx-setup
buildx-setup: ## Set up Docker buildx for multi-architecture builds
	@echo "$(BLUE)[BUILDX]$(NC) Setting up multi-architecture builder..."
	@docker buildx create --name $(BUILDX_BUILDER) --use --bootstrap 2>/dev/null || \
	 docker buildx use $(BUILDX_BUILDER) 2>/dev/null || \
	 (echo "$(YELLOW)[WARNING]$(NC) Using default buildx builder" && docker buildx use default)
	@docker buildx inspect --bootstrap

.PHONY: buildx
buildx: buildx-setup buildx-js buildx-py ## Build multi-architecture images

.PHONY: buildx-js
buildx-js: buildx-setup ## Build JS Echo Server for multiple architectures
	@echo "$(BLUE)[BUILDX]$(NC) Building JS Echo Server for $(PLATFORMS)..."
	@cd images/js-echo-server && \
	docker buildx build \
		--platform $(PLATFORMS) \
		$(DOCKER_BUILD_ARGS) \
		$(if $(CACHE_FROM_JS),--cache-from $(CACHE_FROM_JS)) \
		$(if $(CACHE_TO_JS),--cache-to $(CACHE_TO_JS)) \
		-t $(JS_SERVER_IMAGE):$(IMAGE_TAG) \
		$(if $(DOCKER_REGISTRY),-t $(DOCKER_REGISTRY)/$(JS_SERVER_IMAGE):$(IMAGE_TAG)) \
		--load \
		.

.PHONY: buildx-py
buildx-py: buildx-setup ## Build Python Test Harness for multiple architectures
	@echo "$(BLUE)[BUILDX]$(NC) Building Python Test Harness for $(PLATFORMS)..."
	@cd images/py-test-harness && \
	docker buildx build \
		--platform $(PLATFORMS) \
		$(DOCKER_BUILD_ARGS) \
		$(if $(CACHE_FROM_PY),--cache-from $(CACHE_FROM_PY)) \
		$(if $(CACHE_TO_PY),--cache-to $(CACHE_TO_PY)) \
		-t $(PY_CLIENT_IMAGE):$(IMAGE_TAG) \
		$(if $(DOCKER_REGISTRY),-t $(DOCKER_REGISTRY)/$(PY_CLIENT_IMAGE):$(IMAGE_TAG)) \
		--load \
		.

# Push targets
.PHONY: push
push: build push-js push-py ## Build and push all images

.PHONY: push-js
push-js: ## Push JS Echo Server image
	@if [ -z "$(DOCKER_REGISTRY)" ]; then \
		echo "$(RED)[ERROR]$(NC) DOCKER_REGISTRY must be set to push images"; \
		exit 1; \
	fi
	@echo "$(BLUE)[PUSH]$(NC) Pushing JS Echo Server image..."
	@docker push $(DOCKER_REGISTRY)/$(JS_SERVER_IMAGE):$(IMAGE_TAG)
	@echo "$(GREEN)[SUCCESS]$(NC) JS Echo Server image pushed successfully"

.PHONY: push-py
push-py: ## Push Python Test Harness image
	@if [ -z "$(DOCKER_REGISTRY)" ]; then \
		echo "$(RED)[ERROR]$(NC) DOCKER_REGISTRY must be set to push images"; \
		exit 1; \
	fi
	@echo "$(BLUE)[PUSH]$(NC) Pushing Python Test Harness image..."
	@docker push $(DOCKER_REGISTRY)/$(PY_CLIENT_IMAGE):$(IMAGE_TAG)
	@echo "$(GREEN)[SUCCESS]$(NC) Python Test Harness image pushed successfully"

# Multi-architecture push targets
.PHONY: pushx
pushx: buildx-setup pushx-js pushx-py ## Build and push multi-architecture images

.PHONY: pushx-js
pushx-js: buildx-setup ## Build and push JS Echo Server for multiple architectures
	@if [ -z "$(DOCKER_REGISTRY)" ]; then \
		echo "$(RED)[ERROR]$(NC) DOCKER_REGISTRY must be set to push images"; \
		exit 1; \
	fi
	@echo "$(BLUE)[PUSHX]$(NC) Building and pushing JS Echo Server for $(PLATFORMS)..."
	@cd images/js-echo-server && \
	docker buildx build \
		--platform $(PLATFORMS) \
		$(DOCKER_BUILD_ARGS) \
		$(if $(CACHE_FROM_JS),--cache-from $(CACHE_FROM_JS)) \
		$(if $(CACHE_TO_JS),--cache-to $(CACHE_TO_JS)) \
		-t $(DOCKER_REGISTRY)/$(JS_SERVER_IMAGE):$(IMAGE_TAG) \
		--push \
		.

.PHONY: pushx-py
pushx-py: buildx-setup ## Build and push Python Test Harness for multiple architectures
	@if [ -z "$(DOCKER_REGISTRY)" ]; then \
		echo "$(RED)[ERROR]$(NC) DOCKER_REGISTRY must be set to push images"; \
		exit 1; \
	fi
	@echo "$(BLUE)[PUSHX]$(NC) Building and pushing Python Test Harness for $(PLATFORMS)..."
	@cd images/py-test-harness && \
	docker buildx build \
		--platform $(PLATFORMS) \
		$(DOCKER_BUILD_ARGS) \
		$(if $(CACHE_FROM_PY),--cache-from $(CACHE_FROM_PY)) \
		$(if $(CACHE_TO_PY),--cache-to $(CACHE_TO_PY)) \
		-t $(DOCKER_REGISTRY)/$(PY_CLIENT_IMAGE):$(IMAGE_TAG) \
		--push \
		.

# Test targets
.PHONY: test
test: build ## Run all tests
	@echo "$(BLUE)[TEST]$(NC) Running all tests..."
	@./scripts/test-local.sh
	@echo "$(GREEN)[SUCCESS]$(NC) All tests completed successfully"

.PHONY: test-unit
test-unit: build ## Run unit tests only
	@echo "$(BLUE)[TEST]$(NC) Running unit tests..."
	@./scripts/test-local.sh unit

.PHONY: test-property
test-property: build ## Run property-based tests only
	@echo "$(BLUE)[TEST]$(NC) Running property-based tests..."
	@./scripts/test-local.sh property

.PHONY: test-integration
test-integration: build ## Run integration tests only
	@echo "$(BLUE)[TEST]$(NC) Running integration tests..."
	@./scripts/test-local.sh integration

.PHONY: test-config
test-config: ## Run configuration validation tests
	@echo "$(BLUE)[TEST]$(NC) Running configuration tests..."
	@./scripts/test-local.sh config

# Docker Compose targets
.PHONY: up
up: build ## Start all services with Docker Compose
	@echo "$(BLUE)[COMPOSE]$(NC) Starting services..."
	@docker-compose -f $(COMPOSE_FILE) up

.PHONY: up-detached
up-detached: build ## Start all services in background
	@echo "$(BLUE)[COMPOSE]$(NC) Starting services in background..."
	@docker-compose -f $(COMPOSE_FILE) up -d

.PHONY: down
down: ## Stop and remove all services
	@echo "$(BLUE)[COMPOSE]$(NC) Stopping services..."
	@docker-compose -f $(COMPOSE_FILE) down --remove-orphans --volumes

.PHONY: logs
logs: ## Show logs from all services
	@docker-compose -f $(COMPOSE_FILE) logs

.PHONY: logs-follow
logs-follow: ## Follow logs from all services
	@docker-compose -f $(COMPOSE_FILE) logs -f

# Development targets
.PHONY: dev-build
dev-build: ## Build images for development (no cache)
	@echo "$(BLUE)[DEV]$(NC) Building development images..."
	@BUILD_CACHE=false ./scripts/build-local.sh

.PHONY: dev-test
dev-test: dev-build ## Run tests in development mode
	@echo "$(BLUE)[DEV]$(NC) Running development tests..."
	@VERBOSE=true ./scripts/test-local.sh

.PHONY: dev-shell-js
dev-shell-js: build ## Start interactive shell in JS container
	@docker run --rm -it \
		-v $(PWD)/images/js-echo-server:/app \
		-w /app \
		$(JS_SERVER_IMAGE):$(IMAGE_TAG) \
		bash

.PHONY: dev-shell-py
dev-shell-py: build ## Start interactive shell in Python container
	@docker run --rm -it \
		-v $(PWD)/images/py-test-harness:/app \
		-w /app \
		$(PY_CLIENT_IMAGE):$(IMAGE_TAG) \
		bash

# Validation targets
.PHONY: validate
validate: ## Validate configuration and setup
	@echo "$(BLUE)[VALIDATE]$(NC) Validating configuration..."
	@./lib/validate-config.sh

.PHONY: validate-compose
validate-compose: ## Validate Docker Compose configuration
	@echo "$(BLUE)[VALIDATE]$(NC) Validating Docker Compose configuration..."
	@docker-compose -f $(COMPOSE_FILE) config --quiet
	@echo "$(GREEN)[SUCCESS]$(NC) Docker Compose configuration is valid"

.PHONY: validate-images
validate-images: build ## Validate built images
	@echo "$(BLUE)[VALIDATE]$(NC) Validating Docker images..."
	@docker run --rm $(JS_SERVER_IMAGE):$(IMAGE_TAG) node --version
	@docker run --rm $(PY_CLIENT_IMAGE):$(IMAGE_TAG) python3 --version
	@echo "$(GREEN)[SUCCESS]$(NC) All images are functional"

# Cleanup targets
.PHONY: clean
clean: down ## Clean up containers and networks
	@echo "$(BLUE)[CLEAN]$(NC) Cleaning up containers and networks..."
	@docker container prune -f
	@docker network prune -f

.PHONY: clean-images
clean-images: ## Remove built images
	@echo "$(BLUE)[CLEAN]$(NC) Removing built images..."
	@docker rmi $(JS_SERVER_IMAGE):$(IMAGE_TAG) 2>/dev/null || true
	@docker rmi $(PY_CLIENT_IMAGE):$(IMAGE_TAG) 2>/dev/null || true
	@if [ -n "$(DOCKER_REGISTRY)" ]; then \
		docker rmi $(DOCKER_REGISTRY)/$(JS_SERVER_IMAGE):$(IMAGE_TAG) 2>/dev/null || true; \
		docker rmi $(DOCKER_REGISTRY)/$(PY_CLIENT_IMAGE):$(IMAGE_TAG) 2>/dev/null || true; \
	fi

.PHONY: clean-cache
clean-cache: ## Clean Docker build cache
	@echo "$(BLUE)[CLEAN]$(NC) Cleaning Docker build cache..."
	@docker builder prune -f

.PHONY: clean-all
clean-all: clean clean-images clean-cache ## Clean everything

# Information targets
.PHONY: info
info: ## Show build information
	@echo "$(BLUE)[INFO]$(NC) Build Information:"
	@echo "  Project: $(PROJECT_NAME)"
	@echo "  Image Tag: $(IMAGE_TAG)"
	@echo "  Registry: $(if $(DOCKER_REGISTRY),$(DOCKER_REGISTRY),<none>)"
	@echo "  Build Date: $(BUILD_DATE)"
	@echo "  Git Commit: $(GIT_COMMIT)"
	@echo "  Platforms: $(PLATFORMS)"
	@echo "  Test Timeout: $(TEST_TIMEOUT)s"
	@echo ""
	@echo "$(BLUE)[IMAGES]$(NC) Image Names:"
	@echo "  JS Server: $(JS_SERVER_IMAGE):$(IMAGE_TAG)"
	@echo "  Python Client: $(PY_CLIENT_IMAGE):$(IMAGE_TAG)"

.PHONY: version
version: ## Show version information
	@echo "$(PROJECT_NAME)"
	@echo "Git Commit: $(GIT_COMMIT)"
	@echo "Build Date: $(BUILD_DATE)"

# Generate image.json for test-plans compatibility
.PHONY: image-json
image-json: build ## Generate image.json file
	@echo "$(BLUE)[GENERATE]$(NC) Generating image.json..."
	@echo '{' > image.json
	@echo '  "js-echo-server": {' >> image.json
	@echo '    "image": "$(if $(DOCKER_REGISTRY),$(DOCKER_REGISTRY)/)$(JS_SERVER_IMAGE):$(IMAGE_TAG)",' >> image.json
	@echo '    "build_date": "$(BUILD_DATE)",' >> image.json
	@echo '    "git_commit": "$(GIT_COMMIT)"' >> image.json
	@echo '  },' >> image.json
	@echo '  "py-test-harness": {' >> image.json
	@echo '    "image": "$(if $(DOCKER_REGISTRY),$(DOCKER_REGISTRY)/)$(PY_CLIENT_IMAGE):$(IMAGE_TAG)",' >> image.json
	@echo '    "build_date": "$(BUILD_DATE)",' >> image.json
	@echo '    "git_commit": "$(GIT_COMMIT)"' >> image.json
	@echo '  }' >> image.json
	@echo '}' >> image.json
	@echo "$(GREEN)[SUCCESS]$(NC) image.json generated successfully"

# CI/CD targets
.PHONY: ci-build
ci-build: ## Build for CI environment
	@echo "$(BLUE)[CI]$(NC) Building for CI environment..."
	@BUILD_CACHE=false VERBOSE=true ./scripts/build-local.sh

.PHONY: ci-test
ci-test: ci-build ## Test in CI environment
	@echo "$(BLUE)[CI]$(NC) Testing in CI environment..."
	@TEST_TIMEOUT=600 VERBOSE=true ./scripts/test-local.sh

.PHONY: ci-push
ci-push: ci-build image-json ## Build, test, and push for CI
	@if [ -z "$(DOCKER_REGISTRY)" ]; then \
		echo "$(RED)[ERROR]$(NC) DOCKER_REGISTRY must be set for CI push"; \
		exit 1; \
	fi
	@echo "$(BLUE)[CI]$(NC) Pushing images for CI..."
	@$(MAKE) push
	@echo "$(GREEN)[SUCCESS]$(NC) CI build and push completed"

# Phony targets declaration
.PHONY: all help build build-js build-py buildx-setup buildx buildx-js buildx-py \
        push push-js push-py pushx pushx-js pushx-py \
        test test-unit test-property test-integration test-config \
        up up-detached down logs logs-follow \
        dev-build dev-test dev-shell-js dev-shell-py \
        validate validate-compose validate-images \
        clean clean-images clean-cache clean-all \
        info version image-json \
        ci-build ci-test ci-push