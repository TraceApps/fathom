import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsService;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import '../services/diagnostics.dart';
import '../services/tv_mode.dart';
import '../state/preferences.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import '../state/syncplay.dart';
import '../state/watchlist.dart';
import '../api/error_text.dart';
import '../widgets/error_view.dart';
import '../widgets/checked_menu_item.dart';
import '../widgets/watchlist_toggle.dart';
import '../state/library_providers.dart';
import '../widgets/clapper_icon.dart';
import '../widgets/hover_pill_button.dart';
import '../widgets/media_image.dart';
import '../widgets/meta_pill.dart';
import '../widgets/spin_wheel.dart';
import '../widgets/tv_focus.dart';
import '../widgets/tv_keyboard.dart';
import '../widgets/app_spinner.dart';
import '../api/jellyfin_client.dart';

/// "Can't decide what to watch?" wheel. Candidates come from the Watchlist
/// plus anything added from the library, narrowed by optional filters. Three
/// ways to play: knock titles out one spin at a time until one is left, let
/// a single spin decide, or first to two landings. Single-device by design:
/// whoever holds the phone or remote spins while the room watches. In a
/// Watch Together group, playing the result starts it for everyone.
class MovieWheelScreen extends ConsumerStatefulWidget {
  const MovieWheelScreen({super.key});

  @override
  ConsumerState<MovieWheelScreen> createState() => _MovieWheelScreenState();
}

enum _Phase { setup, spinning, winner }

enum _Mode {
  last('last'),
  single('single'),
  best3('best3');

  const _Mode(this.key);
  final String key;

  static _Mode fromKey(String k) =>
      values.firstWhere((m) => m.key == k, orElse: () => last);
}

enum _OverlayKind { out, scored }

class _Overlay {
  const _Overlay(this.item, this.kind);
  final BaseItemDto item;
  final _OverlayKind kind;
}

/// One reversible step, so Undo can walk the game back.
sealed class _Action {
  const _Action();
}

class _Eliminated extends _Action {
  const _Eliminated(this.item);
  final BaseItemDto item;
}

class _Scored extends _Action {
  const _Scored(this.id);
  final String id;
}

class _Narrowed extends _Action {
  const _Narrowed(this.previousPool);
  final List<BaseItemDto> previousPool;
}

class _MovieWheelScreenState extends ConsumerState<MovieWheelScreen> {
  _Phase _phase = _Phase.setup;
  final _wheelKey = GlobalKey<SpinWheelState>();
  bool _wheelFocused = false; // TV: the remote is on the wheel

  // Setup.
  bool _prefsLoaded = false;
  _Mode _mode = _Mode.last;
  Set<String> _deselected = {};
  // Library titles added on top of the Watchlist, in the order added.
  final Map<String, BaseItemDto> _extras = {};
  // Richer copies (genres, watched state, synopsis) fetched once per title.
  final Map<String, BaseItemDto> _details = {};
  final Set<String> _detailsRequested = {};
  bool _unwatchedOnly = false;
  bool _under2h = false;
  String? _genre;
  final _searchCtl = TextEditingController();
  Timer? _searchDebounce;
  String _lastQuery = '';
  List<BaseItemDto> _results = [];
  bool _searching = false;

  // Game.
  List<BaseItemDto> _pool = [];
  List<String> _order = [];
  final List<_Action> _history = [];
  final Map<String, int> _tally = {};
  int _spins = 0;
  bool _tiebreak = false;
  _Overlay? _overlay;
  BaseItemDto? _winner;
  bool _awaitingWinner = false;

  final _audio = _WheelAudio();

  @override
  void initState() {
    super.initState();
    _searchCtl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtl.dispose();
    _audio.dispose();
    super.dispose();
  }

  BaseItemDto _best(BaseItemDto i) => _details[i.id] ?? i;

  void _loadPrefs(Prefs p) {
    if (_prefsLoaded) return;
    _prefsLoaded = true;
    _mode = _Mode.fromKey(p.movieWheelMode);
    _deselected = p.movieWheelDeselected.toSet();
    if (p.movieWheelExtras.isNotEmpty) {
      unawaited(_fetchDetails(p.movieWheelExtras, asExtras: true));
    }
  }

  void _savePrefs(List<BaseItemDto> candidates) {
    final ids = {for (final c in candidates) c.id};
    ref.read(preferencesProvider.notifier).edit((x) => x.copyWith(
          movieWheelMode: _mode.key,
          // Drop titles that are no longer candidates so this never grows
          // without bound.
          movieWheelDeselected: [
            for (final id in _deselected)
              if (ids.contains(id)) id,
          ],
          movieWheelExtras: _extras.keys.toList(),
        ));
  }

