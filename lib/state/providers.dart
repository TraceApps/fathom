import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/jellyfin_client.dart';
import '../services/resilient_secure_storage.dart';
import 'session_expiry.dart';

/// A stable per-install device id. Overridden in `main()` with the real value
/// read from secure storage before the app starts.
final deviceIdProvider = Provider<String>((ref) {
  throw UnimplementedError('deviceIdProvider must be overridden in main()');
});

final secureStorageProvider = Provider<ResilientSecureStorage>((ref) {
  return const ResilientSecureStorage();
});

final jellyfinClientProvider = Provider<JellyfinClient>((ref) {
  return JellyfinClient(deviceId: ref.watch(deviceIdProvider))
    // A refused sign-in token: checked, then the app asks to sign in again.
    ..onUnauthorized = (token) =>
        ref.read(sessionExpiryProvider.notifier).refused(token);
});
