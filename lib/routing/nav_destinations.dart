import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../state/arr_providers.dart';
import '../state/library_providers.dart';
import '../state/preferences.dart';
import '../state/radio.dart';
import '../state/seerr_providers.dart';
import '../state/youtube_providers.dart';
import '../widgets/arr_widgets.dart';
import '../widgets/seerr_icon.dart';

/// A sidebar/bottom-bar navigation destination. [fixed] items (Home) can't be
/// hidden, so the nav can never be emptied.
typedef NavDest = ({String route, IconData icon, String label, bool fixed});

/// Every nav destination currently available — respecting server capabilities
/// (Live TV) and the integration toggles (Seerr / YouTube / Radio) — in the
/// app's DEFAULT order. This is the single source of truth for both the shell
/// and the Navigation customization screen.
List<NavDest> availableNavDestinations(WidgetRef ref, AppLocalizations l) {
  final seerrOn = ref.watch(seerrConfiguredProvider);
  final arrOn = ref.watch(arrConfiguredProvider);
  final youtubeOn = ref.watch(youtubeEnabledProvider);
  final radioOn = ref.watch(radioEnabledProvider);
  final views = ref.watch(userViewsProvider).asData?.value;
  final hasLiveTv = views?.any((v) => v.collectionType == 'livetv') ?? true;
  return [
    (route: '/home', icon: Icons.home_rounded, label: l.appNavHome, fixed: true),
    (
      route: '/search',
      icon: Icons.search_rounded,
      label: l.commonSearch,
      fixed: false
    ),
    (
      route: '/libraries',
      icon: Icons.video_library_rounded,
      label: l.appNavLibraries,
      fixed: false
    ),
    // A group, not a page: Playlists, Genres, Studios and Artists fold out
    // of it. On its own in the list, so hiding Libraries leaves it be.
    (
      route: navBrowseGroup,
      icon: Icons.grid_view_rounded,
      label: l.miscBrowse,
      fixed: false
    ),
    (
      route: '/favorites',
      icon: Icons.favorite_rounded,
      label: l.appNavFavorites,
      fixed: false
    ),
    (
      route: '/watchlist',
      icon: Icons.bookmark_rounded,
      label: l.appNavWatchlist,
      fixed: false
    ),
    (
      route: '/downloads',
      icon: Icons.download_done_rounded,
      label: l.appDownloads,
      fixed: false
    ),
    if (hasLiveTv)
      (
        route: '/livetv',
        icon: Icons.live_tv_rounded,
        label: l.appNavLiveTv,
        fixed: false
      ),
    if (seerrOn)
      (
        route: '/discover',
        // Drawn as the Seerr logo wherever the navigation shows it (see
        // navDestIcon); this is only the fallback.
        icon: Icons.travel_explore_rounded,
        label: l.browseDiscover,
        fixed: false
      ),
    if (arrOn)
      (route: '/arr', icon: kManageIcon, label: l.appNavManage, fixed: false),
    if (youtubeOn)
      (
        route: '/youtube',
        icon: Icons.smart_display_rounded,
        label: 'YouTube',
        fixed: false
      ),
    if (radioOn)
      (
        route: '/radio',
        icon: Icons.radio_rounded,
        label: l.appNavRadio,
        fixed: false
      ),
  ];
}

/// The Browse group's place in the list. No page answers to it.
const navBrowseGroup = '/browse';

/// [all] in the saved [order]. One the saved order doesn't know keeps its
/// default place after the ordered ones; except Browse, which stood under
/// Libraries before it had a place of its own, and stays there.
List<NavDest> sortNavDestinations(List<NavDest> all, List<String> order) {
  if (order.isEmpty) return all;
  final rank = <String, double>{
    for (var i = 0; i < order.length; i++) order[i]: i.toDouble(),
  };
  final libraries = rank['/libraries'];
  if (libraries != null) rank.putIfAbsent(navBrowseGroup, () => libraries + 0.5);
  final indexed = all.asMap().entries.toList();
  indexed.sort((a, b) {
    final ra = rank[a.value.route] ?? (1000.0 + a.key);
    final rb = rank[b.value.route] ?? (1000.0 + b.key);
    return ra.compareTo(rb);
  });
  return [for (final e in indexed) e.value];
}

/// A destination's icon as the navigation draws it: its own, except Discover,
/// which keeps the Seerr logo.
Widget navDestIcon(NavDest d, {required Color color, double size = 23}) =>
    d.route == '/discover'
    ? SeerrIcon(color: color, size: size)
    : Icon(d.icon, color: color, size: size);

/// Applies the user's saved order ([Prefs.navOrder]) and hidden set
/// ([Prefs.navHidden]) to [all]. Fixed destinations (Home) are never hidden.
/// Destinations not present in the saved order keep their default position after
/// the ordered ones.
List<NavDest> orderNavDestinations(List<NavDest> all, Prefs p) {
  final hidden = p.navHidden.toSet();
  final visible =
      all.where((d) => d.fixed || !hidden.contains(d.route)).toList();
  return sortNavDestinations(visible, p.navOrder);
}
