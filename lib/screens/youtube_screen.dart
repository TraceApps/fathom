import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/youtube_channel.dart';
import '../models/youtube_history.dart';
import '../models/youtube_video.dart';
import '../services/shared_files.dart';
import '../state/youtube_providers.dart';
import '../widgets/pick_bar.dart';
import '../widgets/cached_image.dart';
import '../widgets/context_menu.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';
import '../widgets/search_field.dart';
import '../widgets/tv_focus.dart';
import '../widgets/tv_keyboard.dart';
import '../widgets/youtube_cards.dart';
import '../models/youtube_playlist.dart';
import '../models/youtube_local_playlist.dart';
import '../models/youtube_feed_group.dart';
import '../models/youtube_download.dart';
import '../widgets/subscribe_button.dart';
import '../widgets/youtube_video_collection.dart';
import '../widgets/youtube_skeletons.dart';
import '../services/subscription_transfer.dart';
import '../services/youtube_search_params.dart';
import '../services/youtube_download.dart';
import '../l10n/generated/app_localizations.dart';
import '../routing/app_shell.dart';
import '../widgets/app_snack.dart';
import '../widgets/app_spinner.dart';
import '../widgets/ui_common.dart';

/// The YouTube section: subscribed channels, what they've posted, and search.
class YoutubeScreen extends ConsumerWidget {
  /// Tab to land on (e.g. the Downloads pill deep-links to it). Falls back to
  /// the usual Search/Subscriptions default when unset.
  final int? initialTab;
  const YoutubeScreen({super.key, this.initialTab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final subs = ref.watch(youtubeSubscriptionsProvider).asData?.value ??
        const <YoutubeChannel>[];
    // Land on Search until there's something subscribed to show.
    return DefaultTabController(
      length: 6,
      initialIndex: initialTab ?? (subs.isEmpty ? 0 : 1),
      child: Scaffold(
        appBar: AppBar(
          leading: mobileDrawerLeading(context),
          title: const Text('YouTube'),
          // Subscriptions lists the channels themselves; the merged
          // newest-first feed is its own tab. They were one screen before, so
          // every channel's uploads arrived shuffled together under a heading
          // that promised channels.
          bottom: TabBar(isScrollable: true, tabs: [
            Tab(text: l.commonSearch),
            Tab(text: l.ytSubscriptions),
            Tab(text: l.ytWhatsNew),
            Tab(text: l.ytPlaylists),
            Tab(text: l.ytDownloads),
            Tab(text: l.ytHistory),
          ]),
        ),
        body: const TabBarView(children: [
          _SearchTab(),
          _SubscriptionsTab(),
          _FeedTab(),
          _PlaylistsTab(),
          _DownloadsTab(),
          _HistoryTab(),
        ]),
      ),
    );
  }
}

// ---- Subscribed channels ----

/// The channels you follow: picture, name, and how many subscribers they have.
/// Tapping one opens that channel and its videos.
class _SubscriptionsTab extends ConsumerWidget {
  const _SubscriptionsTab();

  /// Reads a Google Takeout CSV or a NewPipe JSON backup. Subscriptions here
  /// are local, so importing is the only way to arrive with more than a few.
  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // Android/iOS turn an extension filter into a MIME-type filter, and cloud
    // providers (Drive, Nextcloud, Proton) report a Takeout CSV / NewPipe JSON
    // under types that don't match, so those files grey out and can't be picked.
    // On mobile, accept any file and validate by parsing below; desktop keeps
    // the tidy csv/json filter.
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final picked = await FilePicker.pickFile(
      type: isMobile ? FileType.any : FileType.custom,
      allowedExtensions: isMobile ? null : const ['csv', 'json'],
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();

    List<YoutubeChannel> parsed;
    try {
      parsed = SubscriptionTransfer.parse(utf8.decode(bytes));
    } catch (_) {
      parsed = const [];
    }
    if (parsed.isEmpty) {
      showSnackOn(messenger, l.ytImportNotFound);
      return;
    }
    final added = await ref
        .read(youtubeSubscriptionsProvider.notifier)
        .importAll(parsed);
    showSnackOn(messenger, added == 0
          ? l.ytAlreadySubscribedAll(parsed.length)
          : l.ytAddedOfTotal(added, parsed.length), kind: SnackKind.success);
  }

