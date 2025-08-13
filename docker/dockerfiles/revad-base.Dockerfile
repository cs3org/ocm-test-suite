# ----------------------------------------------------------------------------
# Multi-stage build of revad from the cs3org/reva repository.
# This Dockerfile:
# 1. Builds revad from source using Go in a reproducible, pinned environment.
# 2. Creates a minimal runtime image with the revad binary, configurations, and certificates.
#
# ----------------------------------------------------------------------------
# Stage 1: Build Stage
# ----------------------------------------------------------------------------
# Select Go version via build-arg. Default matches your current choice.
ARG GO_VERSION=1.24.6

# Use a specific, pinned Go image to ensure reproducible and secure builds.
FROM golang:${GO_VERSION}-bookworm AS build

# Enable CGO for better performance on certain operations (e.g., SQLite).
ENV CGO_ENABLED=1

# ----------------------------------------------------------------------------
# Install Required Packages
# ----------------------------------------------------------------------------
# Update package list and install build tools needed by revad and its dependencies.
# Use --no-install-recommends to avoid unnecessary packages and reduce image size.
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends --assume-yes \
    git \
    bash \
    make \
    build-essential \
    libsqlite3-dev; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# Set the working directory to root to have a clean starting point.
WORKDIR /

# ----------------------------------------------------------------------------
# Build Arguments
# ----------------------------------------------------------------------------
# These allow customizing which repository and branch to clone at build time.
# CACHEBUST is used to force rebuild steps when needed.
ARG REVA_REPO=https://github.com/cs3org/reva
ARG REVA_BRANCH=v3.0.1
ARG CACHEBUST="default"

# ----------------------------------------------------------------------------
# Clone Repository
# ----------------------------------------------------------------------------
# Clone the specified branch of the OCM stub repository with minimal depth
# to reduce build time and image size. Also fetch submodules if present.
RUN git clone \
    --depth 1 \
    --recursive \
    --shallow-submodules \
    --branch ${REVA_BRANCH} \
    ${REVA_REPO} \
    /reva-git

# ----------------------------------------------------------------------------
# Set Working Directory
# ----------------------------------------------------------------------------
# Set the working directory to the application directory.
WORKDIR /reva-git

# ----------------------------------------------------------------------------
# Install Dependencies
# ----------------------------------------------------------------------------
# Download Go module dependencies specified in go.mod to improve build caching.
RUN go clean -modcache
RUN rm go.sum
RUN go mod tidy
RUN go mod download

# ----------------------------------------------------------------------------
# Build Reva
# ----------------------------------------------------------------------------
# Build the `revad` binary.
# Using `make revad` as per repository instructions. 
RUN make revad

# ----------------------------------------------------------------------------
# Stage 2: Application Image
# ----------------------------------------------------------------------------
# Use a minimal Debian-based image for the runtime environment.
FROM debian:bookworm-slim@sha256:8f8e63bb364a33694362f38ee9a9e38b09eb9eb138584693800b87ca173bfd4a

# ----------------------------------------------------------------------------
# OCI Image Metadata
# ----------------------------------------------------------------------------
# Provide metadata that describes this image, its source, and authorship.
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.title="Pondersource Revad Base Image"
LABEL org.opencontainers.image.source="https://github.com/pondersource/dev-stock"
LABEL org.opencontainers.image.authors="Mohammad Mahdi Baghbani Pourvahid"

# ----------------------------------------------------------------------------
# Install Required Packages
# ----------------------------------------------------------------------------
# Update package list and install:
# - bash: shell for scripts and operations.
# - curl: common utility for network operations.
# - tzdata: for time zone data, set to UTC for consistency.
# - iproute2: networking utilities that might be needed.
# - ca-certificates: to trust system certificates including custom ones.
# Use --no-install-recommends to avoid unnecessary packages and reduce image size.
RUN apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends --assume-yes \
    bash \
    curl \
    tzdata \
    iproute2 \
    ca-certificates; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# Set timezone to UTC for consistent logging and operations.
ENV TZ=Etc/UTC

# Copy TLS certificates from the host and trust them.
# This ensures revad can serve HTTPS or verify other services.
COPY ./tls/certificates/reva* /tls/
COPY ./tls/certificate-authority/* /tls/

# Update the CA certificates store with newly added certificates.
RUN ln -sf /tls/*.crt /usr/local/share/ca-certificates; \
    update-ca-certificates

# Copy the pre-built `revad` binary and related tools from the build stage.
# The `revad` binary is found under /reva-git/cmd in the build stage.
COPY --from=build /reva-git/cmd /reva-git/cmd

# Create necessary directories for runtime operations (e.g., logs, temp files).
RUN mkdir -p /var/tmp/reva/

# Add the revad binary directory to PATH for convenience.
ENV PATH="${PATH}:/reva-git/cmd/revad"

# Copy utility scripts (e.g., entrypoint, run, kill) into the container.
# Ensure these scripts have appropriate shebang lines and `chmod +x` done.
# These scripts are responsible for container lifecycle management.
COPY ./scripts/reva/* /usr/bin/
RUN chmod +x /usr/bin/entrypoint.sh /usr/bin/init.sh /usr/bin/terminate.sh

# ----------------------------------------------------------------------------
# Entrypoint script.
# ----------------------------------------------------------------------------
# Set the container entrypoint. This script can handle preparation steps before starting revad.
ENTRYPOINT ["/usr/bin/entrypoint.sh"]

# ----------------------------------------------------------------------------
# Startup Command
# ----------------------------------------------------------------------------
# The default command is currently to follow the revad log.
CMD ["tail", "-F", "/var/log/revad.log"]

# ----------------------------------------------------------------------------
# Healthcheck
# ----------------------------------------------------------------------------
# Check if the application responds on port 443. Using curl with -k to ignore TLS.
# HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
#   CMD curl -k -f http://localhost:... || exit 1
