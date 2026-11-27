import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../routing/app_shell.dart';
import '../state/preferences.dart';
import '../state/watchlist.dart';
import '../widgets/clapper_icon.dart';
import '../widgets/item_grid.dart';

/// The user's Watchlist as a poster grid — newest addition first, exactly
/// like Netflix's My List. See [WatchlistController] for why this is distinct
/// from Favorites and how it's stored.
class WatchlistScreen extends ConsumerWidget {
  const WatchlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final items = ref.watch(watchlistProvider);
    final wheelEnabled = ref.watch(preferencesProvider
        .select((p) => p.asData?.value.movieWheelEnabled ?? true));
    return Scaffold(
      appBar: AppBar(
        leading: mobileLeading(context),
        title: Text(l.browseWatchlist),
        actions: [
          if (wheelEnabled)
            ClapOnHover(
              child: IconButton(
                tooltip: l.wheelTitle,
                icon: const ClapperIcon(),
                onPressed: () => context.push('/watchlist/wheel'),
              ),
            ),
          IconButton(
            tooltip: l.commonRefresh,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(watchlistProvider),
          ),
        ],
      ),
      body: ItemGridBody(
        items: items,
        emptyIcon: Icons.bookmark_border_rounded,
        emptyTitle: l.browseNoWatchlist,
        onRefresh: () => ref.invalidate(watchlistProvider),
      ),
    );
  }
}