  /// Writes NewPipe's format, so these can be taken elsewhere.
  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final subs = ref.read(youtubeSubscriptionsProvider).asData?.value ??
        const <YoutubeChannel>[];
    if (subs.isEmpty) return;
    final path = await FilePicker.saveFile(
      dialogTitle: l.ytExportSubscriptions,
      fileName: 'fathom_subscriptions.json',
      bytes: utf8.encode(SubscriptionTransfer.exportNewPipeJson(subs)),
    );
    if (path == null) return;
    showSnackOn(messenger, l.ytExportedSubscriptions(subs.length),
        kind: SnackKind.success);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final subs = ref.watch(youtubeSubscriptionsProvider).asData?.value ??
        const <YoutubeChannel>[];
    if (subs.isEmpty) {
      return Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _import(context, ref),
          icon: const Icon(Icons.file_upload_outlined),
          label: Text(l.ytImportSubscriptions),
        ),
        body: EmptyState(
          icon: Icons.subscriptions_rounded,
          title: l.ytNoSubscriptionsTitle,
          message: l.ytNoSubscriptionsMessage,
        ),
      );
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Row(
          children: [
            Text(l.ytChannelCount(subs.length),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _import(context, ref),
              icon: const Icon(Icons.file_upload_outlined, size: 18),
              label: Text(l.ytImport),
            ),
            TextButton.icon(
              onPressed: () => _export(context, ref),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: Text(l.ytExport),
            ),
          ],
        ),
      ),
      Expanded(
        child: LayoutBuilder(builder: (context, box) {
      // Wide windows get more columns rather than absurdly stretched cards.
      final columns = (box.maxWidth / 260).floor().clamp(1, 6);
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisExtent: 96,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: subs.length,
        itemBuilder: (_, i) => _SubscriptionCard(channel: subs[i]),
      );
        }),
      ),
    ]);
  }
}

class _SubscriptionCard extends ConsumerWidget {
  final YoutubeChannel channel;
  const _SubscriptionCard({required this.channel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return TvFocusRing(
      borderRadius: BorderRadius.circular(12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/youtube/channel',
              extra: (channelId: channel.id, title: channel.title)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: scheme.surfaceContainerHigh,
                  foregroundImage: channel.logoUrl.isEmpty
                      ? null
                      : cachedImageProvider(channel.logoUrl),
                  child: const Icon(Icons.person_rounded),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        channel.title.isEmpty
                            ? l.ytChannelFallback
                            : channel.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (channel.subscribersLabel.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(channel.subscribersLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: l.commonMore,
                  onSelected: (v) {
                    if (v == 'unsub') {
                      ref
                          .read(youtubeSubscriptionsProvider.notifier)
                          .unsubscribe(channel.id);
                    } else if (v == 'groups') {
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        showDragHandle: true,
                        builder: (_) => _FeedGroupSheet(channel: channel),
                      );
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'groups', child: Text(l.ytFeedGroups)),
                    PopupMenuItem(value: 'unsub', child: Text(l.ytUnsubscribe)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---- What's New: every subscribed channel's uploads, newest first ----

class _FeedTab extends ConsumerWidget {
  const _FeedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final subs = ref.watch(youtubeSubscriptionsProvider).asData?.value ??
        const <YoutubeChannel>[];
    if (subs.isEmpty) {
      return EmptyState(
        icon: Icons.subscriptions_rounded,
        title: l.ytNoSubscriptionsTitle,
        message: l.ytFeedEmptyMessage,
      );
    }
    final feed = ref.watch(youtubeFeedProvider);
    return Column(children: [
      const _FeedGroupBar(),
      Expanded(
        child: RefreshIndicator(
      onRefresh: () async => ref.invalidate(youtubeFeedProvider),
      child: NotificationListener<ScrollNotification>(
        // Pull the next pages in as the end comes into view.
        onNotification: (n) {
          final res = feed.asData?.value;
          if (res != null &&
              res.hasMore &&
              !res.loadingMore &&
              n.metrics.pixels >= n.metrics.maxScrollExtent - 600) {
            ref.read(youtubeFeedProvider.notifier).loadMore();
          }
          return false;
        },
        child: feed.when(
          loading: () => const YoutubeVideosSkeleton(),
          error: (e, _) => ErrorView(
            message: '$e',
            onRetry: () => ref.invalidate(youtubeFeedProvider),
          ),
          data: (res) {
            if (res.videos.isEmpty) {
              return EmptyState(
                icon: Icons.videocam_off_rounded,
                title: l.ytNothingNew,
              );
            }
            return YoutubeVideoCollection(
              videos: res.videos,
              loadingMore: res.hasMore,
            );
          },
        ),
      ),
        ),
      ),
    ]);
  }
}

/// Filters What's New to one feed group. Hidden until a group exists: with a
/// handful of subscriptions the merged feed is fine, and this would be an empty
/// row of chrome.
class _FeedGroupBar extends ConsumerWidget {
  const _FeedGroupBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(youtubeFeedGroupsProvider).asData?.value ??
        const <YoutubeFeedGroup>[];
    if (groups.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final active = ref.watch(youtubeActiveFeedGroupProvider);
    final notifier = ref.read(youtubeActiveFeedGroupProvider.notifier);

    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(l.ytAll),
              selected: active == null,
              onSelected: (_) => notifier.set(null),
            ),
          ),
          for (final g in groups)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(g.name),
                selected: active == g.id,
                onSelected: (_) => notifier.set(g.id),
              ),
            ),
        ],
      ),
    );
  }
}

