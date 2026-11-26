import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fathom/api/arr_client.dart';
import 'package:fathom/api/jellyfin_client.dart';
import 'package:fathom/state/retry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Riverpod asks a failed provider ten more times by itself, whatever the
// failure. A refused API key then shows a spinner for a minute and asks the
// server eleven times. The app's own rule: twice, and only for a connection
// that dropped or timed out.
void main() {
  DioException dio(DioExceptionType type, [int? status]) => DioException(
    requestOptions: RequestOptions(path: '/x'),
    type: type,
    response: status == null
        ? null
        : Response(requestOptions: RequestOptions(path: '/x'), statusCode: status),
  );

  test('a dropped or timed-out connection: twice, quickly', () {
    for (final e in <Object>[
      dio(DioExceptionType.connectionError),
      dio(DioExceptionType.connectionTimeout),
      dio(DioExceptionType.receiveTimeout),
      dio(DioExceptionType.sendTimeout),
      const SocketException('refused'),
      TimeoutException('slow'),
    ]) {
      expect(fathomRetry(0, e), isNotNull, reason: '$e');
      expect(fathomRetry(1, e), isNotNull, reason: '$e');
      expect(fathomRetry(2, e), isNull, reason: '$e');
      expect(fathomRetry(0, e)! + fathomRetry(1, e)!, lessThan(const Duration(seconds: 2)));
    }
  });

  test('an answer from the server is the answer', () {
    for (final e in <Object>[
      dio(DioExceptionType.badResponse, 401),
      dio(DioExceptionType.badResponse, 403),
      dio(DioExceptionType.badResponse, 404),
      dio(DioExceptionType.badResponse, 500),
      dio(DioExceptionType.badCertificate),
      dio(DioExceptionType.cancel),
      ArrException('Radarr rejected the API key.'),
      ArrException('Could not reach Radarr.'),
      const FormatException('not JSON'),
      StateError('Not signed in'),
    ]) {
      expect(fathomRetry(0, e), isNull, reason: '$e');
    }
  });

  test("a client's own error is judged by the failure inside it", () {
    // Jellyfin and the Manage apps wrap every failed request in their own
    // exception. Without this a TV that starts before its Wi-Fi does showed
    // empty pages until someone pressed Retry.
    final dropped = dio(DioExceptionType.connectionError);
    final refused = dio(DioExceptionType.badResponse, 401);
    expect(
      fathomRetry(0, JellyfinException('Lost connection.', cause: dropped)),
      isNotNull,
    );
    expect(
      fathomRetry(0, ArrException('Could not reach Radarr.', cause: dropped)),
      isNotNull,
    );
    expect(
      fathomRetry(0, JellyfinException('Sign in again.', cause: refused)),
      isNull,
    );
    expect(
      fathomRetry(0, ArrException('Radarr rejected the key.', cause: refused)),
      isNull,
    );
    // And still only twice.
    expect(
      fathomRetry(2, JellyfinException('Lost connection.', cause: dropped)),
      isNull,
    );
  });

  test('the clients hand the failure on with their message', () {
    for (final f in Directory('lib/api').listSync().whereType<File>()) {
      final src = f.readAsStringSync();
      expect(
        RegExp(r'JellyfinException\(_friendlyDioError\(e2?(, connecting: true)?\)\)')
            .hasMatch(src),
        isFalse,
        reason: f.path,
      );
      expect(
        RegExp(r'ArrException\((arrErrorMessage|arrAppErrorMessage|downloadErrorMessage)\([^)]*\)\)')
            .hasMatch(src),
        isFalse,
        reason: f.path,
      );
    }
  });

  test('a provider that a server refused is asked once', () async {
    var asked = 0;
    final refused = FutureProvider<int>((ref) async {
      asked++;
      throw ArrException('Radarr rejected the API key.');
    });
    final c = ProviderContainer(retry: fathomRetry);
    addTearDown(c.dispose);
    c.listen(refused, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    expect(asked, 1);
    expect(c.read(refused).hasError, isTrue);
    // And it says so at once, not after the retries.
    expect(c.read(refused).isLoading, isFalse);
  });

  test('one whose connection dropped is asked three times, then says so', () async {
    var asked = 0;
    final dropped = FutureProvider<int>((ref) async {
      asked++;
      throw dio(DioExceptionType.connectionError);
    });
    final c = ProviderContainer(retry: fathomRetry);
    addTearDown(c.dispose);
    c.listen(dropped, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    expect(asked, 3);
    expect(c.read(dropped).hasError, isTrue);
    expect(c.read(dropped).isLoading, isFalse);
  });

  test('the app and its background check both use it', () {
    expect(
      File('lib/main.dart').readAsStringSync(),
      contains('retry: fathomRetry'),
    );
    expect(
      File('lib/services/arr_background.dart').readAsStringSync(),
      contains('ProviderContainer(retry: fathomRetry)'),
    );
    // No other container is made without it.
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      expect(
        RegExp(r'ProviderContainer\(\s*\)').hasMatch(src),
        isFalse,
        reason: f.path,
      );
    }
  });
}
