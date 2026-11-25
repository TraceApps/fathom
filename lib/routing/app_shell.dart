import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/jellyfin_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import '../services/resilient_secure_storage.dart';
import '../theme/app_theme.dart' show kInlineButtonStyle;
import '../services/tv_mode.dart';
import '../state/audio_player.dart';
import '../state/library_providers.dart';
import '../state/notifications_controller.dart';
import '../state/preferences.dart';
import '../state/providers.dart';
import '../services/arr_background.dart';
import '../state/arr_event_watcher.dart';
import '../state/seerr_request_watcher.dart';
import '../state/session_controller.dart';
import '../state/syncplay.dart';
import '../state/ui_providers.dart';
import '../state/updates.dart';
import '../widgets/window_frame.dart';
import '../widgets/tv_focus.dart';
import '../widgets/tv_keyboard.dart';
import 'nav_destinations.dart';
import '../widgets/seerr_icon.dart';
import '../widgets/glass.dart';
import '../widgets/app_logo.dart';
import '../widgets/download_pill.dart';
import '../widgets/update_banner.dart';
import '../widgets/mini_player.dart';
import '../widgets/mini_video.dart';
import '../widgets/user_avatar.dart';
import '../widgets/ui_common.dart';
import '../widgets/app_snack.dart';
import '../widgets/app_spinner.dart';


/// The shell's inner navigator. Held here so navigation code can pop any pushed
/// pages (a detail screen, Settings) when needed. Wired onto the [ShellRoute] in
/// app_router.dart.
final shellNavigatorKey = GlobalKey<NavigatorState>();

/// The GoRouter root navigator (full-screen routes like /player live here). A
/// stable handle so code outside the widget tree — e.g. the OS media session's
/// Stop button (SMTC/MPRIS) — can pop the player without a (possibly stale)
/// BuildContext.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// The phone shell's Scaffold, so a top-level screen's hamburger (see
/// [mobileDrawerLeading]) can open the slide-out navigation drawer from anywhere.
final shellScaffoldKey = GlobalKey<ScaffoldState>();

/// On TV, scroll a freshly-focused rail tile into view (centered). The rail's
/// sticky-footer sliver doesn't reliably auto-scroll on upward focus moves, so
/// do it explicitly. No-op off TV or when not inside a scrollable; clamps at the
/// ends, so the first/last tile isn't pushed past the edge.
void _tvEnsureVisible(BuildContext context) {
  if (!isTvDevice || !context.mounted) return;
  if (Scrollable.maybeOf(context) == null) return;
  Scrollable.ensureVisible(context,
      alignment: 0.5,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut);
}

/// A hamburger for a top-level screen's AppBar that opens the phone navigation
/// drawer. Returns null on tablet/desktop, which use the persistent rail instead
/// of a drawer, so those screens get no leading button. Screens use it as
/// `AppBar(leading: mobileDrawerLeading(context), ...)`.
Widget? mobileDrawerLeading(BuildContext context) {
  // TV uses the persistent rail, so top-level screens get no leading button.
  if (isTvDevice) return null;
  if (MediaQuery.of(context).size.shortestSide >= 600) return null;
  return const DrawerMenuButton();
}

/// Leading control for a secondary screen's AppBar on phones. Shows a Back
/// button when the route can pop (reached via push, e.g. the offline banner's
/// jump to Downloads, or an artist opened from the Artists list), otherwise the
/// drawer hamburger (reached as a drawer destination via `go`, e.g. Playlists,
/// Genres, Downloads), so those screens are never a dead end. Null on
/// tablet/desktop, which navigate from the persistent rail.
Widget? mobileLeading(BuildContext context) {
  // TV: a secondary (pushed) screen shows a focusable Back button; a top-level
  // screen relies on the persistent rail, so no hamburger.
  if (isTvDevice) {
    return Navigator.of(context).canPop() ? const BackButton() : null;
  }
  if (MediaQuery.of(context).size.shortestSide >= 600) return null;
  if (Navigator.of(context).canPop()) return const BackButton();
  return const DrawerMenuButton();
}

/// The hamburger itself: opens the drawer and carries a small badge when there
/// are unread notifications or an available update, so those stay noticeable
/// without opening the drawer (the animated bell lives inside it). On desktop it
/// renders nothing.
class DrawerMenuButton extends ConsumerWidget {
  const DrawerMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isTvDevice || MediaQuery.of(context).size.shortestSide >= 600) {
      return const SizedBox.shrink();
    }
    final unread = ref.watch(unreadNotifCountProvider);
    final updateAvailable = ref
            .watch(updateControllerProvider)
            .asData
            ?.value
            ?.updateAvailable ??
        false;
    Widget icon = const Icon(Icons.menu_rounded);
    if (unread > 0) {
      icon = Badge(
          label: Text(unread > 99 ? '99+' : '$unread'), child: icon);
    } else if (updateAvailable) {
      icon = Badge(child: icon);
    }
    return IconButton(
      icon: icon,
      tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
      onPressed: () => shellScaffoldKey.currentState?.openDrawer(),
    );
  }
}

