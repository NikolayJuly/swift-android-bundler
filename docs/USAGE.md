# Usage

## Prerequisites

- [swiftly](https://github.com/swiftlang/swiftly) — Swift toolchain version manager
- [patchelf](https://github.com/NixOS/patchelf) — ELF binary patching (`brew install patchelf`)
- Android SDK with NDK installed (default: `~/Library/Android/sdk`)
- Swift for Android SDK — install via `swift sdk install`
- [firebase-tools](https://firebase.google.com/docs/cli) — only if using `--firebase-app-id` (`npm install -g firebase-tools`)

## Auto-discovery

Both commands automatically discover the Swift toolchain and Android SDK:

- **Swift version**: if `--swift-version` is not provided, the latest installed toolchain is detected via `swiftly list`
- **Android SDK**: discovered via `swift sdk list` + `swift sdk configure --show-configuration`. If `--swift-version` is provided, only SDKs matching that version are considered. The Swift SDK version must match the toolchain version exactly.
- **Several Android SDKs installed**: from Swift 6.4.0 `build` passes `swift build --swift-sdk <sdk id> --triple <triple>`, so other installed SDKs do not clash. SwiftPM before 6.4.0 ignores `--triple` next to an SDK id, so there `build` passes the triple alone, which needs a single Android SDK installed for that triple.
- **NDK for `swift build`**: Swift 6.4.3 looks the NDK up itself. When neither `ANDROID_NDK_HOME` nor `ANDROID_NDK_ROOT` is set, `build` sets `ANDROID_NDK_HOME` to the latest NDK under `--android-sdk-path`.

## swift-android-bundler build

Builds Swift packages for Android, constructs a full dependency graph with symbol-level analysis, strips phantom dependencies, and copies only the needed .so files.

### Minimal example

```bash
swift-android-bundler build \
  --product MyLibrary \
  --swift-package /path/to/my-package \
  --destination /path/to/jniLibs
```

### Full example

```bash
swift-android-bundler build \
  --product MyLibrary \
  --swift-package /path/to/my-package \
  --destination /path/to/jniLibs \
  --arch arm64 \
  --api-level 28 \
  --swift-version 6.4.3 \
  --configuration release \
  --exclude all \
  --strip all \
  --android-sdk-path ~/Library/Android/sdk \
  --manifest-destination /path/to/assets \
  --symbols-destination /path/to/symbols \
  --firebase-app-id 1:123456789:android:abcdef123456
```

### Parameters

**Required:**

| Parameter | Description |
|-----------|-------------|
| `--product` | Swift library product name to build (can be repeated) |
| `--swift-package` | Path to Swift package directory (can be repeated) |
| `--destination` | Output folder for .so files |

**Optional — target:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--arch` | arm64 | Target architecture: arm64, arm7, x86, x86_64. Can be repeated for multi-arch builds. |
| `--api-level` | 28 | Android API level |
| `--triplet` | — | Full target triplet (e.g. `aarch64-unknown-linux-android28`). Alternative to `--arch` + `--api-level` — cannot be used together with them. |

**Optional — toolchain:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--swift-version` | latest installed | Swift version, full with patch (e.g. `6.4.3`). Selects both toolchain and Android SDK. |

**Optional — build:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--configuration` | release | Build configuration: `release` or `debug` |
| `--exclude` | none | Exclusion mode: `none`, `full-foundation`, `foundation-networking`, `all` |
| `--strip` | none | Strip mode for .so files: `none`, `debug`, `all` |
| `--android-sdk-path` | `~/Library/Android/sdk` | Path to Android SDK. Needed for NDK tools (`llvm-nm` for symbol analysis, `llvm-strip` for stripping). Not used by `collect`. |

**Optional — output:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--manifest-destination` | — | Directory for `swift-libs-manifest.json`. If not set, no manifest is generated. |
| `--symbols-destination` | see below | Directory for archived debug symbols |
| `--firebase-app-id` | — | Firebase app ID for uploading symbols to Crashlytics |

### Debug symbols archive

Every build automatically archives all unstripped .so files to a timestamped folder:

- **macOS**: `~/Library/Application Support/swift-android-bundler/symbols/<timestamp>_<product>_<config>/`
- **Linux**: `~/.local/share/swift-android-bundler/symbols/<timestamp>_<product>_<config>/`

Override with `--symbols-destination`.

Each archive contains:
- All .so files with full debug symbols
- A `README.md` with Firebase upload instructions

### --manifest-destination

Optional. Generates a JSON manifest with all .so libraries in topological load order.

While `System.loadLibrary()` can resolve transitive dependencies on its own, you may want explicit control over load order — for example, to ensure `libdispatch.so` is loaded on the main thread (required by Swift concurrency runtime) while loading other libraries on a background thread to avoid freezing the UI with ~27 MB of allocations.

`--manifest-destination` writes `swift-libs-manifest.json` with the exact order computed via topological sort:

```json
{
  "product": "MyLibrary",
  "libraries": [
    "BlocksRuntime",
    "dispatch",
    "swiftCore",
    "swift_Concurrency",
    "FoundationEssentials",
    "MyLibrary"
  ]
}
```

Library names use the format `System.loadLibrary()` expects (`libswiftCore.so` → `swiftCore`). Example usage on the Android side:

```kotlin
val manifest = Json.decodeFromString<SwiftLibsManifest>(
    context.assets.open("swift-libs-manifest.json").reader().readText()
)

// Load dispatch on main thread (required by Swift concurrency)
System.loadLibrary("dispatch")

// Load the rest on a background thread to avoid UI freeze
thread {
    manifest.libraries
        .filter { it != "dispatch" }
        .forEach { System.loadLibrary(it) }
}
```

### --firebase-app-id

Uploads debug symbols to Firebase Crashlytics. Without it, symbols are still archived locally. See [Firebase CLI setup](#firebase-cli-setup) below.

## swift-android-bundler collect

Collects .so dependencies for a pre-built Swift Android binary using `patchelf --print-needed` BFS traversal.

### Minimal example

```bash
swift-android-bundler collect /path/to/binary.xctest \
  --destination /path/to/output
```

### Full example

```bash
swift-android-bundler collect /path/to/binary.xctest \
  --destination /path/to/output \
  --arch x86_64 \
  --api-level 29 \
  --swift-version 6.4.3 \
  --build-folder /path/to/build/output \
  --verbose
```

### Parameters

**Required:**

| Parameter | Description |
|-----------|-------------|
| `<binary-path>` | Path to the binary (.xctest, .so, or executable) |
| `--destination` | Output folder for collected .so files |

**Optional:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--arch` | arm64 | Target architecture: arm64, arm7, x86, x86_64 |
| `--api-level` | 28 | Android API level |
| `--triplet` | — | Full target triplet. Alternative to `--arch` + `--api-level`. |
| `--swift-version` | latest installed | Swift version for SDK discovery |
| `--build-folder` | parent dir of binary | Additional folder to search for built .so files |
| `--verbose` / `-v` | false | Enable debug logging |

## Protected libraries

Some .so files are needed at runtime but have no direct symbol references from Swift code. These are protected and will never be stripped:

- **libSwiftJava.so** — loaded by the Java/Android runtime via JNI, not referenced through ELF dynamic linking.

## Firebase CLI setup

1. Install: `npm install -g firebase-tools`
2. Login: `firebase login`
3. Find your App ID in [Firebase Console](https://console.firebase.google.com/) → Project Settings → Your Apps
4. Pass it via `--firebase-app-id`
