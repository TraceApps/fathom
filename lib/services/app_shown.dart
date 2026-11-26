import 'package:flutter/widgets.dart';

/// Whether anyone can see the app: on screen, or on screen without the
/// keyboard's attention. False once it's minimized, in the background or
/// behind the lock screen.
///
/// A page that refreshes itself on a timer asks this first, so a page left
/// open doesn't keep asking a server for something nobody is looking at.
bool get appShown => appShownIn(WidgetsBinding.instance.lifecycleState);

@visibleForTesting
bool appShownIn(AppLifecycleState? state) => switch (state) {
  null || AppLifecycleState.resumed || AppLifecycleState.inactive => true,
  AppLifecycleState.hidden ||
  AppLifecycleState.paused ||
  AppLifecycleState.detached => false,
};