/// Wraps the signed-in content routes with a desktop navigation rail and docks
/// the mini now-playing bar at the bottom. Full-screen routes (video player,
/// now-playing, auth) sit outside this.
class AppShell extends ConsumerWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final location = GoRouterState.of(context).matchedLocation;
    final extended = ref.watch(railExtendedProvider);
    // Keep the Seerr request poller alive for the app's lifetime (no-op until
    // Seerr is configured), so request status changes fire notifications.
    ref.watch(seerrRequestWatcherProvider);
    // What Sonarr, Radarr and Lidarr did, into the bell.
    ref.watch(arrEventWatcherProvider);
    // And while Fathom is closed, on Android.
    ref.watch(arrBackgroundScheduleProvider);
    // On a TV the bottom mini-player is hard to drive with a remote, so when
    // music actually starts (nothing → a track) open the full Now Playing
    // screen, which is fully D-pad operable. Track-to-track changes don't
    // re-trigger it, so browsing while music plays is undisturbed.
    if (isTvDevice) {
      ref.listen(audioControllerProvider.select((s) => s.current?.id),
          (prev, next) {
        if (prev == null && next != null) {
          if (location != '/nowplaying' && location != '/player') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) context.push('/nowplaying');
            });
          }
        }
      });
    }

    // Destinations come from the shared registry, then get the user's saved
    // order + hidden set applied (Settings > Navigation).
    final prefs = ref.watch(preferencesProvider).asData?.value ?? const Prefs();
    final destinations =
        orderNavDestinations(availableNavDestinations(ref, l), prefs);
    final scheme = Theme.of(context).colorScheme;

    // Phones get a slide-out drawer shell; tablets and desktop keep the rail.
    // A TV always keeps the rail (never the drawer) even though its logical
    // shortestSide can read below 600: a persistent, always-on-screen rail is
    // the reachable-by-D-pad navigation, where a hamburger drawer is not.
    if (MediaQuery.of(context).size.shortestSide < 600 && !isTvDevice) {
      return _MobileShell(
          destinations: destinations, location: location, child: child);
    }

    const dur = Duration(milliseconds: 240);
    const curve = Curves.easeOutCubic;
    // The rail is persistent on TV but collapsible: it defaults to expanded
    // there (see railExtendedProvider) and the menu button toggles it to a slim
    // icon rail, so `extended` alone drives the width on every platform.
    // A tighter expanded rail on TV (less oversized from the couch).
    final width = extended ? (isTvDevice ? 200.0 : 228.0) : 76.0;

    // The rail is its own focus-traversal group so a D-pad's Up/Down cycles the
    // nav destinations instead of escaping sideways into the content grid; the
    // remote only crosses to content when there's nothing left in the pressed
    // direction within the rail (and vice-versa for the content group below).
    final sidebar = FocusTraversalGroup(
      policy: isTvDevice ? TvRailPolicy() : null,
      child: NavSidebar(
        destinations: destinations,
        extended: extended,
        onToggle: () => ref.read(railExtendedProvider.notifier).toggle(),
      ),
    );

    // A Material ancestor so all shell chrome (profile menu, tooltips, ink)
    // always has one, regardless of what the child route provides.
    //
    // The top SafeArea clears the status bar when this rail shell runs on an
    // Android tablet (shortestSide >= 600). On desktop the WindowFrame injects a
    // 34px top padding for full-bleed art to run BEHIND the transparent title
    // bar, so we must NOT consume it here (that left a solid strip above heroes)
    // — the nested Scaffolds drop their app bars below the title bar instead.
    return Material(
      color: scheme.surface,
      child: SafeArea(
        top: !isDesktopWindowFrame,
        bottom: false,
        child: Column(
          children: [
            const _OfflineBanner(),
            const _KeyringBanner(),
          Expanded(
            child: Stack(
              children: [
                // An accent wash across the whole surface. It now shows through
                // the (transparent) content too, giving the app a soft ambient
                // depth behind cards and bars rather than a flat slab.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color.alphaBlend(
                              scheme.primary.withValues(alpha: 0.10),
                              scheme.surface),
                          scheme.surface,
                          Color.alphaBlend(
                              scheme.tertiary.withValues(alpha: 0.06),
                              scheme.surface),
                        ],
                        stops: const [0, 0.55, 1],
                      ),
                    ),
                  ),
                ),
                // Routed content, inset for the sidebar. Transparent so the
                // ambient wash reads behind it.
                AnimatedPositioned(
                  duration: dur,
                  curve: curve,
                  left: width,
                  top: 0,
                  right: 0,
                  bottom: 0,
                  child: isTvDevice
                      ? TvContent(location: location, child: child)
                      : FocusTraversalGroup(
                          child: Material(
                              color: Colors.transparent, child: child),
                        ),
                ),
                // Frosted glass sidebar floating over the wash.
                AnimatedPositioned(
                  duration: dur,
                  curve: curve,
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: width,
                  child: GlassSurface(
                    blur: 26,
                    opacity: 0.55,
                    border: Border(
                      right: BorderSide(
                          color: scheme.outlineVariant.withValues(alpha: 0.3)),
                    ),
                    // Keep the sidebar's controls clear of the window title bar
                    // while the glass itself runs to the top edge.
                    child: SafeArea(
                      top: true,
                      right: false,
                      bottom: false,
                      child: sidebar,
                    ),
                  ),
                ),
                // Floating minimized video (picture-in-picture).
                const MiniVideo(),
                const Positioned.fill(child: DownloadPills()),
                const Positioned.fill(child: UpdateBanner()),
              ],
            ),
          ),
          const MiniPlayer(),
          ],
        ),
      ),
    );
  }
}

/// The navigation rail contents: brand header, destinations (with the
/// expandable Libraries and Browse groups), and the update/notifications/account
/// controls at the foot. Shared by the desktop rail and the phone's slide-out
/// drawer, so both look and behave the same.
class NavSidebar extends ConsumerWidget {
  final List<NavDest> destinations;
  final bool extended;

