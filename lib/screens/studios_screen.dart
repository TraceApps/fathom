import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/error_text.dart';
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

/// Browse all studios/networks; tap one to see its titles.
class StudiosScreen extends ConsumerWidget {
  const StudiosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(studiosProvider);
    return Scaffold(
      appBar: AppBar(leading: mobileLeading(context), title: Text(l.browseStudios)),
      body: async.when(
        loading: () => const ChipWrapSkeleton(),
        error: (e, _) => ErrorView(message: errorText(e), onRetry: () => ref.invalidate(studiosProvider)),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
                icon: Icons.business_rounded, title: l.browseNoStudios);
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
              onceKey: 'studio-${list[i].name}',
              child: GradientBrowseTile(
                label: list[i].name,
                icon: Icons.business_rounded,
                autofocus: isTvDevice && i == 0,
                onTap: () => context.push('/studio', extra: list[i].name),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Grid of titles from a single studio/network.
class StudioItemsScreen extends ConsumerStatefulWidget {
  final String studio;
  const StudioItemsScreen({super.key, required this.studio});

  @override
  ConsumerState<StudioItemsScreen> createState() => _StudioItemsScreenState();
}

class _StudioItemsScreenState extends ConsumerState<StudioItemsScreen> {
  String _sortBy = 'SortName';
  String _sortOrder = 'Ascending';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final sortOptions = _browseSortOptions(l);
    final async = ref.watch(studioItemsProvider(
        (studio: widget.studio, sortBy: _sortBy, sortOrder: _sortOrder)));
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.studio),
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
        emptyTitle: l.browseNothingFromStudio(widget.studio),
        emptyIcon: Icons.business_rounded,
        onRefresh: () => ref.invalidate(studioItemsProvider(
            (studio: widget.studio, sortBy: _sortBy, sortOrder: _sortOrder))),
      ),
    );
  }
}

/// Library sort options as a map of Jellyfin sort key -> localized label.
/// A function (not a const map) so the labels can be localized.
Map<String, String> _browseSortOptions(AppLocalizations l) => {
      'SortName': l.browseSortName,
      'DateCreated': l.browseSortDateAdded,
      'PremiereDate': l.browseSortReleaseDate,
      'CommunityRating': l.browseSortRating,
      'Random': l.browseSortRandom,
    };
