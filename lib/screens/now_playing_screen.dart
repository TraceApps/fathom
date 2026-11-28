import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import '../models/radio_station.dart';
import '../models/youtube_audio_item.dart';
import '../services/tv_mode.dart';
import '../state/audio_player.dart';
import '../state/cast.dart';
import '../state/lyrics_provider.dart';
import '../state/preferences.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import '../state/youtube_providers.dart';
import '../widgets/cast_button.dart';
import '../widgets/control_button.dart';
import '../widgets/glass.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/media_image.dart';
import '../widgets/motion.dart';
import '../widgets/reorder.dart';
import '../widgets/volume_control.dart';
import '../widgets/sleep_timer_sheet.dart';
import '../api/jellyfin_client.dart';

/// Full-screen now-playing: large art, draggable seek bar, transport controls,
/// shuffle and repeat.
class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final audio = ref.watch(audioControllerProvider);
    if (audio.isRadio) return const _RadioNowPlaying();
    if (audio.isYoutubeAudio) return const _YoutubeNowPlaying();
    final track = audio.current;

    // A manual artwork/lyrics flip belongs to the song it was made on. When the
    // track changes, drop back to the preference default rather than carrying a
    // "show lyrics" choice onto a song that may have none.
    ref.listen(
      audioControllerProvider.select((a) => a.current?.id),
      (prev, next) {
        if (prev != next) ref.read(showingLyricsProvider.notifier).reset();
      },
    );
    final controller = ref.read(audioControllerProvider.notifier);
    final player = ref.watch(audioPlayerProvider);
    final theme = Theme.of(context);
    final cast = ref.watch(castControllerProvider);

    if (track == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l.playerNothingPlaying)),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      // No text field on this screen, so it has no business reacting to a
      // keyboard inset. Left at the default, a stuck/late-clearing inset
      // (#40: "looks like the keyboard isn't removed") shrinks the body and
      // leaves the transport row and Up Next rendered off the visible screen.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(l.playerNowPlaying),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          SleepTimerButton(endOfItemLabel: l.sleepTimerEndOfTrack),
          // Music can cast to any device, including audio-only speakers. The
          // whole queue is handed to the receiver so Skip advances on-device.
          CastButton(
            videoOnly: false,
            title: track.name,
            queueResolve: () async {
              final session =
                  ref.read(sessionControllerProvider).asData?.value;
              if (session == null) return null;
              final client = ref.read(jellyfinClientProvider);
              final q = ref.read(audioControllerProvider).queue;
              if (q.isEmpty) return null;
              String? img(BaseItemDto t) {
                if (t.primaryImageTag != null) {
                  return client.imageUrl(
                      baseUrl: session.baseUrl,
                      itemId: t.id,
                      type: 'Primary',
                      tag: t.primaryImageTag);
                }
                if (t.albumId != null && t.albumPrimaryImageTag != null) {
                  return client.imageUrl(
                      baseUrl: session.baseUrl,
                      itemId: t.albumId!,
                      type: 'Primary',
                      tag: t.albumPrimaryImageTag);
                }
                return null;
              }

              final items = [
                for (final t in q)
                  {
                    'url': client.castAudioUrl(
                        baseUrl: session.baseUrl,
                        userId: session.userId,
                        itemId: t.id,
                        token: session.accessToken),
                    'contentType': 'audio/mpeg',
                    'title': t.name,
                    'subtitle': t.artists.isNotEmpty
                        ? t.artists.join(', ')
                        : (t.albumArtist ?? ''),
                    if (img(t) != null) 'image': img(t)!,
                  },
              ];
              final start = q.indexWhere((t) => t.id == track.id);
              return (
                items: items,
                startIndex: start < 0 ? 0 : start,
              );
            },
          ),
          _LyricsToggle(track: track),
          _FavoriteButton(track: track),
          _QueueButton(
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: theme.colorScheme.surface,
              showDragHandle: true,
              builder: (_) => const _QueueSheet(),
            ),
          ),
        ],
      ),
      body: BackdropBackground(
        item: track,
        child: SafeArea(
          child: LayoutBuilder(
          builder: (context, constraints) {
            // Put the art on the LEFT and the info+transport on the RIGHT when
            // the viewport is wide (TV/desktop) OR short-and-landscape (a phone
            // rotated to landscape), so the vertical stack doesn't overflow into
            // a scroll. Portrait keeps the centered stack.
            final wide = (isTvDevice && constraints.maxWidth >= 840) ||
                (constraints.maxWidth > constraints.maxHeight &&
                    constraints.maxHeight < 500);
            final cover = wide
                ? math
                    .min(constraints.maxWidth * 0.34,
                        constraints.maxHeight - 96)
                    .clamp(160.0, 360.0)
                : math
                    .min(constraints.maxWidth - 56, constraints.maxHeight * 0.46)
                    .clamp(120.0, 420.0);
            final coverWidget =
                _CoverOrLyrics(track: track, player: player, size: cover);
            final infoColumn = Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: wide
                        ? CrossAxisAlignment.stretch
                        : CrossAxisAlignment.center,
                    children: [
                      Text(track.name,
                          textAlign: wide ? TextAlign.start : TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      if (track.artistLine != null)
                        _LinkText(
                          text: track.artistLine!,
                          style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                          onTap: track.artistItems.isNotEmpty
                              ? () {
                                  final a = track.artistItems.first;
                                  context.push('/artist',
                                      extra: BaseItemDto(id: a.id, name: a.name));
                                }
                              : null,
                        ),
                      if (track.album != null && track.album!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: _LinkText(
                            text: track.album!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.7)),
                            onTap: track.albumId != null
                                ? () => context.push('/item',
                                    extra: BaseItemDto(
                                        id: track.albumId!,
                                        name: track.album!,
                                        type: 'MusicAlbum'))
                                : null,
                          ),
                        ),
                      const SizedBox(height: 20),
                      _SeekBar(
                        player: player,
                        onSeek: controller.seek,
                        positionOverride: cast.casting
                            ? Duration(milliseconds: cast.positionMs)
                            : null,
                        durationOverride: cast.casting
                            ? Duration(
                                milliseconds: cast.durationMs > 0
                                    ? cast.durationMs
                                    : ((track.runTimeTicks ?? 0) ~/ 10000))
                            : null,
                      ),
                      const SizedBox(height: 4),
                      // scaleDown, not a bare Stack: the reserved volume slot
                      // below adds real width, and on a narrow phone that can
                      // be more than the available width has room for. This
                      // shrinks the whole control cluster uniformly instead of
                      // overflowing, rather than assuming every device has
                      // enough slack (#40).
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        // Transport in the true center and volume at the right
                        // edge, balanced by an equal gap on the left. The pill
                        // floats over the page when it opens, so it never
                        // shoves the controls or re-centers the page. (An
                        // Align(centerRight) in a Stack here collapsed to the
                        // button's own width inside the FittedBox and sat on
                        // top of Play.)
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!isTvDevice) const SizedBox(width: 48),
                              IconButton(
                            tooltip: AppLocalizations.of(context).browseShuffle,
                            icon: const Icon(Icons.shuffle_rounded),
                            isSelected: audio.shuffle,
                            color: audio.shuffle
                                ? theme.colorScheme.primary
                                : null,
                            onPressed: controller.toggleShuffle,
                          ),
                          IconButton(
                            tooltip: AppLocalizations.of(context).commonPrevious,
                            iconSize: 38,
                            icon: const Icon(Icons.skip_previous_rounded),
                            onPressed: controller.previous,
                          ),
                          if (cast.casting)
                            ControlButton(
                              size: 64,
                              autofocus: isTvDevice,
                              icon: cast.playing
                                  ? Icons.pause_circle_filled_rounded
                                  : Icons.play_circle_fill_rounded,
                              tooltip: cast.playing ? l.commonPause : l.commonPlay,
                              onTap: controller.togglePlay,
                            )
                          else
                            StreamBuilder<bool>(
                              stream: player.stream.playing,
                              initialData: player.state.playing,
                              builder: (context, snap) {
                                final playing = snap.data ?? false;
                                return ControlButton(
                                  size: 64,
                                  autofocus: isTvDevice,
                                  icon: playing
                                      ? Icons.pause_circle_filled_rounded
                                      : Icons.play_circle_fill_rounded,
                                  tooltip: playing ? l.commonPause : l.commonPlay,
                                  onTap: controller.togglePlay,
                                );
                              },
                            ),
                          IconButton(
                            tooltip: AppLocalizations.of(context).commonNext,
                            iconSize: 38,
                            icon: const Icon(Icons.skip_next_rounded),
                            onPressed: controller.next,
                          ),
                          IconButton(
                            tooltip: AppLocalizations.of(context).commonRepeat,
                            icon: Icon(audio.repeat == PlaylistMode.single
                                ? Icons.repeat_one_rounded
                                : Icons.repeat_rounded),
                            isSelected: audio.repeat != PlaylistMode.none,
                            color: audio.repeat != PlaylistMode.none
                                ? theme.colorScheme.primary
                                : null,
                            onPressed: controller.cycleRepeat,
                          ),
                          // No volume on TV, the remote owns it.
                          if (!isTvDevice)
                            VerticalVolumeButton(player: player, floating: true),
                            ],
                          ),
                      ),
                      const SizedBox(height: 12),
                      _UpNextPeek(
                        audio: audio,
                        onTap: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: theme.colorScheme.surface,
                          showDragHandle: true,
                          builder: (_) => const _QueueSheet(),
                        ),
                      ),
                    ],
                  );
            // The 440px cap is a wide (TV) affordance; narrow keeps the original
            // full-width column so desktop/mobile are unchanged.
            final info = wide
                ? ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: infoColumn)
                : infoColumn;
            final content = wide
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      coverWidget,
                      const SizedBox(width: 48),
                      info,
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      coverWidget,
                      const SizedBox(height: 28),
                      info,
                    ],
                  );
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(minHeight: constraints.maxHeight - 44),
                child: Center(child: content),
              ),
            );
          },
        ),
        ),
      ),
    );
  }
}

