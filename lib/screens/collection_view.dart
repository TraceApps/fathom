import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import '../services/tv_mode.dart';
import '../state/library_providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';
import '../widgets/media_cards.dart';
import '../widgets/motion.dart';
import '../widgets/shimmer.dart';

/// Contents of a collection (BoxSet): its child items as a grid. Rendered by
/// DetailScreen when the opened item is a BoxSet.
class CollectionView extends ConsumerWidget {
  final BaseItemDto collection;
  const CollectionView({super.key, required this.collection});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final items = ref.watch(collectionItemsProvider(collection.id));
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: Colors.transparent,
          title: Text(collection.name),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Builder(builder: (context) {
                  final n = items.asData?.value.length ?? 0;
                  if (n == 0) return const SizedBox.shrink();
                  return Text(l.browseTitlesCount(n),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant));
                }),
                if (collection.overview != null &&
                    collection.overview!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(collection.overview!,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(height: 1.5)),
                ],
              ],
            ),
          ),
        ),
        items.when(
          loading: () => const SliverToBoxAdapter(
            child: SizedBox(height: 560, child: PosterGridSkeleton()),
          ),
          error: (e, _) =>
              SliverToBoxAdapter(child: ErrorView(
          message: '$e',
          onRetry: () => ref.invalidate(collectionItemsProvider(collection.id)),
        )),
          data: (list) {
            if (list.isEmpty) {
              return SliverToBoxAdapter(
                child: EmptyState(
                    icon: Icons.collections_bookmark_rounded,
                    title: l.browseCollectionEmpty),
              );
            }
            return SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverGrid.builder(
                gridDelegate:
                    const SliverGridDelegateWithMaxCrossAxisExtent(
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
                    autofocus: isTvDevice && i == 0,
                    onTap: () => context.push('/item', extra: list[i]),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
