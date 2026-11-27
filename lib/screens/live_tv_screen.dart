import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/error_text.dart';
import '../l10n/generated/app_localizations.dart';
import '../routing/app_shell.dart';
import '../models/base_item.dart';
import '../state/library_providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';
import '../widgets/media_image.dart';
import '../widgets/tv_focus.dart';
import 'guide_view.dart';
import '../widgets/app_spinner.dart';

/// Live TV, with a proper EPG guide grid and a simple channel list.
class LiveTvScreen extends ConsumerWidget {
  const LiveTvScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          leading: mobileLeading(context),
          title: Text(l.extraLiveTvTitle),
          actions: [
            IconButton(
              tooltip: l.commonRefresh,
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () {
                ref.invalidate(liveTvChannelsProvider);
                ref.invalidate(guideProvider);
                ref.invalidate(recordingsProvider);
              },
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: l.extraTabGuide),
              Tab(text: l.extraTabChannels),
              Tab(text: l.extraTabRecordings),
            ],
          ),
        ),
        body: const TabBarView(
          children: [GuideView(), _ChannelsList(), _RecordingsList()],
        ),
      ),
    );
  }
}

/// DVR recordings list. Tap a recording to open its detail and play.
class _RecordingsList extends ConsumerWidget {
  const _RecordingsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final recordings = ref.watch(recordingsProvider);
    return recordings.when(
      loading: () => const Center(child: AppSpinner()),
      error: (e, _) => ErrorView(
          message: errorText(e),
          onRetry: () => ref.invalidate(recordingsProvider),
        ),
      data: (items) {
        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.fiber_manual_record_rounded,
            title: l.extraNoRecordings,
            message: l.extraNoRecordingsHint,
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final rec = items[i];
            return TvFocusRing(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 6,
                ),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 96,
                    height: 54,
                    child: MediaImage(item: rec, landscape: true),
                  ),
                ),
                title: Text(
                  rec.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: rec.overview != null
                    ? Text(
                        rec.overview!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      )
                    : null,
                onTap: () => context.push('/item', extra: rec),
              ),
            );
          },
        );
      },
    );
  }
}

/// Simple channel list: logo, number, name, current program + progress bar.
class _ChannelsList extends ConsumerWidget {
  const _ChannelsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final channels = ref.watch(liveTvChannelsProvider);
    return channels.when(
      loading: () => const Center(child: AppSpinner()),
      error: (e, _) => ErrorView(
          message: errorText(e),
          onRetry: () => ref.invalidate(liveTvChannelsProvider),
        ),
      data: (items) {
        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.live_tv_rounded,
            title: l.extraNoChannelsFound,
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) => _ChannelTile(channel: items[i]),
        );
      },
    );
  }
}

class _ChannelTile extends StatelessWidget {
  final BaseItemDto channel;
  const _ChannelTile({required this.channel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final program = channel.currentProgram;
    final progress = _programProgress(program);

    return TvFocusRing(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          width: 64,
          height: 40,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          clipBehavior: Clip.antiAlias,
          child: MediaImage(
            item: channel,
            placeholderIcon: Icons.live_tv_rounded,
          ),
        ),
        title: Row(
          children: [
            if (channel.channelNumber != null) ...[
              Text(
                channel.channelNumber!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                channel.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        subtitle: program == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      program.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                    if (progress != null) ...[
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
        trailing: const Icon(Icons.play_arrow_rounded),
        onTap: () => context.push('/player', extra: channel),
      ),
    );
  }

  double? _programProgress(BaseItemDto? program) {
    final start = program?.startDate, end = program?.endDate;
    if (start == null || end == null) return null;
    final total = end.difference(start).inSeconds;
    if (total <= 0) return null;
    final elapsed = DateTime.now().difference(start).inSeconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }
}