/// Position slider that follows playback but holds still while dragging.
/// Now Playing for internet radio: station logo, name, live ICY title, and
/// play/stop + volume + cast. No scrubber or skip (it's a live stream).
class _RadioNowPlaying extends ConsumerWidget {
  const _RadioNowPlaying();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final audio = ref.watch(audioControllerProvider);
    final player = ref.watch(audioPlayerProvider);
    final cast = ref.watch(castControllerProvider);
    final s = audio.radioStation;
    if (s == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: scheme.surface,
      // No text field on this screen; see the music Now Playing screen for why
      // this matters (#40).
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(l.radioNowPlaying),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // A live station has no end to stop at, so timed stops only.
          const SleepTimerButton(),
          CastButton(
            videoOnly: false,
            title: s.name,
            resolve: () async => (
              url: s.url,
              contentType: s.url.toLowerCase().contains('.m3u8')
                  ? 'application/x-mpegurl'
                  : 'audio/mpeg',
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // A soft accent-tinted backdrop (a nod to the art without sampling it).
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.alphaBlend(
                        scheme.primary.withValues(alpha: 0.10), scheme.surface),
                    scheme.surface,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(builder: (context, c) {
              // Desktop/TV-wide, OR short-and-landscape (a phone rotated),
              // matching the music Now Playing screen's own threshold, so a
              // phone in landscape reliably gets the wide layout too instead
              // of needing to cross 840 logical pixels on width alone.
              final wide = c.maxWidth >= 840 ||
                  (c.maxWidth > c.maxHeight && c.maxHeight < 500);
              final info = ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child:
                    _info(context, ref, l, audio, player, s, theme, cast, wide),
              );
              // Wide: art on the LEFT, info on the RIGHT, the whole pair centered
              // both ways on screen. Narrow: the same, stacked in a column.
              final content = wide
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _hero(context, ref, player, audio, s, theme, cast, 280),
                        const SizedBox(width: 48),
                        info,
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _hero(context, ref, player, audio, s, theme, cast, 250),
                        const SizedBox(height: 28),
                        info,
                      ],
                    );
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
                child: ConstrainedBox(
                  // Fill the viewport so Center puts the block in the true middle
                  // of the screen; scrolls only if it's ever too tall.
                  constraints: BoxConstraints(minHeight: c.maxHeight - 44),
                  child: Center(child: content),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _hero(BuildContext context, WidgetRef ref, Player player,
      AudioState audio, RadioStation s, ThemeData theme, CastState cast,
      double size) {
    return StreamBuilder<bool>(
      stream: player.stream.playing,
      initialData: player.state.playing,
      builder: (context, snap) {
        final art = audio.radioArtwork;
        final hasArt = art != null && art.isNotEmpty;
        // While casting the local player is paused, so pulse to the cast state.
        final playing = cast.casting ? cast.playing : (snap.data ?? false);
        return _AuraGlow(
          playing: playing,
          borderRadius: 18,
          color: theme.colorScheme.primary,
          child: Container(
            width: size,
            height: size,
            // Album art fills the card; a logo-only station has its logo
            // contained (padded) as the hero itself.
            padding: hasArt ? EdgeInsets.zero : EdgeInsets.all(size * 0.16),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(18),
            ),
            child: hasArt
                ? Image.network(art,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                    // If the resolved art URL fails, drop it so we fall back to
                    // the station logo AND the redundant logo chip disappears.
                    errorBuilder: (context, _, _) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        ref
                            .read(audioControllerProvider.notifier)
                            .clearRadioArtwork(art);
                      });
                      return _radioLogo(theme, s);
                    })
                : _radioLogo(theme, s),
          ),
        );
      },
    );
  }

  Widget _info(BuildContext context, WidgetRef ref, AppLocalizations l,
      AudioState audio, Player player, RadioStation s, ThemeData theme,
      CastState cast, bool wide) {
    final scheme = theme.colorScheme;
    final controller = ref.read(audioControllerProvider.notifier);
    final hasIcy = audio.radioTitle != null && audio.radioTitle!.isNotEmpty;
    final hasArt = audio.radioArtwork != null && audio.radioArtwork!.isNotEmpty;
    const tAlign = TextAlign.center;
    // The landscape alignment (controls centered under the seek bar, volume
    // centered under the LIVE badge) only makes sense once there's an actual
    // seek bar to align against; not yet seekable or casting falls back to
    // the plain stacked composition below, same as narrow/portrait.
    final landscapeAligned = wide && audio.radioSeekable && !cast.casting;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // A small station-logo chip when album art is the hero, so you still
        // know which station you're on. Dropped when the logo IS the hero.
        if (hasArt && s.favicon != null && s.favicon!.isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(s.favicon!,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink()),
          ),
          const SizedBox(height: 12),
        ],
        Text(s.name,
            textAlign: tAlign,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(hasIcy ? audio.radioTitle! : l.radioLiveStream,
            textAlign: tAlign,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 20),
        if (landscapeAligned) ...[
          _RadioScrubBar(
            window: audio.radioWindow,
            behind: audio.radioBehindLive,
            onSeekBehind: controller.radioSeekBehind,
            onGoLive: controller.radioGoLive,
            badgeWidth: _landscapeBadgeSlot,
          ),
          const SizedBox(height: 14),
          _landscapeTransport(
              context, l, audio, controller, player, theme, cast),
        ] else ...[
          // Time-shift only applies to the local buffer, hide it while
          // casting.
          if (!cast.casting) ...[
            _liveRow(context, l, audio, controller, theme),
            const SizedBox(height: 14),
          ],
          _controls(context, l, audio, controller, player, theme, cast),
        ],
      ],
    );
  }

  /// The live status: a scrub bar on seekable streams, otherwise the LIVE pill
  /// (red at the edge) plus a "-M:SS" catch-up when behind.
  Widget _liveRow(BuildContext context, AppLocalizations l, AudioState audio,
      AudioController controller, ThemeData theme) {
    final scheme = theme.colorScheme;
    // Show the scrub bar as soon as the stream is seekable — the same gate the
    // rewind/skip buttons use — so the two never appear out of step. The window
    // starts small and grows; the bar just fills in. The swap eases in (crossfade
    // + height) rather than popping.
    final Widget child;
    if (audio.radioSeekable) {
      child = _RadioScrubBar(
        key: const ValueKey('scrub'),
        window: audio.radioWindow,
        behind: audio.radioBehindLive,
        onSeekBehind: controller.radioSeekBehind,
        onGoLive: controller.radioGoLive,
      );
    } else {
      // Full width (badge centered) so swapping to the equally wide scrub bar
      // only eases the height, not the width.
      child = SizedBox(
        key: const ValueKey('live'),
        width: double.infinity,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!audio.radioAtLive) ...[
              Text('-${_fmtDur(audio.radioBehindLive)}',
                  style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 10),
            ],
            radioLiveBadge(context,
                atLive: audio.radioAtLive, onTap: controller.radioGoLive),
          ],
        ),
      );
    }
    final d =
        reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 320);
    return AnimatedSize(
      duration: d,
      curve: Curves.easeOutCubic,
      child: AnimatedSwitcher(
        duration: d,
        switchInCurve: Curves.easeOut,
        child: child,
      ),
    );
  }

  /// Previous-station / rewind / play / skip / next-station, with no volume
  /// and no outer layout, so both [_controls] (narrow: trails with volume via
  /// a Spacer) and the landscape composition (centered under the seek bar,
  /// volume aligned separately under the LIVE badge) can share it.
  List<Widget> _transportButtons(AppLocalizations l, AudioState audio,
      AudioController controller, Player player, ThemeData theme,
      CastState cast) {
    final scheme = theme.colorScheme;
    // Rewind/skip act on the local buffer, so they're only meaningful when NOT
    // casting.
    final showSeek = audio.radioSeekable && !cast.casting;
    return [
      // Previous/next STATION (distinct from the rewind/skip pair below,
      // which seek within this station's own live buffer).
      IconButton(
        iconSize: 38,
        tooltip: l.radioPreviousStation,
        icon: const Icon(Icons.skip_previous_rounded),
        onPressed: controller.previous,
      ),
      if (showSeek) ...[
        ControlButton(
          icon: Icons.fast_rewind_rounded,
          tooltip: l.radioRewind,
          size: 32,
          grow: false,
          color: scheme.onSurfaceVariant,
          onTap: () => controller.radioSeekBy(const Duration(seconds: -15)),
        ),
        const SizedBox(width: 10),
      ],
      StreamBuilder<bool>(
        stream: player.stream.playing,
        initialData: player.state.playing,
        builder: (context, snap) {
          // While casting the local player is paused; reflect the cast's
          // state (togglePlay already routes to the cast device).
          final playing = cast.casting ? cast.playing : (snap.data ?? false);
          return ControlButton(
            icon: playing
                ? Icons.pause_circle_filled_rounded
                : Icons.play_circle_fill_rounded,
            tooltip: playing ? l.commonPause : l.commonPlay,
            size: 72,
            // TV: land the remote on play/stop when the screen opens, same as
            // the music Now Playing, else nothing has focus and the D-pad
            // appears to do nothing.
            autofocus: isTvDevice,
            onTap: controller.togglePlay,
          );
        },
      ),
      if (showSeek) ...[
        const SizedBox(width: 10),
        ControlButton(
          icon: Icons.fast_forward_rounded,
          tooltip: l.radioSkip,
          size: 32,
          grow: false,
          color: scheme.onSurfaceVariant,
          onTap: () => controller.radioSeekBy(const Duration(seconds: 15)),
        ),
      ],
      IconButton(
        iconSize: 38,
        tooltip: l.radioNextStation,
        icon: const Icon(Icons.skip_next_rounded),
        onPressed: controller.next,
      ),
    ];
  }

  Widget _controls(BuildContext context, AppLocalizations l, AudioState audio,
      AudioController controller, Player player, ThemeData theme,
      CastState cast) {
    // Transport clusters at the LEFT; volume sits at the far RIGHT and opens
    // upward, so it never pushes the transport row off-screen.
    return Row(
      children: [
        ..._transportButtons(l, audio, controller, player, theme, cast),
        const Spacer(),
        // No volume on TV, the remote owns it.
        if (!isTvDevice) VerticalVolumeButton(player: player),
      ],
    );
  }

  /// Landscape composition: the seek bar and the transport row share the same
  /// Expanded-plus-fixed-trailing-slot shape, so the controls land centered
  /// under the seek bar itself (not the LIVE badge beside it), and the volume
  /// button lands centered under the LIVE badge above it. [badgeSlot] is a
  /// fixed width rather than a measured one: exact-matching two independent
  /// rows' intrinsic widths isn't worth the complexity for what's a close
  /// visual approximation either way.
  static const _landscapeBadgeSlot = 72.0;

  Widget _landscapeTransport(BuildContext context, AppLocalizations l,
      AudioState audio, AudioController controller, Player player,
      ThemeData theme, CastState cast) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children:
                  _transportButtons(l, audio, controller, player, theme, cast),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: _landscapeBadgeSlot,
          // No volume on TV, the remote owns it.
          child: isTvDevice
              ? null
              : Center(child: VerticalVolumeButton(player: player)),
        ),
      ],
    );
  }

  /// Station logo (contained) with a radio-icon fallback, used when there's no
  /// per-song album art to show.
  Widget _radioLogo(ThemeData theme, RadioStation s) =>
      s.favicon != null && s.favicon!.isNotEmpty
          ? Image.network(s.favicon!,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => Icon(Icons.radio_rounded,
                  size: 80, color: theme.colorScheme.onSurfaceVariant))
          : Icon(Icons.radio_rounded,
              size: 80, color: theme.colorScheme.onSurfaceVariant);
}