  /// The rail's collapse toggle; null hides it (the phone drawer has no collapse).
  final VoidCallback? onToggle;

  const NavSidebar({
    super.key,
    required this.destinations,
    this.extended = true,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    // Prefer the live policy; fall back to the stored session flag while it loads.
    final liveAdmin =
        ref.watch(currentUserProvider).asData?.value?.isAdministrator;
    final storedAdmin =
        ref.watch(sessionControllerProvider).asData?.value?.isAdmin ?? false;
    final isAdmin = liveAdmin ?? storedAdmin;
    // The rail's D-pad landing tile (tvNavBarNode). Prefer the active
    // destination, but a pushed route (e.g. /item detail) matches nothing, so
    // fall back to the first plain tile — never the expandable Libraries group —
    // so the node is ALWAYS attached and LEFT-from-content reliably reaches the
    // rail on every screen.
    final plain = destinations.where((d) => d.route != '/libraries');
    final navAnchorRoute = plain
        .firstWhere((d) => location.startsWith(d.route),
            orElse: () => plain.isEmpty ? destinations.first : plain.first)
        .route;
    // The scrollable nav destinations (shared by both layouts).
    final navTiles = <Widget>[
      for (final d in destinations)
        if (d.route == '/libraries') ...[
          _LibrariesNav(extended: extended, location: location),
          _BrowseNav(extended: extended, location: location),
        ] else
          _NavTile(
            label: d.label,
            extended: extended,
            selected: location.startsWith(d.route),
            // On TV the anchor tile owns the rail's landing node, so
            // LEFT from content always reaches the rail (see navAnchorRoute).
            focusNode: (isTvDevice && d.route == navAnchorRoute)
                ? tvNavBarNode
                : null,
            icon: d.route == '/discover' ? null : d.icon,
            iconBuilder: d.route == '/discover'
                ? (color) => SeerrIcon(color: color)
                : null,
            onTap: () => context.go(d.route),
          ),
    ];

    // On TV the mini player sits outside the D-pad content scope, so it's
    // unreachable by the remote. A Now Playing rail entry (only while audio is
    // loaded, and not already on that screen) is the reachable way back to the
    // full music/radio screen.
    final nowPlayingEntry = Consumer(builder: (context, ref, _) {
      final hasAudio = ref
          .watch(audioControllerProvider.select((s) => s.current != null || s.isRadio));
      if (!hasAudio || location == '/nowplaying') {
        return const SizedBox.shrink();
      }
      return _NavTile(
        label: AppLocalizations.of(context).playerNowPlaying,
        extended: extended,
        selected: false,
        icon: Icons.music_note_rounded,
        onTap: () => context.push('/nowplaying'),
      );
    });

    // The foot controls: update indicator (only when an update is available),
    // notifications, account/settings.
    final footControls = <Widget>[
      _UpdateRailButton(extended: extended),
      _NotifBell(extended: extended),
      const SizedBox(height: 2),
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
        child: _ProfileMenu(isAdmin: isAdmin, extended: extended),
      ),
    ];

    // TV: everything lives in ONE scroll view so a D-pad can walk DOWN through
    // every item (nav → Now Playing → notifications → account) — nothing is
    // pinned outside the scrollable out of the remote's reach. A sticky footer
    // (SliverFillRemaining + Spacer) keeps the account/notifications controls
    // pinned to the BOTTOM when the nav fits, and lets the whole thing scroll
    // when it doesn't. Desktop/phone keep the pinned-foot Column layout below.
    if (isTvDevice) {
      // On TV the foot controls are rendered as ordinary nav tiles: the desktop
      // foot widgets (notifications bell, account popup) are bare GestureDetectors
      // with no focus node, so a D-pad can't land on them AND they don't line up
      // with the nav icons/labels. As tiles they're focusable, reachable by DOWN,
      // and perfectly aligned with the rest of the rail.
      final tvFoot = <Widget>[
        Consumer(builder: (context, ref, _) {
          final upd = ref.watch(updateControllerProvider).asData?.value;
          if (upd == null || !upd.updateAvailable) {
            return const SizedBox.shrink();
          }
          return _NavTile(
            icon: Icons.system_update_alt_rounded,
            label: AppLocalizations.of(context).updatesTitle,
            selected: location.startsWith('/updates'),
            extended: extended,
            onTap: () => context.push('/updates'),
          );
        }),
        Consumer(builder: (context, ref, _) {
          final scheme = Theme.of(context).colorScheme;
          final count = ref.watch(unreadNotifCountProvider);
          return _NavTile(
            icon: Icons.notifications_rounded,
            label: AppLocalizations.of(context).miscNotifications,
            selected: location.startsWith('/notifications'),
            extended: extended,
            trailing: count > 0
                ? Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                        color: scheme.error,
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(count > 99 ? '99+' : '$count',
                        style: TextStyle(
                            color: scheme.onError,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  )
                : null,
            onTap: () => context.push('/notifications'),
          );
        }),
        // One account tile that opens the SAME menu as the desktop/mobile
        // profile popup, in the same order (Profile, Watch Together, Quick
        // Connect, Settings, Administration, Sign Out) — not split into separate
        // rail buttons.
        Consumer(builder: (context, ref, _) {
          final name =
              ref.watch(sessionControllerProvider).asData?.value?.userName;
          return _NavTile(
            iconBuilder: (_) => const UserAvatar(radius: 11),
            label: name ?? AppLocalizations.of(context).miscAccount,
            selected: false,
            extended: extended,
            onTap: () => _showTvAccountMenu(context, ref, isAdmin: isAdmin),
          );
        }),
      ];
      return Column(
        children: [
          _BrandHeader(extended: extended, onToggle: onToggle),
          const SizedBox(height: 2),
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      children: [
                        ...navTiles,
                        nowPlayingEntry,
                        const Spacer(),
                        ...tvFoot,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        _BrandHeader(extended: extended, onToggle: onToggle),
        const SizedBox(height: 6),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: navTiles,
          ),
        ),
        ...footControls,
      ],
    );
  }
}

/// The phone layout: routed content with a slide-out navigation drawer, which is
/// the same [NavSidebar] the desktop uses as its rail. It's opened by the
/// hamburger in each top-level screen's app bar ([mobileDrawerLeading]) or an
/// edge swipe, and dismissed automatically on navigation. Tablets/desktop use
/// the persistent rail in [AppShell] instead.
class _MobileShell extends ConsumerStatefulWidget {
  final List<NavDest> destinations;
  final String location;
  final Widget child;
  const _MobileShell({
    required this.destinations,
    required this.location,
    required this.child,
  });