  void _ensureDetails(List<BaseItemDto> items) {
    final missing = [
      for (final i in items)
        if (!_detailsRequested.contains(i.id)) i.id,
    ];
    if (missing.isEmpty) return;
    _detailsRequested.addAll(missing);
    Future.microtask(() => _fetchDetails(missing));
  }

  Future<void> _fetchDetails(List<String> ids, {bool asExtras = false}) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    _detailsRequested.addAll(ids);
    try {
      final got = await ref.read(jellyfinClientProvider).getItemsByIds(
            baseUrl: s.baseUrl,
            userId: s.userId,
            token: s.accessToken,
            ids: ids,
          );
      if (!mounted) return;
      setState(() {
        for (final i in got) {
          _details[i.id] = i;
          if (asExtras) _extras[i.id] = i;
        }
      });
    } catch (e) {
      // Filters just work with what the list already has; retry next time.
      _detailsRequested.removeAll(ids);
      Diagnostics.instance.add('wheel', 'details fetch failed: $e');
    }
  }

  List<BaseItemDto> _candidates(List<BaseItemDto> watchlist) {
    final seen = <String>{};
    return [
      for (final i in [..._extras.values, ...watchlist])
        if (seen.add(i.id)) _best(i),
    ];
  }

  bool _passes(BaseItemDto i) {
    if (_unwatchedOnly && i.userData.played) return false;
    if (_under2h) {
      final m = i.runtimeMinutes;
      if (m != null && m > 120) return false;
    }
    if (_genre != null && !i.genres.contains(_genre)) return false;
    return true;
  }

  // ---- Library search ----

  void _onSearchChanged() {
    final q = _searchCtl.text.trim();
    if (q == _lastQuery) return;
    _lastQuery = q;
    _searchDebounce?.cancel();
    if (q.length < 2) {
      setState(() {
        _results = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _searchDebounce =
        Timer(const Duration(milliseconds: 350), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    final s = ref.read(sessionControllerProvider).asData?.value;
    if (s == null) return;
    try {
      final r = await ref.read(jellyfinClientProvider).getItems(
            baseUrl: s.baseUrl,
            userId: s.userId,
            token: s.accessToken,
            searchTerm: q,
            includeItemTypes: 'Movie,Series',
            recursive: true,
            limit: 12,
          );
      if (!mounted || q != _lastQuery) return;
      setState(() {
        _results = r.items;
        _searching = false;
      });
    } catch (_) {
      if (!mounted || q != _lastQuery) return;
      setState(() {
        _results = [];
        _searching = false;
      });
    }
  }

  void _addExtra(BaseItemDto item, List<BaseItemDto> watchlist) {
    setState(() {
      _extras[item.id] = item;
      _deselected.remove(item.id);
      _searchCtl.clear();
      _results = [];
    });
    _ensureDetails([item]);
    _savePrefs(_candidates(watchlist));
  }

  void _removeExtra(String id, List<BaseItemDto> watchlist) {
    setState(() => _extras.remove(id));
    _savePrefs(_candidates(watchlist));
  }

  // ---- Game flow ----

  void _start(List<BaseItemDto> picks) {
    setState(() {
      _pool = List.of(picks)..shuffle();
      _order = [for (final i in _pool) i.id];
      _history.clear();
      _tally.clear();
      _spins = 0;
      _tiebreak = false;
      _overlay = null;
      _winner = null;
      _awaitingWinner = false;
      _phase = _Phase.spinning;
    });
    unawaited(_audio.prepareTick());
  }

  /// Reads a result out for screen-reader users (the overlay and the wheel
  /// are visual only).
  void _announce(String message) {
    if (!mounted) return;
    SemanticsService.sendAnnouncement(
        View.of(context), message, Directionality.of(context));
  }

  void _onLanded(int index) {
    final item = _pool[index];
    final l = AppLocalizations.of(context);
    switch (_mode) {
      case _Mode.last:
        setState(() => _overlay = _Overlay(item, _OverlayKind.out));
        _announce(l.wheelEliminated(item.name));
      case _Mode.single:
        _crown(item);
      case _Mode.best3:
        if (_tiebreak) {
          _crown(item);
          return;
        }
        _history.add(_Scored(item.id));
        setState(() {
          _tally[item.id] = (_tally[item.id] ?? 0) + 1;
          _spins++;
          _overlay = _Overlay(item, _OverlayKind.scored);
        });
        _announce(l.wheelScored(item.name));
    }
  }

  void _dismissOverlay() {
    final o = _overlay;
    if (o == null) return;
    setState(() => _overlay = null);
    switch (_mode) {
      case _Mode.last:
        _history.add(_Eliminated(o.item));
        setState(() {
          _pool = [
            for (final i in _pool)
              if (i.id != o.item.id) i,
          ];
          if (_pool.length == 1) {
            _winner = _pool.first;
            _awaitingWinner = true;
          }
        });
      case _Mode.best3:
        if ((_tally[o.item.id] ?? 0) >= 2) {
          _crown(o.item);
        } else if (_spins >= 3) {
          // Three spins, three different titles: a final spin between them.
          final landed = _tally.keys.toSet();
          _history.add(_Narrowed(_pool));
          setState(() {
            _tiebreak = true;
            _pool = [
              for (final i in _pool)
                if (landed.contains(i.id)) i,
            ];
          });
        }
      case _Mode.single:
        break;
    }
  }

  /// The wheel shrinks every other wedge away so the pick fills it, then
  /// [_onSettled] reveals the result.
  void _crown(BaseItemDto item) {
    setState(() {
      _winner = item;
      _awaitingWinner = true;
      _pool = [item];
    });
  }

  void _onSettled() {
    if (!_awaitingWinner || _pool.length != 1) return;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    Future.delayed(Duration(milliseconds: reduce ? 150 : 700), () {
      if (!mounted || !_awaitingWinner) return;
      setState(() {
        _awaitingWinner = false;
        _phase = _Phase.winner;
      });
      unawaited(_audio.winner());
      final w = _winner ?? _pool.first;
      _announce(AppLocalizations.of(context).a11yWinner(w.name));
    });
  }

  bool get _canUndo =>
      _history.isNotEmpty && _overlay == null && !_awaitingWinner;

  void _undo() {
    if (!_canUndo || (_wheelKey.currentState?.isBusy ?? false)) return;
    final a = _history.removeLast();
    setState(() {
      switch (a) {
        case _Eliminated(:final item):
          final keep = {for (final i in _pool) i.id, item.id};
          final byId = {for (final i in _pool) i.id: i, item.id: item};
          _pool = [
            for (final id in _order)
              if (keep.contains(id)) byId[id]!,
          ];
        case _Scored(:final id):
          final n = (_tally[id] ?? 1) - 1;
          if (n <= 0) {
            _tally.remove(id);
          } else {
            _tally[id] = n;
          }
          _spins--;
        case _Narrowed(:final previousPool):
          _pool = previousPool;
          _tiebreak = false;
      }
    });
  }

  void _restart() {
    setState(() {
      _phase = _Phase.setup;
      _pool = [];
      _overlay = null;
      _winner = null;
      _awaitingWinner = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final prefs = ref.watch(preferencesProvider).asData?.value;
    if (prefs != null) _loadPrefs(prefs);
    final sound = prefs?.movieWheelSound ?? true;
    _audio.muted = !sound;
    final watchlistAsync = ref.watch(watchlistProvider);
    final watchlist = watchlistAsync.value ?? const <BaseItemDto>[];
    final candidates = _candidates(watchlist);
    _ensureDetails(candidates);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.wheelTitle),
        actions: [
          IconButton(
            tooltip: sound ? l.wheelMute : l.wheelUnmute,
            icon: Icon(
                sound ? Icons.volume_up_rounded : Icons.volume_off_rounded),
            onPressed: () => ref
                .read(preferencesProvider.notifier)
                .edit((x) => x.copyWith(movieWheelSound: !sound)),
          ),
        ],
      ),
      body: switch (_phase) {
        // Until the Watchlist has loaded, an empty list would wrongly say
        // there's nothing on it; when it can't load, say why and offer Retry.
        _Phase.setup when !watchlistAsync.hasValue => watchlistAsync.hasError
            ? ErrorView(
                message: errorText(watchlistAsync.error!),
                onRetry: () => ref.invalidate(watchlistProvider),
              )
            : const Center(child: AppSpinner()),
        _Phase.setup => _buildSetup(context, candidates, watchlist),
        _Phase.spinning => _buildSpin(context, sound),
        _Phase.winner => _WinnerView(
            winner: _best(_winner ?? _pool.first),
            onRestart: _restart,
          ),
      },
    );
  }

  // ---- Setup screen ----

  Widget _buildSetup(BuildContext context, List<BaseItemDto> candidates,
      List<BaseItemDto> watchlist) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final eligible = candidates.where(_passes).toList();
    final picks =
        eligible.where((i) => !_deselected.contains(i.id)).toList();
    final genres = {
      for (final c in candidates) ...c.genres,
    }.toList()
      ..sort();
    final candidateIds = {for (final c in candidates) c.id};
    final modeHint = switch (_mode) {
      _Mode.last => l.wheelModeLastHint,
      _Mode.single => l.wheelModeSingleHint,
      _Mode.best3 => l.wheelModeBest3Hint,
    };

    final header = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: TvTextField(
          controller: _searchCtl,
          label: l.wheelSearchLabel,
          hint: l.wheelSearchHint,
          icon: Icons.search_rounded,
        ),
      ),
      if (_searching)
        const Padding(
          padding: EdgeInsets.all(12),
          child: Center(
              child: AppSpinner.inline()),
        )
      else if (_lastQuery.length >= 2 && _results.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Text(l.wheelNoResults, style: TextStyle(color: muted)),
        )
      else
        for (final r in _results)
          ListTile(
            leading: _Thumb(item: r),
            title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: r.productionYear != null
                ? Text('${r.productionYear}')
                : null,
            trailing: Icon(
              candidateIds.contains(r.id)
                  ? Icons.check_circle_rounded
                  : Icons.add_circle_outline_rounded,
              color: theme.colorScheme.primary,
            ),
            onTap: candidateIds.contains(r.id)
                ? null
                : () => _addExtra(r, watchlist),
          ),
      // Single scrolling rows rather than wrapping ones, so the controls
      // stay a compact band on a phone and the list keeps the space.
      _ChipRow(children: [
        for (final m in _Mode.values)
          ChoiceChip(
            label: Text(switch (m) {
              _Mode.last => l.wheelModeLast,
              _Mode.single => l.wheelModeSingle,
              _Mode.best3 => l.wheelModeBest3,
            }),
            selected: _mode == m,
            onSelected: (_) {
              setState(() => _mode = m);
              _savePrefs(candidates);
            },
          ),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Text(modeHint,
            style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
      ),
      _ChipRow(children: [
        FilterChip(
          label: Text(l.wheelFilterUnwatched),
          selected: _unwatchedOnly,
          onSelected: (v) => setState(() => _unwatchedOnly = v),
        ),
        FilterChip(
          label: Text(l.wheelFilterUnder2h),
          selected: _under2h,
          onSelected: (v) => setState(() => _under2h = v),
        ),
        if (genres.isNotEmpty)
          PopupMenuButton<String>(
            tooltip: l.wheelFilterGenre,
            onSelected: (g) => setState(() => _genre = g.isEmpty ? null : g),
            itemBuilder: (_) => [
              CheckedMenuItem(
                value: '',
                checked: _genre == null,
                child: Text(l.wheelFilterAllGenres),
              ),
              for (final g in genres)
                CheckedMenuItem(value: g, checked: _genre == g, child: Text(g)),
            ],
            child: Chip(
              avatar: const Icon(Icons.theater_comedy_rounded, size: 18),
              label: Text(_genre ?? l.wheelFilterGenre),
              backgroundColor:
                  _genre != null ? theme.colorScheme.secondaryContainer : null,
            ),
          ),
        ActionChip(
          avatar: const Icon(Icons.done_all_rounded, size: 18),
          label: Text(l.wheelSelectAll),
          onPressed: () {
            setState(() => _deselected.removeAll(eligible.map((e) => e.id)));
            _savePrefs(candidates);
          },
        ),
        ActionChip(
          avatar: const Icon(Icons.remove_done_rounded, size: 18),
          label: Text(l.wheelSelectNone),
          onPressed: () {
            setState(() => _deselected.addAll(eligible.map((e) => e.id)));
            _savePrefs(candidates);
          },
        ),
      ]),
    ];

    final emptyMessage = candidates.isEmpty
        ? l.wheelNeedsWatchlist
        : eligible.isEmpty
            ? l.wheelNothingMatches
            : null;

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 8),
            itemCount: header.length + (emptyMessage != null ? 1 : eligible.length),
            itemBuilder: (context, i) {
              if (i < header.length) return header[i];
              if (emptyMessage != null) {
                return Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(emptyMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted)),
                );
              }
              final item = eligible[i - header.length];
              return _CandidateTile(
                item: item,
                autofocus: isTvDevice && i == header.length,
                selected: !_deselected.contains(item.id),
                added: _extras.containsKey(item.id),
                onToggle: () {
                  setState(() {
                    _deselected.contains(item.id)
                        ? _deselected.remove(item.id)
                        : _deselected.add(item.id);
                  });
                  _savePrefs(candidates);
                },
                onRemove: () => _removeExtra(item.id, watchlist),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: ClapOnHover(
              child: FilledButton.icon(
                onPressed: picks.length >= 2 ? () => _start(picks) : null,
                icon: const ClapperIcon(),
                label: Text(picks.length >= 2
                    ? l.wheelStartWith(picks.length)
                    : l.wheelNeedTwo),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---- Spin screen ----

  Widget _buildSpin(BuildContext context, bool sound) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final header = switch (_mode) {
      _Mode.last => l.wheelRemaining(_pool.length),
      _Mode.single => l.wheelSingleHeader,
      _Mode.best3 => _tiebreak
          ? l.wheelTiebreak
          : l.wheelSpinOf(math.min(_spins + 1, 3), 3),
    };
    final eliminated = [
      for (final a in _history)
        if (a is _Eliminated) a.item,
    ];
    final scored = _mode == _Mode.best3
        ? [
            for (final i in _order)
              if ((_tally[i] ?? 0) > 0) i,
          ]
        : const <String>[];
    final byId = {for (final e in eliminated) e.id: e};
    for (final i in _pool) {
      byId[i.id] = i;
    }
    final hasStrip = eliminated.isNotEmpty || scored.isNotEmpty;

    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                header,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: Center(
                child: LayoutBuilder(builder: (context, c) {
                  // Fit the space actually there, pointer (24px above the
                  // wheel) included. A fixed 220px minimum overflowed a
                  // phone held sideways, silently cropping the wheel's
                  // bottom.
                  final size = math.min(c.maxWidth - 32, c.maxHeight - 24 - 12);
                  final wheel = SpinWheel(
                    key: _wheelKey,
                    items: _pool,
                    size: size.clamp(120.0, 820.0),
                    marks: _tally,
                    onTick: _audio.tick,
                    onLanded: _onLanded,
                    onSettled: _onSettled,
                    focused: _wheelFocused,
                  );
                  // The wheel's own tap-to-spin is a bare GestureDetector
                  // with no focus node, so a remote can't reach it without
                  // this wrap. TvFocusable is a no-op off TV. The wheel draws
                  // its own round focus ring, and doesn't grow on focus since
                  // it's already sized to fill the space.
                  return TvFocusable(
                    autofocus: isTvDevice,
                    showRing: false,
                    scale: 1.0,
                    onFocusChange: (v) => setState(() => _wheelFocused = v),
                    onTap: () => _wheelKey.currentState?.spin(),
                    child: wheel,
                  );
                }),
              ),
            ),
            if (hasStrip)
              SizedBox(
                height: 72,
                child: Row(
                  children: [
                    Expanded(
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          for (final e in eliminated)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _OutThumb(item: e),
                            ),
                          for (final id in scored)
                            if (byId[id] != null)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _ScoreChip(
                                    item: byId[id]!, count: _tally[id] ?? 0),
                              ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: TextButton.icon(
                        onPressed: _canUndo ? _undo : null,
                        icon: const Icon(Icons.undo_rounded),
                        label: Text(l.wheelUndo),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: Text(isTvDevice ? l.wheelPressToSpin : l.wheelTapToSpin,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            ),
          ],
        ),
        if (_overlay != null)
          _ResultOverlay(
            key: ValueKey('${_overlay!.item.id}-${_history.length}'),
            overlay: _overlay!,
            onDone: _dismissOverlay,
          ),
      ],
    );
  }
}

/// Every wheel sound goes through one player that lives as long as the
/// screen and keeps its audio stream open between sounds (mpv's
/// audio-stream-silence). A new player per sound meant a new audio stream
/// per sound, and a stream that is still starting up swallows a short
/// effect: the opening ticks of a spin and the whole winner jingle went
/// silent even though mpv reported them as playing.
class _WheelAudio {
  _WheelAudio() {
    unawaited(_init());
  }

  static const _tick = 'wheel_tick.wav';
  static const _winner = 'wheel_winner.wav';

  final _player = Player();
  final _clock = Stopwatch()..start();
  // Android serves the ticks from SoundPool instead (see WheelSfx.kt): one
  // media_kit stream restarted every 50ms smears on Android's media-sized
  // output buffer, so the rattle lagged the wheel and sounded slower than the
  // same code does on the desktop, even though both tick at the same rate.
  static const _sfx = MethodChannel('app.fathom.player/sfx');
  bool get _nativeTicks => defaultTargetPlatform == TargetPlatform.android;
  bool _nativeTickReady = false;
  bool muted = false;
  bool _disposed = false;
  // The asset currently open and ready to play, null while switching.
  String? _loaded;
  int _lastTickMicros = -1000000;
  bool _replaying = false;

  Future<void> _init() async {
    if (_nativeTicks) {
      try {
        await _sfx.invokeMethod('load', {'asset': 'assets/audio/$_tick'});
        _nativeTickReady = true;
      } catch (e) {
        Diagnostics.instance.add('wheel', 'native tick setup failed: $e');
      }
    }
    try {
      final p = _player.platform;
      if (p is NativePlayer) {
        await p.setProperty('audio-stream-silence', 'yes');
      }
      await _load(_tick);
      // One silent play so the audio device is already running before the
      // first spin rather than starting up on its first tick.
      await _player.setVolume(0);
      await _player.play();
      await Future.delayed(const Duration(milliseconds: 200));
      await _player.pause();
      await _player.seek(Duration.zero);
      await _player.setVolume(100);
    } catch (e) {
      Diagnostics.instance.add('wheel', 'sound setup failed: $e');
    }
  }

  // Media's constructor resolves the asset path synchronously, so this must
  // be an async function for a missing asset to land in the catch.
  Future<void> _load(String asset) async {
    if (_loaded == asset) return;
    _loaded = null;
    try {
      await _player.open(Media('asset:///assets/audio/$asset'), play: false);
      if (!_disposed) _loaded = asset;
    } catch (e) {
      Diagnostics.instance.add('wheel', 'sound $asset failed to open: $e');
    }
  }

  Future<void> prepareTick() => _load(_tick);

  void tick() {
    if (muted || _disposed) return;
    if (_nativeTickReady) {
      // SoundPool mixes overlapping plays, so no throttle and no restart: every
      // crossing gets its own click, at the rate the wheel actually turns.
      unawaited(_sfx
          .invokeMethod('play', {'asset': 'assets/audio/$_tick'})
          .catchError((_) => null));
      return;
    }
    if (_loaded != _tick) return;
    // At full speed a peg passes nearly every frame, and each replay seeks
    // back to the start, discarding the previous tick before it reaches the
    // speakers. Spacing them out keeps every tick audible as a fast rattle.
    final now = _clock.elapsedMicroseconds;
    if (now - _lastTickMicros < 45000) return;
    // Each replay is two platform round trips, and on a phone they take long
    // enough that firing the next one before the last has landed just queues
    // them: the rattle then drifts behind the wheel instead of tracking it.
    // One in flight at a time, so ticks come as fast as the device can serve
    // them and always match where the wheel actually is.
    // Each replay is two platform round trips; starting the next before the
    // last has landed only queues them, so the rattle drifts behind the wheel.
    // One in flight at a time keeps the ticks on the wedges.
    if (_replaying) return;
    _lastTickMicros = now;
    _replaying = true;
    unawaited(() async {
      try {
        await _player.seek(Duration.zero);
        await _player.play();
      } catch (_) {
      } finally {
        _replaying = false;
      }
    }());
  }

  Future<void> winner() async {
    Diagnostics.instance.add('wheel', 'winner sound: muted=$muted');
    if (muted || _disposed) return;
    await _load(_winner);
    if (_disposed || _loaded != _winner) return;
    try {
      await _player.seek(Duration.zero);
      await _player.play();
      // media_kit can report success without anything audible happening,
      // so record the state a moment later rather than trusting play().
      await Future.delayed(const Duration(milliseconds: 300));
      if (_disposed) return;
      final st = _player.state;
      Diagnostics.instance.add('wheel',
          'winner sound: playing=${st.playing} pos=${st.position} duration=${st.duration}');
    } catch (e) {
      Diagnostics.instance.add('wheel', 'winner sound failed: $e');
    }
  }

  void dispose() {
    _disposed = true;
    _player.dispose();
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          for (final c in children)
            Padding(padding: const EdgeInsets.only(right: 8), child: c),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.item});
  final BaseItemDto item;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 40,
        height: 56,
        child: MediaImage(item: item),
      ),
    );
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    required this.item,
    required this.selected,
    required this.added,
    required this.onToggle,
    required this.onRemove,
    this.autofocus = false,
  });

  final BaseItemDto item;
  final bool selected;
  final bool added;
  final bool autofocus;
  final VoidCallback onToggle;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final meta = [
      if (item.productionYear != null) '${item.productionYear}',
      if (item.runtimeMinutes != null) fmtRuntime(item.runtimeMinutes!),
      if (item.userData.played) l.wheelWatched,
      if (added) l.wheelAdded,
    ].join(' · ');
    return ListTile(
      autofocus: autofocus,
      onTap: onToggle,
      leading: _Thumb(item: item),
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: meta.isEmpty ? null : Text(meta, maxLines: 1),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (added)
            IconButton(
              tooltip: l.commonRemove,
              icon: const Icon(Icons.close_rounded),
              onPressed: onRemove,
            ),
          // The whole row is the D-pad stop and toggles on Select, so the
          // checkbox itself stays out of focus traversal.
          ExcludeFocus(
            child: Checkbox(value: selected, onChanged: (_) => onToggle()),
          ),
        ],
      ),
    );
  }
}

