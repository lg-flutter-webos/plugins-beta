# API Reference — firebase_analytics_webos

> **Note:** For standard API documentation, see [`firebase_analytics` on pub.dev](https://pub.dev/packages/firebase_analytics).
> This document covers webOS-specific behavior only.

## Features

- GA4 event logging via the Google Analytics Measurement Protocol (HTTP)
- User ID management
- Default event parameters
- Analytics collection toggle
- Persistent client ID generation and storage

## Overview

This plugin provides the webOS platform implementation of `firebase_analytics`.
It implements `FirebaseAnalyticsPlatform` and sends events directly to the
Google Analytics 4 Measurement Protocol endpoint over HTTP, bypassing the
Firebase C++ SDK entirely. A stable client ID is persisted to the app support
directory using `path_provider`.

## Configuration

Before any events can be logged, the plugin must be configured with GA4 credentials:

```dart
FirebaseAnalyticsWebos.configure(
  measurementId: 'G-XXXXXXXXXX',
  apiSecret: 'YOUR_API_SECRET',
);
```

Both fields are required and must be non-empty strings. Passing an empty value
throws `ArgumentError`. If `configure()` is not called, all `logEvent()` calls
are silently dropped.

## Supported APIs

### Core

| API | Supported | Notes |
|-----|-----------|-------|
| `FirebaseAnalyticsWebos.configure()` | Yes | webOS-only static method; must be called before logging |
| `logEvent()` | Yes | Sends event via GA4 Measurement Protocol |
| `setUserId()` | Yes | Stored in-memory; included in all subsequent events |
| `setDefaultEventParameters()` | Yes | Merged into every `logEvent()` call |
| `setAnalyticsCollectionEnabled()` | Yes | When `false`, all events are silently dropped |
| `resetAnalyticsData()` | Yes | Clears user ID and default event parameters |
| `isSupported()` | Yes | Always returns `true` |
| `getAppInstanceId()` | Yes | Returns the persistent GA4 client ID |


## webOS-Specific Behavior

- **Measurement Protocol transport**: Events are sent as HTTP POST requests to
  `https://www.google-analytics.com/mp/collect` with a 10-second timeout.
  No Firebase C++ SDK is involved in event dispatch.
- **Client ID persistence**: A UUID v4 client ID is generated on first launch
  and stored in `.firebase_analytics_client_id` under the app support directory.
  The same ID is reused on subsequent launches. If storage is unavailable, a
  new ephemeral UUID is generated per session.
- **Event name validation**: Event names are validated against GA4 rules before
  dispatch. Invalid names cause the event to be silently dropped (no exception thrown).
- **Parameter merging**: Default event parameters (set via `setDefaultEventParameters()`)
  are merged with per-event parameters. Event-level parameters take precedence on
  key conflicts.
- **Parameter limit**: Only the first 25 parameters are sent per event (GA4 limit).
  Parameters beyond 25 are silently trimmed.
- **Boolean conversion**: `bool` parameter values are converted to `int`
  (`true` → `1`, `false` → `0`). `null` and unsupported types are silently excluded.
- **Silent error handling**: All HTTP errors and validation failures are caught
  internally and do not propagate to the caller.

## Event Name Validation Rules

| Rule | Detail |
|------|--------|
| Non-empty | Empty names are rejected |
| Max length | 40 characters |
| Starting character | Must start with a letter (`A–Z`, `a–z`) |
| Allowed characters | Letters, digits, and underscores only (`[A-Za-z][A-Za-z0-9_]*`) |
| Reserved prefixes | Names starting with `firebase_`, `google_`, or `ga_` are rejected |

## Supported Parameter Value Types

| Type | Behavior |
|------|----------|
| `String` | Sent as-is |
| `int` | Sent as-is |
| `double` | Sent as-is |
| `bool` | Converted to `int` (`true` → `1`, `false` → `0`) |
| `null` | Silently excluded |
| Other types | Silently excluded |

## Error Codes

This plugin does not throw or surface error codes to the caller. All failures
(invalid event names, missing configuration, HTTP errors) are silently caught.
