import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/seerr_providers.dart';
import '../widgets/cached_image.dart';
import '../widgets/error_view.dart';
import '../widgets/motion.dart';
import '../widgets/seerr_poster_card.dart';
import '../widgets/app_spinner.dart';

/// A movie collection (franchise): backdrop + overview, then its titles.
class SeerrCollectionScreen extends ConsumerWidget {
  final int collectionId;
  const SeerrCollectionScreen({super.key, required this.collectionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(seerrCollectionProvider(collectionId));
    return Scaffold(
      body: async.when(
        loading: () => const Center(child: AppSpinner()),
        error: (e, _) => SafeArea(
          child: Column(
            children: [
              const Align(alignment: Alignment.centerLeft, child: BackButton()),
              Expanded(child: ErrorView(
          message: '$e',
          onRetry: () => ref.invalidate(seerrCollectionProvider(collectionId)),
        )),
            ],
          ),
        ),
        data: (c) => CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 260,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(c.name,
                    style: const TextStyle(
                        shadows: [Shadow(blurRadius: 8, color: Colors.black)])),
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (c.backdropUrl != null)
                      CachedImage(
                          url: c.backdropUrl!,
                          errorBuilder: (_) => Container(
                              color: theme.colorScheme.surfaceContainerHigh))
                    else
                      Container(color: theme.colorScheme.surfaceContainerHigh),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black87],
                          stops: [0.45, 1.0],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (c.overview != null && c.overview!.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(c.overview!, style: theme.textTheme.bodyMedium),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 184,
                  mainAxisSpacing: 18,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.54,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => EntranceFade(
                    index: i,
                    onceKey: 'cp${c.parts[i].tmdbId}',
                    child: SeerrGridCard(result: c.parts[i]),
                  ),
                  childCount: c.parts.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
