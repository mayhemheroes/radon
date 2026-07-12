# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile — radon (Go, legacy GOPATH layout + vendored deps).
# Builds on the org C/C++ base (clang links the go-fuzz libFuzzer archive), adding
# a pinned Go toolchain + go-fuzz under /opt/toolchains, then runs mayhem/build.sh.
#
# GOROOT/GOPATH/GOMODCACHE are pinned at FIXED, $HOME-independent paths under
# /opt/toolchains so the toolchain and caches survive the PATCH tier's offline
# re-run under a different $HOME (SPEC §6.2 items 8/9, §6.5). radon itself builds
# in GOPATH mode against its vendored tree (see mayhem/build.sh) — no module
# resolution or network at build time.
#
# Build (from the repo root, on the `mayhem` branch):
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile \
#       --build-arg COMMIT=$(git rev-parse HEAD) -t radon-commit:test .

FROM ghcr.io/mayhemheroes/base:20260621

ARG COMMIT
ARG REPO_URL
ARG SOURCE_DATE_EPOCH
ARG SANITIZER_FLAGS

# Pin the Go version AND its tarball sha256 (reproducible fetch); pin go-fuzz by a
# module pseudo-version (NOT @latest) so the toolchain GOPATH is deterministic.
ARG GO_VERSION=1.25.12
ARG GO_SHA256=234828b7a89e0e303d2556310ee549fbcf253d28de937bac3da13d6294262ac1
ARG GO_FUZZ_VERSION=v0.0.0-20240924070022-e577bee5275c

ENV GOROOT=/opt/toolchains/go \
    GOPATH=/opt/toolchains/go-path \
    GOMODCACHE=/opt/toolchains/go-path/pkg/mod \
    GOCACHE=/opt/toolchains/go-path/build-cache \
    GOTOOLCHAIN=local \
    PATH=/opt/toolchains/go/bin:/opt/toolchains/go-path/bin:${PATH}

USER root
RUN install -d /opt/toolchains/go-path \
 && curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -o /tmp/go.tgz \
 && echo "${GO_SHA256}  /tmp/go.tgz" | sha256sum -c - \
 && tar -C /opt/toolchains -xzf /tmp/go.tgz && rm -f /tmp/go.tgz \
 # go-fuzz + go-fuzz-build (the libFuzzer build path), pinned by pseudo-version.
 && go install "github.com/dvyukov/go-fuzz/go-fuzz@${GO_FUZZ_VERSION}" \
 && go install "github.com/dvyukov/go-fuzz/go-fuzz-build@${GO_FUZZ_VERSION}" \
 # radon builds in legacy GOPATH mode (GO111MODULE=off), where go-fuzz-build
 # resolves github.com/dvyukov/go-fuzz/go-fuzz-dep from GOPATH/src, not the module
 # graph — materialize the (already downloaded) go-fuzz source there.
 && mkdir -p /opt/toolchains/go-path/src/github.com/dvyukov \
 && cp -r "${GOMODCACHE}/github.com/dvyukov/go-fuzz@${GO_FUZZ_VERSION}" \
          /opt/toolchains/go-path/src/github.com/dvyukov/go-fuzz \
 && chmod -R u+w /opt/toolchains/go-path/src \
 # The commit build AND the air-gapped PATCH re-run run as `mayhem` (2000): it must
 # read the toolchain and read/refresh the caches, so hand the GOPATH to 2000.
 && chown -R 2000:2000 /opt/toolchains/go-path

USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

# Builds the libFuzzer target and pre-compiles the upstream test suite (GOPATH
# mode against the vendored tree — self-contained, no network).
RUN bash mayhem/build.sh

RUN bash mayhem/test.sh

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
