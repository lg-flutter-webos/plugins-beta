/*
 * Stub for firebase/firestore/timestamp.h
 *
 * This file is required because the WebOS NDK sysroot Firebase installation is
 * missing this header despite the pre-built library having been compiled with it.
 *
 * Class layout derived from the workspace SDK source:
 *   cpp firebase sdk/firestore/src/android/timestamp_portable.cc
 *
 * Key facts:
 *   - Class is in namespace firebase:: (NOT firebase::firestore::)
 *   - Path is firebase/firestore/timestamp.h (unusual but correct)
 *   - Constructor: Timestamp(int64_t seconds, int32_t nanoseconds)
 *   - Binary layout: [int64_t seconds_, int32_t nanoseconds_]
 *   - Integration test: firebase::Timestamp{1, 2} with .seconds()==1, .nanoseconds()==2
 */

#ifndef FIREBASE_FIRESTORE_SRC_INCLUDE_FIREBASE_FIRESTORE_TIMESTAMP_H_
#define FIREBASE_FIRESTORE_SRC_INCLUDE_FIREBASE_FIRESTORE_TIMESTAMP_H_

#include <chrono>
#include <cstdint>
#include <ctime>
#include <iosfwd>
#include <string>

namespace firebase {

/**
 * @brief An immutable object representing a point in time with nanosecond
 * precision.
 *
 * Timestamp is in the firebase:: namespace (not firebase::firestore::), even
 * though the header lives under firebase/firestore/.
 */
class Timestamp final {
 public:
  /** Creates a default Timestamp at the Unix epoch (seconds=0, nanoseconds=0). */
  Timestamp() : seconds_(0), nanoseconds_(0) {}

  /**
   * @brief Creates a Timestamp from the given seconds and nanoseconds.
   *
   * @param seconds     Seconds since Unix epoch. May be negative.
   * @param nanoseconds Non-negative fractions of a second, in [0, 999999999].
   */
  Timestamp(int64_t seconds, int32_t nanoseconds)
      : seconds_(seconds), nanoseconds_(nanoseconds) {}

  Timestamp(const Timestamp& other) = default;
  Timestamp(Timestamp&& other) = default;
  Timestamp& operator=(const Timestamp& other) = default;
  Timestamp& operator=(Timestamp&& other) = default;

  /** Returns the number of seconds since Unix epoch. */
  int64_t seconds() const { return seconds_; }

  /** Returns the non-negative fractions of a second (nanoseconds). */
  int32_t nanoseconds() const { return nanoseconds_; }

  /** Returns the current time as a Timestamp. */
  static Timestamp Now();

  /** Creates a Timestamp from a POSIX time_t value. */
  static Timestamp FromTimeT(time_t seconds_since_unix_epoch);

  /** Creates a Timestamp from a std::chrono::system_clock time_point. */
  static Timestamp FromTimePoint(
      std::chrono::time_point<std::chrono::system_clock> time_point);

  /** Returns a string representation of this Timestamp. */
  std::string ToString() const;

  friend std::ostream& operator<<(std::ostream& out, const Timestamp& ts);

 private:
  int64_t seconds_;
  int32_t nanoseconds_;
};

inline bool operator==(const Timestamp& lhs, const Timestamp& rhs) {
  return lhs.seconds() == rhs.seconds() &&
         lhs.nanoseconds() == rhs.nanoseconds();
}

inline bool operator!=(const Timestamp& lhs, const Timestamp& rhs) {
  return !(lhs == rhs);
}

inline bool operator<(const Timestamp& lhs, const Timestamp& rhs) {
  if (lhs.seconds() != rhs.seconds()) return lhs.seconds() < rhs.seconds();
  return lhs.nanoseconds() < rhs.nanoseconds();
}

inline bool operator>(const Timestamp& lhs, const Timestamp& rhs) {
  return rhs < lhs;
}

inline bool operator<=(const Timestamp& lhs, const Timestamp& rhs) {
  return !(rhs < lhs);
}

inline bool operator>=(const Timestamp& lhs, const Timestamp& rhs) {
  return !(lhs < rhs);
}

}  // namespace firebase

#endif  // FIREBASE_FIRESTORE_SRC_INCLUDE_FIREBASE_FIRESTORE_TIMESTAMP_H_
