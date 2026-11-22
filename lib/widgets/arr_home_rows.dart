import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../api/arr_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/arr.dart';
import '../state/arr_providers.dart';
import 'arr_queue_poll.dart';
import 'arr_widgets.dart';
import 'media_cards.dart';
import 'media_section.dart';
import 'motion.dart';

// Home's two rows from Sonarr and Radarr: what's downloading, and what's due
// this week. Both are extras on a page that's for watching, so neither says
// anything while it has nothing to show: no placeholder while it loads, no
// error when the apps can't be reached (away from home, say). The Manage
// section is where that is told.

/// The time, as Home's rows read it. Tests set the clock.
@visibleForTesting
DateTime Function() arrHomeNow = DateTime.now;

ArrClient? _clientOf(WidgetRef ref, ArrKind kind) => kind == ArrKind.sonarr
    ? ref.watch(sonarrClientProvider)
    : ref.watch(radarrClientProvider);

IconData _iconOf(ArrKind kind) =>
    kind == ArrKind.sonarr ? Icons.live_tv_rounded : Icons.movie_rounded;

/// Downloading Now: a card for each movie and show in the queue, with how
/// far along it is. The row keeps itself current while it's on screen, and
/// looks now and then for a download that has started while it's empty.
class ArrDownloadingRow extends ConsumerStatefulWidget {
  /// The row's height, the card's picture growing or shrinking to fit.
  final double height;
  const ArrDownloadingRow({super.key, required this.height});

  @override
  ConsumerState<ArrDownloadingRow> createState() => _ArrDownloadingRowState();
}

class _ArrDownloadingRowState extends ConsumerState<ArrDownloadingRow> {
  // An app that misses an answer or two keeps its cards: they'd be back a
  // moment later. One that stays silent loses them, their numbers going
  // stale.
  final _known = ArrLastKnown<ArrQueueItem>(
    kindOf: (q) => q.kind,
    patience: 2,
    order: arrQueueOrder,
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // `value`, not the loading state: a reload keeps the cards it has.
    final queue = ref.watch(arrQueueProvider).value;
    final titles = arrHomeDownloads(
      queue == null ? _known.shown : _known.of(queue),
    );
    return ArrQueuePoll(
      every: Duration(seconds: titles.isEmpty ? 60 : 15),
      child: titles.isEmpty
          ? const SizedBox.shrink()
          : MediaSection(
              title: l.arrHomeDownloading,
              height: widget.height,
              // Over Home, as every other See All: Back comes back here.
              onSeeAll: () => context.push('/arr?tab=activity'),
              children: [
                for (final (i, t) in titles.indexed)
                  EntranceFade(
                    index: i,
                    onceKey: 'home-arr-queue-${t.kind.name}-${t.titleId}',
                    child: _DownloadCard(title: t),
                  ),
              ],
            ),
    );
  }
}

class _DownloadCard extends ConsumerWidget {
  final ArrHomeDownload title;
  const _DownloadCard({required this.title});

  static const double width = 304;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final client = _clientOf(ref, title.kind);
    final state = title.lead.state;
    final (standing, color) = arrQueueStanding(l, scheme, title.lead);
    final left = title.finishes?.difference(arrHomeNow());
    // What of the title is coming, then how it's doing: how far along while
    // it downloads, and in a word once it's anything else.
    final about = [
      if (title.kind == ArrKind.sonarr)
        if (title.items.length == 1)
          ?title.lead.episodeCode
        else
          l.detailEpisodeCount(title.items.length),
      if (state != ArrQueueState.downloading)
        standing
      else ...[
        '${(title.progress * 100).round()}%',
        if (left != null && !left.isNegative) l.arrTimeLeft(arrDuration(left)),
      ],
    ].join(' · ');
    // A problem is said in its color; anything else stays quiet.
    final loud = state.needsHelp;
    // The wide picture, or the poster cut to the card where there's none.
    final wide = client?.imageUrl(title.images, 'fanart') != null;
    return _HomeCard(
      width: width,
      aspectRatio: 16 / 9,
      title: title.title,
      subtitle: about,
      subtitleColor: loud ? color : null,
      onTap: () => arrOpenTitlePage(context, title.kind, title.titleId),
      art: ArrArt(
        client: client,
        images: title.images,
        type: wide ? 'fanart' : 'poster',
        width: wide ? 780 : 500,
        placeholderIcon: _iconOf(title.kind),
        alignment: wide ? Alignment.center : const Alignment(0, -0.5),
      ),
      overlay: ArrPosterBar(color: color, fraction: title.progress),
    );
  }
}

