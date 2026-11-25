import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'session_controller.dart';

/// The sign-in token the server no longer takes, once that's certain; null
/// while the session is good.
///
/// A token stops working when it's revoked on the server, when the device is
/// removed from the user's devices, or when the user is deleted. Every
/// request then fails with 401, and the app used to say "The server returned
/// an error (401)" on each row, with nothing to do about it.
class SessionExpiry extends Notifier<String?> {
  bool _checking = false;

  @override
  String? build() => null;

  /// A request carrying [token] came back 401. That alone isn't proof (some
  /// servers answer 401 for a thing one user may not do), so the server is
  /// asked once, plainly, whether it still knows the token.
  Future<void> refused(String token) async {
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null || session.accessToken != token) return;
    if (state == token || _checking) return;
    _checking = true;
    try {
      final gone = await ref
          .read(jellyfinClientProvider)
          .tokenRefused(baseUrl: session.baseUrl, token: token);
      if (!ref.mounted) return;
      final now = ref.read(sessionControllerProvider).asData?.value;
      if (gone && now?.accessToken == token) state = token;
    } finally {
      _checking = false;
    }
  }
}

final sessionExpiryProvider = NotifierProvider<SessionExpiry, String?>(
  SessionExpiry.new,
);

/// Whether the account in use has to sign in again. False again as soon as
/// it has (a new token) or another account is switched to.
final sessionExpiredProvider = Provider<bool>((ref) {
  final refused = ref.watch(sessionExpiryProvider);
  final session = ref.watch(sessionControllerProvider).asData?.value;
  return refused != null && session?.accessToken == refused;
});
