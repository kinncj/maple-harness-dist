# syntax=docker/dockerfile:1.7
#
# maple-proxy in a container, built from a published release (nothing is compiled here):
#
#   docker buildx build --build-arg MAPLE_VERSION=v2.0.0 \
#     --platform linux/amd64,linux/arm64 -t registry.example.com/you/maple-proxy:2.0.0 --push .
#
# The build stage downloads maple-proxy_linux_<arch> from the release, and refuses it unless its
# checksum is in the release's SHA256SUMS and, for a signed release, that file's signature verifies
# against the trusted release key (fetch-release.sh, the same checks as the installer). The image
# holds that one static binary and its licences: no shell, no package manager, no secrets. It runs
# as a non-root user with a read-only root file system; everything the proxy writes goes under the
# one volume /data.
#
# For reproducible builds, pin both base images by digest (FROM image@sha256:...).

# The release to package, as tagged (v2.0.0). Required: no image is built from "whatever is latest".
ARG MAPLE_VERSION

FROM --platform=$BUILDPLATFORM debian:bookworm-slim AS fetch
ARG MAPLE_VERSION
ARG TARGETARCH
ARG MAPLE_REPO=kinncj/maple-harness-dist
RUN test -n "$MAPLE_VERSION" || { echo "set --build-arg MAPLE_VERSION=vX.Y.Z (a published release)"; exit 1; }
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl openssl \
 && rm -rf /var/lib/apt/lists/*
COPY fetch-release.sh /usr/local/bin/fetch-release.sh
RUN MAPLE_REPO="$MAPLE_REPO" fetch-release.sh "$MAPLE_VERSION" "$TARGETARCH" /out \
 && mkdir -p /out/data

# distroless/static: CA certificates, the nonroot user (65532), time zones; no shell.
FROM gcr.io/distroless/static-debian12:nonroot
ENV HOME=/data \
    XDG_CONFIG_HOME=/data/config \
    XDG_CACHE_HOME=/data/cache \
    XDG_DATA_HOME=/data/share \
    MAPLE_CONTAINER=1 \
    MAPLE_OPENAI_LISTEN=0.0.0.0:11535 \
    MAPLE_ANTHROPIC_LISTEN=0.0.0.0:11537 \
    MAPLE_WEBUI_LISTEN=127.0.0.1:11539 \
    MAPLE_SECRETS_BACKEND=mounted \
    MAPLE_SECRETS_DIR=/run/secrets/maple \
    MAPLE_LOG_FORMAT=json
COPY --from=fetch --chown=65532:65532 /out/data /data
COPY --from=fetch /out/maple-proxy /usr/local/bin/maple-proxy
COPY --from=fetch /out/licenses/ /usr/share/maple-harness/
USER 65532:65532
WORKDIR /data
VOLUME ["/data"]
EXPOSE 11535 11537
HEALTHCHECK --interval=15s --timeout=3s --start-period=20s --retries=3 \
    CMD ["/usr/local/bin/maple-proxy", "healthcheck"]
ENTRYPOINT ["/usr/local/bin/maple-proxy"]
CMD ["serve"]