  @override
  ConsumerState<_MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends ConsumerState<_MobileShell> {
  GoRouter? _router;

  @override
  void initState() {
    super.initState();
    // Run the startup update check here too: on mobile the rail button that
    // normally triggers it lives in the drawer, which isn't built until opened,
    // so without this the check (and its notification/banner) would wait for the
    // user to open the drawer. check() is a no-op if one already ran this launch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(updateControllerProvider.notifier).maybeAutoCheck(startup: true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Close the drawer on ANY navigation. The router delegate notifies on every
    // route change (both go() and push()), which is reliable — comparing the
    // shell's matchedLocation missed pushed routes (Settings, a library), so the
    // drawer stayed open over them.
    final router = GoRouter.of(context);
    if (router != _router) {
      _router?.routerDelegate.removeListener(_closeDrawer);
      _router = router;
      _router!.routerDelegate.addListener(_closeDrawer);
    }
  }

  void _closeDrawer() {
    final state = shellScaffoldKey.currentState;
    if (state != null && state.isDrawerOpen) state.closeDrawer();
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_closeDrawer);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      key: shellScaffoldKey,
      backgroundColor: scheme.surface,
      drawer: Drawer(
        // Match the desktop rail's extended width (228) rather than Material's
        // wide default, so it doesn't hog the phone screen.
        width: 236,
        backgroundColor: scheme.surface,
        child: SafeArea(
          right: false,
          child: NavSidebar(destinations: widget.destinations),
        ),
      ),
      // The top status-bar inset is reserved once here so the offline banner and
      // content clear it (SafeArea removes it from the MediaQuery below, so the
      // nested screens don't double-inset). On desktop the WindowFrame's 34px is
      // left in place so full-bleed art runs behind the transparent title bar.
      body: SafeArea(
        top: !isDesktopWindowFrame,
        bottom: false,
        left: false,
        right: false,
        child: Column(
          children: [
            const _OfflineBanner(),
            const _KeyringBanner(),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: SafeArea(
                      top: !isDesktopWindowFrame,
                      bottom: false,
                      child: Material(
                          color: Colors.transparent, child: widget.child),
                    ),
                  ),
                  const MiniVideo(),
                  const Positioned.fill(child: DownloadPills()),
                const Positioned.fill(child: UpdateBanner()),
                ],
              ),
            ),
            const MiniPlayer(),
          ],
        ),
      ),
    );
  }
}

/// A slim bar shown when the active server can't be reached, with a shortcut to
/// what's still available offline: downloads.
class _OfflineBanner extends ConsumerWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reachable = ref.watch(serverReachableProvider).asData?.value ?? true;
    if (reachable) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 8, 8 + (isDesktopWindowFrame ? kWindowControlsWidth : 0), 8),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 18, color: scheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(l.appServerUnreachableOffline,
                  style: TextStyle(
                      color: scheme.onErrorContainer,
                      fontWeight: FontWeight.w600)),
            ),
            TextButton(
              onPressed: () => context.push('/downloads'),
              style: TextButton.styleFrom(
                  foregroundColor: scheme.onErrorContainer),
              child: Text(l.appDownloads),
            ),
          ],
        ),
      ),
    );
  }
}

