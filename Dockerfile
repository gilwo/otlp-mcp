# Stage 1: Build otlp-mcp from local source
FROM golang:1.25-alpine AS builder
ARG VERSION=dev
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -ldflags "-X main.version=${VERSION}" -o /otlp-mcp ./cmd/otlp-mcp

# Stage 2: Get otelcol binary from official image
FROM otel/opentelemetry-collector:0.146.1 AS otelcol

# Stage 3: Final image
FROM alpine:3.21

ARG VERSION=dev
ARG COMMIT=unknown
ARG BUILD_DATE=unknown

LABEL org.opencontainers.image.title="otlp-mcp" \
      org.opencontainers.image.description="OpenTelemetry MCP server for AI agent observability" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${COMMIT}" \
      org.opencontainers.image.source="https://github.com/tobert/otlp-mcp" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.authors="gilwo@null.net" \
      org.opencontainers.image.created="${BUILD_DATE}"

RUN addgroup -g 65532 -S otlpmcp && adduser -u 65532 -S -G otlpmcp otlpmcp

COPY --from=builder /otlp-mcp /usr/local/bin/otlp-mcp
COPY --from=otelcol /otelcol /usr/local/bin/otelcol
COPY otel-config.yaml /etc/otel/config.yaml
COPY entrypoint.sh /entrypoint.sh

ENV MCP_PORT=9912
ENV OTLP_PORT=4317
ENV VERSION=${VERSION}

EXPOSE 4317 4318 9912

USER otlpmcp
ENTRYPOINT ["/entrypoint.sh"]
