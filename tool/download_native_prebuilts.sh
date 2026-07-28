#!/usr/bin/env bash
# Download published datachannel prebuilts into native/prebuilt/.
# Tag comes from native/PREBUILT_TAG (or SCOMM_NATIVE_PREBUILT_TAG / first arg).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="${SCOMM_NATIVE_PREBUILT_REPO:-scomm-ai/connect_sdk}"
TAG="${1:-${SCOMM_NATIVE_PREBUILT_TAG:-}}"
if [[ -z "$TAG" && -f "$ROOT/native/PREBUILT_TAG" ]]; then
  TAG="$(tr -d '[:space:]' < "$ROOT/native/PREBUILT_TAG")"
fi
if [[ -z "$TAG" ]]; then
  echo "No prebuilt tag (native/PREBUILT_TAG or SCOMM_NATIVE_PREBUILT_TAG)" >&2
  exit 1
fi

OUT="$ROOT/native/prebuilt"
mkdir -p "$OUT"
BASE="https://github.com/${REPO}/releases/download/${TAG}"

download_one() {
  local asset="$1"
  local url="${BASE}/${asset}"
  local tmp
  tmp="$(mktemp)"
  echo "Downloading $url"
  if ! curl -fsSL "$url" -o "$tmp"; then
    echo "[WARN] missing asset: $asset" >&2
    rm -f "$tmp"
    return 1
  fi
  # Assets are zips named datachannel-<triple>.zip
  unzip -o -q "$tmp" -d "$OUT"
  rm -f "$tmp"
  return 0
}

ok=0
for asset in \
  datachannel-windows-x86_64.zip \
  datachannel-linux-x86_64.zip \
  datachannel-linux-aarch64.zip \
  datachannel-android-arm64-v8a.zip \
  datachannel-android-x86_64.zip \
  datachannel-macos-arm64.zip \
  datachannel-macos-x86_64.zip \
  datachannel-ios-arm64.zip
do
  if download_one "$asset"; then
    ok=$((ok + 1))
  fi
done

# Convenience layout for Android Gradle jniLibs
if [[ -f "$OUT/android-arm64-v8a/libdatachannel.so" ]]; then
  mkdir -p "$OUT/android-jni/arm64-v8a"
  cp -f "$OUT/android-arm64-v8a/libdatachannel.so" "$OUT/android-jni/arm64-v8a/"
fi
if [[ -f "$OUT/android-x86_64/libdatachannel.so" ]]; then
  mkdir -p "$OUT/android-jni/x86_64"
  cp -f "$OUT/android-x86_64/libdatachannel.so" "$OUT/android-jni/x86_64/"
fi

if [[ "$ok" -eq 0 ]]; then
  echo "[ERROR] No prebuilt assets downloaded for tag $TAG" >&2
  exit 1
fi

echo "[OK] Downloaded $ok prebuilt asset(s) for $TAG into $OUT"
