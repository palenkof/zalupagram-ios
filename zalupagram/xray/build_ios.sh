#!/bin/bash
# ZalupaGram fork: builds Xray-core with main.go into a static library for
# iOS arm64 and packs it as third-party/ZalupaGramXray/ZGXray.xcframework.
# Needs Go and Xcode. Usage: build_ios.sh <xray tag>, e.g. v26.10.21
set -euo pipefail

TAG="$1"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
WORK="$HERE/work"
OUT="$ROOT/third-party/ZalupaGramXray/ZGXray.xcframework"

rm -rf "$WORK" "$OUT"
mkdir -p "$WORK"
git clone --depth 1 --branch "$TAG" https://github.com/XTLS/Xray-core.git "$WORK/Xray-core"

# Built as a package of Xray-core itself: its go.sum pins every dependency,
# so nothing is looked up in sum.golang.org (not reachable from the runner).
mkdir -p "$WORK/Xray-core/zgxray"
cp "$HERE/main.go" "$WORK/Xray-core/zgxray/main.go"
cd "$WORK/Xray-core"
export GOSUMDB=off
export GOFLAGS=-mod=mod

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
export GOOS=ios
export GOARCH=arm64
export CGO_ENABLED=1
export CC="$(xcrun --sdk iphoneos -f clang)"
export CGO_CFLAGS="-isysroot $SDK -arch arm64 -miphoneos-version-min=15.0"
export CGO_LDFLAGS="-isysroot $SDK -arch arm64 -miphoneos-version-min=15.0"
go build -buildmode=c-archive -trimpath -ldflags="-s -w -buildid=" -o "$WORK/libzgxray.a" ./zgxray

mkdir -p "$WORK/include"
cp "$WORK/libzgxray.h" "$WORK/include/zgxray.h"
xcodebuild -create-xcframework -library "$WORK/libzgxray.a" -headers "$WORK/include" -output "$OUT"
ls -la "$OUT"/*
du -sh "$OUT"