class _OutThumb extends StatelessWidget {
  const _OutThumb({required this.item});
  final BaseItemDto item;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: item.name,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 40,
          height: 60,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColorFiltered(
                colorFilter: const ColorFilter.matrix([
                  0.33, 0.33, 0.33, 0, 0, //
                  0.33, 0.33, 0.33, 0, 0, //
                  0.33, 0.33, 0.33, 0, 0, //
                  0, 0, 0, 0.55, 0,
                ]),
                child:
                    MediaImage(item: item),
              ),
              const Center(
                child: Icon(Icons.close_rounded,
                    color: Color(0xFFEF4444), size: 30),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreChip extends StatelessWidget {
  const _ScoreChip({required this.item, required this.count});
  final BaseItemDto item;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Chip(
        avatar: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 22,
            height: 32,
            child: MediaImage(item: item),
          ),
        ),
        label: Text('${'★' * count}  ${item.name}',
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _ResultOverlay extends StatefulWidget {
  const _ResultOverlay({super.key, required this.overlay, required this.onDone});
  final _Overlay overlay;
  final VoidCallback onDone;

  @override
  State<_ResultOverlay> createState() => _ResultOverlayState();
}

class _ResultOverlayState extends State<_ResultOverlay> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) widget.onDone();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final item = widget.overlay.item;
    final out = widget.overlay.kind == _OverlayKind.out;
    return Positioned.fill(
      child: GestureDetector(
        onTap: widget.onDone,
        child: Container(
          color: Colors.black.withValues(alpha: 0.78),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: out
                      ? null
                      : Border.all(color: const Color(0xFFFFD54A), width: 3),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 120,
                    height: 170,
                    child: Opacity(
                      opacity: out ? 0.5 : 1,
                      child: MediaImage(
                          item: item),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(out ? l.wheelEliminated(item.name) : l.wheelScored(item.name),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: out ? Colors.white : const Color(0xFFFFD54A),
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

class _WinnerView extends ConsumerStatefulWidget {
  const _WinnerView({required this.winner, required this.onRestart});
  final BaseItemDto winner;
  final VoidCallback onRestart;

  @override
  ConsumerState<_WinnerView> createState() => _WinnerViewState();
}

class _WinnerViewState extends ConsumerState<_WinnerView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _confettiController;
  late final List<_ConfettiPiece> _confetti;
  bool _watchlistBusy = false;

  @override
  void initState() {
    super.initState();
    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4800),
    );
    final r = math.Random();
    _confetti = List.generate(200, (_) => _ConfettiPiece(r));
    HapticFeedback.heavyImpact();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!reduce && !_confettiController.isAnimating &&
        _confettiController.value == 0) {
      _confettiController.forward();
    }
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  // The same add/remove toggle as the detail screen's Watchlist button.
  Future<void> _toggleWatchlist(List<BaseItemDto> watchlist) async {
    setState(() => _watchlistBusy = true);
    try {
      await toggleWatchlist(
          ScaffoldMessenger.of(context),
          AppLocalizations.of(context),
          ref.read(watchlistProvider.notifier),
          watchlist,
          widget.winner);
    } finally {
      if (mounted) setState(() => _watchlistBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final w = widget.winner;
    final inGroup = ref.watch(syncPlayControllerProvider);
    // .value keeps the last list while it reloads after a toggle, so the
    // pill doesn't flicker back to "not on the Watchlist" mid-refresh.
    final watchlist =
        ref.watch(watchlistProvider).value ?? const <BaseItemDto>[];
    final inWatchlist = inWatchlistFor(watchlist, w);
    final playTarget = playTargetFor(ref, w);

    return Stack(
      children: [
        LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= 720;
          final poster = ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: wide ? 240 : 170,
              height: wide ? 360 : 255,
              child: MediaImage(
                item: w,
                maxHeight: 720,
                filterQuality: FilterQuality.high,
              ),
            ),
          );
          final align =
              wide ? CrossAxisAlignment.start : CrossAxisAlignment.center;
          final textAlign = wide ? TextAlign.start : TextAlign.center;
          final info = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: align,
            children: [
              Text(l.wheelWinnerLabel,
                  style: TextStyle(
                      color: cs.primary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2)),
              const SizedBox(height: 8),
              Text(w.name,
                  textAlign: textAlign,
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: wide ? WrapAlignment.start : WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (w.productionYear != null) Text('${w.productionYear}'),
                  if (w.runtimeMinutes != null)
                    Text(fmtRuntime(w.runtimeMinutes!)),
                  if (w.officialRating != null) CertBadge(text: w.officialRating!),
                  if (w.communityRating != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 18, color: Color(0xFFFFD54A)),
                        const SizedBox(width: 2),
                        Text(w.communityRating!.toStringAsFixed(1)),
                      ],
                    ),
                ],
              ),
              if (w.genres.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(w.genres.take(3).join(' · '),
                    textAlign: textAlign,
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ],
              if ((w.overview ?? '').isNotEmpty) ...[
                const SizedBox(height: 14),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Text(w.overview!,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      textAlign: textAlign,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
                ),
              ],
              const SizedBox(height: 22),
              // The same expand-on-hover pills as the detail screen's actions.
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: wide ? WrapAlignment.start : WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  HoverPillButton(
                    // This phase change is an internal setState, not a
                    // route change, so the shell's autofocus never refires.
                    autofocus: isTvDevice,
                    primary: true,
                    icon: inGroup
                        ? Icons.groups_rounded
                        : Icons.play_arrow_rounded,
                    label: inGroup ? l.wheelPlayForGroup : l.commonPlay,
                    // A show plays its Next Up, like its title page.
                    onTap: playTarget == null
                        ? null
                        : () => context.push('/player', extra: playTarget),
                  ),
                  if (w.trailerUrl != null)
                    HoverPillButton(
                      icon: Icons.movie_outlined,
                      label: l.detailTrailer,
                      onTap: () => context.push('/trailer',
                          extra: (url: w.trailerUrl!, title: w.name)),
                    ),
                  HoverPillButton(
                    tinted: inWatchlist,
                    icon: inWatchlist
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    label: watchlistToggleLabel(l, watchlist, w),
                    onTap: _watchlistBusy
                        ? null
                        : () => _toggleWatchlist(watchlist),
                  ),
                  ClapOnHover(
                    child: HoverPillButton(
                      icon: Icons.movie_filter_rounded,
                      iconWidget:
                          ClapperIcon(size: 20, color: cs.onSurfaceVariant),
                      label: l.wheelSpinAgain,
                      onTap: widget.onRestart,
                    ),
                  ),
                ],
              ),
              if (inGroup) ...[
                const SizedBox(height: 10),
                Text(l.wheelGroupHint,
                    textAlign: textAlign,
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ],
            ],
          );
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 960),
                    child: wide
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              poster,
                              const SizedBox(width: 36),
                              Flexible(child: info),
                            ],
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              poster,
                              const SizedBox(height: 20),
                              info,
                            ],
                          ),
                  ),
                ),
              ),
            ),
          );
        }),
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _confettiController,
            builder: (context, _) => CustomPaint(
              painter: _ConfettiPainter(
                  pieces: _confetti, t: _confettiController.value),
              size: Size.infinite,
            ),
          ),
        ),
      ],
    );
  }
}