/// A slim bar shown while the system keyring can't be used and sign-ins and
/// keys go to a file that isn't encrypted (see [ResilientSecureStorage]), so
/// that it's never a silent change: what was saved before isn't there this
/// run, and what's saved now isn't protected.
class _KeyringBanner extends StatelessWidget {
  const _KeyringBanner();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: ResilientSecureStorage.usingFallback,
    builder: (context, fallback, _) {
      if (!fallback) return const SizedBox.shrink();
      final l = AppLocalizations.of(context);
      final scheme = Theme.of(context).colorScheme;
      return Material(
        color: scheme.errorContainer,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            8 + (isDesktopWindowFrame ? kWindowControlsWidth : 0),
            8,
          ),
          child: Row(
            children: [
              Icon(
                Icons.key_off_rounded,
                size: 18,
                color: scheme.onErrorContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l.storageFallbackBanner,
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: Text(l.storageFallbackTitle),
                    content: Text(l.storageFallbackBody),
                    actions: [
                      FilledButton(
                        style: kInlineButtonStyle,
                        autofocus: true,
                        onPressed: () => Navigator.pop(d),
                        child: Text(
                          MaterialLocalizations.of(d).okButtonLabel,
                        ),
                      ),
                    ],
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onErrorContainer,
                ),
                child: Text(l.storageFallbackDetails),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// A rail-foot indicator shown only when a newer release is available. Kicks
/// the throttled startup check on first build, then watches the result; tapping
/// it opens the Updates screen. Accent-tinted so it reads as an action, and it
/// simply disappears once you're on the latest version.
class _UpdateRailButton extends ConsumerStatefulWidget {
  final bool extended;
  const _UpdateRailButton({required this.extended});

  @override
  ConsumerState<_UpdateRailButton> createState() => _UpdateRailButtonState();
}

class _UpdateRailButtonState extends ConsumerState<_UpdateRailButton> {
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(updateControllerProvider.notifier).maybeAutoCheck(startup: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(updateControllerProvider).asData?.value;
    if (status == null || !status.updateAvailable) {
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final version = status.latest!.version;
    final icon = Icon(Icons.system_update_alt_rounded,
        color: scheme.primary, size: 23);

    void open() => context.push('/updates');

    if (!widget.extended) {
      return Tooltip(
        message: l.updateBannerAvailable(version),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: open,
            child: Container(
              height: 44,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: _hover
                    ? scheme.primary.withValues(alpha: 0.12)
                    : scheme.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(child: icon),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: open,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 48,
            decoration: BoxDecoration(
              color: _hover
                  ? scheme.primary.withValues(alpha: 0.14)
                  : scheme.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const SizedBox(width: 16),
                icon,
                const SizedBox(width: 16),
                Expanded(
                  child: Text(l.updatesTitle,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      softWrap: false,
                      style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The branded header at the top of the sidebar: wordmark + collapse toggle.
class _BrandHeader extends StatelessWidget {
  final bool extended;
  // Null in the phone drawer, which has no collapse toggle.
  final VoidCallback? onToggle;
  const _BrandHeader({required this.extended, this.onToggle});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    // Themed mark (tinted to the accent) rather than the full colored tile, so
    // it sits with the flat sidebar chrome like the Seerr icon does.
    final tv = isTvDevice;
    final logo = FathomGlyph(size: tv ? 26 : 30, color: scheme.primary);
    if (extended) {
      return SizedBox(
        height: tv ? 50 : 60,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 8, 0),
          child: Row(
            children: [
              logo,
              const SizedBox(width: 10),
              Expanded(
                child: Text('Fathom',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    softWrap: false,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800, letterSpacing: -0.3)),
              ),
              if (onToggle != null)
                IconButton(
                  tooltip: l.miscCollapseSidebar,
                  icon: const Icon(Icons.menu_open_rounded),
                  onPressed: onToggle,
                ),
            ],
          ),
        ),
      );
    }
    // Collapsed: just the expand toggle, centred.
    return SizedBox(
      height: tv ? 50 : 60,
      child: Center(
        child: IconButton(
          tooltip: l.miscExpandSidebar,
          icon: const Icon(Icons.menu_rounded),
          onPressed: onToggle,
        ),
      ),
    );
  }
}

/// The sidebar notification bell with an unread badge; opens the notification
/// centre. The bell swings like it's being rung the moment a new notification
/// arrives, and gives a gentle re-ring on a timer while any stay unread.
class _NotifBell extends ConsumerStatefulWidget {
  final bool extended;
  const _NotifBell({this.extended = false});

  @override
  ConsumerState<_NotifBell> createState() => _NotifBellState();
}

class _NotifBellState extends ConsumerState<_NotifBell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ring = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 720));
  // A decaying swing, pivoting at the top like a real handbell.
  late final Animation<double> _angle = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.24), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 0.24, end: -0.19), weight: 2),
    TweenSequenceItem(tween: Tween(begin: -0.19, end: 0.14), weight: 2),
    TweenSequenceItem(tween: Tween(begin: 0.14, end: -0.09), weight: 2),
    TweenSequenceItem(tween: Tween(begin: -0.09, end: 0.05), weight: 2),
    TweenSequenceItem(tween: Tween(begin: 0.05, end: 0.0), weight: 2),
  ]).animate(CurvedAnimation(parent: _ring, curve: Curves.easeInOut));
  Timer? _timer;
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted &&
          ref.read(unreadNotifCountProvider) > 0 &&
          !_ring.isAnimating) {
        _ring.forward(from: 0);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ring at once when the unread count climbs (a fresh notification).
    ref.listen<int>(unreadNotifCountProvider, (prev, next) {
      if (next > (prev ?? 0) && !_ring.isAnimating) _ring.forward(from: 0);
    });
    final l = AppLocalizations.of(context);
    final count = ref.watch(unreadNotifCountProvider);
    final scheme = Theme.of(context).colorScheme;
    final fg = _hover ? scheme.onSurface : scheme.onSurfaceVariant;

    final bell = AnimatedBuilder(
      animation: _angle,
      builder: (_, child) => Transform.rotate(
          angle: _angle.value, alignment: Alignment.topCenter, child: child),
      child: Icon(Icons.notifications_rounded, color: fg, size: 23),
    );
    final badged = Badge(
      isLabelVisible: count > 0,
      label: Text(count > 99 ? '99+' : '$count'),
      child: bell,
    );

    void open() => context.push('/notifications');

    if (!widget.extended) {
      return Tooltip(
        message: l.miscNotifications,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: open,
            child: Container(
              height: 44,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: _hover
                    ? scheme.onSurface.withValues(alpha: 0.06)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(child: badged),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: open,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 48,
            decoration: BoxDecoration(
              color: _hover
                  ? scheme.onSurface.withValues(alpha: 0.06)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const SizedBox(width: 16),
                badged,
                const SizedBox(width: 16),
                Expanded(
                  child: Text(l.miscNotifications,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      softWrap: false,
                      style: TextStyle(color: fg, fontWeight: FontWeight.w500)),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A single sidebar entry with an animated selection pill and hover highlight.
class _NavTile extends StatefulWidget {
  final IconData? icon;
  final Widget Function(Color color)? iconBuilder;
  final String label;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;
  final Widget? trailing; // shown at the right edge when extended
  final FocusNode? focusNode;
  const _NavTile({
    required this.label,
    required this.selected,
    required this.extended,
    required this.onTap,
    this.icon,
    this.iconBuilder,
    this.trailing,
    this.focusNode,
  });

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hover = false;
  // D-pad/keyboard focus (TV remotes) reuses the hover highlight.
  bool _focused = false;
  bool get _active => _hover || _focused;

  @override
  void didUpdateWidget(_NavTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // On a TV the rail's landing node moves to the tile of the section that
    // opened: the node this tile was lit by is no longer the one it hears
    // from, so it would stay lit once the remote has gone into the page.
    if (oldWidget.focusNode != widget.focusNode) {
      _focused = widget.focusNode?.hasFocus ?? false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final fg = selected
        ? scheme.primary
        : (_active ? scheme.onSurface : scheme.onSurfaceVariant);
    final bg = selected
        ? scheme.primary.withValues(alpha: 0.14)
        : (_active
            ? scheme.onSurface.withValues(alpha: 0.06)
            : Colors.transparent);

    // On TV the rail is tighter (smaller rows, icons, text, gaps) so the whole
    // set fits on-screen without feeling oversized from the couch.
    final tv = isTvDevice;
    final gap = tv ? 12.0 : 16.0;
    final iconWidget = widget.iconBuilder != null
        ? widget.iconBuilder!(fg)
        : Icon(widget.icon, color: fg, size: tv ? 20 : 23);

    Widget tile = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: FocusableActionDetector(
        // A new detector with a new node: the old one never heard its node
        // lose the remote, and would take the next focus as no change.
        key: ObjectKey(widget.focusNode),
        focusNode: widget.focusNode,
        // TV needs real focus (D-pad) to light the tile; off TV keep the original
        // keyboard-highlight-only behaviour so desktop is unchanged.
        onFocusChange: isTvDevice
            ? (v) {
                setState(() => _focused = v);
                if (v) _tvEnsureVisible(context);
              }
            : null,
        onShowFocusHighlight:
            isTvDevice ? null : (v) => setState(() => _focused = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          height: tv ? 40 : 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            // A bold accent ring when a D-pad remote lands on the tile, so the
            // current nav target is unmistakable from the couch.
            border: _focused
                ? Border.all(color: scheme.primary, width: 2.5)
                : null,
          ),
          child: widget.extended
              ? Row(
                  children: [
                    SizedBox(width: gap),
                    iconWidget,
                    SizedBox(width: gap),
                    Expanded(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        softWrap: false,
                        style: TextStyle(
                          color: fg,
                          fontSize: tv ? 13.5 : null,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (widget.trailing != null) widget.trailing!,
                    const SizedBox(width: 8),
                  ],
                )
              : Center(child: iconWidget),
        ),
      ),
      ),
    );

    if (!widget.extended) {
      tile = Tooltip(message: widget.label, child: tile);
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: tv ? 1.5 : 3),
      child: tile,
    );
  }
}

/// The Libraries nav item: tapping the row opens the full Libraries screen; the
/// chevron expands an inline list of the user's libraries (Live TV excluded —
/// it has its own section).
/// Genres, Studios, Artists, Playlists and Downloads — each has a full screen,
/// but they were reachable only as chips inside the Libraries hub. Grouped here
/// under one expandable "Browse" item so they're a tap away without crowding
/// the top level.
class _BrowseNav extends ConsumerWidget {
  final bool extended;
  final String location;
  const _BrowseNav({required this.extended, required this.location});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final expanded = ref.watch(browseNavExpandedProvider);
    // On phones these are drill-downs, so push (a real Back button, uniform with
    // Settings/details). On the desktop rail they're peers you switch between, so
    // keep the replace so the rail selection tracks and pages don't stack.
    final mobile = MediaQuery.of(context).size.shortestSide < 600;
    void openBrowse(String route) =>
        mobile ? context.push(route) : context.go(route);
    final items = <(String, String, IconData)>[
      (l.miscNavPlaylists, '/playlists', Icons.playlist_play_rounded),
      (l.miscNavGenres, '/genres', Icons.category_rounded),
      (l.miscNavStudios, '/studios', Icons.business_rounded),
      (l.miscNavArtists, '/artists', Icons.groups_rounded),
      (l.appDownloads, '/downloads', Icons.download_done_rounded),
    ];
    final selected = items.any((i) => location.startsWith(i.$2));

    // Collapsed: no room to expand inline, and these are distinct pages (not a
    // single hub), so tapping opens a flyout menu of the destinations.
    if (!extended) {
      return MenuAnchor(
        menuChildren: [
          for (final i in items)
            MenuItemButton(
              leadingIcon: Icon(i.$3),
              onPressed: () => context.go(i.$2),
              child: Text(i.$1),
            ),
        ],
        builder: (context, controller, _) => _NavTile(
          label: l.miscBrowse,
          icon: Icons.grid_view_rounded,
          extended: false,
          selected: selected,
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
        ),
      );
    }

    return Column(
      children: [
        _NavTile(
          label: l.miscBrowse,
          icon: Icons.grid_view_rounded,
          extended: extended,
          selected: selected,
          onTap: () => ref.read(browseNavExpandedProvider.notifier).toggle(),
          trailing: AnimatedRotation(
            turns: expanded ? 0.25 : 0,
            duration: const Duration(milliseconds: 200),
            child: Icon(Icons.chevron_right_rounded,
                size: 20,
                color: selected ? scheme.primary : scheme.onSurfaceVariant),
          ),
        ),
        if (extended)
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: expanded ? 1 : 0,
                // Folded away, its entries are no stops for a remote or the
                // Tab key (they sit unseen under the tiles that follow).
                child: ExcludeFocus(
                  excluding: !expanded,
                  child: Column(
                    children: [
                      for (final i in items)
                        _NavSubTile(
                          label: i.$1,
                          icon: i.$3,
                          onTap: () => openBrowse(i.$2),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _LibrariesNav extends ConsumerWidget {
  final bool extended;
  final String location;
  const _LibrariesNav({required this.extended, required this.location});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final expanded = ref.watch(librariesNavExpandedProvider);
    final views = (ref.watch(userViewsProvider).asData?.value ??
            const <BaseItemDto>[])
        .where((v) => v.collectionType != 'livetv')
        .toList();
    final selected = location.startsWith('/libraries') ||
        location.startsWith('/library');
    final canExpand = extended && views.isNotEmpty;

    return Column(
      children: [
        _NavTile(
          label: l.appNavLibraries,
          icon: Icons.video_library_rounded,
          extended: extended,
          selected: selected,
          // Clicking the row expands the list (Fladder-style); collapsed rail
          // has no room, so it opens the full Libraries screen instead.
          onTap: () {
            if (canExpand) {
              ref.read(librariesNavExpandedProvider.notifier).toggle();
            } else {
              context.go('/libraries');
            }
          },
          trailing: canExpand
              ? AnimatedRotation(
                  turns: expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.chevron_right_rounded,
                      size: 20,
                      color:
                          selected ? scheme.primary : scheme.onSurfaceVariant),
                )
              : null,
        ),
        if (extended)
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: expanded ? 1 : 0,
                // Folded away, its entries are no stops for a remote or the
                // Tab key (they sit unseen under the tiles that follow).
                child: ExcludeFocus(
                  excluding: !expanded,
                  child: Column(
                    children: [
                      for (final v in views)
                        _NavSubTile(
                          label: v.name,
                          icon: collectionTypeIcon(v.collectionType),
                          onTap: () => context.push('/library', extra: v),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// An indented library entry shown under the expanded Libraries item.
class _NavSubTile extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _NavSubTile(
      {required this.label, required this.icon, required this.onTap});

  @override
  State<_NavSubTile> createState() => _NavSubTileState();
}

class _NavSubTileState extends State<_NavSubTile> {
  bool _hover = false;
  // A D-pad remote must be able to land on library sub-entries (they were
  // mouse-only before, so the remote skipped straight over them).
  bool _focused = false;
  bool get _active => _hover || _focused;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = _active ? scheme.onSurface : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 2, 10, 2),
      child: FocusableActionDetector(
        // TV needs real focus (D-pad) to light the tile; off TV keep the original
        // keyboard-highlight-only behaviour so desktop is unchanged.
        onFocusChange: isTvDevice
            ? (v) {
                setState(() => _focused = v);
                if (v) _tvEnsureVisible(context);
              }
            : null,
        onShowFocusHighlight:
            isTvDevice ? null : (v) => setState(() => _focused = v),
        mouseCursor: SystemMouseCursors.click,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onTap: widget.onTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              height: 40,
              decoration: BoxDecoration(
                color: _active
                    ? scheme.onSurface.withValues(alpha: 0.06)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: _focused
                    ? Border.all(color: scheme.primary, width: 2.5)
                    : null,
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(widget.icon, size: 19, color: fg),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: fg, fontSize: 13.5)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The TV account menu: the D-pad-friendly equivalent of the desktop/mobile
/// profile popup ([_ProfileMenu]), with the SAME options in the SAME order.
/// Rendered as a bottom sheet of focusable rows so a remote can reach each one.
Future<void> _showTvAccountMenu(BuildContext context, WidgetRef ref,
    {required bool isAdmin}) async {
  final l = AppLocalizations.of(context);
  final scheme = Theme.of(context).colorScheme;
  final session = ref.read(sessionControllerProvider).asData?.value;
  final syncPlayOn =
      ref.read(preferencesProvider).asData?.value.syncPlayEnabled ?? true;
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: scheme.surfaceContainerHigh,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            autofocus: true,
            leading: const UserAvatar(radius: 18),
            title: Text(session?.userName ?? l.miscAccount),
            subtitle:
                session?.serverName != null ? Text(session!.serverName!) : null,
            onTap: () => Navigator.of(ctx).pop('profile'),
          ),
          const Divider(),
          if (syncPlayOn)
            ListTile(
              leading: const Icon(Icons.groups_rounded),
              title: Text(l.miscWatchTogether),
              onTap: () => Navigator.of(ctx).pop('syncplay'),
            ),
          ListTile(
            leading: const Icon(Icons.qr_code_scanner_rounded),
            title: Text(l.miscQuickConnect),
            onTap: () => Navigator.of(ctx).pop('quickconnect'),
          ),
          ListTile(
            leading: const Icon(Icons.settings_rounded),
            title: Text(l.miscSettings),
            onTap: () => Navigator.of(ctx).pop('settings'),
          ),
          if (isAdmin)
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_rounded),
              title: Text(l.miscAdministration),
              onTap: () => Navigator.of(ctx).pop('admin'),
            ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.logout_rounded, color: scheme.error),
            title:
                Text(l.commonSignOut, style: TextStyle(color: scheme.error)),
            onTap: () => Navigator.of(ctx).pop('signout'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'profile':
      context.push('/profile');
    case 'syncplay':
      context.push('/syncplay');
    case 'settings':
      context.push('/settings');
    case 'quickconnect':
      showDialog<void>(
          context: context,
          builder: (_) => const _QuickConnectAuthorizeDialog());
    case 'admin':
      context.push('/admin');
    case 'signout':
      ref.read(sessionControllerProvider.notifier).signOut();
  }
}

/// The user menu docked at the bottom of the rail: tapping the avatar opens
/// user-specific settings, Administration (admins only), and sign out, the way
/// Jellyfin and Fladder surface account actions behind the profile picture.
class _ProfileMenu extends ConsumerWidget {
  final bool isAdmin;
  final bool extended;
  const _ProfileMenu({required this.isAdmin, required this.extended});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final session = ref.watch(sessionControllerProvider).asData?.value;
    final scheme = Theme.of(context).colorScheme;
    final syncPlayOn = ref.watch(
        preferencesProvider.select((p) => p.asData?.value.syncPlayEnabled ?? true));
    final inGroup = ref.watch(syncPlayControllerProvider);
    return PopupMenuButton<String>(
      tooltip: session?.userName ?? l.miscAccount,
      offset: const Offset(56, 0),
      position: PopupMenuPosition.over,
      onSelected: (value) {
        switch (value) {
          case 'profile':
            context.push('/profile');
          case 'syncplay':
            context.push('/syncplay');
          case 'settings':
            context.push('/settings');
          case 'quickconnect':
            showDialog<void>(
                context: context,
                builder: (_) => const _QuickConnectAuthorizeDialog());
          case 'admin':
            context.push('/admin');
          case 'signout':
            ref.read(sessionControllerProvider.notifier).signOut();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'profile',
          child: Row(
            children: [
              const UserAvatar(radius: 18),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(session?.userName ?? '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (session?.serverName != null)
                      Text(session!.serverName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        if (syncPlayOn)
          PopupMenuItem<String>(
            value: 'syncplay',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.groups_rounded,
                  color: inGroup ? scheme.primary : null),
              title: Text(l.miscWatchTogether),
              subtitle: inGroup ? Text(l.miscInAGroup) : null,
              trailing: inGroup
                  ? Icon(Icons.circle, size: 10, color: scheme.primary)
                  : null,
            ),
          ),
        PopupMenuItem<String>(
          value: 'quickconnect',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.qr_code_scanner_rounded),
            title: Text(l.miscQuickConnect),
          ),
        ),
        PopupMenuItem<String>(
          value: 'settings',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.settings_rounded),
            title: Text(l.miscSettings),
          ),
        ),
        if (isAdmin)
          PopupMenuItem<String>(
            value: 'admin',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.admin_panel_settings_rounded),
              title: Text(l.miscAdministration),
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'signout',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout_rounded, color: scheme.error),
            title: Text(l.commonSignOut, style: TextStyle(color: scheme.error)),
          ),
        ),
      ],
      child: extended
          ? SizedBox(
              height: 48,
              child: Row(
                children: [
                  // Places the avatar's centre on the same x as the nav icons
                  // and the bell above it.
                  const SizedBox(width: 12),
                  const UserAvatar(radius: 15),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      session?.userName ?? l.miscAccount,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            )
          : const Center(child: UserAvatar(radius: 16)),
    );
  }
}

/// Lets a signed-in user approve a Quick Connect code shown on another device.
class _QuickConnectAuthorizeDialog extends ConsumerStatefulWidget {
  const _QuickConnectAuthorizeDialog();

  @override
  ConsumerState<_QuickConnectAuthorizeDialog> createState() =>
      _QuickConnectAuthorizeDialogState();
}

class _QuickConnectAuthorizeDialogState
    extends ConsumerState<_QuickConnectAuthorizeDialog> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _authorize() async {
    final code = _ctrl.text.trim();
    if (code.isEmpty) return;
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await ref.read(jellyfinClientProvider).authorizeQuickConnect(
            baseUrl: session.baseUrl,
            token: session.accessToken,
            code: code,
          );
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop();
        showSnackOn(messenger, l.miscDeviceApproved);
      } else {
        setState(() => _error = l.miscCodeNotApproved);
      }
    } on JellyfinException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l.miscQuickConnect),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.miscEnterCodePrompt,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TvTextField(
            controller: _ctrl,
            autofocus: true,
            label: l.miscCode,
            hint: l.miscCode,
            textCapitalization: TextCapitalization.characters,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, letterSpacing: 6),
            onSubmitted: (_) => _busy ? null : _authorize(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: TextStyle(color: theme.colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _authorize,
          child: _busy
              ? AppSpinner.inline()
              : Text(l.miscApprove),
        ),
      ],
    );
  }
}
