// test/traffic_log_parsing_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flclash_v2board_client/business/auth/traffic_log_model.dart';

void main() {
  group('TrafficLogModel & Parsing Tests', () {
    test('Correctly parses standard V2Board / Laravel Paginator JSON with string types', () {
      final json = {
        'id': 101,
        'user_id': '42',
        'u': '52428800', // 50 MB as string
        'd': '104857600', // 100 MB as string
        'record_at': '1713000000',
        'server_rate': '1.50',
      };

      final model = TrafficLogModel.fromJson(json);

      expect(model.u, 52428800);
      expect(model.d, 104857600);
      expect(model.totalBytes, 157286400);
      expect(model.userId, 42);
      expect(model.recordAt, 1713000000);
      expect(model.serverRate, 1.50);
      expect(model.formattedUpload, '50.00 MB');
      expect(model.formattedDownload, '100.00 MB');
      expect(model.formattedTotal, '150.00 MB');
    });

    test('Correctly parses numeric types from standard API response', () {
      final json = {
        'u': 1073741824, // 1 GB
        'd': 2147483648, // 2 GB
        'record_at': 1713000000,
        'server_rate': 2.0,
      };

      final model = TrafficLogModel.fromJson(json);

      expect(model.u, 1073741824);
      expect(model.d, 2147483648);
      expect(model.totalBytes, 3221225472);
      expect(model.formattedTotal, '3.00 GB');
      expect(model.serverRate, 2.0);
    });

    test('Handles missing, null, or invalid values gracefully without throwing', () {
      final json = <String, dynamic>{
        'u': null,
        'd': null,
        'record_at': null,
        'server_rate': 'invalid_rate',
      };

      final model = TrafficLogModel.fromJson(json);

      expect(model.u, 0);
      expect(model.d, 0);
      expect(model.totalBytes, 0);
      expect(model.serverRate, 1.0); // default
      expect(model.formattedTotal, '0 B');
    });
  });
}
