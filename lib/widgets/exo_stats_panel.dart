import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import 'exo_video.dart';

/// Playback Info panel for the native ExoPlayer backend (Android TV YouTube +
/// Jellyfin/Live). Reads the live [ExoState] the native side pushes and lays it
/// out exactly like the media_kit player's stats panel, so all three players
/// read the same. Reuses the shared stat strings.
class ExoStatsPanel extends StatelessWidget {
  final ExoVideoController controller;
  final VoidCallback onClose;
  const ExoStatsPanel(
      {super.key, required this.controller, required this.onClose});

  static const _dash = '-';

  // Map ExoPlayer's raw MIME subtypes to the friendly names the media_kit panel
  // shows (mpv reports "vp9"/"aac" already), so both players read the same.
  static const _codecNames = {
    'avc': 'H264',
    'h264': 'H264',
    'hevc': 'HEVC',
    'h265': 'HEVC',
    'av01': 'AV1',
    'av1': 'AV1',
    'x-vnd.on2.vp9': 'VP9',
    'vp9': 'VP9',
    'x-vnd.on2.vp8': 'VP8',
    'vp8': 'VP8',
    'mpeg2': 'MPEG2',
    'mp4a-latm': 'AAC',
    'mp4a': 'AAC',
    'aac': 'AAC',
    'opus': 'OPUS',
    'vorbis': 'VORBIS',
    'ac3': 'AC3',
    'eac3': 'EAC3',
    'mpeg': 'MP3',
  };

  String _codec(String raw) {
    if (raw.isEmpty) return _dash;
    final s = (raw.contains('/') ? raw.split('/').last : raw).toLowerCase();
    return _codecNames[s] ?? s.toUpperCase();
  }

  String _mbps(int bps) =>
      bps <= 0 ? _dash : '${(bps / 1e6).toStringAsFixed(1)} Mbps';
  String _kbps(int bps) => bps <= 0 ? _dash : '${(bps / 1000).round()} kbps';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ValueListenableBuilder<ExoState>(
      valueListenable: controller.state,
      builder: (context, s, _) {
        final res =
            (s.width > 0 && s.height > 0) ? '${s.width} × ${s.height}' : _dash;
        final fps =
            s.frameRate > 0 ? '${s.frameRate.toStringAsFixed(2)} fps' : _dash;
        final channels = s.audioChannels > 0 ? '${s.audioChannels}' : _dash;
        final rate = s.audioSampleRate > 0
            ? '${(s.audioSampleRate / 1000).toStringAsFixed(1)} kHz'
            : _dash;
        final bufferMs = (s.buffered - s.position).inMilliseconds;
        final buffer =
            bufferMs > 0 ? '${(bufferMs / 1000).toStringAsFixed(1)} s' : _dash;
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
                    Semantics(button: true, label: l.commonClose, child: InkResponse(
                      onTap: onClose,
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
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _section(l.playerStatVideo),
                    _row(l.playerStatResolution, res),
                    _row(l.playerStatCodec, _codec(s.videoCodec)),
                    _row(l.playerStatFrameRate, fps),
                    _row(l.playerStatBitrate, _mbps(s.videoBitrate)),
                    _row(l.playerStatDroppedFrames, '${s.droppedFrames}'),
                    _section(l.playerStatAudio),
                    _row(l.playerStatCodec, _codec(s.audioCodec)),
                    _row(l.playerStatChannels, channels),
                    _row(l.playerStatSampleRate, rate),
                    _row(l.playerStatBitrate, _kbps(s.audioBitrate)),
                    _section(l.playerStatGeneral),
                    _row(l.playerStatBuffer, buffer),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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

  Widget _row(String label, String value) => Padding(
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
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontFeatures: [FontFeature.tabularFigures()],
                      fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );
}