String _fmtDur(Duration d) {
  final s = d.inSeconds.abs();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// The LIVE pill, matching the video player's live badge: solid red at the edge
/// (not tappable), outlined when behind (tap to catch up).
Widget radioLiveBadge(BuildContext context,
    {required bool atLive, VoidCallback? onTap}) {
  final scheme = Theme.of(context).colorScheme;
  final l = AppLocalizations.of(context);
  const red = Color(0xFFE53935);
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: atLive ? null : onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: atLive ? red : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: atLive ? red : scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle,
              size: 7,
              color: atLive
                  ? Colors.white
                  : scheme.onSurfaceVariant.withValues(alpha: 0.6)),
          const SizedBox(width: 5),
          Text(l.playerBadgeLive,
              style: TextStyle(
                  color: atLive ? Colors.white : scheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5)),
        ],
      ),
    ),
  );
}

/// A live time-shift scrub bar: drag to rewind within the buffered window, with
/// the current offset on the left and the LIVE badge (tap to catch up) at right.
class _RadioScrubBar extends StatefulWidget {
  final Duration window;
  final Duration behind;
  final Future<void> Function(Duration behind) onSeekBehind;
  final Future<void> Function() onGoLive;

  /// Reserves this exact width for the LIVE badge (centered within it)
  /// instead of the badge's own intrinsic width, so it lines up with the
  /// same-width volume slot in the landscape transport row beneath it. Null
  /// (the default) keeps the badge at its natural size.
  final double? badgeWidth;
  const _RadioScrubBar({
    super.key,
    required this.window,
    required this.behind,
    required this.onSeekBehind,
    required this.onGoLive,
    this.badgeWidth,
  });

