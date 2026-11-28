import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/error_text.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import '../models/play_queue.dart';
import '../models/session.dart';
import '../services/tv_mode.dart';
import '../state/playlist_run.dart';
import '../state/playlist_providers.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import '../widgets/checked_menu_item.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';
import '../widgets/media_image.dart';
import '../widgets/reorder.dart';
import '../widgets/hover_pill_button.dart';
import '../widgets/app_snack.dart';
import '../widgets/app_spinner.dart';
import '../widgets/tv_keyboard.dart';
import '../widgets/tv_focus.dart';
import '../widgets/ui_common.dart';
import '../api/jellyfin_client.dart';

/// Shows the contents of a playlist with play, reorder-free removal, and
/// delete-playlist actions.
class PlaylistDetailScreen extends ConsumerWidget {
  final BaseItemDto playlist;
  const PlaylistDetailScreen({super.key, required this.playlist});

  /// Whether [items] holds the same entry id more than once. Jellyfin 10.9
  /// and later give an item that's in a playlist twice one entry id for
  /// both, and then acts on the wrong one, or on both.
  static bool _hasRepeats(List<BaseItemDto> items) {
    final ids = {for (final i in items) i.playlistItemId ?? i.id};
    return ids.length < items.length;
  }

  /// Sends the playlist as [order], for a list with repeats in it.
  Future<void> _setOrder(WidgetRef ref, Session session,
          List<BaseItemDto> order) =>
      ref.read(jellyfinClientProvider).setPlaylistItems(
            baseUrl: session.baseUrl,
            token: session.accessToken,
            playlistId: playlist.id,
            itemIds: [for (final i in order) i.id],
          );

