import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/seerr_person.dart';
import '../state/seerr_providers.dart';
import '../widgets/shimmer.dart';
import '../widgets/cached_image.dart';
import '../widgets/error_view.dart';
import '../widgets/motion.dart';
import '../widgets/seerr_poster_card.dart';

/// Seerr person page: a rotating backdrop of their work, their bio, and a
/// filterable grid of appearances (each opens the title's detail page).
class SeerrPersonScreen extends ConsumerStatefulWidget {
  final int personId;
  const SeerrPersonScreen({super.key, required this.personId});

  @override
  ConsumerState<SeerrPersonScreen> createState() => _SeerrPersonScreenState();
}

class _SeerrPersonScreenState extends ConsumerState<SeerrPersonScreen> {
  String _filter = 'all'; // all | movie | tv

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(seerrPersonProvider(widget.personId));
    return Scaffold(
      body: async.when(
        loading: () => const HeaderGridSkeleton(headerHeight: 160),
        error: (e, _) => SafeArea(
          child: Column(
            children: [
              const Align(alignment: Alignment.centerLeft, child: BackButton()),
              Expanded(child: ErrorView(
          message: '$e',
          onRetry: () => ref.invalidate(seerrPersonProvider(widget.personId)),
        )),
            ],
          ),
        ),
        data: (person) => _body(context, person),
      ),
    );
  }

  Widget _body(BuildContext context, SeerrPerson person) {
    final l = AppLocalizations.of(context);
    final credits = switch (_filter) {
      'movie' => person.movies,
      'tv' => person.series,
      _ => person.credits,
    };
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _PersonHeader(person: person)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Row(
              children: [
                Text(l.detailAppearances,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const Spacer(),
                if (person.movies.isNotEmpty && person.series.isNotEmpty)
                  SegmentedButton<String>(
                    style: const ButtonStyle(
                        visualDensity: VisualDensity.compact),
                    segments: [
                      ButtonSegment(value: 'all', label: Text(l.detailAll)),
                      ButtonSegment(
                          value: 'movie', label: Text(l.detailMovies)),
                      ButtonSegment(value: 'tv', label: Text(l.detailSeries)),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (s) =>
                        setState(() => _filter = s.first),
                  ),
              ],
            ),
          ),
        ),
        if (credits.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Center(child: Text(l.detailNoAppearances)),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 184,
                mainAxisSpacing: 18,
                crossAxisSpacing: 14,
                childAspectRatio: 0.54,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => EntranceFade(
                  index: i,
                  onceKey: 'pc${credits[i].mediaType}${credits[i].tmdbId}',
                  child: SeerrGridCard(result: credits[i]),
                ),
                childCount: credits.length,
              ),
            ),
          ),
      ],
    );
  }
}

class _PersonHeader extends StatelessWidget {
  final SeerrPerson person;
  const _PersonHeader({required this.person});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 300,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _RotatingBackdrop(urls: person.backdrops),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black54, Colors.black87],
                    stops: [0.0, 1.0],
                  ),
                ),
              ),
              const SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: BackButton(color: Colors.white),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    CircleAvatar(
                      radius: 52,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      foregroundImage: person.profileUrl != null
                          ? NetworkImage(person.profileUrl!)
                          : null,
                      child: person.profileUrl == null
                          ? const Icon(Icons.person_rounded, size: 44)
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(person.name,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  shadows: const [
                                    Shadow(blurRadius: 8, color: Colors.black)
                                  ])),
                          if (_born(l, person) != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(_born(l, person)!,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 13)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (person.alsoKnownAs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Text(
                l.detailAlsoKnownAs(person.alsoKnownAs.take(4).join(', ')),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        if (person.biography != null && person.biography!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _Biography(text: person.biography!),
          ),
      ],
    );
  }

  String? _born(AppLocalizations l, SeerrPerson p) {
    if (p.birthday == null) return null;
    final where = p.placeOfBirth != null ? '  |  ${p.placeOfBirth}' : '';
    return '${l.detailBorn(p.birthday!)}$where';
  }
}

/// The biography, collapsed to a few lines with a Read More / Less toggle.
class _Biography extends StatefulWidget {
  final String text;
  const _Biography({required this.text});
  @override
  State<_Biography> createState() => _BiographyState();
}

class _BiographyState extends State<_Biography> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: Text(widget.text,
              maxLines: _expanded ? null : 5,
              overflow:
                  _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium),
        ),
        TextButton(
          onPressed: () => setState(() => _expanded = !_expanded),
          style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          child: Text(_expanded ? l.detailReadLess : l.detailReadMore),
        ),
      ],
    );
  }
}

/// Crossfades through a person's backdrops, like the Jellyseerr person header.
class _RotatingBackdrop extends StatefulWidget {
  final List<String> urls;
  const _RotatingBackdrop({required this.urls});
  @override
  State<_RotatingBackdrop> createState() => _RotatingBackdropState();
}

class _RotatingBackdropState extends State<_RotatingBackdrop> {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.urls.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 6), (_) {
        if (!mounted) return;
        setState(() => _index = (_index + 1) % widget.urls.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (widget.urls.isEmpty) {
      return ColoredBox(color: scheme.surfaceContainerHigh);
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 800),
      child: CachedImage(
        key: ValueKey(widget.urls[_index]),
        url: widget.urls[_index],
        errorBuilder: (_) => ColoredBox(color: scheme.surfaceContainerHigh),
      ),
    );
  }
}