  @override
  State<_RadioScrubBar> createState() => _RadioScrubBarState();
}

class _RadioScrubBarState extends State<_RadioScrubBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final w = widget.window.inSeconds.clamp(1, 1 << 30).toDouble();
    // 0 = oldest buffered, 1 = live edge.
    final value =
        _drag ?? (1 - (widget.behind.inSeconds / w)).clamp(0.0, 1.0);
    final atLive = _drag == null && widget.behind.inMilliseconds < 2500;
    final badge = radioLiveBadge(context, atLive: atLive, onTap: widget.onGoLive);
    // Seek bar and the LIVE badge on one row, to its right, like the video
    // player's transport bar.
    return Row(
      children: [
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: value,
              onChanged: (v) => setState(() => _drag = v),
              onChangeEnd: (v) {
                setState(() => _drag = null);
                widget.onSeekBehind(Duration(seconds: ((1 - v) * w).round()));
              },
            ),
          ),
        ),
        const SizedBox(width: 10),
        widget.badgeWidth == null
            ? badge
            : SizedBox(width: widget.badgeWidth, child: Center(child: badge)),
      ],
    );
  }
}

/// Wraps the radio logo/art in a soft accent glow that gently pulses while the
/// station is playing (a sound "aura"), still when paused. Honours reduced
/// motion. Mirrors LiftTrace's playing-state art pulse.
class _AuraGlow extends StatefulWidget {
  final bool playing;
  final double borderRadius;
  final Color color;
  final Widget child;
  const _AuraGlow({
    required this.playing,
    required this.borderRadius,
    required this.color,
    required this.child,
  });

