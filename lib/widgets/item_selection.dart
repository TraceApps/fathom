import 'pick_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import '../state/library_providers.dart';
import '../api/jellyfin_client.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import 'add_to_playlist.dart';
import 'app_snack.dart';
import 'ui_common.dart';

/// Which items a grid currently has selected.
///
/// Selection is a mode the grid enters (from a card's own menu, the same way
/// YouTube Downloads does it) rather than a standing affordance, so an ordinary
/// tap keeps opening a title. The chosen items are held whole, not just their
/// ids, because the bulk actions need names for their messages and types to
/// decide what can be deleted.
class ItemSelection extends ChangeNotifier {
  final _items = <String, BaseItemDto>{};

  bool _active = false;
  bool get active => _active;

  Iterable<BaseItemDto> get items => _items.values;
  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;
  bool contains(String id) => _items.containsKey(id);

  void start([BaseItemDto? first]) {
    _active = true;
    if (first != null) _items[first.id] = first;
    notifyListeners();
  }

  void stop() {
    _active = false;
    _items.clear();
    notifyListeners();
  }

  void toggle(BaseItemDto item) {
    if (_items.remove(item.id) == null) _items[item.id] = item;
    notifyListeners();
  }

  void selectAll(Iterable<BaseItemDto> all) {
    for (final i in all) {
      _items[i.id] = i;
    }
    notifyListeners();
  }
}

/// The bar shown above a grid while it's selecting: how many, select-all, and
/// the actions that can run over the whole set.
class SelectionBar extends ConsumerStatefulWidget {
  const SelectionBar({
    super.key,
    required this.selection,
    required this.all,
    this.canDelete = false,
    this.onChanged,
  });

  final ItemSelection selection;

  /// Everything currently on screen, for Select All.
  final List<BaseItemDto> all;

  /// Whether the account may delete media on the server.
  final bool canDelete;

  /// Refreshes whatever the host grid reads from, after a bulk action. Home
  /// rows and item details are invalidated here, but the grid's own source
  /// varies (a paged local list in the library, a different provider per
  /// screen elsewhere), and without this a deleted title stays on screen.
  final VoidCallback? onChanged;

  @override
  ConsumerState<SelectionBar> createState() => _SelectionBarState();
}

class _SelectionBarState extends ConsumerState<SelectionBar> {
  bool _busy = false;

  /// Runs [each] over every selected item and reports once at the end, rather
  /// than a message per item: fifty snackbars for a fifty-item selection is
  /// worse than none.
  Future<void> _bulk(
    Future<void> Function(BaseItemDto item) each,
    String Function(int n) done,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final chosen = widget.selection.items.toList();
    setState(() => _busy = true);
    var ok = 0;
    Object? failure;
    for (final item in chosen) {
      try {
        await each(item);
        ok++;
      } catch (e) {
        failure ??= e;
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    widget.selection.stop();
    final container = ProviderScope.containerOf(context, listen: false);
    container.invalidate(resumeItemsProvider);
    container.invalidate(latestItemsProvider);
    container.invalidate(favoriteItemsProvider);
    container.invalidate(nextUpItemsProvider);
    for (final item in chosen) {
      container.invalidate(itemDetailProvider(item.id));
    }
    widget.onChanged?.call();
    if (failure != null && ok == 0) {
      showErrorOn(messenger, failure);
    } else {
      showSnackOn(messenger, done(ok), kind: SnackKind.success);
    }
  }

  Future<void> _setPlayed(bool played) async {
    final l = AppLocalizations.of(context);
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final client = ref.read(jellyfinClientProvider);
    await _bulk(
      (item) => client.setPlayed(
        baseUrl: s.baseUrl,
        userId: s.userId,
        token: s.accessToken,
        itemId: item.id,
        played: played,
      ),
      (n) => played ? l.selectionMarkedWatched(n) : l.selectionMarkedUnwatched(n),
    );
  }

  Future<void> _setFavorite(bool favorite) async {
    final l = AppLocalizations.of(context);
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final client = ref.read(jellyfinClientProvider);
    await _bulk(
      (item) => client.setFavorite(
        baseUrl: s.baseUrl,
        userId: s.userId,
        token: s.accessToken,
        itemId: item.id,
        favorite: favorite,
      ),
      (n) => favorite ? l.selectionFavorited(n) : l.selectionUnfavorited(n),
    );
  }

  void _addToPlaylist() {
    final l = AppLocalizations.of(context);
    final ids = [for (final i in widget.selection.items) i.id];
    final label = l.selectionCount(ids.length);
    widget.selection.stop();
    showAddToPlaylistSheet(context, ref, itemIds: ids, label: label);
  }

  Future<void> _delete() async {
    final l = AppLocalizations.of(context);
    final n = widget.selection.length;
    final ok = await confirm(context,
        title: l.selectionDeleteTitle(n),
        message: l.selectionDeleteBody,
        confirmLabel: l.commonDelete,
        destructive: true);
    if (!ok || !mounted) return;
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    final client = ref.read(jellyfinClientProvider);
    await _bulk(
      (item) => client.deleteItem(
        baseUrl: s.baseUrl,
        token: s.accessToken,
        itemId: item.id,
      ),
      l.selectionDeleted,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final sel = widget.selection;
    return PickBar(
      count: sel.length,
      busy: _busy,
      onCancel: sel.stop,
      onSelectAll: () => sel.selectAll(widget.all),
      actions: [
        PickAction(
          Icons.check_circle_outline_rounded,
          l.detailMarkWatched,
          () => _setPlayed(true),
        ),
        PickAction(
          Icons.remove_done_rounded,
          l.detailMarkUnwatched,
          () => _setPlayed(false),
        ),
        PickAction(
          Icons.favorite_border_rounded,
          l.detailAddFavorite,
          () => _setFavorite(true),
        ),
        PickAction(
          Icons.playlist_add_rounded,
          l.detailAddToPlaylist,
          _addToPlaylist,
        ),
        if (widget.canDelete)
          PickAction(
            Icons.delete_outline_rounded,
            l.commonDelete,
            _delete,
            danger: true,
          ),
      ],
    );
  }
}
