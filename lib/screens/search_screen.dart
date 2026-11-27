import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/jellyfin_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../state/seerr_providers.dart';
import '../routing/app_shell.dart';
import '../models/base_item.dart';
import '../state/library_providers.dart';
import '../state/preferences.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';
import '../widgets/media_cards.dart';
import '../widgets/search_field.dart';
import '../widgets/motion.dart';
import '../widgets/shimmer.dart';

/// Global search across the server. Debounced query, results as a poster grid.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  // The include-item-types query for each filter id (not user-facing).
  static const _filterTypes = <String, String>{
    'all': 'Movie,Series,Episode,BoxSet,MusicAlbum,MusicArtist',
    'movies': 'Movie',
    'shows': 'Series',
    'episodes': 'Episode',
    'music': 'MusicAlbum,MusicArtist',
  };

  // The filter chips as (id, localized label). A function so labels localize.
  List<(String, String)> _filterOptions(AppLocalizations l) => [
        ('all', l.browseAll),
        ('movies', l.browseMovies),
        ('shows', l.browseShows),
        ('episodes', l.browseEpisodes),
        ('music', l.browseMusic),
      ];
  String _filter = 'all';
  final _controller = TextEditingController();
  Timer? _debounce;
  List<BaseItemDto> _results = const [];
  bool _loading = false;
  bool _searched = false;
  String? _error;
  int _requestId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value));
  }

  Future<void> _search(String term) async {
    final query = term.trim();
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _searched = false;
        _error = null;
      });
      return;
    }
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return;

    final reqId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ref.read(jellyfinClientProvider).getItems(
            baseUrl: session.baseUrl,
            userId: session.userId,
            token: session.accessToken,
            searchTerm: query,
            includeItemTypes: _filterTypes[_filter],
            recursive: true,
            limit: 60,
          );
      if (!mounted || reqId != _requestId) return; // stale response
      setState(() {
        _results = res.items;
        _searched = true;
      });
    } on JellyfinException catch (e) {
      if (mounted && reqId == _requestId) setState(() => _error = e.message);
    } finally {
      if (mounted && reqId == _requestId) setState(() => _loading = false);
    }
  }

  void _saveRecent(String q) {
    final term = q.trim();
    if (term.length < 2) return;
    final cur =
        ref.read(preferencesProvider).asData?.value.recentSearches ?? const [];
    final next = [
      term,
      ...cur.where((e) => e.toLowerCase() != term.toLowerCase()),
    ].take(10).toList();
    ref.read(preferencesProvider.notifier)
        .edit((x) => x.copyWith(recentSearches: next));
  }

  void _runRecent(String term) {
    _controller.text = term;
    _saveRecent(term);
    _search(term);
  }

  /// Opens a result. The search box gives up focus first: it would take it
  /// back on the way back, and bring the keyboard up over the results every
  /// time.
  void _open(BaseItemDto item) {
    FocusManager.instance.primaryFocus?.unfocus();
    context.push('/item', extra: item);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: mobileDrawerLeading(context),
        title: SearchField(
          controller: _controller,
          autofocus: true,
          hint: l.browseSearchHint,
          onChanged: _onChanged,
          onSubmitted: (v) => _saveRecent(v),
          onClear: () => _search(''),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              children: [
                for (final (id, label) in _filterOptions(l))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _filter == id,
                      onSelected: (_) {
                        setState(() => _filter = id);
                        _search(_controller.text);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: _body(),
    );
  }

  Widget _idleLanding() {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final recent =
        ref.watch(preferencesProvider).asData?.value.recentSearches ??
            const <String>[];
    final latest =
        ref.watch(latestItemsProvider).asData?.value ?? const <BaseItemDto>[];
    if (recent.isEmpty && latest.isEmpty) {
      return EmptyState(
        icon: Icons.search_rounded,
        title: l.browseSearchLibraryTitle,
        message: l.browseSearchLibraryMessage,
      );
    }
    final controller = ref.read(preferencesProvider.notifier);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (recent.isNotEmpty) ...[
          Row(
            children: [
              Text(l.browseRecentSearches,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton(
                onPressed: () => controller
                    .edit((x) => x.copyWith(recentSearches: const [])),
                child: Text(l.commonClear),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in recent)
                InputChip(
                  label: Text(r),
                  avatar: const Icon(Icons.history_rounded, size: 18),
                  onPressed: () => _runRecent(r),
                  onDeleted: () => controller.edit((x) => x.copyWith(
                      recentSearches:
                          recent.where((e) => e != r).toList())),
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],
        if (latest.isNotEmpty) ...[
          Text(l.browseSuggested,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          GridView.builder(
            clipBehavior: Clip.none,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 184,
              mainAxisSpacing: 18,
              crossAxisSpacing: 14,
              childAspectRatio: 0.54,
            ),
            itemCount: latest.length > 12 ? 12 : latest.length,
            itemBuilder: (context, i) => PosterTile(
              item: latest[i],
              onTap: () => _open(latest[i]),
            ),
          ),
        ],
      ],
    );
  }

  Widget _body() {
    final l = AppLocalizations.of(context);
    if (_loading && _results.isEmpty) {
      return const PosterGridSkeleton();
    }
    if (_error != null) {
      return ErrorView(
          message: _error!, onRetry: () => _search(_controller.text));
    }
    if (!_searched) {
      return _idleLanding();
    }
    if (_results.isEmpty) {
      // Not on the server: with Seerr connected, Discover can find it to ask
      // for (movies and shows; Seerr has no music or single episodes).
      final term = _controller.text.trim();
      final discover = ref.watch(seerrConfiguredProvider) &&
          term.isNotEmpty &&
          const {'all', 'movies', 'shows'}.contains(_filter);
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: l.browseNoResults,
        message: discover
            ? l.browseNotOnServer(term)
            : l.browseTryDifferentSearch,
        action: discover
            ? FilledButton.icon(
                onPressed: () {
                  ref.read(seerrQueryProvider.notifier).set(term);
                  context.push('/discover?tab=search');
                },
                icon: const Icon(Icons.travel_explore_rounded),
                label: Text(l.browseSearchInDiscover),
              )
            : null,
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 184,
        mainAxisSpacing: 18,
        crossAxisSpacing: 14,
        childAspectRatio: 0.54,
      ),
      itemCount: _results.length,
      itemBuilder: (context, i) => EntranceFade(
        index: i,
        onceKey: _results[i].id,
        child: PosterTile(
          item: _results[i],
          onTap: () => _open(_results[i]),
        ),
      ),
    );
  }
}

