import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/error_text.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/seerr_detail.dart';
import '../state/seerr_providers.dart';
import '../widgets/cached_image.dart';
import '../widgets/error_view.dart';
import '../widgets/app_spinner.dart';

/// The episode list for one season of a series.
class SeerrSeasonScreen extends ConsumerWidget {
  final int tvId;
  final int seasonNumber;
  final String seasonName;
  const SeerrSeasonScreen({
    super.key,
    required this.tvId,
    required this.seasonNumber,
    required this.seasonName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async =
        ref.watch(seerrSeasonProvider((tvId: tvId, seasonNumber: seasonNumber)));
    return Scaffold(
      appBar: AppBar(title: Text(seasonName)),
      body: async.when(
        loading: () => const Center(child: AppSpinner()),
        error: (e, _) => ErrorView(
          message: errorText(e),
          onRetry: () => ref.invalidate(seerrSeasonProvider((tvId: tvId, seasonNumber: seasonNumber))),
        ),
        data: (episodes) => episodes.isEmpty
            ? Center(child: Text(l.detailNoEpisodes))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
                itemCount: episodes.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) => _EpisodeTile(episode: episodes[i]),
              ),
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  final SeerrEpisode episode;
  const _EpisodeTile({required this.episode});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = episode;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (e.stillUrl != null)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: CachedImage(
                  url: e.stillUrl!,
                  errorBuilder: (_) => Container(
                      color: theme.colorScheme.surfaceContainerHighest)),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text('${e.episodeNumber}. ${e.name}',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    if (e.voteAverage != null && e.voteAverage! > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text('★ ${e.voteAverage!.toStringAsFixed(1)}',
                            style: theme.textTheme.bodySmall),
                      ),
                  ],
                ),
                if (e.airDate != null && e.airDate!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(e.airDate!,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ),
                if (e.overview != null && e.overview!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(e.overview!, style: theme.textTheme.bodyMedium),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
