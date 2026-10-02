# firebase_analytics_webos

The webOS implementation of [`firebase_analytics`](https://pub.dev/packages/firebase_analytics).

> **Important**: This plugin requires a dedicated webOS NDK and firmware image (EPK), which are only available to authorized partners.
>
> **Beta**: This plugin relies on the [Firebase C++ SDK for desktop platforms](https://firebase.google.com/docs/cpp/setup?platform=android#libraries-desktop), which Google currently provides as a beta feature.

## Supported platforms

This plugin is supported on webOS 26 media or above.

## Usage

Add both `firebase_analytics` and `firebase_analytics_webos` as dependencies in your `pubspec.yaml`:

```yaml
dependencies:
  firebase_core: ^3.0.0
  firebase_core_webos: ^1.0.0
  firebase_analytics: any
  firebase_analytics_webos: ^1.0.0
```

Then import the upstream package:

```dart
import 'package:firebase_analytics/firebase_analytics.dart';
```

The webOS implementation is automatically used when running on webOS devices.

### Configuration

Unlike other platforms, `firebase_analytics_webos` requires explicit configuration with your GA4 credentials before logging any events. Call `FirebaseAnalyticsWebos.configure()` once at app startup, after `Firebase.initializeApp()`:

```dart
import 'package:firebase_analytics_webos/firebase_analytics_webos.dart';

FirebaseAnalyticsWebos.configure(
  measurementId: 'G-XXXXXXXXXX',
  apiSecret: 'YOUR_API_SECRET',
);
```

> **Where to find these values:**
> - **Measurement ID**: Google Analytics → Admin → Data Streams → Your stream
> - **API Secret**: Google Analytics → Admin → Data Streams → Your stream → Measurement Protocol API secrets

## Example

For a complete example app, see the [`example`](example/) directory.

## API Reference

See [API_REFERENCE.md](API_REFERENCE.md) for webOS-specific API details.

## Limitations

- `FirebaseAnalyticsWebos.configure()` must be called before any events are logged; events are silently dropped if credentials are not set.
- User ID and default event parameters are in-memory only and not persisted across app restarts.
- Failed HTTP dispatches are silently caught and not retried.
- Standard GA4 Measurement Protocol quotas and limits apply.