  @override
  State<_AuraGlow> createState() => _AuraGlowState();
}

class _AuraGlowState extends State<_AuraGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 3));

  @override
  void initState() {
    super.initState();
    if (widget.playing) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_AuraGlow old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.playing && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Paused (or reduced motion) shows the art with no glow.
    if (!widget.playing || reduceMotion(context)) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.32 * t),
                blurRadius: 34 * t,
                spreadRadius: 7 * t,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SeekBar extends StatefulWidget {
  final Player player;
  final void Function(Duration) onSeek;
  // When set (casting), the bar shows the cast device's position/duration
  // instead of the local player's.
  final Duration? positionOverride;
  final Duration? durationOverride;
  const _SeekBar({
    required this.player,
    required this.onSeek,
    this.positionOverride,
    this.durationOverride,
  });

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: widget.player.stream.position,
      initialData: widget.player.state.position,
      builder: (context, snap) {
        final position =
            widget.positionOverride ?? snap.data ?? Duration.zero;
        final duration =
            widget.durationOverride ?? widget.player.state.duration;
        final maxMs = duration.inMilliseconds.toDouble();
        // Guard: a cast device can report an unknown/zero duration (maxMs <= 0),
        // and clamp(0.0, maxMs) throws when the upper bound is below the lower.
        final posMs = maxMs <= 0
            ? 0.0
            : position.inMilliseconds.toDouble().clamp(0.0, maxMs);
        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                min: 0,
                max: maxMs <= 0 ? 1 : maxMs,
                value: _dragValue ?? (maxMs <= 0 ? 0 : posMs),
                onChanged: maxMs <= 0
                    ? null
                    : (v) => setState(() => _dragValue = v),
                onChangeEnd: (v) {
                  widget.onSeek(Duration(milliseconds: v.round()));
                  setState(() => _dragValue = null);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_fmt(position),
                      style: Theme.of(context).textTheme.bodySmall),
                  Text(_fmt(duration),
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// The up-next queue: reorder, tap to jump, or remove tracks. Reflects the
/// player's real order (so it stays correct after shuffle).
class _QueueSheet extends ConsumerWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final audio = ref.watch(audioControllerProvider);
    final controller = ref.read(audioControllerProvider.notifier);
    final theme = Theme.of(context);
    final currentId = audio.current?.id;

    // A fixed-height sheet (not DraggableScrollableSheet): its internal
    // LayoutBuilder conflicts with ReorderableListView and throws
    // "_RenderLayoutBuilder was mutated" mid-reorder.
    final maxH = MediaQuery.of(context).size.height * 0.7;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(l.playerUpNext,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: audio.queue.length,
                // ignore: deprecated_member_use
                onReorder: controller.moveQueue,
                itemBuilder: (context, i) {
                  final t = audio.queue[i];
                  final isCurrent = t.id == currentId;
                  return dragAnywhere(
                    key: ValueKey('${t.id}_$i'),
                    index: i,
                    child: ListTile(
                    onTap: () {
                      controller.jumpTo(i);
                      Navigator.of(context).pop();
                    },
                    leading: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.drag_indicator, color: dragGripColor(context)),
                        const SizedBox(width: 6),
                        isCurrent
                            ? Icon(Icons.equalizer_rounded,
                                color: theme.colorScheme.primary)
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: MediaImage(
                                      item: t,
                                      placeholderIcon:
                                          Icons.music_note_rounded),
                                ),
                              ),
                      ],
                    ),
                    title: Text(t.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight:
                              isCurrent ? FontWeight.w700 : FontWeight.w500,
                          color: isCurrent ? theme.colorScheme.primary : null,
                        )),
                    subtitle: t.artistLine != null
                        ? Text(t.artistLine!,
                            maxLines: 1, overflow: TextOverflow.ellipsis)
                        : null,
                    // The whole row is draggable (long-press / press-drag), so a
                    // single Remove action is all that's needed here.
                    trailing: IconButton(
                      tooltip: l.commonRemove,
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => controller.removeAt(i),
                    ),
                  ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The queue button, with a quick press-in / elastic spring-back bump so the
/// tap feels tactile (no highlight), then opens the queue sheet.
class _QueueButton extends StatefulWidget {
  final VoidCallback onTap;
  const _QueueButton({required this.onTap});

  @override
  State<_QueueButton> createState() => _QueueButtonState();
}

class _QueueButtonState extends State<_QueueButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 340));
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
        tween:
            Tween(begin: 1.0, end: 0.8).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40),
    TweenSequenceItem(
        tween: Tween(begin: 0.8, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 60),
  ]).animate(_c);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: AppLocalizations.of(context).playerQueue,
      icon: ScaleTransition(
          scale: _scale, child: const Icon(Icons.queue_music_rounded)),
      onPressed: () {
        if (!reduceMotion(context)) _c.forward(from: 0);
        widget.onTap();
      },
    );
  }
}

