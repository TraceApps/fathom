import 'dart:async' show Timer, unawaited;
import 'dart:io' show Platform, Process, ProcessSignal, pid, sleep;
import 'dart:isolate';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'l10n/generated/app_localizations.dart';
import 'l10n/l10n.dart';
import 'routing/app_router.dart';
import 'services/diagnostics.dart';
import 'services/settings_backup.dart' show secretPrefKeys;
import 'services/live_players.dart';
import 'services/tv_mode.dart';
import 'services/live_streams.dart';
import 'services/notifications.dart';
import 'state/audio_handler.dart';
import 'state/audio_player.dart';
import 'state/interface_scale.dart';
import 'state/syncplay_session.dart';
import 'state/mpris_integration.dart';
import 'state/smtc_integration.dart';
import 'state/pip_controller.dart';
import 'state/popout_controller.dart';
import 'state/preferences.dart';
import 'state/session_controller.dart';
import 'state/server_address.dart';
import 'theme/app_theme.dart';
import 'widgets/app_snack.dart';
import 'widgets/interface_scale.dart';
import 'widgets/popout_video.dart';
import 'widgets/window_frame.dart';

/// Lets a mouse and trackpad drag-scroll, not just touch. Without this, the
/// horizontal rows (Discover, Home) can't be scrolled at all on desktop, so
/// only the first few tiles are ever reachable.
/// Runs in a spawned isolate as the exit backstop. Its own thread keeps
/// ticking even when the main isolate's event loop is jammed (a stalled/failed
/// video load, or mpv work), so this SIGKILL still lands. [ms] is passed as the
/// spawn argument. Kept top-level because isolate entry points must be static.
void _forceKillAfter(int ms) {
  sleep(Duration(milliseconds: ms));
  try {
    Process.killPid(pid, ProcessSignal.sigkill);
  } catch (_) {}
}

class _AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  // Momentum-based scrolling with a soft overscroll, so every list feels
  // buttery and consistent across platforms rather than the abrupt desktop
  // clamp.
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(
          parent: RangeMaintainingScrollPhysics());
}

class FathomApp extends ConsumerStatefulWidget {
  const FathomApp({super.key});

  @override
  ConsumerState<FathomApp> createState() => _FathomAppState();
}

