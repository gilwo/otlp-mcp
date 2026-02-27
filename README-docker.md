# OTLP-MCP Docker

An all-in-one Docker image that bundles [otlp-mcp](https://github.com/tobert/otlp-mcp) with an OpenTelemetry Collector, exposing both gRPC and HTTP/protobuf OTLP endpoints.

## Architecture

```
gRPC clients  ──4317──►  otlp-mcp (direct)
HTTP clients  ──4318──►  OTel Collector ──gRPC──►  otlp-mcp
MCP agents    ──9912──►  otlp-mcp MCP HTTP API
```

- **Port 4317** — OTLP gRPC, handled directly by otlp-mcp
- **Port 4318** — OTLP HTTP/protobuf, received by OTel Collector and forwarded to otlp-mcp via gRPC
- **Port 9912** — MCP HTTP API for agent queries

gRPC clients bypass the OTel Collector entirely and talk to otlp-mcp directly.

## Quick Start

### All-in-one (recommended)

Single container running both the OTel Collector and otlp-mcp:

```bash
make docker-build   # Build the image
make docker-run     # Start the container
```

Exposes:
- `localhost:4317` — OTLP gRPC (send traces/logs/metrics here)
- `http://localhost:4318` — OTLP HTTP/protobuf (send traces/logs/metrics here)
- `http://localhost:9912` — MCP HTTP API (query telemetry here)

### Standalone (two processes)

Run otlp-mcp on the host and the proxy in Docker separately:

```bash
# Terminal 1: Start otlp-mcp on the host
make serve

# Terminal 2: Start the HTTP-to-gRPC proxy in Docker
make docker-proxy
```

## Makefile Targets

```
$ make help
  help             Show this help
  build            Build otlp-mcp binary
  test             Run all tests
  fmt              Format Go source files
  vet              Run Go vet linter
  serve            Start otlp-mcp on the host (no Docker)
  docker-build     Build all-in-one Docker image
  docker-run       Run all-in-one container
  docker-run-bg    Run all-in-one container in background
  docker-proxy     Start HTTP-to-gRPC proxy only (Docker)

Variables:
  MCP_PORT     MCP HTTP port          (default: 9912)
  OTLP_PORT    OTLP gRPC port         (default: 4317)
  STATELESS    Run otlp-mcp stateless (default: off, set to 1 to enable)
```

### Examples

```bash
# Custom ports
make docker-run MCP_PORT=8080

# Stateless mode
make docker-run STATELESS=1

# Standalone with custom ports
make serve MCP_PORT=8080 OTLP_PORT=5555
make docker-proxy OTLP_PORT=5555

# Go development
make build
make test
make fmt
make vet
```

## Configuration

The container automatically picks up a config file mounted at `/etc/otlp-mcp/config.json`. If a `.otlp-mcp.json` file exists in the project root, `make run` mounts it automatically.

To get started, copy the example and customize:

```bash
cp .otlp-mcp.json.example .otlp-mcp.json
# Edit .otlp-mcp.json to your needs
make run
```

See [`.otlp-mcp.json.example`](.otlp-mcp.json.example) for all available settings and defaults.

For trace-heavy workloads, increase `trace_buffer_size` and reduce the others:

```json
{
  "comment": "Trace-heavy workload configuration",
  "otlp_port": 4317,
  "trace_buffer_size": 100000,
  "log_buffer_size": 20000,
  "metric_buffer_size": 20000,
  "verbose": true
}
```

You can also mount a config file manually or override the path:

```bash
# Manual mount
docker run --rm \
  -v /path/to/config.json:/etc/otlp-mcp/config.json \
  -p 4317:4317 -p 4318:4318 -p 9912:9912 \
  otlp-mcp

# Override the config file path
make run CONFIG_FILE=my-custom-config.json
```

When no config file is mounted, otlp-mcp uses its built-in defaults (10K traces, 50K logs, 100K metrics).

## Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Multi-stage build: otlp-mcp from local source + OTel Collector |
| `entrypoint.sh` | Starts both processes with signal handling |
| `otel-config.yaml` | OTel Collector config: HTTP/protobuf receiver → gRPC exporter |
| `Makefile` | Build, run, and development commands |
| `.dockerignore` | Excludes unnecessary files from the Docker build context |

## Versioning

The image version is derived from `git describe --tags --always --dirty` at build time. `make build` automatically:

- Tags the image as `otlp-mcp:<version>` and `otlp-mcp:latest`
- Embeds the version into OCI labels and the Go binary
- Logs the version as the first line on container startup

```bash
# Check image labels
docker inspect otlp-mcp:latest --format '{{json .Config.Labels}}' | python3 -m json.tool

# Check binary version
docker run --rm --entrypoint otlp-mcp otlp-mcp:latest --version
```

## Security

- Container runs as non-root user `otlpmcp` (UID 65532)
- Alpine base image pinned to `3.21` for reproducible builds
- OTel Collector pinned to `0.146.1`

## Notes

- The all-in-one container connects the OTel Collector to otlp-mcp via `localhost`, avoiding Docker networking issues.
- In standalone mode on macOS Docker Desktop, the Makefile forces IPv4 (`192.168.65.254`) to work around unreachable IPv6 routes via `host.docker.internal`.
- gRPC compression is disabled (`compression: none`) because otlp-mcp does not support gzip decompression.
