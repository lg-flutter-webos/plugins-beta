import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';

Map<String?, Object?> convertDataToPigeonMap(Map<String, dynamic> data) {
  final result = <String?, Object?>{};
  data.forEach((key, value) {
    result[key] = convertValueToPigeon(value);
  });
  return result;
}

Object? convertValueToPigeon(dynamic value) {
  if (value == null) return null;
  if (value is String || value is num || value is bool) return value;
  if (value is DateTime) {
    return <String?, Object?>{
      '__datatype__': 'timestamp',
      'milliseconds': value.millisecondsSinceEpoch,
    };
  }
  if (value is Timestamp) {
    return <String?, Object?>{
      '__datatype__': 'timestamp',
      'milliseconds': value.millisecondsSinceEpoch,
    };
  }
  if (value is GeoPoint) {
    return <String?, Object?>{
      'latitude': value.latitude,
      'longitude': value.longitude,
    };
  }
  if (value is Blob) return value.bytes;
  if (value is DocumentReferencePlatform) return value.path;
  if (value is FieldValuePlatform) {
    final delegate = FieldValuePlatform.getDelegate(value);
    final dynamic type = delegate.type;
    final dynamic operand = delegate.value;
    final op = type.toString().split('.').last;
    return <String?, Object?>{
      '__fieldValueOp__': op,
      'operand': convertValueToPigeon(operand),
    };
  }
  if (value is List) {
    return value.map(convertValueToPigeon).toList();
  }
  if (value is Map) {
    final result = <String?, Object?>{};
    value.forEach((key, val) {
      result[key.toString()] = convertValueToPigeon(val);
    });
    return result;
  }
  return value.toString();
}

Object? convertValueFromPigeon(dynamic value) {
  if (value == null) return null;
  if (value is String || value is bool) return value;
  if (value is double) return value;
  if (value is int) return value;
  if (value is List) {
    return value.map(convertValueFromPigeon).toList();
  }
  if (value is Map) {
    final map = value as Map<Object?, Object?>;

    final typeTag = map['__datatype__'];
    if (typeTag == 'timestamp') {
      final milliseconds = map['milliseconds'];
      if (milliseconds is int) {
        return Timestamp.fromMillisecondsSinceEpoch(milliseconds);
      }
      final seconds = map['seconds'];
      final nanoseconds = map['nanoseconds'];
      if (seconds is int && nanoseconds is int) {
        return Timestamp(seconds, nanoseconds);
      }
    }

    if (map.containsKey('latitude') && map.containsKey('longitude')) {
      return GeoPoint(
        (map['latitude'] as num).toDouble(),
        (map['longitude'] as num).toDouble(),
      );
    }

    final result = <String, dynamic>{};
    map.forEach((key, val) {
      if (key != null) {
        result[key.toString()] = convertValueFromPigeon(val);
      }
    });
    return result;
  }
  return value;
}
