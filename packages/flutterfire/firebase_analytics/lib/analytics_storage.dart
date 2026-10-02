import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class AnalyticsStorage {
  static const String _fileName =
      '.firebase_analytics_client_id';

  static Future<String> getClientId() async {
    try {
      // Returns an app-specific directory on webOS.
      final directory =
          await getApplicationSupportDirectory();

      final file = File(
        '${directory.path}/$_fileName',
      );

      // Reuse existing client ID if available.
      if (await file.exists()) {
        final existing =
            await file.readAsString();

        if (existing.trim().isNotEmpty) {
          return existing.trim();
        }
      }

      // Generate and persist a new client ID.
      final clientId =
          const Uuid().v4();

      await file.writeAsString(clientId);

      return clientId;
    } catch (_) {
      // Fallback if storage is unavailable.
      return const Uuid().v4();
    }
  }
}