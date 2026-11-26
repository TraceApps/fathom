import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/error_text.dart';
import '../models/base_item.dart';
import '../services/tv_mode.dart';
import '../state/library_providers.dart';
import '../state/session_controller.dart';
import 'empty_state.dart';
import 'error_view.dart';
import 'item_selection.dart';
import 'media_cards.dart';
import 'motion.dart';
import 'shimmer.dart';

/// Renders a poster grid from an async list, with shimmer/empty/error states.
/// Reused by person filmography, favorites, and collection screens.
///
/// Every grid can multi-select: a card's own menu has Select, which puts the
/// grid into selection mode with a bar above it for acting on the whole set.
/// Off TV only, where the menu itself lives.
class ItemGridBody extends ConsumerStatefulWidget {
  final AsyncValue<List<BaseItemDto>> items;
  final String emptyTitle;
  final IconData emptyIcon;

  /// Re-reads whatever provider fed [items], after a bulk action changed it.
  /// Without it, titles deleted from a selection stay on screen.
  final VoidCallback? onRefresh;

  const ItemGridBody({
    super.key,
    required this.items,
    this.emptyTitle = 'Nothing here',
    this.emptyIcon = Icons.inbox_rounded,
    this.onRefresh,
  });

  @override
  ConsumerState<ItemGridBody> createState() => _ItemGridBodyState();
}

class _ItemGridBodyState extends ConsumerState<ItemGridBody> {
  final _selection = ItemSelection();

  @override
  void initState() {
    super.initState();
    _selection.addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    _selection.removeListener(_onSelectionChanged);
    _selection.dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return widget.items.when(
      loading: () => const PosterGridSkeleton(),
      error: (e, _) => ErrorView(message: errorText(e), onRetry: widget.onRefresh),
      data: (list) {
        if (list.isEmpty) {
          return EmptyState(icon: widget.emptyIcon, title: widget.emptyTitle);
        }
        final user = ref.watch(currentUserProvider).asData?.value;
        final session = ref.watch(sessionControllerProvider).asData?.value;
        final canDelete = (user?.enableContentDeletion ?? false) ||
            (user?.isAdministrator ?? false) ||
            (session?.canDelete ?? false);
        final grid = GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          clipBehavior: Clip.none,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 184,
            mainAxisSpacing: 18,
            crossAxisSpacing: 14,
            childAspectRatio: 0.54,
          ),
          itemCount: list.length,
          itemBuilder: (context, i) => EntranceFade(
            index: i,
            onceKey: list[i].id,
            child: PosterTile(
              item: list[i],
              // On TV the first tile grabs focus so the remote lands on content.
              autofocus: isTvDevice && i == 0,
              selected: _selection.active
                  ? _selection.contains(list[i].id)
                  : null,
              onSelect:
                  isTvDevice ? null : () => _selection.start(list[i]),
              onTap: () => _selection.active
                  ? _selection.toggle(list[i])
                  : context.push('/item', extra: list[i]),
            ),
          ),
        );
        if (!_selection.active) return grid;
        return Column(
          children: [
            SelectionBar(
              selection: _selection,
              all: list,
              canDelete: canDelete,
              onChanged: widget.onRefresh,
            ),
            Expanded(child: grid),
          ],
        );
      },
    );
  }
}
