import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../routing/app_shell.dart';
import '../services/tv_mode.dart';
import '../state/library_providers.dart';
import '../widgets/list_toolbar.dart';
import '../widgets/browse_tile.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';
import '../widgets/item_grid.dart';
import '../widgets/motion.dart';
import '../widgets/shimmer.dart';

/// Browse all genres; tap one to see the movies and shows in it.
class GenresScreen extends ConsumerWidget {
  const GenresScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(genresProvider);
    return Scaffold(
      appBar: AppBar(leading: mobileLeading(context), title: Text(l.browseGenres)),
      body: async.when(
        loading: () => const ChipWrapSkeleton(),
        error: (e, _) => ErrorView(message: '$e', onRetry: () => ref.invalidate(genresProvider)),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
                icon: Icons.category_rounded, title: l.browseNoGenres);
          }
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.7,
            ),
            itemCount: list.length,
            itemBuilder: (context, i) => EntranceFade(
              index: i,
              onceKey: 'genre-${list[i].name}',
              child: GradientBrowseTile(
                label: list[i].name,
                icon: Icons.category_rounded,
                autofocus: isTvDevice && i == 0,
                onTap: () => context.push('/genre', extra: list[i].name),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Grid of titles in a single genre, with sort controls (consistent with the
/// library screen).
class GenreItemsScreen extends ConsumerStatefulWidget {
  final String genre;
  const GenreItemsScreen({super.key, required this.genre});

  @override
  ConsumerState<GenreItemsScreen> createState() => _GenreItemsScreenState();
}

class _GenreItemsScreenState extends ConsumerState<GenreItemsScreen> {
  String _sortBy = 'SortName';
  String _sortOrder = 'Ascending';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final sortOptions = _browseSortOptions(l);
    final async = ref.watch(genreItemsProvider(
        (genre: widget.genre, sortBy: _sortBy, sortOrder: _sortOrder)));
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.genre),
        actions: [
          SortMenu<String>(
            value: _sortBy,
            options: sortOptions,
            descending: _sortOrder == 'Descending',
            startsDescending: (v) => v != 'SortName',
            onChanged: (v, desc) => setState(() {
              _sortBy = v;
              _sortOrder = desc ? 'Descending' : 'Ascending';
            }),
          ),
        ],
      ),
      body: ItemGridBody(
        items: async,
        emptyTitle: l.browseNothingInGenre(widget.genre),
        emptyIcon: Icons.category_rounded,
        onRefresh: () => ref.invalidate(genreItemsProvider(
            (genre: widget.genre, sortBy: _sortBy, sortOrder: _sortOrder))),
      ),
    );
  }
}

/// The library sort options as a map of Jellyfin sort key -> localized label.
/// A function (not a const map) so the labels can be localized.
Map<String, String> _browseSortOptions(AppLocalizations l) => {
      'SortName': l.browseSortName,
      'DateCreated': l.browseSortDateAdded,
      'PremiereDate': l.browseSortReleaseDate,
      'CommunityRating': l.browseSortRating,
      'Random': l.browseSortRandom,
    };
