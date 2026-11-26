import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/jellyfin_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import '../services/tv_mode.dart';
import '../state/providers.dart';
import '../state/preferences.dart';
import '../state/session_controller.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';
import '../widgets/arr_widgets.dart' show ArrRefreshKeys;
import '../widgets/item_selection.dart';
import '../widgets/list_toolbar.dart';
import '../widgets/search_field.dart';
import '../state/library_providers.dart';
import '../widgets/media_cards.dart';
import '../widgets/media_image.dart';
import '../widgets/motion.dart';
import '../widgets/shimmer.dart';
import '../widgets/tv_focus.dart';
import '../widgets/app_spinner.dart';

/// Full contents of one library, as a paged poster grid with infinite scroll.
class LibraryScreen extends ConsumerStatefulWidget {
  final BaseItemDto library;
  const LibraryScreen({super.key, required this.library});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  static const _pageSize = 100;
  final _scroll = ScrollController();
  final _selection = ItemSelection();
  final _search = TextEditingController();
  Timer? _searchWait;
  String _query = '';

  /// Counts reloads, so a page asked for before one doesn't arrive after it.
  int _load = 0;
  final List<BaseItemDto> _items = [];
  int _total = 0;
  bool _loading = false;
  bool _loadedOnce = false;
  String? _error;
  String _sortBy = 'SortName';
  String _sortOrder = 'Ascending';
  bool _unwatchedOnly = false;
  bool _favoritesOnly = false;
  String? _genre;
  bool _filtersOpen = false;
  List<BaseItemDto> _genres = const [];
  bool _genresLoaded = false;

  int get _activeFilters =>
      (_unwatchedOnly ? 1 : 0) +
      (_favoritesOnly ? 1 : 0) +
      (_genre != null ? 1 : 0);

  bool get _narrowed => _activeFilters > 0 || _query.isNotEmpty;

  void _clearNarrowing() {
    _searchWait?.cancel();
    _search.clear();
    setState(() {
      _query = '';
      _unwatchedOnly = false;
      _favoritesOnly = false;
      _genre = null;
    });
    _reload();
  }

  /// Searches once the typing pauses, not on every letter.
  void _onSearch(String text) {
    _searchWait?.cancel();
    _searchWait = Timer(const Duration(milliseconds: 350), () {
      final q = text.trim();
      if (!mounted || q == _query) return;
      setState(() => _query = q);
      _reload();
    });
  }

  void _reload() {
    _load++;
    if (_selection.active) _selection.stop();
    setState(() {
      _loading = false;
      _items.clear();
      _total = 0;
      _loadedOnce = false;
      _error = null;
    });
    _loadMore();
  }

