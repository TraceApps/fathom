import 'dart:convert';
import 'dart:io';

import 'package:fathom/services/resilient_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Sign-ins, API keys and settings live in the system keyring. Where there is
// none at all, Fathom saves to a plain file instead of failing to start. One
// passing error used to move a whole run onto that file, in silence: the app
// opened signed out, and what was typed in was saved unprotected.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final keyring = <String, String>{};
  late Directory dir;

  /// How many of the next calls the keyring refuses.
  var failures = 0;
  var calls = 0;

  setUp(() {
    keyring.clear();
    failures = 0;
    calls = 0;
    dir = Directory.systemTemp.createTempSync('fathom_storage_test');
    ResilientSecureStorage.reset();
    ResilientSecureStorage.fallbackDirForTesting = dir;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls++;
          if (failures > 0) {
            failures--;
            throw PlatformException(code: 'Libsecret error', message: 'not ready');
          }
          final args = Map<String, dynamic>.from(call.arguments as Map);
          switch (call.method) {
            case 'read':
              return keyring[args['key']];
            case 'write':
              keyring['${args['key']}'] = '${args['value']}';
              return null;
            case 'delete':
              keyring.remove(args['key']);
              return null;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    ResilientSecureStorage.reset();
    ResilientSecureStorage.fallbackDirForTesting = null;
    dir.deleteSync(recursive: true);
  });

  File file() => File('${dir.path}/fathom_insecure_fallback.json');
  const storage = ResilientSecureStorage();

  test('a keyring that answers is all that is used', () async {
    await storage.write(key: 'k', value: 'v');
    expect(await storage.read(key: 'k'), 'v');
    expect(keyring, {'k': 'v'});
    expect(ResilientSecureStorage.usingFallback.value, isFalse);
    expect(file().existsSync(), isFalse);
  });

  test('one that fails once is asked again, and nothing moves', () async {
    keyring['session'] = 'signed-in';
    failures = 1;
    expect(await storage.read(key: 'session'), 'signed-in');
    expect(calls, 2);
    expect(ResilientSecureStorage.usingFallback.value, isFalse);
    failures = 1;
    await storage.write(key: 'k', value: 'v');
    expect(keyring['k'], 'v');
    expect(ResilientSecureStorage.usingFallback.value, isFalse);
    expect(file().existsSync(), isFalse);
  });

  test('one that is not there: the file, and the app says so', () async {
    failures = 1 << 30;
    expect(await storage.read(key: 'session'), isNull);
    expect(ResilientSecureStorage.usingFallback.value, isTrue);
    await storage.write(key: 'k', value: 'v');
    await storage.write(key: 'k2', value: 'v2');
    expect(await storage.read(key: 'k'), 'v');
    expect(jsonDecode(file().readAsStringSync()), {'k': 'v', 'k2': 'v2'});
    // Written whole: nothing half-written is left beside it.
    expect(
      dir.listSync().map((e) => e.uri.pathSegments.last).toList(),
      ['fathom_insecure_fallback.json'],
    );
    await storage.delete(key: 'k');
    expect(jsonDecode(file().readAsStringSync()), {'k2': 'v2'});
    // Once on the file, the keyring isn't asked again this run.
    final asked = calls;
    await storage.read(key: 'k2');
    expect(calls, asked);
  });
}
