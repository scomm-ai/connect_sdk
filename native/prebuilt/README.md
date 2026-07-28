# Native prebuilts (libdatachannel)

Published shared/static libraries so Flutter app CI does not compile mbedtls +
libdatachannel from source on every run.

## Layout

```
native/prebuilt/
  windows-x86_64/datachannel.dll
  linux-x86_64/libdatachannel.so
  linux-aarch64/libdatachannel.so
  android-arm64-v8a/libdatachannel.so
  android-x86_64/libdatachannel.so
  android-jni/{arm64-v8a,x86_64}/libdatachannel.so   # Gradle jniLibs
  macos-arm64/libdatachannel.a
  macos-x86_64/libdatachannel.a
  ios-arm64/libdatachannel.a
```

Binaries are **not** committed. Download from GitHub Releases using the tag in
[`../PREBUILT_TAG`](../PREBUILT_TAG):

```bash
./tool/download_native_prebuilts.sh
# or
pwsh ./tool/download_native_prebuilts.ps1
```

## CMake / Gradle / CocoaPods

- Desktop & Android CMake: auto-uses a matching prebuilt unless `SCOMM_FORCE_SOURCE=1`.
- Android Gradle: uses `android-jni` when both ABIs are present (skips NDK compile).
- Apple: `tool/build_libdatachannel_apple.sh` copies the prebuilt `.a` when present.

## Publishing

Workflow [`.github/workflows/native-prebuilts.yml`](../../.github/workflows/native-prebuilts.yml)
builds each triple and uploads release assets `datachannel-<triple>.zip`.

```bash
# After merging native changes, cut a release tag:
git tag native-v1.0.0 && git push origin native-v1.0.0
# Then set native/PREBUILT_TAG to that tag and commit.
```
