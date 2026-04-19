# Building

## macOS (native)

```bash
swiftly run swift build -c release +6.3.0
```

This builds the `swift-android-bundler` executable.

To build explicitly:

```bash
swiftly run swift build --product swift-android-bundler -c release +6.3.0
```

## Linux (cross-compilation with Static Linux SDK)

Cross-compile from macOS to Linux using the [Static Linux SDK](https://www.swift.org/documentation/articles/static-linux-getting-started.html) (musl).

### Prerequisites

Install the Static Linux SDK:

```bash
swift sdk install swift-6.3-RELEASE_static-linux-0.1.0
```

Verify it's available:

```bash
swift sdk list
```

You should see `swift-6.3-RELEASE_static-linux-0.1.0` in the list.

### Build command

```bash
swiftly run swift build --swift-sdk x86_64-swift-linux-musl --product swift-android-bundler -c release +6.3.0
```

The resulting binary is statically linked and can run on any x86_64 Linux without external dependencies.

Output location: `.build/release/`
