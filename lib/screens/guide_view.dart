import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../widgets/motion.dart';
import '../api/error_text.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import '../models/guide_data.dart';
import '../state/library_providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';
import '../widgets/media_image.dart';
import '../widgets/app_spinner.dart';
import '../widgets/format.dart';

// The floor; the guide stretches wider than this when the window is short
// enough to leave empty space on a wide screen.
const _minPxPerMin = 4.0;
const _rowHeight = 74.0;
const _channelColWidth = 132.0;
const _headerHeight = 30.0;

/// EPG guide grid: channels down the left, a time-aligned program timeline
/// across, with a live "now" line. Channel column and rows scroll vertically in
/// sync; the timeline + header scroll horizontally together.
class GuideView extends ConsumerStatefulWidget {
  const GuideView({super.key});

  @override
  ConsumerState<GuideView> createState() => _GuideViewState();
}

class _GuideViewState extends ConsumerState<GuideView> {
  final _vChannels = ScrollController();
  final _vRows = ScrollController();
  final _horizontal = ScrollController();
  bool _syncing = false;
  bool _didAutoScroll = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _vChannels.addListener(() => _sync(_vChannels, _vRows));
    _vRows.addListener(() => _sync(_vRows, _vChannels));
    // Pull in the next chunk of EPG as the timeline nears its right edge, so the
    // guide keeps extending as far as the server has data.
    _horizontal.addListener(_maybeLoadMore);
    // Advance the "now" line and re-evaluate which program is airing, so the
    // guide stays live instead of freezing at the time it was opened.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  void _maybeLoadMore() {
    if (!_horizontal.hasClients) return;
    final pos = _horizontal.position;
    // Within ~1200px of the end: kick off the next fetch. The notifier ignores
    // the call while one is in flight or once the EPG runs out.
    if (pos.pixels >= pos.maxScrollExtent - 1200) {
      ref.read(guideProvider.notifier).loadMore();
    }
  }

  void _sync(ScrollController from, ScrollController to) {
    if (_syncing) return;
    if (!to.hasClients || to.offset == from.offset) return;
    _syncing = true;
    to.jumpTo(from.offset);
    _syncing = false;
  }

  @override
  void dispose() {
    _tick?.cancel();
    _vChannels.dispose();
    _vRows.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  /// Scroll the timeline so "now" sits just in from the left edge, once, after
  /// the first layout.
  void _autoScrollToNow(GuideData data, double pxPerMin) {
    if (_didAutoScroll) return;
    _didAutoScroll = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_horizontal.hasClients) return;
      final nowMin =
          DateTime.now().difference(data.windowStart).inMinutes.toDouble();
      final target = (nowMin * pxPerMin - 120)
          .clamp(0.0, _horizontal.position.maxScrollExtent);
      _horizontal.jumpTo(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    final guide = ref.watch(guideProvider);
    return guide.when(
      loading: () => const Center(child: AppSpinner()),
      error: (e, _) => ErrorView(
          message: errorText(e),
          onRetry: () => ref.invalidate(guideProvider),
        ),
      data: (data) {
        if (data.channels.isEmpty) {
          return EmptyState(
              icon: Icons.live_tv_rounded,
              title: AppLocalizations.of(context).extraNoChannelsFound);
        }
        final totalMinutes =
            data.windowEnd.difference(data.windowStart).inMinutes;
        return LayoutBuilder(builder: (context, constraints) {
          // Stretch the timeline to fill the width when the window would
          // otherwise leave dead space to the right; still scrolls when long.
          final timelineWidth = constraints.maxWidth - _channelColWidth - 1;
          final pxPerMin = totalMinutes > 0
              ? math.max(_minPxPerMin, timelineWidth / totalMinutes)
              : _minPxPerMin;
          final totalWidth = totalMinutes * pxPerMin;
          _autoScrollToNow(data, pxPerMin);
          return _guide(context, data, pxPerMin, totalWidth);
        });
      },
    );
  }

  Widget _guide(
      BuildContext context, GuideData data, double pxPerMin, double totalWidth) {
    return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Channel column (fixed)
            SizedBox(
              width: _channelColWidth,
              child: Column(
                children: [
                  const SizedBox(height: _headerHeight),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      controller: _vChannels,
                      itemExtent: _rowHeight,
                      itemCount: data.channels.length,
                      itemBuilder: (context, i) =>
                          _ChannelCell(channel: data.channels[i]),
                    ),
                  ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            // Timeline (horizontal scroll shared by header + rows)
            Expanded(
              child: SingleChildScrollView(
                controller: _horizontal,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: totalWidth,
                  child: Column(
                    children: [
                      SizedBox(
                        height: _headerHeight,
                        child: _TimeRuler(
                            start: data.windowStart,
                            end: data.windowEnd,
                            pxPerMin: pxPerMin),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: Stack(
                          children: [
                            ListView.builder(
                              controller: _vRows,
                              itemExtent: _rowHeight,
                              itemCount: data.channels.length,
                              itemBuilder: (context, i) {
                                final ch = data.channels[i];
                                return _ProgramRow(
                                  channel: ch,
                                  programs:
                                      data.programsByChannel[ch.id] ?? const [],
                                  windowStart: data.windowStart,
                                  windowEnd: data.windowEnd,
                                  width: totalWidth,
                                  pxPerMin: pxPerMin,
                                );
                              },
                            ),
                            _NowLine(data: data, pxPerMin: pxPerMin),
                            if (data.loadingMore)
                              const Positioned(
                                right: 10,
                                top: 0,
                                bottom: 0,
                                child: Center(
                                  child: AppSpinner.inline(),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
  }
}

class _ChannelCell extends StatelessWidget {
  final BaseItemDto channel;
  const _ChannelCell({required this.channel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.12)),
        ),
      ),
      child: InkWell(
      onTap: () => context.push('/player', extra: channel),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 30,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: MediaImage(
                  item: channel, placeholderIcon: Icons.live_tv_rounded),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (channel.channelNumber != null)
                    Text(channel.channelNumber!,
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  Text(channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
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

class _TimeRuler extends StatelessWidget {
  final DateTime start;
  final DateTime end;
  final double pxPerMin;
  const _TimeRuler(
      {required this.start, required this.end, required this.pxPerMin});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marks = <Widget>[];
    var t = start;
    while (t.isBefore(end)) {
      final left = t.difference(start).inMinutes * pxPerMin;
      marks.add(Positioned(
        left: left,
        top: 0,
        bottom: 0,
        child: Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(clockTime(context, t),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        ),
      ));
      t = t.add(const Duration(minutes: 30));
    }
    return Stack(children: marks);
  }
}

class _ProgramRow extends StatefulWidget {
  final BaseItemDto channel;
  final List<BaseItemDto> programs;
  final DateTime windowStart;
  final DateTime windowEnd;
  final double width;
  final double pxPerMin;

  const _ProgramRow({
    required this.channel,
    required this.programs,
    required this.windowStart,
    required this.windowEnd,
    required this.width,
    required this.pxPerMin,
  });

  @override
  State<_ProgramRow> createState() => _ProgramRowState();
}

class _ProgramRowState extends State<_ProgramRow> {
  // One node per rendered program block, so LEFT/RIGHT can step between them.
  final List<FocusNode> _nodes = [];

  FocusNode _nodeAt(int i) {
    while (_nodes.length <= i) {
      _nodes.add(FocusNode(debugLabel: 'guideProgram'));
    }
    return _nodes[i];
  }

  @override
  void dispose() {
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _ensureVisible(int i) {
    final ctx = _nodeAt(i).context;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          alignment: 0.15,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut);
    }
  }

  // LEFT walks back through this row's programs (scrolling the earlier one into
  // view) and only escapes to the channel column at the FIRST program; RIGHT
  // walks forward. Everything else falls through so the framework still handles
  // UP/DOWN between channels and SELECT to open a program.
  KeyEventResult _onKey(int i, int count, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft) {
      if (i > 0) {
        _nodeAt(i - 1).requestFocus();
        _ensureVisible(i - 1);
        return KeyEventResult.handled;
      }
      // First program: hand LEFT to the focused node's traversal group (the
      // content policy), which escapes to the channel column (same row, left).
      FocusManager.instance.primaryFocus
          ?.focusInDirection(TraversalDirection.left);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      if (i < count - 1) {
        _nodeAt(i + 1).requestFocus();
        _ensureVisible(i + 1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final totalMinutes =
        widget.windowEnd.difference(widget.windowStart).inMinutes;
    final now = DateTime.now();
    // Lay the renderable programs out first so the LEFT/RIGHT handler knows the
    // block count and each block's focus-node index.
    final laid = <({
      BaseItemDto p,
      double left,
      double w,
      bool isNow,
      double? progress
    })>[];
    for (final p in widget.programs) {
      final start = p.startDate, end = p.endDate;
      if (start == null || end == null) continue;
      final startMin = start
          .difference(widget.windowStart)
          .inMinutes
          .clamp(0, totalMinutes);
      final endMin =
          end.difference(widget.windowStart).inMinutes.clamp(0, totalMinutes);
      final w = (endMin - startMin) * widget.pxPerMin;
      if (w <= 0) continue;
      final isNow = now.isAfter(start) && now.isBefore(end);
      final progress = isNow
          ? (now.difference(start).inSeconds / end.difference(start).inSeconds)
              .clamp(0.0, 1.0)
          : null;
      laid.add((
        p: p,
        left: startMin * widget.pxPerMin,
        w: w,
        isNow: isNow,
        progress: progress
      ));
    }
    final count = laid.length;
    final blocks = <Widget>[
      for (var i = 0; i < count; i++)
        Positioned(
          left: laid[i].left,
          width: laid[i].w,
          top: 3,
          bottom: 3,
          // A non-focusable Focus that still sees the block's key events; it
          // intercepts LEFT/RIGHT before the framework's geometric traversal
          // would jump straight to the channel column.
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: (node, e) => _onKey(i, count, e),
            child: _ProgramBlock(
              program: laid[i].p,
              isNow: laid[i].isNow,
              progress: laid[i].progress,
              focusNode: _nodeAt(i),
              onTap: () => context.push('/program',
                  extra: (
                    channel: widget.channel,
                    program: laid[i].p,
                    isNow: laid[i].isNow
                  )),
            ),
          ),
        ),
    ];
    return Container(
      width: widget.width,
      height: _rowHeight,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context)
                .colorScheme
                .outlineVariant
                .withValues(alpha: 0.12),
          ),
        ),
      ),
      child: Stack(children: blocks),
    );
  }
}

class _ProgramBlock extends StatelessWidget {
  final BaseItemDto program;
  final bool isNow;
  final double? progress;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  const _ProgramBlock(
      {required this.program,
      required this.isNow,
      required this.onTap,
      this.focusNode,
      this.progress});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 3),
      child: Material(
        color: isNow ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(
            color: isNow
                ? scheme.primary.withValues(alpha: 0.6)
                : scheme.outlineVariant.withValues(alpha: 0.25),
          ),
        ),
        child: InkWell(
          focusNode: focusNode,
          onTap: onTap,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(program.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isNow ? scheme.onPrimaryContainer : null,
                        )),
                    if (program.episodeTitle != null &&
                        program.episodeTitle!.isNotEmpty)
                      Text(program.episodeTitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: (isNow
                                    ? scheme.onPrimaryContainer
                                    : scheme.onSurface)
                                .withValues(alpha: 0.7),
                          )),
                  ],
                ),
              ),
              // Live progress along the bottom of the airing program.
              if (progress != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 3,
                    backgroundColor: scheme.primary.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(scheme.primary),
                  ),
                ),
              // Live / recording markers. A program that is on air now AND has
              // a timer is recording this second: it gets a pulsing "REC" badge,
              // which also stands in for the LIVE badge (it's plainly on air).
              // A timer on a future program is merely scheduled: a static dot.
              if (isNow || program.timerId != null)
                Positioned(
                  top: 4,
                  right: 4,
                  child: (isNow && program.timerId != null)
                      ? const _RecBadge()
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (program.timerId != null) ...[
                              const _RecordingDot(),
                              const SizedBox(width: 4),
                            ],
                            if (isNow) const _LiveBadge(),
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

/// A static red dot marking a program with a recording scheduled for later.
class _RecordingDot extends StatelessWidget {
  const _RecordingDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: Colors.red,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Colors.red.withValues(alpha: 0.6), blurRadius: 4),
        ],
      ),
    );
  }
}