/// Coming This Week: a poster for each movie and show with something due
/// today or in the six days after, that the apps will go and get. The row
/// looks again now and then, which is also how it finds out that it's
/// tomorrow.
class ArrComingUpRow extends ConsumerStatefulWidget {
  final double height;
  const ArrComingUpRow({super.key, required this.height});

  @override
  ConsumerState<ArrComingUpRow> createState() => _ArrComingUpRowState();
}

class _ArrComingUpRowState extends ConsumerState<ArrComingUpRow> {
  // An app that doesn't answer keeps its posters for a few tries: what's
  // due this week hasn't changed because it was busy.
  final _known = ArrLastKnown<ArrCalendarEntry>(
    kindOf: (e) => e.kind,
    patience: 5,
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final week = arrHomeWeek(arrHomeNow());
    final asked = ref.watch(arrHomeComingUpProvider(week));
    final answer = asked.value;
    // Without an answer yet (a new day's first), the last one stands.
    final due = arrHomeComingUp(
      answer == null ? _known.shown : _known.of(answer),
      week,
    );
    return ArrPoll(
      // The week's plans change slowly. An app that didn't answer is asked
      // again sooner.
      every: Duration(minutes: (answer?.errors.isEmpty ?? true) ? 15 : 1),
      waiting: asked.isLoading,
      onPoll: () {
        // Built again as well: the day may have changed.
        setState(() {});
        ref.invalidate(arrHomeComingUpProvider);
      },
      child: due.isEmpty
          ? const SizedBox.shrink()
          : MediaSection(
              title: l.arrHomeComingUp,
              height: widget.height,
              onSeeAll: () => context.push('/arr?tab=calendar'),
              children: [
                for (final (i, r) in due.indexed)
                  EntranceFade(
                    index: i,
                    onceKey:
                        'home-arr-due-${r.first.kind.name}-${r.first.titleId}',
                    child: _ComingUpCard(release: r, today: week.start),
                  ),
              ],
            ),
    );
  }
}

class _ComingUpCard extends ConsumerWidget {
  final ArrHomeRelease release;
  final DateTime today;
  const _ComingUpCard({required this.release, required this.today});

  static const double width = 176;

  /// The day in a word. Within a week of today the weekday alone says
  /// which day it is.
  String _day(BuildContext context, AppLocalizations l, DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    if (day == today) return l.arrToday;
    if (day == DateTime(today.year, today.month, today.day + 1)) {
      return l.arrTomorrow;
    }
    return DateFormat.EEEE(
      Localizations.localeOf(context).toString(),
    ).format(day);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final e = release.first;
    final about = e.kind == ArrKind.sonarr
        ? release.more > 0 && e.episodeCode != null
              ? l.arrHomeEpisodeAndMore(e.episodeCode!, release.more)
              : [
                  e.episodeCode,
                  e.episodeTitle,
                ].whereType<String>().where((s) => s.isNotEmpty).join(' · ')
        : switch (e.release) {
            ArrRelease.cinemas => l.arrInCinemas,
            ArrRelease.digital => l.arrDigitalRelease,
            ArrRelease.physical => l.arrPhysicalRelease,
            null => '',
          };
    return _HomeCard(
      width: width,
      aspectRatio: 2 / 3,
      title: e.title,
      subtitle: about,
      onTap: () => arrOpenTitlePage(context, e.kind, e.titleId!),
      art: ArrArt(
        client: _clientOf(ref, e.kind),
        images: e.images,
        placeholderIcon: _iconOf(e.kind),
      ),
      overlay: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: ArrChip(
            label: _day(context, l, e.date),
            color: Colors.white,
            onArt: true,
          ),
        ),
      ),
    );
  }
}

/// A card of one of the rows: the picture, the title and a line under it,
/// in the shape of Home's own cards.
class _HomeCard extends StatelessWidget {
  final double width;
  final double aspectRatio;
  final String title;
  final String subtitle;
  final Color? subtitleColor;
  final VoidCallback onTap;
  final Widget art;
  final Widget overlay;

  const _HomeCard({
    required this.width,
    required this.aspectRatio,
    required this.title,
    required this.subtitle,
    this.subtitleColor,
    required this.onTap,
    required this.art,
    required this.overlay,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Flexible, so the picture gives way rather than the card
              // spilling out of its row when the text is set larger.
              Flexible(
                child: AspectRatio(
                  aspectRatio: aspectRatio,
                  child: HoverPosterArt(
                    onTap: onTap,
                    art: art,
                    overlay: overlay,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: subtitleColor ?? theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