/// One confetti piece's fixed randomized traits, drawn at a position derived
/// purely from the shared clock [t] rather than storing mutable per-frame
/// state, so nothing needs to advance it except the one controller.
///
/// Each piece falls over its own slice of the timeline ([delay] to
/// [delay] + [life]): a big opening burst, then a steady rain for a couple of
/// seconds more instead of one wave that's gone almost at once.
class _ConfettiPiece {
  final double x0;
  final double delay;
  final double life;
  final double drift;
  final double spin;
  final double tumble;
  final double phase;
  final double size;
  final bool round;
  final Color color;

  factory _ConfettiPiece(math.Random r) {
    final life = 0.45 + r.nextDouble() * 0.15;
    final burst = r.nextDouble() < 0.4;
    return _ConfettiPiece._(
      x0: r.nextDouble(),
      delay: (burst ? r.nextDouble() * 0.06 : r.nextDouble()) * (1 - life),
      life: life,
      drift: (r.nextDouble() - 0.5) * 0.35,
      spin: (r.nextDouble() - 0.5) * 14,
      tumble: 2 + r.nextDouble() * 5,
      phase: r.nextDouble() * math.pi * 2,
      size: 6 + r.nextDouble() * 6,
      round: r.nextDouble() < 0.2,
      color: _kConfettiColors[r.nextInt(_kConfettiColors.length)],
    );
  }