// ---- Playlists you made ----

/// Local playlists. These are yours and live on this device; the playlists in
/// search results belong to other people and are fetched live.
class _PlaylistsTab extends ConsumerWidget {
  const _PlaylistsTab();

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.ytNewPlaylist),
        content: TvTextField(
          controller: controller,
          autofocus: true,
          label: l.ytName,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(l.commonCancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(l.ytCreate),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await ref.read(youtubeLocalPlaylistsProvider.notifier).create(name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final playlists = ref.watch(youtubeLocalPlaylistsProvider).asData?.value ??
        const <YoutubeLocalPlaylist>[];
    final saved = ref.watch(youtubeSavedPlaylistsProvider).asData?.value ??
        const <YoutubePlaylist>[];

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: Text(l.ytNewPlaylist),
      ),
      body: playlists.isEmpty && saved.isEmpty
          ? EmptyState(
              icon: Icons.playlist_play_rounded,
              title: l.ytNoPlaylistsTitle,
              message: l.ytNoPlaylistsMessage,
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                if (playlists.isNotEmpty) ...[
                  _PlaylistSectionLabel(
                      text: l.ytYourPlaylists, count: playlists.length),
                  for (final p in playlists)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _LocalPlaylistRow(playlist: p),
                    ),
                ],
                // Saved ones are separate on purpose: they're someone else's,
                // fetched live, and can change or vanish under you.
                if (saved.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _PlaylistSectionLabel(text: l.ytSaved, count: saved.length),
                  for (final p in saved)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _SavedPlaylistRow(playlist: p),
                    ),
                ],
              ],
            ),
    );
  }
}