  String? get _includeTypes {
    switch (widget.library.collectionType) {
      case 'movies':
        return 'Movie';
      case 'tvshows':
        return 'Series';
      case 'music':
        return 'MusicAlbum';
      default:
        return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _selection.addListener(_onSelectionChanged);
    _scroll.addListener(_onScroll);
    _loadMore();
  }

  void _onSelectionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _selection.removeListener(_onSelectionChanged);
    _selection.dispose();
    _searchWait?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 600) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loading) return;
    if (_loadedOnce && _items.length >= _total) return;
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return;

    final load = _load;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ref.read(jellyfinClientProvider).getItems(
            baseUrl: session.baseUrl,
            userId: session.userId,
            token: session.accessToken,
            parentId: widget.library.id,
            includeItemTypes: _includeTypes,
            recursive: _includeTypes != null,
            sortBy: _sortBy,
            sortOrder: _sortOrder,
            filters: _unwatchedOnly ? 'IsUnplayed' : null,
            isFavorite: _favoritesOnly ? true : null,
            genres: _genre,
            searchTerm: _query.isEmpty ? null : _query,
            startIndex: _items.length,
            limit: _pageSize,
          );
      if (!mounted || load != _load) return;
      setState(() {
        _items.addAll(res.items);
        _total = res.totalRecordCount;
        _loadedOnce = true;
      });
    } on JellyfinException catch (e) {
      if (mounted && load == _load) setState(() => _error = e.message);
    } catch (e) {
      if (mounted && load == _load) setState(() => _error = '$e');
    } finally {
      if (mounted && load == _load) setState(() => _loading = false);
    }
  }

  void _toggleFilters() {
    setState(() => _filtersOpen = !_filtersOpen);
    if (_filtersOpen && !_genresLoaded) _loadGenres();
  }

  Future<void> _loadGenres() async {
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return;
    try {
      final g = await ref.read(jellyfinClientProvider).getGenres(
            baseUrl: session.baseUrl,
            userId: session.userId,
            token: session.accessToken,
            parentId: widget.library.id,
          );
      if (mounted) setState(() => _genres = g);
    } catch (_) {
      // Leave genres empty; toggles still work.
    } finally {
      if (mounted) setState(() => _genresLoaded = true);
    }
  }

  /// Inline, collapsible filter panel (rendered in the body — no modal, which
  /// wouldn't display from this screen).
  Widget _filterPanel() {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.4)),
          ),
        ),
        child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune_rounded,
                    size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(l.browseFilter,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant)),
                const Spacer(),
                if (_activeFilters > 0)
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _unwatchedOnly = false;
                        _favoritesOnly = false;
                        _genre = null;
                      });
                      _reload();
                    },
                    icon: const Icon(Icons.clear_rounded, size: 16),
                    label: Text(l.commonClear),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilterChip(
                    label: Text(l.browseUnwatched),
                    selected: _unwatchedOnly,
                    onSelected: (v) {
                      setState(() => _unwatchedOnly = v);
                      _reload();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilterChip(
                    label: Text(l.browseFavorites),
                    selected: _favoritesOnly,
                    onSelected: (v) {
                      setState(() => _favoritesOnly = v);
                      _reload();
                    },
                  ),
                ),
              ],
            ),
            if (!_genresLoaded)
              const Padding(
                padding: EdgeInsets.all(12),
                child: AppSpinner.inline(),
              )
            else if (_genres.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(l.browseGenre,
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(l.browseAll),
                    selected: _genre == null,
                    onSelected: (_) {
                      setState(() => _genre = null);
                      _reload();
                    },
                  ),
                  for (final g in _genres)
                    ChoiceChip(
                      label: Text(g.name),
                      selected: _genre == g.name,
                      onSelected: (_) {
                        setState(() => _genre = g.name);
                        _reload();
                      },
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final listView =
        ref.watch(preferencesProvider).asData?.value.libraryViewMode == 'list';
    final user = ref.watch(currentUserProvider).asData?.value;
    final session = ref.watch(sessionControllerProvider).asData?.value;
    final toolbar = ListToolbar(
      search: SearchField(
        controller: _search,
        hint: l.browseSearchLibrary,
        onChanged: _onSearch,
        onClear: () => _onSearch(''),
      ),
      menus: [
        IconButton(
          tooltip: l.arrFilter,
          isSelected: _filtersOpen,
          icon: ListFilterIcon(active: _activeFilters),
          onPressed: _toggleFilters,
        ),
        SortMenu<String>(
          value: _sortBy,
          options: _browseSortOptions(l),
          descending: _sortOrder == 'Descending',
          startsDescending: (v) => v != 'SortName',
          onChanged: (v, desc) {
            setState(() {
              _sortBy = v;
              _sortOrder = desc ? 'Descending' : 'Ascending';
            });
            _reload();
          },
        ),
      ],
      tools: [
        ListTool(
          listView ? Icons.grid_view_rounded : Icons.view_list_rounded,
          listView ? l.browseGridView : l.browseListView,
          () => ref.read(preferencesProvider.notifier).edit(
            (x) => x.copyWith(libraryViewMode: listView ? 'grid' : 'list'),
          ),
        ),
        // Picking several is a touch and mouse job, not a remote's.
        if (!isTvDevice && _items.isNotEmpty && !_selection.active)
          ListTool(Icons.checklist_rounded, l.arrSelect, _selection.start),
      ],
    );
    final scroll = RefreshIndicator(
      onRefresh: () async => _reload(),
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: toolbar),
          SliverToBoxAdapter(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _filtersOpen
                  ? _filterPanel()
                  : const SizedBox(width: double.infinity),
            ),
          ),
          _body(listView),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.library.name),
        bottom: _total > 0
            ? PreferredSize(
                preferredSize: const Size.fromHeight(20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      l.browseItemsCount(_total),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              )
            : null,
      ),
      // Back ends picking first, as it does in Manage.
      body: PopScope(
        canPop: !_selection.active,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _selection.stop();
        },
        child: ArrRefreshKeys(
          onRefresh: _reload,
          child: Column(
            children: [
              if (_selection.active)
                SelectionBar(
                  selection: _selection,
                  all: _items,
                  onChanged: _reload,
                  canDelete: (user?.enableContentDeletion ?? false) ||
                      (user?.isAdministrator ?? false) ||
                      (session?.canDelete ?? false),
                ),
              Expanded(child: scroll),
            ],
          ),
        ),
      ),
    );
  }

  /// The grid or list under the toolbar, as a sliver.
  Widget _body(bool listView) {
    final l = AppLocalizations.of(context);
    if (!_loadedOnce && _loading) {
      return const SliverFillRemaining(child: PosterGridSkeleton());
    }
    if (_error != null && _items.isEmpty) {
      return SliverFillRemaining(
        child: ErrorView(message: _error!, onRetry: _reload),
      );
    }
    if (_items.isEmpty) {
      // A library with nothing in it and one with nothing that matches are
      // different news: only the first is "empty".
      return SliverFillRemaining(
        child: _narrowed
            ? EmptyState(
                icon: Icons.search_off_rounded,
                title: l.arrNoMatches,
                action: FilledButton.tonal(
                  onPressed: _clearNarrowing,
                  child: Text(l.browseClearFilters),
                ),
              )
            : EmptyState(
                icon: Icons.inbox_rounded,
                title: l.browseLibraryEmpty,
              ),
      );
    }
    bool? picked(BaseItemDto item) =>
        _selection.active ? _selection.contains(item.id) : null;
    void open(BaseItemDto item) => _selection.active
        ? _selection.toggle(item)
        : context.push('/item', extra: item);
    VoidCallback? pick(BaseItemDto item) =>
        isTvDevice ? null : () => _selection.start(item);
    if (listView) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        sliver: SliverList.separated(
          itemCount: _items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) => EntranceFade(
            index: i,
            onceKey: _items[i].id,
            child: _LibraryListRow(
              item: _items[i],
              autofocus: isTvDevice && i == 0,
              selected: picked(_items[i]),
              onSelect: pick(_items[i]),
              onTap: () => open(_items[i]),
            ),
          ),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 184,
          mainAxisSpacing: 18,
          crossAxisSpacing: 14,
          childAspectRatio: 0.54,
        ),
        itemCount: _items.length,
        itemBuilder: (context, i) => EntranceFade(
          index: i,
          onceKey: _items[i].id,
          child: PosterTile(
            item: _items[i],
            // On TV the first tile grabs focus so the remote lands on
            // content, not the toolbar above it.
            autofocus: isTvDevice && i == 0,
            selected: picked(_items[i]),
            onSelect: pick(_items[i]),
            onTap: () => open(_items[i]),
          ),
        ),
      ),
    );
  }
}

