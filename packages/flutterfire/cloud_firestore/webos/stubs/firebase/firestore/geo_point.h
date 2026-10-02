/*
 * Stub for firebase/firestore/geo_point.h
 *
 * This file is required because the WebOS NDK sysroot Firebase installation is
 * missing this header despite the pre-built library having been compiled with it.
 *
 * Class layout derived from the workspace SDK sources:
 *   cpp firebase sdk/firestore/src/android/geo_point_android.cc
 *   cpp firebase sdk/firestore/integration_test/src/integration_test.cc
 *     - usage: firebase::firestore::GeoPoint point{1.23, 4.56}
 *     - methods: point.latitude(), point.longitude()
 *
 * Binary layout: [double latitude_, double longitude_] — two doubles, trivial copy.
 */

#ifndef FIREBASE_FIRESTORE_SRC_INCLUDE_FIREBASE_FIRESTORE_GEO_POINT_H_
#define FIREBASE_FIRESTORE_SRC_INCLUDE_FIREBASE_FIRESTORE_GEO_POINT_H_

#include <iosfwd>
#include <string>

namespace firebase {
namespace firestore {

/**
 * @brief An immutable object representing a geographic location in Firestore.
 */
class GeoPoint final {
 public:
  /** Creates a default GeoPoint at (0, 0). */
  GeoPoint() : latitude_(0.0), longitude_(0.0) {}

  /**
   * @brief Creates a GeoPoint at the given latitude and longitude.
   *
   * @param latitude  Latitude in degrees, in [-90, 90].
   * @param longitude Longitude in degrees, in [-180, 180].
   */
  GeoPoint(double latitude, double longitude)
      : latitude_(latitude), longitude_(longitude) {}

  GeoPoint(const GeoPoint& other) = default;
  GeoPoint(GeoPoint&& other) = default;
  GeoPoint& operator=(const GeoPoint& other) = default;
  GeoPoint& operator=(GeoPoint&& other) = default;

  /** Returns the latitude in degrees. */
  double latitude() const { return latitude_; }

  /** Returns the longitude in degrees. */
  double longitude() const { return longitude_; }

  /** Returns a string representation of this GeoPoint. */
  std::string ToString() const;

  friend std::ostream& operator<<(std::ostream& out, const GeoPoint& geo);

 private:
  double latitude_;
  double longitude_;
};

inline bool operator==(const GeoPoint& lhs, const GeoPoint& rhs) {
  return lhs.latitude() == rhs.latitude() && lhs.longitude() == rhs.longitude();
}

inline bool operator!=(const GeoPoint& lhs, const GeoPoint& rhs) {
  return !(lhs == rhs);
}

inline bool operator<(const GeoPoint& lhs, const GeoPoint& rhs) {
  if (lhs.latitude() != rhs.latitude()) return lhs.latitude() < rhs.latitude();
  return lhs.longitude() < rhs.longitude();
}

}  // namespace firestore
}  // namespace firebase

#endif  // FIREBASE_FIRESTORE_SRC_INCLUDE_FIREBASE_FIRESTORE_GEO_POINT_H_
