import 'dart:async';

import 'package:flutter/material.dart';

import '../models/base_item.dart';
import 'cached_image.dart';
import 'glass.dart';
import 'format.dart';

/// The "now playing" panel for a live channel, shown in the player overlay: the
/// channel number and network, the current show, its episode, a progress bar
/// across the program with start/end times, and a short description. Fades in
/// and out with the rest of the controls.
class LiveInfoPanel extends StatefulWidget {
  final String channelName;
  final String? channelNumber;
  final String? logoUrl;
  final Map<String, String>? headers;
  final BaseItemDto? program;

  const LiveInfoPanel({
    super.key,
    required this.channelName,
    this.channelNumber,
    this.logoUrl,
    this.headers,
    this.program,
  });

  @override
  State<LiveInfoPanel> createState() => _LiveInfoPanelState();
}

class _LiveInfoPanelState extends State<LiveInfoPanel> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Nudge the progress bar forward roughly twice a minute.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// 0..1 through the current program, or null if the times are unknown.
  double? _progress(DateTime? start, DateTime? end) {
    if (start == null || end == null) return null;
    final total = end.difference(start).inSeconds;
    if (total <= 0) return null;
    final done = DateTime.now().difference(start).inSeconds;
    return (done / total).clamp(0.0, 1.0);
  }

  String _clock(DateTime t) => clockTime(context, t);

  String? _episodeLine(BaseItemDto p) {
    final parts = <String>[];
    if (p.parentIndexNumber != null && p.indexNumber != null) {
      parts.add('S${p.parentIndexNumber} E${p.indexNumber}');
    } else if (p.indexNumber != null) {
      parts.add('E${p.indexNumber}');
    }
    if ((p.episodeTitle ?? '').isNotEmpty) parts.add(p.episodeTitle!);
    return parts.isEmpty ? null : parts.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = widget.program;
    final showTitle = (p?.name ?? '').isNotEmpty ? p!.name : widget.channelName;
    final episode = p == null ? null : _episodeLine(p);
    final progress = _progress(p?.startDate, p?.endDate);
    final overview = p?.overview ?? '';

    return GlassSurface(
      blur: 14,
      color: Colors.black.withValues(alpha: 0.38),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Channel row: logo, number, network.
              Row(
                children: [
                  if (widget.logoUrl != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: CachedImage(
                        url: widget.logoUrl!,
                        headers: widget.headers,
                        height: 24,
                        width: 44,
                        fit: BoxFit.contain,
                        errorBuilder: (_) => const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  if ((widget.channelNumber ?? '').isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(widget.channelNumber!,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(widget.channelName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Show title.
              Text(showTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      height: 1.1)),
              if (episode != null) ...[
                const SizedBox(height: 4),
                Text(episode,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
              ],
              // Program progress + times.
              if (progress != null) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: Colors.white.withValues(alpha: 0.20),
                    valueColor:
                        AlwaysStoppedAnimation(theme.colorScheme.primary),
                  ),
                ),
                const SizedBox(height: 6),
                Text('${_clock(p!.startDate!)}  -  ${_clock(p.endDate!)}',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
              ],
              // Description.
              if (overview.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(overview,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 13,
                        height: 1.35)),
              ],
            ],
          ),
        ),
    );
  }
}

/// The live "now playing" info block for the frosted bottom bar: show title,
/// episode, the program's air window, and the full description. The interactive
/// transport (a seekable buffer bar and a LIVE button) is rendered below this by
/// the controls, and the channel identity lives up in the top bar, so neither is
/// repeated here.
class LiveBottomInfo extends StatefulWidget {
  final String channelName;
  final BaseItemDto? program;

  const LiveBottomInfo({
    super.key,
    required this.channelName,
    this.program,
  });

  @override
  State<LiveBottomInfo> createState() => _LiveBottomInfoState();
}

class _LiveBottomInfoState extends State<LiveBottomInfo> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _clock(DateTime t) => clockTime(context, t);

  String? _episodeLine(BaseItemDto p) {
    final parts = <String>[];
    if (p.parentIndexNumber != null && p.indexNumber != null) {
      parts.add('S${p.parentIndexNumber} E${p.indexNumber}');
    } else if (p.indexNumber != null) {
      parts.add('E${p.indexNumber}');
    }
    if ((p.episodeTitle ?? '').isNotEmpty) parts.add(p.episodeTitle!);
    return parts.isEmpty ? null : parts.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = widget.program;
    final showTitle = (p?.name ?? '').isNotEmpty ? p!.name : widget.channelName;
    final episode = p == null ? null : _episodeLine(p);
    final overview = p?.overview ?? '';
    final airWindow = (p?.startDate != null && p?.endDate != null)
        ? '${_clock(p!.startDate!)}  -  ${_clock(p.endDate!)}'
        : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(showTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                height: 1.1)),
        if (episode != null || airWindow != null) ...[
          const SizedBox(height: 4),
          Text([episode, airWindow].whereType<String>().join('   ·   '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ],
        if (overview.isNotEmpty) ...[
          const SizedBox(height: 8),
          // Full description, uncapped. A long synopsis scrolls within a bounded
          // height so it never grows the bar tall enough to swallow the video.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 120),
            child: SingleChildScrollView(
              child: Text(overview,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.80),
                      fontSize: 13,
                      height: 1.4)),
            ),
          ),
        ],
      ],
    );
  }
}