/// A compact library row for list view: small poster, title, meta, and a
/// watched tick.
class _LibraryListRow extends StatelessWidget {
  final BaseItemDto item;
  final VoidCallback onTap;
  final bool autofocus;

  /// Whether it's picked, while picking; null otherwise.
  final bool? selected;

  /// Starts picking with this row (a long press).
  final VoidCallback? onSelect;
  const _LibraryListRow({
    required this.item,
    required this.onTap,
    this.autofocus = false,
    this.selected,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = [
      if (item.productionYear != null) '${item.productionYear}',
      if (item.officialRating != null) item.officialRating!,
    ].join('  ·  ');
    final watched = item.userData.played;
    return TvFocusRing(
      borderRadius: BorderRadius.circular(10),
      child: HoverHighlight(
      child: ListTile(
        autofocus: autofocus,
        // HoverHighlight provides the hover tint; suppress ListTile's own so
        // they don't stack.
        hoverColor: Colors.transparent,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child:
              SizedBox(width: 46, height: 69, child: MediaImage(item: item)),
        ),
        title: Text(item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: meta.isEmpty
            ? null
            : Text(meta,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        trailing: selected != null
            ? Icon(
                selected!
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected!
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              )
            : watched
            ? Icon(Icons.check_circle,
                size: 18, color: theme.colorScheme.primary)
            : null,
        selected: selected ?? false,
        onTap: onTap,
        onLongPress: selected == null ? onSelect : null,
      ),
    ),
    );
  }
}

/// Library sort options as a map of Jellyfin sort key -> localized label.
/// A function (not a const map) so the labels can be localized.
Map<String, String> _browseSortOptions(AppLocalizations l) => {
      'SortName': l.browseSortName,
      'DateCreated': l.browseSortDateAdded,
      'PremiereDate': l.browseSortReleaseDate,
      'CommunityRating': l.browseSortRating,
      'Random': l.browseSortRandom,
    };