/// Heart toggle for the current track. Optimistic + resets when the track
/// changes, since the audio queue items aren't backed by a refreshable provider.
class _FavoriteButton extends ConsumerStatefulWidget {
  final BaseItemDto track;
  const _FavoriteButton({required this.track});

  @override
  ConsumerState<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends ConsumerState<_FavoriteButton>
    with SingleTickerProviderStateMixin {
  late bool _fav = widget.track.userData.isFavorite;
  late String _forId = widget.track.id;

  late final AnimationController _pop = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 460));
  // A quick swell then an elastic settle: the heart gives a little beat the
  // moment you favourite a track.
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
        tween:
            Tween(begin: 1.0, end: 1.4).chain(CurveTween(curve: Curves.easeOut)),
        weight: 35),
    TweenSequenceItem(
        tween: Tween(begin: 1.4, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 65),
  ]).animate(_pop);

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Follow track changes without losing an in-flight optimistic toggle.
    if (widget.track.id != _forId) {
      _forId = widget.track.id;
      _fav = widget.track.userData.isFavorite;
    }
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return ScaleTransition(
      scale: _scale,
      child: IconButton(
        tooltip: _fav ? l.playerRemoveFavorite : l.playerAddFavorite,
        color: _fav ? scheme.primary : null,
        // The glyph itself swaps with a soft scale/fade so the fill "blooms" in.
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          transitionBuilder: (child, anim) => ScaleTransition(
              scale: anim, child: FadeTransition(opacity: anim, child: child)),
          child: Icon(
            _fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            key: ValueKey(_fav),
          ),
        ),
        onPressed: () async {
          final session = ref.read(sessionControllerProvider).asData?.value;
          if (session == null) return;
          final next = !_fav;
          setState(() => _fav = next);
          if (next && !reduceMotion(context)) _pop.forward(from: 0);
          try {
            await ref.read(jellyfinClientProvider).setFavorite(
                  baseUrl: session.baseUrl,
                  userId: session.userId,
                  token: session.accessToken,
                  itemId: widget.track.id,
                  favorite: next,
                );
          } catch (_) {
            if (mounted) setState(() => _fav = !next);
          }
        },
      ),
    );
  }
}

/// A compact "Up Next" pill showing the following track; opens the full queue.
class _UpNextPeek extends StatelessWidget {
  final AudioState audio;
  final VoidCallback onTap;
  const _UpNextPeek({required this.audio, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final currentId = audio.current?.id;
    final idx = currentId == null
        ? -1
        : audio.queue.indexWhere((t) => t.id == currentId);
    if (idx < 0) return const SizedBox.shrink();
    // On the last song there's nothing next, but the row keeps its place
    // (unseen, and no stop for a remote or the Tab key): taking it away let
    // the controls above drop down as the page centered itself again.
    final hasNext = idx + 1 < audio.queue.length;
    final nextTrack = audio.queue[hasNext ? idx + 1 : idx];
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Visibility(
      visible: hasNext,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      child: ExcludeFocus(
        excluding: !hasNext,
        child: _peek(context, l, theme, nextTrack),
      ),
    );
  }

  Widget _peek(BuildContext context, AppLocalizations l, ThemeData theme,
      BaseItemDto nextTrack) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Material(
        color: theme.colorScheme.surface.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: MediaImage(
                        item: nextTrack,
                        placeholderIcon: Icons.music_note_rounded),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l.playerUpNext,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          )),
                      const SizedBox(height: 2),
                      Text(nextTrack.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const Icon(Icons.queue_music_rounded, size: 20),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Centered text that reads as a link and becomes tappable when [onTap] is set,
/// otherwise renders as plain text (e.g. an artist with no navigable id).
class _LinkText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final VoidCallback? onTap;
  const _LinkText({required this.text, this.style, this.onTap});

  @override
  Widget build(BuildContext context) {
    final child = Text(text,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style);
    if (onTap == null) return child;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: child,
      ),
    );
  }
}

/// The app-bar button that flips between artwork and lyrics.
///
/// Only present when the track actually has lyrics, so it never offers a view
/// that would just say "no lyrics".
class _LyricsToggle extends ConsumerWidget {
  final BaseItemDto track;
  const _LyricsToggle({required this.track});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyrics = ref.watch(lyricsProvider(lyricsKeyFor(track))).asData?.value;
    if (lyrics == null || lyrics.isEmpty) return const SizedBox.shrink();

    final auto = ref.watch(preferencesProvider).asData?.value
            .showLyricsAutomatically ??
        true;
    final showing = ref.watch(showingLyricsProvider) ?? auto;

    return IconButton(
      tooltip: showing
          ? AppLocalizations.of(context).playerShowArtwork
          : AppLocalizations.of(context).playerShowLyrics,
      color: showing ? Theme.of(context).colorScheme.primary : null,
      // The glyph rotates/fades as it swaps, echoing the artwork flip it drives.
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: RotationTransition(
            turns: Tween<double>(begin: 0.6, end: 1.0).animate(anim),
            child: child,
          ),
        ),
        child: Icon(showing ? Icons.image_rounded : Icons.lyrics_rounded,
            key: ValueKey(showing)),
      ),
      onPressed: () => ref.read(showingLyricsProvider.notifier).set(!showing),
    );
  }
}

/// The cover, or the lyrics occupying the same square.
class _CoverOrLyrics extends ConsumerWidget {
  final BaseItemDto track;
  final Player player;
  final double size;

