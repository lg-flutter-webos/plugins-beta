# FlutterFire webOS Plugins

webOS implementations of [FlutterFire](https://firebase.flutter.dev/) plugins, built on the Firebase C++ SDK with [Pigeon](https://pub.dev/packages/pigeon) for type-safe Dart–C++ communication.

> **Important**: These beta plugins require a dedicated webOS NDK and firmware image (EPK), which are only available to authorized partners.
>
> **Beta**: These plugins rely on the [Firebase C++ SDK for desktop platforms](https://firebase.google.com/docs/cpp/setup?platform=android#libraries-desktop), which Google currently provides as a beta feature.

## Plugins

| Plugin | Upstream Package |
|--------|-----------------|
| [firebase_core](firebase_core/) | [firebase_core](https://pub.dev/packages/firebase_core) |
| [cloud_firestore](cloud_firestore/) | [cloud_firestore](https://pub.dev/packages/cloud_firestore) |
| [firebase_analytics](firebase_analytics/) | [firebase_analytics](https://pub.dev/packages/firebase_analytics) |
| [firebase_remote_config](firebase_remote_config/) | [firebase_remote_config](https://pub.dev/packages/firebase_remote_config) |

## Supported Platforms

All plugins are supported on webOS 26 media or above.

## Prerequisites

All Firebase plugins require `firebase_core` to be initialized first. See each plugin's README for usage details.