/// A "REC" pill with a pulsing dot, marking a program recording right now (on
/// air with a timer). The pulse is what separates it from a scheduled dot.
class _RecBadge extends StatefulWidget {
  const _RecBadge();

  @override
  State<_RecBadge> createState() => _RecBadgeState();
}

class _RecBadgeState extends State<_RecBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    stillIfReduced(context, _c);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: Tween<double>(begin: 1, end: 0.25).animate(_c),
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(AppLocalizations.of(context).extraBadgeRec,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }
}

/// A small red "LIVE" pill on the currently-airing program.
class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(AppLocalizations.of(context).extraBadgeLive,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5)),
    );
  }
}

class _NowLine extends StatelessWidget {
  final GuideData data;
  final double pxPerMin;
  const _NowLine({required this.data, required this.pxPerMin});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    if (now.isBefore(data.windowStart) || now.isAfter(data.windowEnd)) {
      return const SizedBox.shrink();
    }
    final left = now.difference(data.windowStart).inMinutes * pxPerMin;
    final primary = Theme.of(context).colorScheme.primary;
    return Positioned(
      left: left - 6,
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        child: SizedBox(
          width: 12,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Center(
                child: Container(
                  width: 2,
                  decoration: BoxDecoration(
                    color: primary,
                    boxShadow: [
                      BoxShadow(
                          color: primary.withValues(alpha: 0.6), blurRadius: 8),
                    ],
                  ),
                ),
              ),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: primary, shape: BoxShape.circle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
