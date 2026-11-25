import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// A drop-in [FlutterSecureStorage] replacement that transparently falls back
/// to a local, unencrypted file when the platform's secret service is entirely
/// unavailable, e.g. Steam Big Picture / gamescope on Linux, where there is no
/// D-Bus secret service to activate at all (flutter_secure_storage throws
/// "The name is not activatable" on every call). Without this, Fathom crashed
/// before its first frame (issue #32): `_getOrCreateDeviceId` ran unguarded in
/// `main()`, and the same secureStorageProvider backs login, saved passwords,
/// and every other persisted setting throughout the app.
///
/// The fallback only engages after a real failure is observed twice in a row
/// (a keyring that is slow to wake isn't one), never for a working keyring,
/// and then for the rest of the process, so a normal desktop session is
/// unaffected. While it's engaged [usingFallback] is true and the app says so
/// on screen: what was saved in the keyring before isn't there to read, and
/// what's saved now isn't protected. Values written while the fallback is active are NOT
/// encrypted; they're kept in a plain JSON file under the app's support
/// directory, the same tradeoff other desktop apps make when a platform gives
/// them no keyring at all. It's a compatibility fallback for a genuinely
/// absent keyring, not a general opt-out of security.
class ResilientSecureStorage {
  const ResilientSecureStorage();

  static const _delegate = FlutterSecureStorage();

  // Shared across every instance, so a failure discovered by one caller (say,
  // main()'s device-id lookup) is immediately known to every other caller
  // (every provider reading secureStorageProvider), instead of each one
  // separately re-discovering the same D-Bus failure on its own first call.
  static bool _secureBroken = false;
  static Map<String, String>? _fallbackCache;

  /// Whether this run is on the unencrypted file. The app shows a notice
  /// while it is.
  static final ValueNotifier<bool> usingFallback = ValueNotifier(false);

  /// Back to a first run, for tests.
  @visibleForTesting
  static void reset() {
    _secureBroken = false;
    _fallbackCache = null;
    usingFallback.value = false;
  }

  /// Where the file goes in tests, which must never touch the app's own.
  @visibleForTesting
  static Directory? fallbackDirForTesting;

  static Future<File> _fallbackFile() async {
    final dir = fallbackDirForTesting ?? await getApplicationSupportDirectory();
    return File('${dir.path}/fathom_insecure_fallback.json');
  }

  static Future<Map<String, String>> _loadFallback() async {
    final cached = _fallbackCache;
    if (cached != null) return cached;
    var map = <String, String>{};
    try {
      final file = await _fallbackFile();
      if (file.existsSync()) {
        final raw = jsonDecode(file.readAsStringSync());
        if (raw is Map) map = raw.map((k, v) => MapEntry('$k', '$v'));
      }
    } catch (_) {}
    return _fallbackCache = map;
  }

  static Future<void> _saveFallback(Map<String, String> map) async {
    try {
      // Whole or not at all: written beside the file, then put in its place,
      // so a run that ends halfway leaves the last good copy.
      final file = await _fallbackFile();
      final next = File('${file.path}.tmp')
        ..writeAsStringSync(jsonEncode(map), flush: true);
      next.renameSync(file.path);
    } catch (_) {}
  }

  void _markBroken(Object error) {
    if (_secureBroken) return;
    _secureBroken = true;
    usingFallback.value = true;
    debugPrint('[storage] system secret service unavailable ($error); '
        'falling back to a local unencrypted store for this session');
  }

  /// Asks the keyring, and once more after a moment when it fails: a keyring
  /// still waking up (just after sign-in to the desktop) answers the second
  /// time, and one failure used to move the whole run to the file.
  Future<T> _twice<T>(Future<T> Function() ask) async {
    try {
      return await ask();
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return ask();
    }
  }

  Future<String?> read({required String key}) async {
    if (!_secureBroken) {
      try {
        return await _twice(() => _delegate.read(key: key));
      } catch (e) {
        _markBroken(e);
      }
    }
    final map = await _loadFallback();
    return map[key];
  }

  Future<void> write({required String key, required String value}) async {
    if (!_secureBroken) {
      try {
        await _twice(() => _delegate.write(key: key, value: value));
        return;
      } catch (e) {
        _markBroken(e);
      }
    }
    final map = await _loadFallback();
    map[key] = value;
    await _saveFallback(map);
  }

  Future<void> delete({required String key}) async {
    if (!_secureBroken) {
      try {
        await _twice(() => _delegate.delete(key: key));
        return;
      } catch (e) {
        _markBroken(e);
      }
    }
    final map = await _loadFallback();
    if (map.remove(key) != null) await _saveFallback(map);
  }
}
