# syntax=docker/dockerfile:1

# Define the Go version to use and the base image
ARG GO_VERSION="1.20"
ARG BUILDPLATFORM=linux/amd64
ARG BASE_IMAGE="golang:${GO_VERSION}-alpine3.18"

# Use the base image for the initial stage
FROM --platform=${BUILDPLATFORM} ${BASE_IMAGE} as base

###############################################################################
# Builder Stage 1
###############################################################################

# Inherit from the base stage
FROM base as builder-stage-1

# Define environment variables for the build process
ARG BUILDPLATFORM
ARG GOOS=linux
ARG GOARCH=amd64

ENV GOOS=$GOOS
ENV GOARCH=$GOARCH

# Install necessary packages and dependencies
RUN set -eux &&\
    apk update &&\
    apk add --no-cache \
    ca-certificates \
    linux-headers \
    build-base \
    cmake \
    git

# Clone and install mimalloc for musl
WORKDIR ${GOPATH}/src/mimalloc
RUN set -eux &&\
    git clone --depth 1 --branch v2.1.2 \
        https://github.com/microsoft/mimalloc . &&\
    mkdir -p build &&\
    cd build &&\
    cmake .. &&\
    make -j$(nproc) &&\
    make install

# Clone the desired repository
WORKDIR /code
RUN git clone --branch v2.3.3 --depth 1 https://github.com/classic-terra/core.git .

# Set the GIT_COMMIT and GIT_VERSION using Git commands
WORKDIR /code
RUN set -eux && \
    GIT_COMMIT=$(git log -1 --format='%H') && \
    GIT_VERSION=$(git describe --tags | sed 's/^v//') && \
    echo "GIT_COMMIT=${GIT_COMMIT}" > .env && \
    echo "GIT_VERSION=${GIT_VERSION}" >> .env

# Install dependencies using the go.mod and go.sum from the cloned repository
WORKDIR /code
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/root/go/pkg/mod \
    go mod download -x

# Cosmwasm - Download the correct libwasmvm version and verify checksum
RUN set -eux &&\
    WASMVM_VERSION=$(go list -m github.com/CosmWasm/wasmvm | cut -d ' ' -f 5) && \
    WASMVM_DOWNLOADS="https://github.com/classic-terra/wasmvm/releases/download/${WASMVM_VERSION}"; \
    wget ${WASMVM_DOWNLOADS}/checksums.txt -O /tmp/checksums.txt; \
    if [ ${BUILDPLATFORM} = "linux/amd64" ]; then \
        WASMVM_URL="${WASMVM_DOWNLOADS}/libwasmvm_muslc.x86_64.a"; \
    elif [ ${BUILDPLATFORM} = "linux/arm64" ]; then \
        WASMVM_URL="${WASMVM_DOWNLOADS}/libwasmvm_muslc.aarch64.a"; \
    else \
        echo "Unsupported Build Platfrom ${BUILDPLATFORM}"; \
        exit 1; \
    fi; \
    wget ${WASMVM_URL} -O /lib/libwasmvm_muslc.a; \
    CHECKSUM=`sha256sum /lib/libwasmvm_muslc.a | cut -d" " -f1`; \
    grep ${CHECKSUM} /tmp/checksums.txt; \
    rm /tmp/checksums.txt

###############################################################################
# Builder Stage 2
###############################################################################

FROM builder-stage-1 as builder-stage-2

# Import GIT_COMMIT and GIT_VERSION as arguments
ARG GIT_COMMIT
ARG GIT_VERSION

# Set environment variables for the build stage
ARG GOOS=linux
ARG GOARCH=amd64

ENV GOOS=$GOOS
ENV GOARCH=$GOARCH

# Build the application binary using the cloned source
WORKDIR /code
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/root/go/pkg/mod \
    go install \
        -mod=readonly \
        -tags "netgo,muslc" \
        -ldflags " \
            -w -s -linkmode=external -extldflags \
            '-L/go/src/mimalloc/build -lmimalloc -Wl,-z,muldefs -static' \
            -X github.com/cosmos/cosmos-sdk/version.Name='terra' \
            -X github.com/cosmos/cosmos-sdk/version.AppName='terrad' \
            -X github.com/cosmos/cosmos-sdk/version.Version=${GIT_VERSION} \
            -X github.com/cosmos/cosmos-sdk/version.Commit=${GIT_COMMIT} \
            -X github.com/cosmos/cosmos-sdk/version.BuildTags='netgo,muslc' \
        " \
        -trimpath \
        ./...

################################################################################
# Final stage to build the terra-core image with Nginx setup
FROM alpine as terra-core

WORKDIR /app

# Install necessary packages including Nginx
RUN apk update && apk add wget lz4 aria2 curl jq gawk coreutils "zlib>1.2.12-r2" libssl3 nginx

# Create a non-root user and set permissions
RUN addgroup -g 1000 terra && \
    adduser -u 1000 -G terra -D -h /app terra

# Setup Nginx and logs directory with correct permissions
RUN mkdir -p /var/lib/nginx/logs && \
    chown -R terra:terra /var/lib/nginx  && \
    ln -sf /dev/stdout /var/lib/nginx/logs/access.log && \
    ln -sf /dev/stderr /var/lib/nginx/logs/error.log

# Copy the built binary from the builder stage
COPY --from=builder-stage-2 /go/bin/terrad /usr/local/bin/terrad

# Setup for localterra
RUN set -eux &&\
    mkdir -p /app/config && \
    mkdir -p /app/data && \
    chown -R terra:terra /app && \
    terrad init localterra \
        --home /app \
        --chain-id localterra && \
    echo '{"height": "0","round": 0,"step": 0}' > /app/data/priv_validator_state.json

# Copy the Nginx configuration, entrypoint script, and Terra configuration files
COPY --chmod=644 nginx.conf /etc/nginx/nginx.conf
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh
COPY ./terra/priv_validator_key.json \
     ./terra/genesis.json \
     /app/config/

# Set the entry point
ENTRYPOINT [ "entrypoint.sh" ]

# rest server
EXPOSE 1317

# grpc server
EXPOSE 9090

# tendermint p2p
EXPOSE 26656

# tendermint rpc
EXPOSE 26657

# Set the default command
CMD terrad start \
    --home /app \
    --minimum-gas-prices "0.01133uluna,0.15uusd,0.104938usdr,169.77ukrw,428.571umnt,0.125ueur,0.98ucny,16.37ujpy,0.11ugbp,10.88uinr,0.19ucad,0.14uchf,0.19uaud,0.2usgd,4.62uthb,1.25usek" \
    --moniker localterra \
    --p2p.upnp true \
    --rpc.laddr tcp://0.0.0.0:26657 \
    --api.enable true \
    --api.swagger true \
    --api.address tcp://0.0.0.0:1317 \
    --api.enabled-unsafe-cors true \
    --grpc.enable true \
    --grpc.address 0.0.0.0:9090 \
    --grpc-web.enable \
    --grpc-web.address 0.0.0.0:9091
