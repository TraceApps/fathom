import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../l10n/generated/app_localizations.dart';

/// A translucent "playback details" overlay (a stats-for-nerds panel). Polls
/// live mpv properties once a second — resolution, codecs, bitrates, the actual
/// hardware-decode path and dropped-frame counts — alongside the server play
/// method the caller resolved. Read-only; toggled from the player's more menu.
///
/// mpv is the source of truth for what's really rendering (which matters most on
/// arch-sensitive setups: it shows whether hardware decode actually engaged),
/// while [playMethod] answers the separate "is the server transcoding?" question.
class PlaybackStatsOverlay extends StatefulWidget {
  final Player player;
  final String playMethod;
  final VoidCallback? onClose;
  const PlaybackStatsOverlay({
    super.key,
    required this.player,
    required this.playMethod,
    this.onClose,
  });

  @override
  State<PlaybackStatsOverlay> createState() => _PlaybackStatsOverlayState();
}

class _PlaybackStatsOverlayState extends State<PlaybackStatsOverlay> {
  // The mpv properties the panel reads each tick. Kept in one list so a single
  // loop fetches them; any that a given stream doesn't expose come back null.
  static const _props = <String>[
    'width',
    'height',
    'video-format',
    'estimated-vf-fps',
    'video-bitrate',
    'hwdec-current',
    'frame-drop-count',
    'decoder-frame-drop-count',
    'audio-codec-name',
    'audio-params/channel-count',
    'audio-params/channels',
    'audio-params/samplerate',
    'audio-bitrate',
    'file-format',
    'demuxer-cache-duration',
    'avsync',
  ];

  Map<String, String?> _v = const {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer =
        Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<String?> _get(String name) async {
    try {
      final r = await (widget.player.platform as dynamic).getProperty(name);
      if (r == null) return null;
      final s = r.toString().trim();
      return s.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  }

  Future<void> _refresh() async {
    final next = <String, String?>{};
    for (final p in _props) {
      next[p] = await _get(p);
    }
    if (mounted) setState(() => _v = next);
  }

  // --- Derived, display-ready values (all tolerant of missing properties). ---

  static const _dash = '-';

  String get _resolution {
    final w = _v['width'], h = _v['height'];
    return (w != null && h != null) ? '$w × $h' : _dash;
  }

  String get _videoCodec => _v['video-format']?.toUpperCase() ?? _dash;

  String get _fps {
    final d = double.tryParse(_v['estimated-vf-fps'] ?? '');
    return d == null || d <= 0 ? _dash : '${d.toStringAsFixed(2)} fps';
  }

  String _mbps(String? bps) {
    final d = double.tryParse(bps ?? '');
    return d == null || d <= 0 ? _dash : '${(d / 1e6).toStringAsFixed(1)} Mbps';
  }

  String _kbps(String? bps) {
    final d = double.tryParse(bps ?? '');
    return d == null || d <= 0 ? _dash : '${(d / 1000).round()} kbps';
  }

  String _decoder(AppLocalizations l) {
    final hw = _v['hwdec-current'];
    if (hw == null || hw.isEmpty || hw == 'no') return l.playerStatSoftware;
    return '${l.playerStatHardware} ($hw)';
  }

  String get _droppedFrames {
    final dec = _v['decoder-frame-drop-count'] ?? '0';
    final vo = _v['frame-drop-count'] ?? '0';
    return '$dec / $vo';
  }

  String get _channels {
    final n = _v['audio-params/channel-count'];
    final layout = _v['audio-params/channels'];
    if (n == null) return _dash;
    return (layout != null && layout != n) ? '$n ($layout)' : n;
  }

  String get _sampleRate {
    final d = double.tryParse(_v['audio-params/samplerate'] ?? '');
    return d == null || d <= 0
        ? _dash
        : '${(d / 1000).toStringAsFixed(1)} kHz';
  }

  String _seconds(String? v) {
    final d = double.tryParse(v ?? '');
    return d == null ? _dash : '${d.toStringAsFixed(1)} s';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // No fixed max height: the parent bounds it to the video area, so it grows
    // to show everything where there's room (fullscreen) and only scrolls where
    // there isn't (a short window).
    return Container(
      width: 288,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 16, color: Colors.white70),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l.playerPlaybackInfo,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ),
                if (widget.onClose != null)
                  Semantics(button: true, label: l.commonClose, child: InkResponse(
                    onTap: widget.onClose,
                    radius: 18,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close_rounded,
                          size: 16, color: Colors.white70),
                    ),
                  )),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _row(l.playerStatPlayMethod, widget.playMethod, strong: true),
                  _section(l.playerStatVideo),
                  _row(l.playerStatResolution, _resolution),
                  _row(l.playerStatCodec, _videoCodec),
                  _row(l.playerStatFrameRate, _fps),
                  _row(l.playerStatBitrate, _mbps(_v['video-bitrate'])),
                  _row(l.playerStatDecoder, _decoder(l)),
                  _row(l.playerStatDroppedFrames, _droppedFrames),
                  _section(l.playerStatAudio),
                  _row(l.playerStatCodec,
                      _v['audio-codec-name']?.toUpperCase() ?? _dash),
                  _row(l.playerStatChannels, _channels),
                  _row(l.playerStatSampleRate, _sampleRate),
                  _row(l.playerStatBitrate, _kbps(_v['audio-bitrate'])),
                  _section(l.playerStatGeneral),
                  _row(l.playerStatContainer,
                      _v['file-format']?.toUpperCase() ?? _dash),
                  _row(l.playerStatBuffer,
                      _seconds(_v['demuxer-cache-duration'])),
                  _row(l.playerStatAvSync, _seconds(_v['avsync'])),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(title.toUpperCase(),
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8)),
      );

  Widget _row(String label, String value, {bool strong = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 108,
              child: Text(label,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(value,
                  style: TextStyle(
                      color: strong ? Colors.white : Colors.white,
                      fontSize: 12,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      fontWeight:
                          strong ? FontWeight.w700 : FontWeight.w500)),
            ),
          ],
        ),
      );
}
