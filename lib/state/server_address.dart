import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'session_controller.dart';
import '../api/jellyfin_client.dart';

/// Keeps the active [Session.baseUrl] pointed at whichever address is reachable:
/// the internal (home/LAN) one whenever it answers, otherwise the external
/// (remote) one. The decision is pure reachability — never the raw Wi-Fi/cellular
/// event — so it stays seamless and invisible: at home it uses the fast local
/// address, away it falls back to the remote one, and it flips back on return.
///
/// It re-resolves at startup, on app resume, and on a periodic timer. It's a
/// no-op unless the active account has BOTH addresses configured, so
/// single-address accounts behave exactly as before.
///
/// Kept alive for the app's lifetime by a `ref.watch` in FathomApp.
final serverAddressResolverProvider = Provider<void>((ref) {
  final resolver = ServerAddressResolver(ref);
  resolver.start();
  ref.onDispose(resolver.dispose);
});

class ServerAddressResolver {
  final Ref _ref;
  Timer? _timer;
  _LifecycleObserver? _lifecycle;
  bool _resolving = false;

  ServerAddressResolver(this._ref);

  void start() {
    // Re-resolve whenever the active session changes (e.g. the user edits the
    // addresses in settings), plus once immediately for the startup probe.
    _ref.listen(sessionControllerProvider, (_, _) => _resolve(),
        fireImmediately: true);
    // This one keeps going in the background on purpose: music playing
    // with the screen off has to follow the phone from home Wi-Fi to mobile
    // data, and that means noticing the home address has gone.
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _resolve());
    _lifecycle = _LifecycleObserver(onResume: _resolve);
  }

  Future<void> _resolve() async {
    if (_resolving) return;
    final session = _ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return;
    final internal = session.internalUrl;
    final external = session.externalUrl;
    // Single-address mode: nothing to switch between.
    if (internal == null ||
        external == null ||
        internal.isEmpty ||
        external.isEmpty) {
      return;
    }
    _resolving = true;
    try {
      final client = _ref.read(jellyfinClientProvider);
      // Short timeout so the away-from-home fallback is quick.
      final internalOk = await client.pingServer(internal,
          timeout: const Duration(seconds: 2));
      final desired = internalOk ? internal : external;
      if (desired != session.baseUrl) {
        // Land the switch at the frame boundary, never synchronously inside a
        // build or a route/dialog teardown. A background probe can finish right
        // as a modal is being dismissed; emitting the session change mid-pop
        // deactivates an inherited scope while a widget still depends on it and
        // trips framework's `_dependents.isEmpty` assertion.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _ref
              .read(sessionControllerProvider.notifier)
              .setActiveBaseUrl(desired);
        });
      }
    } finally {
      _resolving = false;
    }
  }

  void dispose() {
    _timer?.cancel();
    _lifecycle?.dispose();
  }
}

/// Fires [onResume] when the app returns to the foreground, so the address is
/// re-checked the moment you're back (e.g. after walking in the door).
class _LifecycleObserver with WidgetsBindingObserver {
  final VoidCallback onResume;
  _LifecycleObserver({required this.onResume}) {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }

  void dispose() => WidgetsBinding.instance.removeObserver(this);
}
