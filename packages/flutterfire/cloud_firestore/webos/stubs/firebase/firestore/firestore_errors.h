/*
 * Stub header for firebase/firestore/firestore_errors.h
 *
 * This file is required because the installed Firebase Firestore C++ SDK
 * headers (query.h, document_reference.h, transaction.h) include this header,
 * but it is not shipped as part of the WebOS NDK sysroot installation.
 *
 * The Error enum values below are derived verbatim from the Firebase C++ SDK
 * source in this workspace:
 *   cpp firebase sdk/firestore/integration_test_internal/src/
 *   firestore_integration_test.cc  (switch-case listing all kError values)
 *
 * These values map 1:1 to gRPC Status codes and match the public Firebase
 * Firestore C++ API contract.
 */

#ifndef FIREBASE_FIRESTORE_SRC_INCLUDE_FIREBASE_FIRESTORE_ERRORS_H_
#define FIREBASE_FIRESTORE_SRC_INCLUDE_FIREBASE_FIRESTORE_ERRORS_H_

namespace firebase {
namespace firestore {

/**
 * @brief Error codes used by Cloud Firestore.
 *
 * The values are identical to the gRPC status codes used by Firebase.
 */
enum Error {
  /** The operation completed successfully. */
  kErrorOk = 0,
  /** The operation was cancelled (by the caller). */
  kErrorCancelled = 1,
  /** Unknown error or an error from a different error domain. */
  kErrorUnknown = 2,
  /** Client specified an invalid argument. */
  kErrorInvalidArgument = 3,
  /** Deadline expired before the operation could complete. */
  kErrorDeadlineExceeded = 4,
  /** Some requested document was not found. */
  kErrorNotFound = 5,
  /** Some document that we attempted to create already exists. */
  kErrorAlreadyExists = 6,
  /** The caller does not have permission to execute the specified operation. */
  kErrorPermissionDenied = 7,
  /** Some resource has been exhausted. */
  kErrorResourceExhausted = 8,
  /**
   * The operation was rejected because the system is not in a state required
   * for the operation's execution.
   */
  kErrorFailedPrecondition = 9,
  /**
   * The operation was aborted, typically due to a concurrency issue like
   * transaction aborts, etc.
   */
  kErrorAborted = 10,
  /** Operation was attempted past the valid range. */
  kErrorOutOfRange = 11,
  /** Operation is not implemented or not supported/enabled. */
  kErrorUnimplemented = 12,
  /**
   * Internal errors. Means some invariants expected by the underlying system
   * have been broken.
   */
  kErrorInternal = 13,
  /**
   * The service is currently unavailable. This is a most likely a transient
   * condition and may be corrected by retrying with a backoff.
   */
  kErrorUnavailable = 14,
  /** Unrecoverable data loss or corruption. */
  kErrorDataLoss = 15,
  /** The request does not have valid authentication credentials. */
  kErrorUnauthenticated = 16,
};

}  // namespace firestore
}  // namespace firebase

#endif  // FIREBASE_FIRESTORE_SRC_INCLUDE_FIREBASE_FIRESTORE_ERRORS_H_
