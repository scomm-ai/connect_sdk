#!/usr/bin/env bash
# Ensure third_party/mbedtls exists (v3.6.2 + framework submodule).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MBED="$ROOT/third_party/mbedtls"
if [[ -f "$MBED/CMakeLists.txt" ]]; then
  echo "mbedtls already present at $MBED"
  exit 0
fi
rm -rf "$MBED"
git clone --depth 1 --branch v3.6.2 https://github.com/Mbed-TLS/mbedtls.git "$MBED"
git -C "$MBED" submodule update --init --recursive --depth 1
echo "Cloned mbedtls v3.6.2"