  const _ConfettiPiece._({
    required this.x0,
    required this.delay,
    required this.life,
    required this.drift,
    required this.spin,
    required this.tumble,
    required this.phase,
    required this.size,
    required this.round,
    required this.color,
  });
}

const _kConfettiColors = [
  Color(0xFFEF4444),
  Color(0xFFF59E0B),
  Color(0xFFFFD54A),
  Color(0xFF22C55E),
  Color(0xFF3B82F6),
  Color(0xFF8B5CF6),
  Color(0xFFEC4899),
  Color(0xFF14B8A6),
];

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiPiece> pieces;
  final double t;
  const _ConfettiPainter({required this.pieces, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    for (final p in pieces) {
      final local = (t - p.delay) / p.life;
      if (local <= 0 || local >= 1) continue;
      final fall = Curves.easeIn.transform(local);
      final y = -20 + fall * (size.height + 40);
      final sway = math.sin(local * 4 * math.pi + p.phase) * 22;
      final x = p.x0 * size.width + p.drift * local * size.width + sway;
      final opacity = local > 0.85 ? (1 - local) / 0.15 : 1.0;
      final paint = Paint()
        ..color = p.color.withValues(alpha: opacity.clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(local * p.spin);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.size * 0.32, paint);
      } else {
        // Squashing the width over time reads as the piece tumbling in 3D.
        final w = p.size * math.cos(local * p.tumble * math.pi + p.phase).abs();
        canvas.drawRect(
          Rect.fromCenter(
              center: Offset.zero, width: math.max(w, 1), height: p.size * 0.5),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => true;
}
