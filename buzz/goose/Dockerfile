# syntax=docker/dockerfile:1.7

ARG HYPER_ACP_BASE_IMAGE=hyper-acp-base:local
ARG BUZZ_BASE_IMAGE=${HYPER_ACP_BASE_IMAGE}
ARG GOOSE_FETCH_IMAGE=debian:bookworm-slim

FROM ${GOOSE_FETCH_IMAGE} AS goose-fetch

ARG TARGETARCH
ARG GOOSE_VERSION=1.45.0
ARG GOOSE_AMD64_SHA256=ec5da5f018cf68ea446887d30decf847542035ffcf91536d1d134ed94bb24401
ARG GOOSE_ARM64_SHA256=54afad8e160068cb1769ca2ad3e19e36e8472775e68d7bc89cc90e7779c552d1

RUN apt-get update && apt-get install -y --no-install-recommends \
    bzip2 \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) goose_arch=x86_64; goose_sha256="${GOOSE_AMD64_SHA256}" ;; \
      arm64) goose_arch=aarch64; goose_sha256="${GOOSE_ARM64_SHA256}" ;; \
      *) echo "unsupported Goose target architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    archive="/tmp/goose-${goose_arch}-unknown-linux-gnu.tar.bz2"; \
    curl --fail --location --silent --show-error \
      "https://github.com/aaif-goose/goose/releases/download/v${GOOSE_VERSION}/goose-${goose_arch}-unknown-linux-gnu.tar.bz2" \
      --output "${archive}"; \
    printf '%s  %s\n' "${goose_sha256}" "${archive}" | sha256sum --check --strict; \
    mkdir -p /out; \
    tar -xjf "${archive}" -C /out; \
    test -x /out/goose

FROM ${BUZZ_BASE_IMAGE}

ARG GOOSE_VERSION=1.45.0

USER root
COPY --from=goose-fetch /out/goose /usr/local/bin/goose
COPY --chown=node:node goose/config.yaml /opt/hypercli-buzz/goose-config.yaml
COPY --chown=node:node goose/provider.json /opt/hypercli-buzz/goose-provider.json
COPY --chmod=0755 goose/entrypoint.sh /usr/local/bin/hypercli-buzz-goose-entrypoint
RUN export HOME=/root && \
    goose --version && \
    goose acp --help >/dev/null && \
    printf '%s\n' goose > /opt/hypercli-buzz/runtime

LABEL org.opencontainers.image.title="HyperCLI Buzz Goose Agent" \
      org.hypercli.buzz_runtime="true" \
      org.hypercli.buzz_workspace="/home/node/.buzz" \
      org.hypercli.coding_runtime="goose" \
      org.hypercli.coding_runtime_version="${GOOSE_VERSION}"

ENV GOOSE_PATH_ROOT=/home/node/.goose \
    GOOSE_DISABLE_KEYRING=1 \
    GOOSE_TELEMETRY_ENABLED=false \
    BUZZ_ACP_AGENT_COMMAND=/usr/local/bin/goose \
    BUZZ_ACP_AGENT_ARGS=acp \
    BUZZ_ACP_MCP_COMMAND=/usr/local/bin/buzz-dev-mcp

USER node
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/hypercli-buzz-goose-entrypoint"]
CMD ["sleep", "infinity"]