/// Which groups a channel belongs to.
class _FeedGroupSheet extends ConsumerWidget {
  final YoutubeChannel channel;
  const _FeedGroupSheet({required this.channel});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.ytNewFeedGroup),
        content: TvTextField(
          controller: controller,
          autofocus: true,
          label: l.ytName,
          hint: l.ytFeedGroupHint,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: Text(l.ytCreate)),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final n = ref.read(youtubeFeedGroupsProvider.notifier);
    final g = await n.create(name);
    await n.toggleChannel(g.id, channel.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final groups = ref.watch(youtubeFeedGroupsProvider).asData?.value ??
        const <YoutubeFeedGroup>[];
    final theme = Theme.of(context);

    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
              child: Text(l.ytFeedGroups,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                l.ytFeedGroupsDescription(channel.title),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add_rounded),
              title: Text(l.ytNewGroup),
              onTap: () async {
                await _create(context, ref);
                if (context.mounted) Navigator.pop(context);
              },
            ),
            if (groups.isNotEmpty) const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final g in groups)
                    CheckboxListTile(
                      value: g.contains(channel.id),
                      title: Text(g.name),
                      subtitle: Text(g.countLabel),
                      onChanged: (_) => ref
                          .read(youtubeFeedGroupsProvider.notifier)
                          .toggleChannel(g.id, channel.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistSectionLabel extends StatelessWidget {
  final String text;
  final int count;
  const _PlaylistSectionLabel({required this.text, required this.count});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
        child: Text('$text  ·  $count',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
      );
}

class _SavedPlaylistRow extends ConsumerWidget {
  final YoutubePlaylist playlist;
  const _SavedPlaylistRow({required this.playlist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return TvFocusRing(
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/youtube/playlist',
            extra: (
              playlistId: playlist.id,
              title: playlist.title,
              count: playlist.videoCount
            )),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 140,
                  height: 79,
                  child: playlist.thumbnailUrl.isEmpty
                      ? Container(
                          color: scheme.surfaceContainerHigh,
                          child: Icon(Icons.playlist_play_rounded,
                              color: scheme.onSurfaceVariant),
                        )
                      : CachedImage(
                          url: playlist.thumbnailUrl,
                          errorBuilder: (_) =>
                              Container(color: scheme.surfaceContainerHigh)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(playlist.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    if (playlist.author.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(playlist.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: l.commonRemove,
                icon: const Icon(Icons.bookmark_remove_outlined),
                onPressed: () => ref
                    .read(youtubeSavedPlaylistsProvider.notifier)
                    .toggle(playlist),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocalPlaylistRow extends ConsumerWidget {
  final YoutubeLocalPlaylist playlist;
  const _LocalPlaylistRow({required this.playlist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return TvFocusRing(
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/youtube/my-playlist', extra: playlist.id),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 140,
                  height: 79,
                  child: playlist.thumbnailUrl.isEmpty
                      ? Container(
                          color: scheme.surfaceContainerHigh,
                          child: Icon(Icons.playlist_play_rounded,
                              color: scheme.onSurfaceVariant),
                        )
                      : CachedImage(
                          url: playlist.thumbnailUrl,
                          errorBuilder: (_) =>
                              Container(color: scheme.surfaceContainerHigh)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(playlist.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(playlist.countLabel(l),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: l.commonMore,
                onSelected: (v) async {
                  final n = ref.read(youtubeLocalPlaylistsProvider.notifier);
                  if (v == 'delete') {
                    final ok = await confirm(
                      context,
                      title: l.ytDeletePlaylistTitle,
                      message: l.ytDeletePlaylistBody(playlist.name),
                      confirmLabel: l.commonDelete,
                      destructive: true,
                    );
                    if (ok) await n.delete(playlist.id);
                  } else if (v == 'rename') {
                    final controller =
                        TextEditingController(text: playlist.name);
                    final name = await showDialog<String>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(l.ytRenamePlaylist),
                        content: TvTextField(
                            controller: controller,
                            autofocus: true,
                            label: l.ytName,
                            onSubmitted: (v) => Navigator.pop(ctx, v)),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(l.commonCancel)),
                          FilledButton(
                              onPressed: () =>
                                  Navigator.pop(ctx, controller.text),
                              child: Text(l.commonSave)),
                        ],
                      ),
                    );
                    if (name != null && name.trim().isNotEmpty) {
                      await n.rename(playlist.id, name);
                    }
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'rename', child: Text(l.ytRename)),
                  PopupMenuItem(value: 'delete', child: Text(l.commonDelete)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Downloads ----

/// Downloads in progress, and the files already on disk.
class _DownloadsTab extends ConsumerStatefulWidget {
  const _DownloadsTab();

  @override
  ConsumerState<_DownloadsTab> createState() => _DownloadsTabState();
}

class _DownloadsTabState extends ConsumerState<_DownloadsTab> {
  bool _selectionMode = false;
  final Set<String> _selected = {};

  // Only finished downloads are selectable — an active transfer already has
  // its own Cancel, and bulk-deleting a failed/queued row doesn't mean the
  // same thing as deleting a file.
  void _enterSelection([String? firstId]) => setState(() {
        _selectionMode = true;
        if (firstId != null) _selected.add(firstId);
      });

  void _exitSelection() => setState(() {
        _selectionMode = false;
        _selected.clear();
      });

  void _toggle(String id) => setState(() {
        if (!_selected.remove(id)) _selected.add(id);
      });

  void _selectAll(List<String> ids) => setState(() {
        _selected
          ..clear()
          ..addAll(ids);
      });

  Future<void> _deleteSelected() async {
    final l = AppLocalizations.of(context);
    final ok = await confirm(context,
        title: l.ytDeleteSelectedTitle(_selected.length),
        message: l.ytDeleteSelectedConfirm,
        confirmLabel: l.commonDelete,
        destructive: true);
    if (ok != true || !mounted) return;
    final n = ref.read(youtubeDownloadsProvider.notifier);
    final ids = _selected.toList();
    _exitSelection();
    for (final id in ids) {
      await n.remove(id, deleteFile: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final downloads =
        ref.watch(youtubeDownloadsProvider).asData?.value ?? const [];
    final folder = ref
        .watch(youtubeDownloadFolderLabelProvider(YtDownloadKind.video))
        .asData
        ?.value;
    final hasFfmpeg = ref.watch(ffmpegAvailableProvider).asData?.value ?? true;
    final doneIds = [
      for (final d in downloads)
        if (d.status == YtDownloadStatus.done) d.id,
    ];

    if (downloads.isEmpty) {
      return EmptyState(
        icon: Icons.download_rounded,
        title: l.ytNoDownloadsTitle,
        message: hasFfmpeg
            ? l.ytDownloadsEmptyFfmpeg(folder ?? l.ytDownloadsFolder)
            : l.ytDownloadsEmptyNoFfmpeg,
      );
    }

    return Column(
      children: [
        // Only shown while actually selecting — there's no standing "Select"
        // button; that action lives in each finished download's own menu
        // instead (see _DownloadRow), alongside its other actions rather than
        // as its own prominent affordance for something done rarely.
        if (_selectionMode)
          PickBar(
            count: _selected.length,
            onCancel: _exitSelection,
            onSelectAll: () => _selectAll(doneIds),
            actions: [
              PickAction(
                Icons.delete_outline_rounded,
                l.commonDelete,
                _deleteSelected,
                danger: true,
              ),
            ],
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: downloads.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final d = downloads[i];
              final selectable = d.status == YtDownloadStatus.done;
              return _DownloadRow(
                download: d,
                selecting: _selectionMode,
                selected: _selected.contains(d.id),
                onEnterSelection:
                    selectable ? () => _enterSelection(d.id) : null,
                onToggle: selectable ? () => _toggle(d.id) : null,
              );
            },
          ),
        ),
      ],
    );
  }

}

class _DownloadRow extends ConsumerWidget {
  final YoutubeDownload download;
  final bool selecting;
  final bool selected;
  final VoidCallback? onEnterSelection;
  final VoidCallback? onToggle;
  const _DownloadRow({
    required this.download,
    this.selecting = false,
    this.selected = false,
    this.onEnterSelection,
    this.onToggle,
  });

  /// Hands the file to another app, saying so plainly when none can take it
  /// rather than failing without a word.
  static Future<void> _handOff(
      BuildContext context, Future<void> Function() action) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } catch (_) {
      showSnackOn(messenger, l.ytOpenFileFailed);
    }
  }

  /// The same menu whichever of the three-dot button, right-click, or
  /// long-press opened it. "Select" (when this download has finished) is
  /// just one more entry in it, not a separate gesture of its own.
  Future<void> _openMenu(BuildContext context, WidgetRef ref, Offset at) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final d = download;
    final n = ref.read(youtubeDownloadsProvider.notifier);
    final playable = d.status == YtDownloadStatus.done && d.filePath != null;
    void play() => context.push('/youtube/file', extra: (
          path: d.filePath!,
          videoId: d.id,
          title: d.title,
          author: d.author,
          thumbnailUrl: d.thumbnailUrl,
        ));
    return showContextMenu(context, at: at, actions: [
      if (playable)
        ContextMenuAction(
            icon: Icons.play_arrow_rounded, label: l.commonPlay, onTap: play),
      // Android can't open a folder in another app (a file:// link is
      // refused outright), so there the file itself goes to Open With or
      // Share instead.
      if (d.filePath != null && Platform.isAndroid) ...[
        ContextMenuAction(
          icon: Icons.open_in_new_rounded,
          label: l.ytOpenWith,
          onTap: () => _handOff(context, () => SharedFiles.open(d.filePath!)),
        ),
        ContextMenuAction(
          icon: Icons.share_rounded,
          label: l.ytShareFile,
          onTap: () => _handOff(context, () => SharedFiles.share(d.filePath!)),
        ),
      ] else if (d.filePath != null)
        ContextMenuAction(
          icon: Icons.folder_open_rounded,
          label: l.ytShowInFolder,
          onTap: () => launchUrl(Uri.file(File(d.filePath!).parent.path)),
        ),
      // Bulk delete starts from any one item's own menu, not a standing
      // button, this is a rare action, not one that deserves permanent
      // real estate.
      if (onEnterSelection != null)
        ContextMenuAction(
          icon: Icons.checklist_rounded,
          label: l.ytSelectDownloads,
          onTap: onEnterSelection!,
        ),
      // Two verbs, because they're different intentions: clearing the list
      // is not the same as deleting the video.
      ContextMenuAction(
        icon: Icons.remove_circle_outline_rounded,
        label: l.ytRemoveFromList,
        onTap: () => n.remove(d.id),
      ),
      if (d.filePath != null)
        ContextMenuAction(
          icon: Icons.delete_outline_rounded,
          label: l.ytDeleteFile,
          color: cs.error,
          onTap: () => n.remove(d.id, deleteFile: true),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final d = download;
    final n = ref.read(youtubeDownloadsProvider.notifier);

    final status = switch (d.status) {
      YtDownloadStatus.queued => l.ytDownloadWaiting,
      YtDownloadStatus.downloading =>
        d.stage == 'audio' ? l.ytDownloadingAudio : l.ytDownloadingVideo,
      // Merging has no progress of its own; saying so beats a frozen bar.
      YtDownloadStatus.merging => l.ytDownloadMerging,
      YtDownloadStatus.done => [d.sizeLabel, l.ytDownloadSaved].where((s) => s.isNotEmpty).join('  ·  '),
      YtDownloadStatus.failed => d.error ?? l.ytFailed,
      YtDownloadStatus.cancelled => l.ytDownloadCancelled,
    };

    final playable = d.status == YtDownloadStatus.done && d.filePath != null;
    void play() => context.push('/youtube/file', extra: (
          path: d.filePath!,
          videoId: d.id,
          title: d.title,
          author: d.author,
          thumbnailUrl: d.thumbnailUrl,
        ));

    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      // InkWell has no position-aware long-press/right-click variants, so
      // those two gestures are handled up here instead, around it.
      onLongPressStart: selecting
          ? null
          : (d) => _openMenu(context, ref, d.globalPosition),
      onSecondaryTapUp: selecting
          ? null
          : (d) => _openMenu(context, ref, d.globalPosition),
      child: TvFocusRing(
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        // The whole point of downloading is watching it later, offline. Tapping
        // the row plays the file from disk rather than re-streaming it, unless
        // a bulk selection is in progress, where a tap toggles instead.
        onTap: selecting ? onToggle : (playable ? play : null),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 100,
                  height: 56,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      d.thumbnailUrl.isEmpty
                          ? Container(color: scheme.surfaceContainerHigh)
                          : CachedImage(
                              url: d.thumbnailUrl,
                              errorBuilder: (_) => Container(
                                  color: scheme.surfaceContainerHigh)),
                      if (playable && !selecting)
                        Container(
                          color: Colors.black38,
                          child: const Icon(Icons.play_arrow_rounded,
                              color: Colors.white, size: 28),
                        ),
                      if (selecting && onToggle != null)
                        Container(
                          color: selected ? Colors.black45 : Colors.black26,
                          alignment: Alignment.center,
                          child: Icon(
                            selected
                                ? Icons.check_circle_rounded
                                : Icons.circle_outlined,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(d.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: d.status == YtDownloadStatus.failed
                              ? scheme.error
                              : scheme.onSurfaceVariant,
                        )),
                    if (d.isActive) ...[
                      const SizedBox(height: 6),
                      // Indeterminate when the size is unknown or while merging,
                      // rather than a bar that sits still and looks stuck.
                      LinearProgressIndicator(value: d.progress, minHeight: 3),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (selecting)
                const SizedBox.shrink()
              else if (d.isActive)
                IconButton(
                  tooltip: l.commonCancel,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => n.cancel(d.id),
                )
              else
                Builder(builder: (btnContext) {
                  return IconButton(
                    tooltip: l.commonMore,
                    icon: const Icon(Icons.more_vert_rounded),
                    onPressed: () {
                      final box =
                          btnContext.findRenderObject() as RenderBox?;
                      _openMenu(
                          context,
                          ref,
                          box == null
                              ? Offset.zero
                              : box.localToGlobal(
                                  box.size.center(Offset.zero)));
                    },
                  );
                }),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

// ---- History ----

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final entries = ref.watch(youtubeHistoryProvider).asData?.value ??
        const <YoutubeHistoryEntry>[];
    if (entries.isEmpty) {
      return EmptyState(
        icon: Icons.history_rounded,
        title: l.ytNothingWatchedTitle,
        message: l.ytHistoryEmptyMessage,
      );
    }
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextButton.icon(
              onPressed: () => _confirmClear(context, ref),
              icon: const Icon(Icons.delete_sweep_rounded),
              label: Text(l.ytClearHistory),
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _HistoryRow(entry: entries[i]),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final ok = await confirm(context,
        title: l.ytClearHistory,
        message: l.ytClearHistoryConfirm,
        confirmLabel: l.commonClear,
        destructive: true);
    if (ok) await ref.read(youtubeHistoryProvider.notifier).clear();
  }
}

/// A watched video with a resume bar, and a remove action.
class _HistoryRow extends ConsumerWidget {
  final YoutubeHistoryEntry entry;
  const _HistoryRow({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return YoutubeVideoRow(
      video: YoutubeVideo(
        id: entry.id,
        title: entry.title,
        author: entry.author,
        channelId: entry.channelId,
        url: entry.url,
        thumbnailUrl: entry.thumbnailUrl,
        duration: entry.durationSeconds > 0
            ? Duration(seconds: entry.durationSeconds)
            : null,
      ),
      progress: entry.finished ? null : entry.progress,
      // Inline X (beside the overflow menu, not on top of it).
      onRemove: () =>
          ref.read(youtubeHistoryProvider.notifier).remove(entry.id),
      removeTooltip: l.ytRemoveFromHistory,
    );
  }
}

// ---- Search ----

class _SearchTab extends ConsumerStatefulWidget {
  const _SearchTab();

  @override
  ConsumerState<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends ConsumerState<_SearchTab>
    with AutomaticKeepAliveClientMixin {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;

  /// What's typed, debounced, and only used to fetch suggestions. The committed
  /// search lives in [youtubeQueryProvider].
  String _typed = '';
  bool _suggestionsOpen = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _controller.text = ref.read(youtubeQueryProvider);
    _focus.addListener(() {
      if (!_focus.hasFocus && _suggestionsOpen) {
        setState(() => _suggestionsOpen = false);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      setState(() {
        _typed = value.trim();
        _suggestionsOpen = _typed.isNotEmpty && _focus.hasFocus;
      });
    });
  }

  void _submit(String q) {
    _debounce?.cancel();
    final text = q.trim();
    _controller.text = text;
    setState(() => _suggestionsOpen = false);
    _focus.unfocus();
    ref.read(youtubeQueryProvider.notifier).set(text);
    // Yours, not YouTube's guesses — the fast way back to yesterday's query.
    unawaited(ref.read(youtubeSearchHistoryProvider.notifier).record(text));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l = AppLocalizations.of(context);
    final query = ref.watch(youtubeQueryProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: SearchField(
            controller: _controller,
            focusNode: _focus,
            hint: l.ytSearchYoutube,
            onChanged: _onChanged,
            onSubmitted: _submit,
            onClear: () {
              _debounce?.cancel();
              setState(() {
                _typed = '';
                _suggestionsOpen = false;
              });
              ref.read(youtubeQueryProvider.notifier).set('');
              _focus.requestFocus();
            },
          ),
        ),
        // Always shown, including before a query: hiding these until you'd
        // already typed meant nobody could tell channel and playlist search
        // existed at all.
        const _SearchFilters(),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: query.isEmpty
                    ? _RecentSearches(onPick: _submit)
                    : const _Results(),
              ),
              if (_suggestionsOpen)
                Positioned(
                  left: 16,
                  right: 16,
                  top: 0,
                  child: _Suggestions(query: _typed, onPick: _submit),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Query suggestions from YouTube, shown over the results while typing.
class _Suggestions extends ConsumerWidget {
  final String query;
  final void Function(String) onPick;
  const _Suggestions({required this.query, required this.onPick});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list =
        ref.watch(youtubeSuggestionsProvider(query)).asData?.value ?? const [];
    if (list.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    // Without this, tapping a suggestion fires the field's onTapOutside, which
    // unfocuses, which tears this list down before the tap can complete.
    return TextFieldTapRegion(
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        color: scheme.surfaceContainerHigh,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: [
              for (final s in list.take(10))
                TvFocusRing(
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.search_rounded, size: 18),
                    title:
                        Text(s, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => onPick(s),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the empty Search tab says, worded for whichever filter is selected.
/// One search does NOT cover all three: the filter picks which one runs.
class _SearchPrompt extends ConsumerWidget {
  const _SearchPrompt();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return switch (ref.watch(youtubeSearchFilterProvider).filter) {
      YtSearchFilter.videos => EmptyState(
          icon: Icons.smart_display_rounded,
          title: l.ytSearchVideos,
          message: l.ytSearchVideosMessage,
        ),
      YtSearchFilter.channels => EmptyState(
          icon: Icons.person_search_rounded,
          title: l.ytSearchChannels,
          message: l.ytSearchChannelsMessage,
        ),
      YtSearchFilter.playlists => EmptyState(
          icon: Icons.playlist_play_rounded,
          title: l.ytSearchPlaylists,
          message: l.ytSearchPlaylistsMessage,
        ),
    };
  }
}

/// Recent searches, or the prompt when there aren't any yet.
class _RecentSearches extends ConsumerWidget {
  final void Function(String) onPick;
  const _RecentSearches({required this.onPick});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final recent =
        ref.watch(youtubeSearchHistoryProvider).asData?.value ?? const <String>[];
    if (recent.isEmpty) return const _SearchPrompt();
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Row(
          children: [
            Text(l.ytRecentSearches,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            TextButton(
              onPressed: () =>
                  ref.read(youtubeSearchHistoryProvider.notifier).clear(),
              child: Text(l.commonClear),
            ),
          ],
        ),
        for (final q in recent)
          TvFocusRing(
            borderRadius: BorderRadius.circular(12),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.history_rounded, size: 20),
              title: Text(q, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                tooltip: l.commonRemove,
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () =>
                    ref.read(youtubeSearchHistoryProvider.notifier).remove(q),
              ),
              onTap: () => onPick(q),
            ),
          ),
      ],
    );
  }
}

/// Videos / Channels / Playlists, mirroring YouTube's own search filters, plus
/// the narrowing options that only apply to videos.
class _SearchFilters extends ConsumerWidget {
  const _SearchFilters();

  static String _filterLabel(AppLocalizations l, YtSearchFilter f) =>
      switch (f) {
        YtSearchFilter.videos => l.ytVideos,
        YtSearchFilter.channels => l.ytChannels,
        YtSearchFilter.playlists => l.ytPlaylists,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final q = ref.watch(youtubeSearchFilterProvider);
    final notifier = ref.read(youtubeSearchFilterProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        children: [
          for (final f in YtSearchFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(_filterLabel(l, f)),
                selected: q.filter == f,
                onSelected: (_) => notifier.set(f),
              ),
            ),
          const Spacer(),
          // Sort and narrowing are video-only concepts; a channel has no
          // length, and YouTube ignores those fields anyway.
          if (q.filter == YtSearchFilter.videos)
            ActionChip(
              avatar: Badge(
                isLabelVisible: q.activeCount > 0,
                label: Text('${q.activeCount}'),
                child: const Icon(Icons.tune_rounded, size: 18),
              ),
              label: Text(l.ytFilters),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => const _SearchOptionsSheet(),
              ),
            ),
        ],
      ),
    );
  }
}

class _SearchOptionsSheet extends ConsumerWidget {
  const _SearchOptionsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final q = ref.watch(youtubeSearchFilterProvider);
    final n = ref.read(youtubeSearchFilterProvider.notifier);
    final theme = Theme.of(context);

    Widget group<T>(
      String title,
      Map<T, String> options,
      T current,
      void Function(T) onPick,
    ) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
              child: Text(title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in options.entries)
                    ChoiceChip(
                      label: Text(e.value),
                      selected: current == e.key,
                      onSelected: (_) => onPick(e.key),
                    ),
                ],
              ),
            ),
          ],
        );

    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
                child: Row(
                  children: [
                    Text(l.ytSearchFilters,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const Spacer(),
                    TextButton(
                      onPressed: q.activeCount == 0 ? null : n.reset,
                      child: Text(l.commonReset),
                    ),
                  ],
                ),
              ),
              group<YtSearchSort>(l.ytSortBy, {
                YtSearchSort.relevance: l.ytSortRelevance,
                YtSearchSort.uploadDate: l.ytUploadDate,
                YtSearchSort.viewCount: l.ytSortViewCount,
                YtSearchSort.rating: l.ytSortRating,
              }, q.sort, n.setSort),
              group<YtUploadDate>(l.ytUploadDate, {
                YtUploadDate.any: l.ytUploadAnyTime,
                YtUploadDate.lastHour: l.ytUploadLastHour,
                YtUploadDate.today: l.ytUploadToday,
                YtUploadDate.thisWeek: l.ytUploadThisWeek,
                YtUploadDate.thisMonth: l.ytUploadThisMonth,
                YtUploadDate.thisYear: l.ytUploadThisYear,
              }, q.uploadDate, n.setUploadDate),
              group<YtDuration>(l.ytLength, {
                YtDuration.any: l.ytLengthAny,
                YtDuration.under4Min: l.ytLengthUnder4,
                YtDuration.from4To20Min: l.ytLength4To20,
                YtDuration.over20Min: l.ytLengthOver20,
              }, q.duration, n.setDuration),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(youtubeSearchProvider);
    return async.when(
      loading: () => const YoutubeVideosSkeleton(),
      error: (e, _) => ErrorView(
        message: '$e',
        onRetry: () => ref.invalidate(youtubeSearchProvider),
      ),
      data: (res) {
        if (res.isEmpty) {
          return EmptyState(
            icon: Icons.search_off_rounded,
            title: l.ytNoResults,
          );
        }
        // Pull the next page in as the end of the list comes into view.
        Widget paged(Widget child) => NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (res.hasMore &&
                    !res.loadingMore &&
                    n.metrics.pixels >= n.metrics.maxScrollExtent - 600) {
                  ref.read(youtubeSearchProvider.notifier).loadMore();
                }
                return false;
              },
              child: child,
            );

        // Videos honour the list/grid setting; channels and playlists have
        // their own row shapes and stay as they are.
        if (res.videos.isNotEmpty) {
          return paged(YoutubeVideoCollection(
            videos: res.videos,
            loadingMore: res.hasMore,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          ));
        }
        final rows = <Widget>[
          for (final c in res.channels) _ChannelResultRow(channel: c),
          for (final p in res.playlists) _PlaylistResultRow(playlist: p),
        ];
        return paged(ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          itemCount: rows.length + (res.hasMore ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            if (i >= rows.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: AppSpinner()),
              );
            }
            return rows[i];
          },
        ));
      },
    );
  }
}

/// A channel in search results: picture, name, handle, subscribers, and a
/// Subscribe toggle right there — subscribing shouldn't need a detour through
/// the channel page.
class _ChannelResultRow extends StatelessWidget {
  final YoutubeChannel channel;
  const _ChannelResultRow({required this.channel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final meta = [
      if ((channel.handle ?? '').isNotEmpty) channel.handle!,
      if (channel.subscribersLabel.isNotEmpty) channel.subscribersLabel,
    ].join('  ·  ');
    return TvFocusRing(
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/youtube/channel',
            extra: (channelId: channel.id, title: channel.title)),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: scheme.surfaceContainerHigh,
                foregroundImage: channel.logoUrl.isEmpty
                    ? null
                    : cachedImageProvider(channel.logoUrl),
                child: const Icon(Icons.person_rounded),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(channel.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SubscribeButton(channel: channel),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistResultRow extends StatelessWidget {
  final YoutubePlaylist playlist;
  const _PlaylistResultRow({required this.playlist});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final meta = [
      if (playlist.author.isNotEmpty) playlist.author,
      if (playlist.videoCountLabel.isNotEmpty) playlist.videoCountLabel,
    ].join('  ·  ');
    return TvFocusRing(
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/youtube/playlist',
            extra: (
              playlistId: playlist.id,
              title: playlist.title,
              count: playlist.videoCount
            )),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  children: [
                    SizedBox(
                      width: 178,
                      height: 100,
                      child: playlist.thumbnailUrl.isEmpty
                          ? Container(color: scheme.surfaceContainerHigh)
                          : CachedImage(
                              url: playlist.thumbnailUrl,
                              errorBuilder: (_) => Container(
                                  color: scheme.surfaceContainerHigh)),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 58,
                        color: Colors.black.withValues(alpha: 0.75),
                        child: const Icon(Icons.playlist_play_rounded,
                            color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(playlist.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