class _FathomAppState extends ConsumerState<FathomApp> with WindowListener {
  /// Last rites before the process goes.
  ///
  /// mpv is torn down while the Flutter engine is still alive: closing the
  /// window with playback running crashed on the way out, because the engine
  /// goes first and media_kit's video output then unregisters its texture
  /// against an engine that no longer exists. Screens dispose their own player,
  /// but quitting outright skips that, and the app-wide audio player hangs off
  /// a root provider whose onDispose never runs.
  ///
  /// Two exit paths need catching. [AppLifecycleListener.onExitRequested] covers
  /// the framework's own exit flow. [onWindowClose] covers window_manager's
  /// close (the custom titlebar X calls windowManager.close(), and Alt+F4 / the
  /// compositor route through here too) — main.dart sets preventClose so those
  /// land here instead of destroying the window immediately.
  ///
  /// Live TV streams are handed back for a blunter reason: a tuner is physical.
  /// Jellyfin holds one open until told otherwise, so quitting mid-channel pins
  /// it until the server restarts, and the next tune-in 500s.
  bool get _isDesktop =>
      !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onExitRequested: () async {
      await _teardown();
      return AppExitResponse.exit;
    },
  );

  bool _tearingDown = false;

  Future<void> _teardown() async {
    if (_tearingDown) return;
    _tearingDown = true;

    // Linux: the window-close kill is handled natively (linux/runner does a
    // hard _exit on the GTK thread, which also restores the terminal). That path
    // isn't blocked by the Dart event loop, which is routinely jammed at close
    // (startup, active playback) — the reason a Dart-side kill lagged for
    // seconds. So here we only fire the best-effort cleanup (release the SyncPlay
    // socket + Live TV tuner), never awaited so a network wait can't delay us,
    // and leave a slow fallback kill for exit paths that don't reach the native
    // handler (e.g. a framework onExitRequested rather than a window close).
    if (!kIsWeb && Platform.isLinux) {
      unawaited(
          ref.read(syncPlaySessionProvider).disconnect().catchError((_) {}));
      unawaited(LiveStreams.closeAll().catchError((_) {}));
      // Don't touch the terminal from here: tcsetattr off the foreground group
      // (a backgrounded dev run) raises SIGTTOU and can suspend the whole
      // process. The native close handler restores it safely on its own path.
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      try {
        Process.killPid(pid, ProcessSignal.sigkill);
      } catch (_) {}
      return;
    }

    // Windows: no native close handler, so do the kill here. The graceful mpv
    // disposal deadlocks against the live engine, so SIGKILL instead; a
    // spawned-isolate backstop fires even if the main event loop is jammed, and
    // a fast main-isolate kill covers the common case.
    if (!kIsWeb && Platform.isWindows) {
      Isolate.spawn(_forceKillAfter, 300).ignore();
      unawaited(
          ref.read(syncPlaySessionProvider).disconnect().catchError((_) {}));
      unawaited(LiveStreams.closeAll().catchError((_) {}));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      try {
        Process.killPid(pid, ProcessSignal.sigkill);
      } catch (_) {}
      return;
    }

    // macOS (and anything else): destroy the window cleanly, so do the full
    // graceful teardown first.
    try {
      await ref.read(syncPlaySessionProvider).disconnect();
    } catch (_) {}
    await LiveStreams.closeAll();
    await LivePlayers.disposeAll();
    try {
      final pip = ref.read(pipProvider.notifier);
      final p = pip.player;
      if (p != null) {
        pip.player = null;
        await p.stop();
        await p.dispose();
      }
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  @override
  void initState() {
    super.initState();
    _lifecycle; // create the listener
    if (_isDesktop) windowManager.addListener(this);
    // Android 13+: request the notification permission once the first frame is
    // up (needs a resumed Activity). Without it every notification — including
    // the media-playback controls — is silently blocked.
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AppNotifications.requestPermission();
      });
      // Bring the audio controller up now (when the OS media session exists), so
      // its Android Auto browse callbacks are wired even if the car starts us
      // headless and browses before any screen has mounted.
      if (ref.read(audioHandlerProvider) != null) {
        ref.read(audioControllerProvider.notifier);
      }
      // Draw edge-to-edge with transparent system bars (required behaviour on
      // Android 15+, and a cleaner look elsewhere): the app paints behind the
      // status and gesture-nav bars, and SafeArea insets the content. No forced
      // nav-bar contrast scrim; AppBars still set their own icon brightness.
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ));
    }
  }

  @override
  void onWindowClose() async {
    await _teardown();
    // On Windows the kill happens in _teardown; on Linux the native handler
    // hard-exits. Both race the engine shutdown, so don't also destroy the
    // window here (that can crash). Only macOS does a graceful window destroy.
    if (!kIsWeb && Platform.isMacOS) {
      await windowManager.destroy();
    }
  }

  // The window may now be on a different monitor, which may want a different
  // automatic interface size. Moves arrive continuously while dragging, so
  // check once it settles.
  Timer? _movedSettle;

  @override
  void onWindowMoved() {
    _movedSettle?.cancel();
    _movedSettle = Timer(const Duration(milliseconds: 500), () {
      if (mounted) ref.read(autoInterfaceScaleProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _movedSettle?.cancel();
    if (_isDesktop) windowManager.removeListener(this);
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    // Keep the desktop media integrations alive for the app's lifetime: MPRIS on
    // Linux, SMTC on Windows (each a no-op on the other platform).
    ref.watch(mprisProvider);
    ref.watch(smtcProvider);
    // Keep the internal/external address resolver alive (no-op unless the
    // active account has both addresses configured).
    ref.watch(serverAddressResolverProvider);
    final prefs = ref.watch(preferencesProvider).asData?.value ?? const Prefs();
    // Mirror the diagnostic-logging pref into the app-wide capture flag, so
    // global error hooks and app logs record from launch when it's on.
    Diagnostics.instance.enabled = prefs.diagnosticLogging;
    // And what it must never repeat, by value: the sign-in token and every
    // key and password in the settings.
    final secretPrefs = prefs.toJson();
    final session = ref.watch(sessionControllerProvider).asData?.value;
    Diagnostics.instance.protect(
      [
        session?.accessToken,
        for (final k in secretPrefKeys)
          if (secretPrefs[k] case final String v)
            v
          else if (secretPrefs[k] case final Map m)
            ...m.values.whereType<String>(),
      ],
      // Where the user's servers are: every address in the settings.
      addresses: [
        session?.baseUrl,
        session?.internalUrl,
        session?.externalUrl,
        for (final e in secretPrefs.entries)
          if (e.key.endsWith('Url') && e.value is String) e.value as String,
        for (final s in prefs.arrServers) '${s['url'] ?? ''}',
      ],
    );
    final accent = Color(prefs.accentColor);
    final mode = switch (prefs.themeMode) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    };

    return MaterialApp.router(
      title: 'Fathom',
      scaffoldMessengerKey: globalScaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(accent),
      darkTheme: AppTheme.dark(accent, amoled: prefs.amoled),
      themeMode: mode,
      routerConfig: router,
      scrollBehavior: _AppScrollBehavior(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Scaffolds are transparent (so the shell's ambient wash pervades the
      // app); this paints the solid base beneath everything.
      builder: (context, child) {
        // Record the resolved locale so no-context code (the notification layer)
        // can translate via `tr`. Safe here: the builder runs under Localizations.
        activeLocale = Localizations.localeOf(context);
        // Android TV: switch the routed content to Flutter's directional
        // navigation mode so a D-pad can reach and traverse every focusable
        // control systematically (not just the ones we hand-wrapped). Gated to
        // TV — desktop/mobile keep traditional pointer/tab focus behavior.
        if (isTvDevice) {
          child = MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(navigationMode: NavigationMode.directional),
            child: child ?? const SizedBox(),
          );
        }
        // Android TV / gamepad: the D-pad arrows already move focus (framework
        // default), but the center button ("Select") and gamepad A aren't mapped
        // to activation by default, so focused buttons couldn't be pressed with a
        // remote. Map them to ActivateIntent app-wide (harmless elsewhere — these
        // keys don't exist on a phone/desktop). This composes with the built-in
        // shortcuts rather than replacing them.
        final tvActivation = <ShortcutActivator, Intent>{
          const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
          const SingleActivator(LogicalKeyboardKey.gameButtonA):
              const ActivateIntent(),
        };
        // Interface Size: everything below, dialogs and menus included, drawn
        // at the chosen (or automatic) size. A no-op at 100% and off desktop.
        return InterfaceScale(
        scale: ref.watch(interfaceScaleProvider),
        child: Shortcuts(
        shortcuts: tvActivation,
        child: Consumer(
        builder: (context, ref, _) {
          final poppedOut = ref.watch(popoutProvider);
          return Stack(
            children: [
              WindowFrame(
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surface,
                  child: child ?? const SizedBox(),
                ),
              ),
              // The desktop pop-out fills the (shrunken) window over everything.
              // Wrapped in its own Overlay because this builder sits outside the
              // router's Navigator, and tooltips need an Overlay ancestor.
              if (poppedOut)
                Positioned.fill(
                  child: Overlay(
                    initialEntries: [
                      OverlayEntry(
                        builder: (_) => const Material(
                          color: Colors.black,
                          child: PopoutVideo(),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
        ),
        ),
        );
      },
    );
  }
}
