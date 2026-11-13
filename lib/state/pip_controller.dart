import 'dart:async';

import 'package:flutter/foundation.dart' show VoidCallback;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../services/live_players.dart';

/// The docked mini-video state. Owning the [Player] here (handed off from a
/// player screen that's minimizing) is what lets playback survive navigation:
/// the screen never disposes the player, it transfers it, which also sidesteps
/// media_kit's teardown races.
///
/// Generic over the source: a YouTube watch page or the Jellyfin player both
/// dock here. [route] + the controller's [PipController.routeExtra] are how
/// tapping the dock reopens the right screen, and [matchId] is how that screen
/// recognises its own docked player to reclaim.
class PipState {
  final bool active;
  final String title;

  /// The docked item's id (YouTube videoId or Jellyfin item id), so the screen
  /// reopened from the dock can recognise and reclaim this same live player.
  final String matchId;

  /// The route tapping the dock returns to (e.g. '/youtube/watch' or '/player').
  final String route;

  /// Set the instant a reopen begins, so the mini dock stops rendering the
  /// video controller before the reopened screen mounts its own. A
  /// VideoController can only feed one Video widget; overlapping the two binds
  /// the live texture to the offstage dock and leaves the new screen black.
  final bool reclaiming;
  const PipState({
    this.active = false,
    this.title = '',
    this.matchId = '',
    this.route = '',
    this.reclaiming = false,
  });
}

class PipController extends Notifier<PipState> {
  Player? player;
  VideoController? controller;

  /// The go_router `extra` for [PipState.route], so the dock can reopen the
  /// screen with the same argument it was launched with.
  Object? routeExtra;

  /// Opaque state the minimizing screen stashes and reads back on reclaim (the
  /// Jellyfin live-TV player uses it to carry its open live-stream handles, so a
  /// reclaimed screen can still release the tuner). Null for players that need
  /// nothing.
  Object? handoffData;

  /// Finalizer run once when the dock is closed (not when reclaimed): the
  /// Jellyfin player uses it to report playback stopped so the resume point is
  /// saved. Passed the live player so it can read the final position.
  Future<void> Function(Player player)? _onClose;

  /// Run whenever the dock lets go of the player (reclaimed, closed or
  /// replaced): the YouTube player uses it to stop its dropout recovery.
  VoidCallback? _onRelease;

  void _release() {
    final r = _onRelease;
    _onRelease = null;
    r?.call();
  }

  @override
  PipState build() {
    ref.onDispose(() {
      _release();
      final p = player;
      player = null;
      controller = null;
      routeExtra = null;
      handoffData = null;
      _onClose = null;
      if (p != null) {
        LivePlayers.remove(p);
        unawaited(p.dispose());
      }
    });
    return const PipState();
  }

  /// Take over a live player + controller from a minimizing screen.
  void adopt({
    required Player player,
    required VideoController controller,
    required String title,
    required String matchId,
    required String route,
    required Object routeExtra,
    Object? handoffData,
    Future<void> Function(Player player)? onClose,
    VoidCallback? onRelease,
  }) {
    _release();
    if (this.player != null && this.player != player) {
      unawaited(_dispose(this.player!));
    }
    this.player = player;
    this.controller = controller;
    this.routeExtra = routeExtra;
    this.handoffData = handoffData;
    _onClose = onClose;
    _onRelease = onRelease;
    state = PipState(active: true, title: title, matchId: matchId, route: route);
  }

  /// Begin a reopen: hide the mini dock (so it releases the video controller)
  /// while keeping the live player, then the reopened screen reclaims it. Call
  /// this before navigating.
  void beginReclaim() {
    if (state.active && !state.reclaiming) {
      state = PipState(
          active: true,
          title: state.title,
          matchId: state.matchId,
          route: state.route,
          reclaiming: true);
    }
  }

  /// Drop the dock's ownership of the live player without disposing it, once the
  /// reopened screen has already taken the [player] and [controller] references.
  /// Playback continues on the reclaiming screen.
  ///
  /// Mutates state, so it must run outside a widget build/initState (schedule
  /// it in a post-frame callback).
  void detachForReclaim() {
    if (player == null && controller == null) return;
    _release();
    player = null;
    controller = null;
    routeExtra = null;
    handoffData = null;
    _onClose = null;
    state = const PipState();
  }

  /// Close the mini player and tear the video down.
  Future<void> close() async {
    final p = player;
    final cb = _onClose;
    _release();
    player = null;
    controller = null;
    routeExtra = null;
    handoffData = null;
    _onClose = null;
    // Remove the mini widget from the tree first so nothing renders a
    // disposed controller, then tear down on the next microtask.
    state = const PipState();
    if (p != null) {
      await Future<void>.delayed(Duration.zero);
      // Finalize (e.g. report the stop to Jellyfin) before disposing, while the
      // player can still report its position.
      if (cb != null) {
        try {
          await cb(p);
        } catch (_) {}
      }
      await _dispose(p);
    }
  }

  Future<void> _dispose(Player p) async {
    LivePlayers.remove(p);
    try {
      await p.stop();
    } catch (_) {}
    try {
      await p.dispose();
    } catch (_) {}
  }
}

final pipProvider = NotifierProvider<PipController, PipState>(PipController.new);
