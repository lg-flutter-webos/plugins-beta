# API Reference — cloud_firestore_webos

> **Note:** For standard API documentation, see [`cloud_firestore` on pub.dev](https://pub.dev/packages/cloud_firestore).
> This document covers webOS-specific behavior only.

## Features

- Document and collection CRUD operations
- Real-time document and query snapshot listeners
- Transactions with read-before-write enforcement
- Batch writes
- Aggregate queries (count)
- Query filtering, ordering, and pagination
- Network enable/disable control
- Firestore emulator support
- Pigeon-based type-safe Dart–C++ communication

## Overview

This plugin provides the webOS platform implementation of `cloud_firestore`.
It implements `FirebaseFirestorePlatform` and communicates with the Firebase C++
Firestore SDK through Pigeon-generated platform channels.

## Supported APIs

### Instance Management

| API | Supported | Notes |
|-----|-----------|-------|
| `FirebaseFirestore.instance` | Yes | |
| `FirebaseFirestore.instanceFor()` | Yes | Supports named apps and custom database IDs |
| `firestore.settings` | Yes | Must be set before any other operation |
| `firestore.enableNetwork()` | Yes | |
| `firestore.disableNetwork()` | Yes | |
| `firestore.terminate()` | Yes | Removes instance from internal cache |
| `firestore.waitForPendingWrites()` | Yes | |
| `firestore.clearPersistence()` | Yes | |
| `firestore.useEmulator()` | Yes | |
| `firestore.setLoggingEnabled()` | Yes | |
| `firestore.snapshotsInSync()` | No | Returns empty stream |
| `firestore.loadBundle()` | No | Throws `UnimplementedError` |
| `firestore.namedQueryGet()` | No | Throws `UnimplementedError` |

### Document Operations

| API | Supported | Notes |
|-----|-----------|-------|
| `docRef.get()` | Yes | Supports `GetOptions` (`default`, `server`, `cache`) |
| `docRef.set()` | Yes | Supports `SetOptions(merge: true)` and `mergeFields` |
| `docRef.update()` | Yes | Supports `FieldValue` sentinels |
| `docRef.delete()` | Yes | |
| `docRef.snapshots()` | Yes | Real-time listener; auto-removed on stream cancel |
| `docRef.collection()` | Yes | Returns sub-collection reference |

### Collection & Query Operations

| API | Supported | Notes |
|-----|-----------|-------|
| `collectionRef.add()` | Yes | Generates a new document ID |
| `collectionRef.doc()` | Yes | |
| `query.get()` | Yes | Supports `GetOptions` |
| `query.snapshots()` | Yes | Real-time listener with `DocumentChange` events |
| `query.where()` | Yes | See filter operators table below |
| `query.orderBy()` | Yes | Ascending and descending |
| `query.limit()` | Yes | |
| `query.limitToLast()` | Yes | |
| `query.startAt()` / `startAfter()` | Yes | |
| `query.endAt()` / `endBefore()` | Yes | |
| `query.count()` | Yes | |
| `query.aggregate()` | Partial | `count` only; `sum` and `average` return empty results |
| `firestore.collectionGroup()` | Yes | |

### FieldValue Support

| FieldValue | Supported |
|------------|-----------|
| `FieldValue.serverTimestamp()` | Yes |
| `FieldValue.increment(n)` | Yes |
| `FieldValue.delete()` | Yes |
| `FieldValue.arrayUnion(elements)` | Yes |
| `FieldValue.arrayRemove(elements)` | Yes |

### Query Filter Operators

| Operator | Supported |
|----------|-----------|
| `isEqualTo` (`==`) | Yes |
| `isNotEqualTo` (`!=`) | Yes |
| `isGreaterThan` (`>`) | Yes |
| `isGreaterThanOrEqualTo` (`>=`) | Yes |
| `isLessThan` (`<`) | Yes |
| `isLessThanOrEqualTo` (`<=`) | Yes |
| `arrayContains` | Yes |
| `arrayContainsAny` | Yes |
| `whereIn` | Yes |
| `whereNotIn` | Yes |

### Transactions

| API | Supported | Notes |
|-----|-----------|-------|
| `firestore.runTransaction()` | Yes | Supports `timeout` and `maxAttempts` |
| `transaction.get()` | Yes | Must be called before any writes |
| `transaction.set()` | Yes | |
| `transaction.update()` | Yes | |
| `transaction.delete()` | Yes | |

### Batch Writes

| API | Supported |
|-----|-----------|
| `firestore.batch()` | Yes |
| `batch.set()` | Yes |
| `batch.update()` | Yes |
| `batch.delete()` | Yes |
| `batch.commit()` | Yes |

## webOS-Specific Behavior

- **Multi-app support**: Instances are cached per `(appName, databaseId)` pair.
  Use `FirebaseFirestore.instanceFor(app: app, databaseId: id)` for multi-app
  or multi-database scenarios.
- **Settings must be set early**: `firestore.settings` must be assigned before
  any read/write operation. The default settings use persistence enabled,
  SSL enabled, and `CACHE_SIZE_UNLIMITED`.
- **Real-time listeners**: Document and query snapshot listeners are registered
  on the C++ side and deliver updates via Pigeon callbacks. Listeners are
  automatically removed from the native layer when the Dart stream is cancelled.
- **Transaction read-before-write**: Calling `transaction.get()` after any write
  operation within the same transaction throws `StateError`.
- **Transaction timeout**: `runTransaction()` enforces a configurable timeout
  (default 30 seconds). Exceeding it throws `FirebaseException` with code
  `deadline-exceeded`.
- **Aggregate limitations**: `sum()` and `average()` aggregate fields are
  accepted by the API but return empty results due to a Firebase C++ SDK
  limitation. Only `count()` returns a valid result.
- **`snapshotsInSync()`**: Returns an empty stream. Metadata-only change
  notifications are not supported.
- **FieldPath.documentId**: Normalized to the `__name__` sentinel expected by
  the C++ SDK when used in query filters.

## Error Codes

Errors from the Firebase C++ SDK are surfaced as `FirebaseException` instances.
Common codes:

| Code | Cause |
|------|-------|
| `not-found` | Document does not exist |
| `permission-denied` | Firestore security rules rejected the operation |
| `unavailable` | Network is disabled or Firestore is unreachable |
| `deadline-exceeded` | Transaction timed out |
| `already-exists` | Document already exists on a create operation |
| `cancelled` | Operation was cancelled |
