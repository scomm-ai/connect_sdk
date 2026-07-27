#!/usr/bin/env bash
# Build static libdatachannel for iOS or macOS (run from package root via CocoaPods script phase).
set -euo pipefail

TARGET="${1:-ios}"
CONFIG="${2:-Release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/apple"
SRC="$ROOT/src"

if [[ ! -f "$ROOT/third_party/libdatachannel/CMakeLists.txt" ]]; then
  git -C "$ROOT" submodule update --init --recursive
fi

if [[ ! -f "$ROOT/third_party/mbedtls/CMakeLists.txt" ]]; then
  git clone --depth 1 --branch v3.6.2 https://github.com/Mbed-TLS/mbedtls.git "$ROOT/third_party/mbedtls"
  git -C "$ROOT/third_party/mbedtls" submodule update --init --recursive --depth 1
fi

BUILD_DIR="$OUT/cmake-$TARGET"
mkdir -p "$BUILD_DIR" "$OUT/lib"

CMAKE_ARGS=(
  -S "$SRC"
  -B "$BUILD_DIR"
  -DCMAKE_BUILD_TYPE="$CONFIG"
  -DSCOMM_BUILD_SHARED=OFF
  -DNO_MEDIA=ON
  -DNO_WEBSOCKET=ON
  -DUSE_MBEDTLS=ON
  -DNO_EXAMPLES=ON
  -DNO_TESTS=ON
)

if [[ "$TARGET" == "ios" ]]; then
  # Prefer ios-cmake toolchain if present; otherwise rely on Xcode defaults.
  if [[ -f "$ROOT/third_party/ios-cmake/ios.toolchain.cmake" ]]; then
    CMAKE_ARGS+=(
      -G Xcode
      -DCMAKE_TOOLCHAIN_FILE="$ROOT/third_party/ios-cmake/ios.toolchain.cmake"
      -DPLATFORM=OS64COMBINED
    )
  else
    CMAKE_ARGS+=(-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0)
  fi
elif [[ "$TARGET" == "macos" ]]; then
  CMAKE_ARGS+=(-DCMAKE_OSX_DEPLOYMENT_TARGET=10.15)
else
  echo "Unknown target: $TARGET (expected ios|macos)" >&2
  exit 1
fi

cmake "${CMAKE_ARGS[@]}"
cmake --build "$BUILD_DIR" --config "$CONFIG"

# Locate static archive (name varies with BUILD_SHARED_LIBS=OFF).
LIB="$(find "$BUILD_DIR" -name 'libdatachannel.a' | head -n 1 || true)"
if [[ -z "$LIB" ]]; then
  LIB="$(find "$BUILD_DIR" -name 'datachannel.a' | head -n 1 || true)"
fi
if [[ -z "$LIB" ]]; then
  echo "Failed to find libdatachannel static library under $BUILD_DIR" >&2
  exit 1
fi

cp -f "$LIB" "$OUT/lib/libdatachannel.a"

# Merge dependent static libs when present (Apple -force_load needs one archive ideally).
DEPS=()
for dep in mbedcrypto mbedx509 mbedtls juice usrsctp; do
  FOUND="$(find "$BUILD_DIR" -name "lib${dep}.a" | head -n 1 || true)"
  if [[ -n "$FOUND" ]]; then
    DEPS+=("$FOUND")
  fi
done
if [[ ${#DEPS[@]} -gt 0 ]] && command -v libtool >/dev/null 2>&1; then
  libtool -static -o "$OUT/lib/libdatachannel.a" "$LIB" "${DEPS[@]}"
  echo "Merged static archive with deps: ${DEPS[*]}"
fi

echo "Installed $OUT/lib/libdatachannel.a"
