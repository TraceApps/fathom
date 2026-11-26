import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/error_text.dart';
import '../l10n/generated/app_localizations.dart';
import '../routing/app_shell.dart';
import '../models/base_item.dart';
import '../state/library_providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/media_image.dart';
import '../widgets/motion.dart';
import '../widgets/shimmer.dart';
import '../widgets/ui_common.dart';
import '../widgets/error_view.dart';

/// Hub listing the user's libraries (Movies, Shows, Music, Recordings, Live
/// TV, ...) so they're reachable straight from the sidebar.
class LibrariesScreen extends ConsumerWidget {
  const LibrariesScreen({super.key});

  void _open(BuildContext context, BaseItemDto view) {
    if (view.collectionType == 'livetv') {
      context.push('/livetv');
    } else {
      context.push('/library', extra: view);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final views = ref.watch(userViewsProvider);
    return Scaffold(
      appBar: AppBar(
          leading: mobileDrawerLeading(context),
          title: Text(l.browseLibraries)),
      body: Column(
        children: [
          const _BrowseBar(),
          Expanded(
            child: views.when(
              loading: () => const PosterGridSkeleton(
                  maxExtent: 300, aspectRatio: 16 / 10),
              error: (e, _) => ErrorView(
                message: errorText(e),
                onRetry: () => ref.invalidate(userViewsProvider),
              ),
              data: (all) {
                // Live TV has its own sidebar section; don't list it here.
                final list = all
                    .where((v) => v.collectionType != 'livetv')
                    .toList();
                if (list.isEmpty) {
                  return EmptyState(
                      icon: Icons.video_library_rounded,
                      title: l.browseNoLibraries);
                }
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 300,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 16 / 10,
                  ),
                  itemCount: list.length,
                  itemBuilder: (context, i) => EntranceFade(
                    index: i,
                    onceKey: list[i].id,
                    child: _LibraryTile(
                      view: list[i],
                      onTap: () => _open(context, list[i]),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Quick "browse by" links across the top of the Libraries hub.
class _BrowseBar extends StatelessWidget {
  const _BrowseBar();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final items = <(String, IconData, String)>[
      (l.browseGenres, Icons.category_rounded, '/genres'),
      (l.browseStudios, Icons.business_rounded, '/studios'),
      (l.browseArtists, Icons.person_rounded, '/artists'),
      (l.browsePlaylists, Icons.playlist_play_rounded, '/playlists'),
      (l.browseFavorites, Icons.favorite_rounded, '/favorites'),
      (l.browseWatchlist, Icons.bookmark_rounded, '/watchlist'),
      (l.browseDownloads, Icons.download_rounded, '/downloads'),
    ];
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        children: [
          for (final (label, icon, route) in items)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: Icon(icon, size: 18),
                label: Text(label),
                onPressed: () => context.push(route),
              ),
            ),
        ],
      ),
    );
  }
}

class _LibraryTile extends StatelessWidget {
  final BaseItemDto view;
  final VoidCallback onTap;
  const _LibraryTile({required this.view, required this.onTap});

  IconData get _icon => collectionTypeIcon(view.collectionType);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HoverLift(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              MediaImage(item: view, landscape: true, placeholderIcon: _icon),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_icon, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(view.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            )),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