  const _CoverOrLyrics({
    required this.track,
    required this.player,
    required this.size,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyrics = ref.watch(lyricsProvider(lyricsKeyFor(track))).asData?.value;
    final hasLyrics = lyrics != null && !lyrics.isEmpty;

    final auto = ref.watch(preferencesProvider).asData?.value
            .showLyricsAutomatically ??
        true;
    final showing = hasLyrics && (ref.watch(showingLyricsProvider) ?? auto);

    final art = Hero(
      tag: 'nowPlayingArt',
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 40,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            width: size,
            height: size,
            child: MediaImage(
                item: track, placeholderIcon: Icons.music_note_rounded),
          ),
        ),
      ),
    );

    final lyricsFace = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasLyrics ? LyricsView(lyrics: lyrics, player: player) : null,
    );

    // Turn the square over like a record sleeve to reveal the lyrics.
    return reduceMotion(context)
        ? (showing ? lyricsFace : art)
        : _FlipCard(showBack: showing, front: art, back: lyricsFace);
  }
}

/// A Y-axis card flip between two same-size faces. Toggling [showBack] animates
/// a half-turn, swapping faces at the midpoint (and un-mirroring the back), so
/// it reads as physically flipping the artwork over to the lyrics and back.
class _FlipCard extends StatelessWidget {
  final bool showBack;
  final Widget front;
  final Widget back;
  const _FlipCard({
    required this.showBack,
    required this.front,
    required this.back,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: showBack ? 1 : 0),
      duration: const Duration(milliseconds: 460),
      curve: Curves.easeInOutCubic,
      builder: (context, t, _) {
        final showingBack = t >= 0.5;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012) // a little perspective
            ..rotateY(t * math.pi),
          child: showingBack
              ? Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(math.pi),
                  child: back,
                )
              : front,
        );
      },
    );
  }
}

/// Full-screen controls for background YouTube audio: the video's thumbnail,
/// title and channel, a scrub bar, transport, and Stop (leaves the mode). It's a
/// seekable track, so unlike radio it has a real progress bar and skip.
class _YoutubeNowPlaying extends ConsumerWidget {
  const _YoutubeNowPlaying();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final audio = ref.watch(audioControllerProvider);
    final controller = ref.read(audioControllerProvider.notifier);
    final player = ref.watch(audioPlayerProvider);
    final scheme = Theme.of(context).colorScheme;
    final item = audio.ytCurrent;
    if (item == null) {
      return Scaffold(
          appBar: AppBar(),
          body: Center(child: Text(l.playerNothingPlaying)));
    }
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      // No text field on this screen; see the music Now Playing screen for why
      // this matters (#40).
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(l.playerNowPlaying),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          SleepTimerButton(endOfItemLabel: l.sleepTimerEndOfTrack),
          // Round-trip back to video: reopen the watch page at the current audio
          // position (persisted to history so the player resumes there), and
          // leave audio mode.
          IconButton(
            tooltip: l.ytWatchVideo,
            icon: const Icon(Icons.ondemand_video_rounded),
            onPressed: () async {
              final router = GoRouter.of(context);
              await ref.read(youtubeHistoryProvider.notifier).record(
                    videoId: item.videoId,
                    title: item.title,
                    author: item.author,
                    position: player.state.position,
                    duration: player.state.duration,
                    now: DateTime.now(),
                  );
              await controller.stopYoutubeAudio();
              // Swap this Now Playing route for the watch page (a plain
              // Navigator pop + GoRouter push races and lands nowhere).
              router.pushReplacement('/youtube/watch',
                  extra: (videoId: item.videoId, title: item.title));
            },
          ),
          Consumer(builder: (context, ref, _) {
            final upNext = ref.watch(youtubeQueueProvider);
            if (upNext.isEmpty) return const SizedBox.shrink();
            return IconButton(
              tooltip: l.ytUpNext,
              icon: Badge(
                label: Text('${upNext.length}'),
                child: const Icon(Icons.queue_music_rounded),
              ),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => const _YtQueueSheet(),
              ),
            );
          }),
          TextButton.icon(
            icon: const Icon(Icons.stop_rounded),
            label: Text(l.radioStop),
            onPressed: () {
              controller.stopYoutubeAudio();
              Navigator.of(context).maybePop();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          // Landscape on a phone is short: a full-width 16:9 thumbnail would
          // swallow the viewport and push the transport off the bottom. So put
          // the art beside the controls when it's wider than it is tall, and
          // keep the vertical stack in portrait.
          final landscape = c.maxWidth > c.maxHeight;
          final accent = Theme.of(context).colorScheme.primary;
          final artImage = ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(
              // A crisp thumbnail for the big now-playing art. maxres 404s on
              // some videos, so fall back to the item's own (medium) thumbnail,
              // then to an icon.
              'https://i.ytimg.com/vi/${item.videoId}/maxresdefault.jpg',
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Image.network(
                item.thumbnailUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => ColoredBox(
                  color: scheme.surfaceContainerHighest,
                  child: Icon(Icons.headset_rounded,
                      size: 64, color: scheme.onSurfaceVariant),
                ),
              ),
            ),
          );
          // The same soft accent glow radio uses, pulsing while it plays.
          final art = StreamBuilder<bool>(
            stream: player.stream.playing,
            initialData: player.state.playing,
            builder: (context, snap) => _AuraGlow(
              playing: snap.data ?? false,
              borderRadius: 16,
              color: accent,
              child: artImage,
            ),
          );
          final info = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(item.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 20),
              _YtScrub(player: player),
              const SizedBox(height: 8),
              // scaleDown so the controls shrink together rather than
              // overflowing on a narrow phone, matching the music layout (#40).
              FittedBox(
                fit: BoxFit.scaleDown,
                // Transport in the true center and volume at the right edge,
                // balanced by an equal gap on the left, exactly as the music
                // layout does it. This was a Stack with an Align(centerRight),
                // which inside a FittedBox collapses to the button's own width
                // and sits on top of Play.
                child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isTvDevice) const SizedBox(width: 48),
                      IconButton(
                        tooltip: AppLocalizations.of(context).browseShuffle,
                        icon: const Icon(Icons.shuffle_rounded),
                        isSelected: audio.shuffle,
                        color: audio.shuffle ? scheme.primary : null,
                        onPressed: controller.toggleShuffle,
                      ),
                      IconButton(
                        tooltip: AppLocalizations.of(context).commonPrevious,
                        iconSize: 36,
                        icon: const Icon(Icons.skip_previous_rounded),
                        onPressed: controller.previous,
                      ),
                      const SizedBox(width: 8),
                      StreamBuilder<bool>(
                        stream: player.stream.playing,
                        initialData: player.state.playing,
                        builder: (context, snap) {
                          final playing = snap.data ?? false;
                          return IconButton(
                            tooltip: playing ? AppLocalizations.of(context).commonPause : AppLocalizations.of(context).commonPlay,
                            iconSize: 68,
                            icon: Icon(playing
                                ? Icons.pause_circle_filled_rounded
                                : Icons.play_circle_fill_rounded),
                            onPressed: controller.togglePlay,
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: AppLocalizations.of(context).commonNext,
                        iconSize: 36,
                        icon: const Icon(Icons.skip_next_rounded),
                        onPressed: controller.next,
                      ),
                      IconButton(
                        tooltip: AppLocalizations.of(context).commonRepeat,
                        icon: Icon(audio.repeat == PlaylistMode.single
                            ? Icons.repeat_one_rounded
                            : Icons.repeat_rounded),
                        isSelected: audio.repeat != PlaylistMode.none,
                        color: audio.repeat != PlaylistMode.none
                            ? scheme.primary
                            : null,
                        onPressed: controller.cycleRepeat,
                      ),
                      // No volume on TV, the remote owns it.
                      if (!isTvDevice)
                        VerticalVolumeButton(player: player, floating: true),
                    ],
                  ),
              ),
            ],
          );

          if (landscape) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 5,
                    child: Center(
                      child: AspectRatio(aspectRatio: 16 / 9, child: art),
                    ),
                  ),
                  const SizedBox(width: 28),
                  Expanded(
                    flex: 5,
                    child: Center(child: SingleChildScrollView(child: info)),
                  ),
                ],
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const Spacer(),
                AspectRatio(aspectRatio: 16 / 9, child: art),
                const SizedBox(height: 24),
                info,
                const Spacer(),
              ],
            ),
          );
        }),
      ),
    );
  }
}

