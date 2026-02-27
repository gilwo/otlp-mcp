# ── Version ──────────────────────────────────────────────────────────
VERSION    := $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
COMMIT     := $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_DATE := $(shell date -u +%Y-%m-%dT%H:%M:%SZ)

# ── Ports ────────────────────────────────────────────────────────────
MCP_PORT  ?= 9912
OTLP_PORT ?= 4317

# ── Docker ───────────────────────────────────────────────────────────
IMAGE_NAME   := otlp-mcp
OTEL_IMAGE   := otel/opentelemetry-collector:0.146.1
CONFIG_FILE  ?= .otlp-mcp.json
CONFIG_MOUNT := $(if $(wildcard $(CONFIG_FILE)),-v "$(PWD)/$(CONFIG_FILE)":/etc/otlp-mcp/config.json,)
# Docker Desktop for Mac: force IPv4 for host.docker.internal
HOST_ADDRESS := host.docker.internal
HOST_IPV4    := 192.168.65.254

# Images
OTEL_IMAGE := otel/opentelemetry-collector:0.146.1
IMAGE_NAME := otlp-mcp

.PHONY: help build-local test fmt vet build run run-bg serve proxy release-snapshot release

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Variables:"
	@echo "  \033[33mMCP_PORT\033[0m     MCP HTTP port          (default: $(MCP_PORT))"
	@echo "  \033[33mOTLP_PORT\033[0m    OTLP gRPC port         (default: $(OTLP_PORT))"
	@echo "  \033[33mSTATELESS\033[0m    Run otlp-mcp stateless (default: off, set to 1 to enable)"
	@echo ""
	@echo "Version: $(VERSION) ($(COMMIT))"

# ── Development ──────────────────────────────────────────────────────

build: ## Build otlp-mcp binary
	go build -ldflags "-X main.version=$(VERSION)" -o otlp-mcp ./cmd/otlp-mcp

test: ## Run all tests
	go test ./...

fmt: ## Format Go source files
	go fmt ./...

vet: ## Run Go vet linter
	go vet ./...

serve: ## Start otlp-mcp on the host (no Docker)
	@echo "Starting otlp-mcp..."
	@echo "MCP HTTP:  http://localhost:$(MCP_PORT)"
	@echo "OTLP gRPC: localhost:$(OTLP_PORT)"
	otlp-mcp serve --transport http --http-port $(MCP_PORT) --otlp-port $(OTLP_PORT) --verbose $(if $(STATELESS),--stateless,)

# ── Docker ───────────────────────────────────────────────────────────

docker-build: ## Build all-in-one Docker image
	docker build \
		-t $(IMAGE_NAME):$(VERSION) \
		-t $(IMAGE_NAME):latest \
		--build-arg VERSION=$(VERSION) \
		--build-arg COMMIT=$(COMMIT) \
		--build-arg BUILD_DATE=$(BUILD_DATE) \
		.

release-snapshot: ## Build release artifacts locally (no push, no tag)
	goreleaser release --snapshot --clean --skip=docker

release: ## Full release: binaries, packages, Docker images (requires git tag)
	./release/do-release.sh

run: ## Run all-in-one container (proxy + otlp-mcp)
	@echo "Starting all-in-one container..."
	@echo "OTLP gRPC: localhost:$(OTLP_PORT)"
	@echo "OTel HTTP:  http://localhost:4318"
	@echo "MCP HTTP:   http://localhost:$(MCP_PORT)"
	docker run --rm \
		--name $(IMAGE_NAME) \
		-p $(OTLP_PORT):$(OTLP_PORT) \
		-p 4318:4318 \
		-p $(MCP_PORT):$(MCP_PORT) \
		-e MCP_PORT=$(MCP_PORT) \
		-e OTLP_PORT=$(OTLP_PORT) \
		$(if $(STATELESS),-e STATELESS=1,) \
		$(CONFIG_MOUNT) \
		$(IMAGE_NAME)

docker-run-bg: ## Run all-in-one container in background
	@echo "Starting all-in-one container..."
	@echo "OTLP gRPC: localhost:$(OTLP_PORT)"
	@echo "OTel HTTP:  http://localhost:4318"
	@echo "MCP HTTP:   http://localhost:$(MCP_PORT)"
	docker run --rm -d \
		--name $(IMAGE_NAME) \
		-p $(OTLP_PORT):$(OTLP_PORT) \
		-p 4318:4318 \
		-p $(MCP_PORT):$(MCP_PORT) \
		-e MCP_PORT=$(MCP_PORT) \
		-e OTLP_PORT=$(OTLP_PORT) \
		$(if $(STATELESS),-e STATELESS=1,) \
		$(CONFIG_MOUNT) \
		$(IMAGE_NAME)

docker-proxy: ## Start HTTP-to-gRPC proxy only (Docker)
	@echo "Starting OTel Proxy..."
	@echo "Listening on: http://localhost:4318 (HTTP)"
	@echo "Forwarding to: $(HOST_ADDRESS):$(OTLP_PORT) (gRPC)"
	docker run --rm \
		--name otel-proxy \
		-p 4318:4318 \
		--add-host=$(HOST_ADDRESS):$(HOST_IPV4) \
		-v "$(PWD)/otel-config.yaml":/tmp/config.yaml \
		-e OTLP_MCP_ENDPOINT=$(HOST_ADDRESS):$(OTLP_PORT) \
		$(OTEL_IMAGE) \
		--config /tmp/config.yaml
