# swift-android-bundler

CLI toolkit for building Swift packages for Android and collecting .so dependencies.

## Commands

| Subcommand | Description |
|---|---|
| `build` | Builds Swift packages for Android, analyzes .so dependencies, strips unused ones, copies minimal set to destination |
| `collect` | Collects .so dependencies for a pre-built Swift Android binary — useful for copying test binaries onto an Android emulator |
| `test collect` | Collects every test runner of a package built with `swift build --build-tests`, with the .so files they load, into one folder |
| `test run` | Pushes a `test collect` folder to the device over adb and runs every runner with the given testing libraries |

## Prerequisites

- [swiftly](https://github.com/swiftlang/swiftly) — Swift toolchain manager
- [patchelf](https://github.com/NixOS/patchelf) — ELF binary patching (`brew install patchelf`)
- Android SDK with NDK
- [Swift Android SDK](https://www.swift.org/documentation/articles/android.html) — install via `swift sdk install`

## Example

```bash
swift-android-bundler build \
  --product MyLibrary \
  --swift-package /path/to/package \
  --destination /path/to/jniLibs \
  --arch arm64 --arch x86_64 --arch arm7 \
  --exclude all \
  --strip all
```

This will:
1. Build `MyLibrary` for three Android architectures
2. Analyze symbol-level dependencies — find `.so` files that are linked but have zero real symbol references
3. Remove those phantom dependencies (e.g. Foundation libraries your code doesn't actually use)
4. Strip all debug symbols
5. Output the minimal `.so` set per architecture into `arm64-v8a/`, `x86_64/`, `armeabi-v7a/` subfolders

Swift toolchain and Android SDK are auto-discovered from installed versions. Pin a specific version, patch included, with `--swift-version 6.4.3`.

## Documentation

- [Usage](docs/USAGE.md) — all commands, parameters, and examples
- [Building](docs/BUILDING.md) — how to build the project from source

## License

Apache License 2.0. See [LICENSE](LICENSE) for details.