  Future<void> _removeEntry(BuildContext context, WidgetRef ref,
      List<BaseItemDto> items, int index) async {
    final item = items[index];
    final l = AppLocalizations.of(context);
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null || item.playlistItemId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_hasRepeats(items)) {
        // Removing by entry id would take every copy of it.
        await _setOrder(ref, session, [...items]..removeAt(index));
      } else {
        await ref.read(jellyfinClientProvider).removeFromPlaylist(
              baseUrl: session.baseUrl,
              token: session.accessToken,
              playlistId: playlist.id,
              entryIds: [item.playlistItemId!],
            );
      }
      ref.invalidate(playlistItemsProvider(playlist.id));
      ref.invalidate(playlistsProvider);
      showSnackOn(messenger, l.appRemovedNamed(item.name),
          kind: SnackKind.success);
    } catch (e) {
      showErrorOn(messenger, e);
    }
  }

  Future<void> _deletePlaylist(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await confirm(context,
        title: l.appDeletePlaylist,
        message: l.appDeletePlaylistConfirm(playlist.name),
        confirmLabel: l.commonDelete,
        destructive: true);
    if (!ok) return;
    try {
      await ref.read(jellyfinClientProvider).deletePlaylist(
            baseUrl: session.baseUrl,
            token: session.accessToken,
            playlistId: playlist.id,
          );
      ref.invalidate(playlistsProvider);
      if (context.mounted) {
        context.pop();
        showSnackOn(messenger, l.appDeletedNamed(playlist.name),
            kind: SnackKind.success);
      }
    } catch (e) {
      showErrorOn(messenger, e);
    }
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final current =
        ref.read(playlistNamesProvider)[playlist.id] ?? playlist.name;
    final controller = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.appRenamePlaylist),
        content: TvTextField(
          controller: controller,
          autofocus: true,
          label: l.appPlaylistName,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(l.commonSave)),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == current) return;
    if (!isPlaylistNameFree(name)) {
      showSnackOn(messenger, l.errPlaylistNameReserved, kind: SnackKind.error);
      return;
    }
    try {
      await ref.read(jellyfinClientProvider).renamePlaylist(
            baseUrl: session.baseUrl,
            userId: session.userId,
            token: session.accessToken,
            playlistId: playlist.id,
            name: name,
          );
      ref.read(playlistNamesProvider.notifier).set(playlist.id, name);
      ref.invalidate(playlistsProvider);
      showSnackOn(messenger, l.appRenamedTo(name), kind: SnackKind.success);
    } catch (e) {
      showErrorOn(messenger, e);
    }
  }

  Future<void> _reorder(BuildContext context, WidgetRef ref,
      List<BaseItemDto> items, int oldIndex, int newIndex) async {
    final session = ref.read(sessionControllerProvider).asData?.value;
    final entryId = items[oldIndex].playlistItemId;
    if (session == null || entryId == null) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_hasRepeats(items)) {
        // Moving by entry id would move the first copy, whichever was meant.
        final order = [...items];
        order.insert(newIndex, order.removeAt(oldIndex));
        await _setOrder(ref, session, order);
      } else {
        await ref.read(jellyfinClientProvider).movePlaylistItem(
              baseUrl: session.baseUrl,
              token: session.accessToken,
              playlistId: playlist.id,
              entryId: entryId,
              newIndex: newIndex,
            );
      }
      ref.invalidate(playlistItemsProvider(playlist.id));
    } catch (e) {
      showErrorOn(messenger, e);
    }
  }

  static bool _isFolder(BaseItemDto i) => i.isFolder || i.isSeries || i.isAlbum;

  /// Plays [order] from [start] on, in its own order: songs in the music
  /// player, movies and episodes in the video player, each handing over to
  /// the other where the list changes kind (see [PlaylistRun]).
  ///
  /// [at] is a place in [order], not an item: the same song can be in a
  /// playlist twice.
  Future<void> _playFrom(BuildContext context, WidgetRef ref,
      List<BaseItemDto> order, int at) async {
    final start = order[at];
    final items = <BaseItemDto>[];
    var index = 0;
    for (var i = 0; i < order.length; i++) {
      if (_isFolder(order[i])) continue;
      if (i == at) index = items.length;
      items.add(order[i]);
    }
    final queue = PlayQueue(items, index);
    if (start.isAudio) {
      await ref.read(playlistRunProvider).playSongs(queue);
      if (context.mounted) context.push('/nowplaying');
      return;
    }
    context.push('/player', extra: queue);
  }

  /// Play from the top, or in a shuffled order.
  Future<void> _playAll(BuildContext context, WidgetRef ref,
      List<BaseItemDto> items, {bool shuffle = false}) async {
    final order = [
      for (final i in items)
        if (!_isFolder(i)) i,
    ];
    if (shuffle) order.shuffle();
    if (order.isEmpty) return;
    await _playFrom(context, ref, order, 0);
  }

  Future<void> _openItem(
      BuildContext context, WidgetRef ref, List<BaseItemDto> items, int i) async {
    final item = items[i];
    if (_isFolder(item)) {
      context.push('/item', extra: item);
    } else {
      // On through the rest of the list from the one tapped.
      await _playFrom(context, ref, items, i);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(playlistItemsProvider(playlist.id));
    return Scaffold(
      appBar: AppBar(
        title: Text(
            ref.watch(playlistNamesProvider)[playlist.id] ?? playlist.name),
        actions: [
          PopupMenuButton<String>(
            tooltip: l.commonMore,
            onSelected: (v) {
              if (v == 'rename') _rename(context, ref);
              if (v == 'delete') _deletePlaylist(context, ref);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'rename',
                child: MenuTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(l.appRenamePlaylist),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: MenuTile(
                  leading: Icon(Icons.delete_outline_rounded,
                      color: Theme.of(context).colorScheme.error),
                  title: Text(l.appDeletePlaylist),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: AppSpinner()),
        error: (e, _) => ErrorView(
          message: errorText(e),
          onRetry: () => ref.invalidate(playlistItemsProvider(playlist.id)),
        ),
        data: (items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.playlist_add_rounded,
              title: l.appEmptyPlaylist,
              message: l.appEmptyPlaylistMessage,
            );
          }
          // One key per row. Jellyfin gives the same entry id to an item
          // that's in the playlist twice, and two rows with one key left one
          // of them blank: a repeat gets its count added.
          final seen = <String, int>{};
          final rowKeys = [
            for (final i in items)
              () {
                final id = i.playlistItemId ?? i.id;
                final n = seen.update(id, (v) => v + 1, ifAbsent: () => 0);
                return n == 0 ? id : '$id#$n';
              }(),
          ];
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Row(
                  children: [
                    _PlayStop(
                      child: HoverPillButton(
                        icon: Icons.play_arrow_rounded,
                        label: l.commonPlay,
                        primary: true,
                        showLabel: true,
                        // On a TV the remote lands on Play.
                        autofocus: isTvDevice,
                        onTap: () => _playAll(context, ref, items),
                      ),
                    ),
                    const SizedBox(width: 10),
                    HoverPillButton(
                      icon: Icons.shuffle_rounded,
                      label: l.browseShuffle,
                      onTap: () =>
                          _playAll(context, ref, items, shuffle: true),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      l.appItemsCount(items.length),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  buildDefaultDragHandles: false,
                  itemCount: items.length,
                  // ignore: deprecated_member_use
                  onReorder: (oldIndex, newIndex) =>
                      _reorder(context, ref, items, oldIndex, newIndex),
                  itemBuilder: (context, i) {
                    final item = items[i];
                    return dragAnywhere(
                      key: ValueKey(rowKeys[i]),
                      index: i,
                      child: _UpToPlay(
                      first: i == 0,
                      child: ListTile(
                      leading: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.drag_indicator,
                              color: dragGripColor(context)),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 56,
                            height: 40,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: MediaImage(item: item, landscape: true),
                            ),
                          ),
                        ],
                      ),
                      title: Text(item.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: item.isEpisode
                          ? Text(item.seriesName ?? '',
                              maxLines: 1, overflow: TextOverflow.ellipsis)
                          : (item.artistLine != null
                              ? Text(item.artistLine!,
                                  maxLines: 1, overflow: TextOverflow.ellipsis)
                              : null),
                      // On a TV the row is one stop, and RIGHT steps onto
                      // its buttons.
                      trailing: TvRowActions(child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // A remote can't drag: Move Up and Move Down on a TV.
                          TvMoveButtons(
                            index: i,
                            count: items.length,
                            // _reorder takes a drag's "drop before" index.
                            onMove: (from, to) => _reorder(context, ref, items,
                                from, to > from ? to + 1 : to),
                          ),
                          IconButton(
                            icon: const Icon(
                                Icons.remove_circle_outline_rounded),
                            tooltip: l.commonRemove,
                            onPressed: () =>
                                _removeEntry(context, ref, items, i),
                          ),
                        ],
                      )),
                      onTap: () => _openItem(context, ref, items, i),
                    ),
                    ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Marks Play, so the first row can send the remote to it.
class _PlayStop extends StatelessWidget {
  const _PlayStop({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// On a TV, UP from the first row goes to Play. The rows span the page, so
/// "the nearest thing above" was Shuffle, a little closer to the middle than
/// Play at the left edge, and Play is where the page opened.
class _UpToPlay extends StatelessWidget {
  const _UpToPlay({required this.first, required this.child});
  final bool first;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isTvDevice || !first) return child;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent ||
            event.logicalKey != LogicalKeyboardKey.arrowUp) {
          return KeyEventResult.ignored;
        }
        for (final n in node.nearestScope?.traversalDescendants ??
            const <FocusNode>[]) {
          if (n.canRequestFocus &&
              n.context?.findAncestorWidgetOfExactType<_PlayStop>() != null) {
            n.requestFocus();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}
