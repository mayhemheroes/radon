#!/usr/bin/env bash
#
# mayhem/build.sh — build radon's go-fuzz harness (src/fuzz/sqlparser, legacy
# `func Fuzz(data []byte) int`) as a sanitized libFuzzer binary via the OSS-Fuzz
# Go path: go-fuzz-build -libfuzzer + clang link.
#
# radon is a legacy GOPATH-layout project: packages live under src/ (import paths
# like `fuzz/sqlparser`, `proxy`, `router`) and ALL third-party deps are vendored
# at src/vendor/. So we build in GOPATH mode (GO111MODULE=off) with the repo root
# itself on GOPATH — no module graph, no proxy, no network: the tree is fully
# self-contained, which satisfies the air-gapped re-run contract (SPEC §6.5) by
# construction. go-fuzz-dep is baked into the toolchain GOPATH by the Dockerfile.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
# OSS-Fuzz Go path is ASan-only for the libFuzzer link.
: "${SANITIZER_FLAGS=-fsanitize=address}"
: "${GO_DEBUG_FLAGS:=-g -gdwarf-3}"
: "${MAYHEM_JOBS:=$(nproc)}"
export CC CXX LIB_FUZZING_ENGINE SANITIZER_FLAGS GO_DEBUG_FLAGS MAYHEM_JOBS

# Legacy GOPATH mode: repo root first (packages at $SRC/src/<pkg>, vendored deps at
# $SRC/src/vendor), toolchain GOPATH second (go-fuzz + go-fuzz-dep sources).
export GO111MODULE=off
export GOFLAGS=
export GOPATH="$SRC:/opt/toolchains/go-path"
export CGO_ENABLED=1
# DWARF<4 contract (§6.2 item 10): the clang-compiled cgo shim is the fuzz ELF's
# first CU — thread $GO_DEBUG_FLAGS (-gdwarf-3) through cgo and the final link.
export CGO_CFLAGS="$GO_DEBUG_FLAGS" CGO_CXXFLAGS="$GO_DEBUG_FLAGS"

cd "$SRC"
go version

# Preserve the fork's historical Mayhem target name (`fuzz`) for run continuity.
TARGET="fuzz"
PKG="fuzz/sqlparser"

mkdir -p "$SRC/mayhem-build"
echo "=== building $TARGET (go-fuzz-build -libfuzzer, pkg $PKG) ==="
go-fuzz-build -libfuzzer -func Fuzz -o "$SRC/mayhem-build/$TARGET.a" "$PKG"
$CXX $GO_DEBUG_FLAGS $SANITIZER_FLAGS $LIB_FUZZING_ENGINE "$SRC/mayhem-build/$TARGET.a" -o "/mayhem/$TARGET"
echo "built /mayhem/$TARGET"

# Pre-compile the upstream test suite with NORMAL flags (mayhem/test.sh only RUNS
# it): compile every test binary into the pinned GOCACHE without executing tests,
# so the test.sh run (and any offline re-run) needs no fresh compilation work.
echo "=== pre-building the upstream test suite ==="
go test -vet=off -count=1 -run '^$' \
  xbase xbase/stats xbase/sync2 xcontext config router optimizer planner/... \
  executor/... backend proxy audit syncer ctl/v1 monitor plugins/... \
  fuzz/sqlparser >/dev/null
go test -race -vet=off -count=1 -run '^$' \
  xbase xbase/stats xbase/sync2 backend proxy audit syncer ctl/v1 \
  fuzz/sqlparser >/dev/null

echo "build.sh complete"
