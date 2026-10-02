# firebase_firestore_webos

The webOS implementation of [`cloud_firestore`](https://pub.dev/packages/cloud_firestore).

> **Important**: This plugin requires a dedicated webOS NDK and firmware image (EPK), which are only available to authorized partners.
>
> **Beta**: This plugin relies on the [Firebase C++ SDK for desktop platforms](https://firebase.google.com/docs/cpp/setup?platform=android#libraries-desktop), which Google currently provides as a beta feature.

## Supported platforms

This plugin is supported on webOS 26 media or above.

## Usage

Add both `cloud_firestore` and `firebase_firestore_webos` as dependencies in your `pubspec.yaml`:

```yaml
dependencies:
  firebase_core: ^3.0.0
  firebase_core_webos: ^1.0.0
  cloud_firestore: any
  firebase_firestore_webos: ^1.0.0
```

Then import the upstream package:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
```

The webOS implementation is automatically used when running on webOS devices.

## Example

For a complete example app, see the [`example`](example/) directory.

## API Reference

See [API_REFERENCE.md](API_REFERENCE.md) for webOS-specific API details.

## Limitations

- `loadBundle()` is not supported (throws `UnimplementedError`).
- `namedQueryGet()` is not supported (throws `UnimplementedError`).
- `snapshotsInSync()` returns an empty stream.
- Aggregate `sum()` and `average()` queries return empty results due to a Firebase C++ SDK limitation. Only `count()` is fully supported.