/// A seek bar for the YouTube-audio now-playing screen, bound to the audio
/// player's position/duration.
class _YtScrub extends StatefulWidget {
  final Player player;
  const _YtScrub({required this.player});

  @override
  State<_YtScrub> createState() => _YtScrubState();
}

class _YtScrubState extends State<_YtScrub> {
  double? _drag;

  static String _fmt(Duration d) {
    final h = d.inHours;
    final mm = (d.inMinutes % 60).toString().padLeft(h > 0 ? 2 : 1, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return StreamBuilder<Duration>(
      stream: widget.player.stream.position,
      initialData: widget.player.state.position,
      builder: (context, snap) {
        final dur = widget.player.state.duration;
        final durMs = dur.inMilliseconds;
        final pos = snap.data ?? Duration.zero;
        final frac = _drag ??
            (durMs > 0 ? (pos.inMilliseconds / durMs).clamp(0.0, 1.0) : 0.0);
        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 14),
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: Slider(
                value: frac,
                onChanged: (v) => setState(() => _drag = v),
                onChangeEnd: (v) {
                  if (durMs > 0) widget.player.seek(dur * v);
                  setState(() => _drag = null);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_fmt(durMs > 0 ? dur * frac : pos), style: style),
                  Text(_fmt(dur), style: style),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The shared YouTube up-next queue, shown from the background-audio Now Playing.
/// It's the SAME youtubeQueueProvider the video player uses — tap to jump, drag
/// to reorder, swipe/remove to drop.
class _YtQueueSheet extends ConsumerWidget {
  const _YtQueueSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final queue = ref.watch(youtubeQueueProvider);
    final qn = ref.read(youtubeQueueProvider.notifier);
    final audio = ref.read(audioControllerProvider.notifier);
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
            child: Row(
              children: [
                Text(l.ytUpNext,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                if (queue.isNotEmpty)
                  TextButton(
                    onPressed: qn.clear,
                    child: Text(l.commonClear),
                  ),
              ],
            ),
          ),
          if (queue.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              child: Text(l.ytQueueEmpty,
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            )
          else
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                itemCount: queue.length,
                // onReorderItem, not the deprecated onReorder: reorder()
                // removes the item and then inserts at the index it's given,
                // so it needs the index with the lifted item already accounted
                // for. onReorder passes the pre-removal one, which dropped a
                // video dragged downwards one slot too far.
                onReorderItem: qn.reorder,
                itemBuilder: (context, i) {
                  final v = queue[i];
                  return ListTile(
                    key: ValueKey(v.id),
                    contentPadding: const EdgeInsets.only(left: 16, right: 4),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 56,
                        height: 40,
                        child: Image.network(v.thumbnailUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => ColoredBox(
                                color: scheme.surfaceContainerHighest)),
                      ),
                    ),
                    title: Text(v.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(v.author,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () {
                      // Jump: play the tapped item now, keep the rest as up-next.
                      qn.playAll(queue.sublist(i + 1));
                      audio.playYoutubeAudio(YoutubeAudioItem(
                        videoId: v.id,
                        title: v.title,
                        author: v.author,
                        thumbnailUrl: v.thumbnailUrl,
                        duration: v.duration,
                      ));
                      Navigator.of(context).maybePop();
                    },
                    trailing: IconButton(
                      tooltip: AppLocalizations.of(context).commonRemove,
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => qn.remove(v.id),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
