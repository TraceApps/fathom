import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../api/error_text.dart';
import '../api/mdblist_client.dart';
import '../state/arr_providers.dart';
import '../state/interface_scale.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/shared_files.dart';
import '../services/image_cache.dart';
import '../services/tv_mode.dart';
import '../state/preferences.dart';
import '../widgets/page_width.dart';
import '../widgets/app_dropdown.dart';
import '../widgets/score_pills.dart';
import '../widgets/tv_focus.dart';
import '../widgets/ui_common.dart';
import '../state/youtube_providers.dart';
import '../services/youtube_download.dart';
import '../services/sponsorblock.dart';
import '../services/track_languages.dart';
import '../widgets/app_snack.dart';
import '../widgets/app_spinner.dart';
import '../widgets/error_view.dart';

// One list, shared with the player's online subtitle search (track_languages),
// so the same codes and the same order appear everywhere.
Map<String, String> _languages(AppLocalizations l) => {
      '': l.prefsLanguageServerDefault,
      ...trackLanguages(l),
    };

Map<String, String> _subtitleLanguages(AppLocalizations l) => {
      '': l.prefsNone,
      ...trackLanguages(l),
    };

const _accentColors = [
  0xFF6C8CFF, // indigo (default)
  0xFF7C4DFF, // deep purple
  0xFFB388FF, // lilac
  0xFF448AFF, // blue
  0xFF00B0FF, // sky
  0xFF26C6DA, // cyan
  0xFF00BFA5, // teal
  0xFF1DE9B6, // aqua
  0xFF00C853, // green
  0xFF66BB6A, // light green
  0xFFC6FF00, // lime
  0xFFFFD600, // yellow
  0xFFFFB300, // amber
  0xFFFF7043, // deep orange
  0xFFFF5252, // red
  0xFFEC407A, // pink
  0xFFF06292, // rose
  0xFFD500F9, // magenta
  0xFF8D6E63, // brown
  0xFF90A4AE, // slate
];

Map<int, String> _bitrates(AppLocalizations l) => {
      0: l.prefsBitrateAutoMax,
      20: '20 Mbps (1080p)',
      10: '10 Mbps (720p)',
      4: '4 Mbps (480p)',
      2: l.prefsBitrate2Mobile,
    };

String _sectionTitle(AppLocalizations l, String section) => switch (section) {
      'general' => l.prefsSectionGeneral,
      'appearance' => l.prefsSectionAppearance,
      'home' => l.prefsSectionHome,
      'player' => l.prefsSectionPlayer,
      'audio' => l.prefsSectionAudio,
      'ratings' => l.prefsSectionRatings,
      'youtube' => l.prefsSectionYoutube,
      _ => l.prefsSettingsFallback,
    };

/// A single settings category, driven by [section].
class PreferencesScreen extends ConsumerWidget {
  final String section;
  const PreferencesScreen({super.key, required this.section});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final prefsAsync = ref.watch(preferencesProvider);
    final c = ref.read(preferencesProvider.notifier);
    final title = _sectionTitle(l, section);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: prefsAsync.when(
        loading: () => const Center(child: AppSpinner()),
        error: (e, _) => ErrorView(
          message: errorText(e),
          onRetry: () => ref.invalidate(preferencesProvider),
        ),
        data: (p) => PageWidth(builder: (_, inset) => ListView(
          padding: pageInsets(inset, const EdgeInsets.symmetric(vertical: 8)),
          children: switch (section) {
            'general' => _general(
              context,
              p,
              c,
              // Sonarr, Radarr or Lidarr: what the notifications watch.
              manage: ref.watch(arrLibraryKindsProvider).isNotEmpty,
            ),
            'appearance' => _appearance(context, p, c),
            'home' => _home(context, p, c),
            'player' => _player(context, p, c),
            'audio' => _audio(context, p, c),
            'ratings' => _ratings(context, p, c),
            'youtube' => _youtube(context, p, c),
            _ => const [],
          },
        )),
      ),
    );
  }

  /// Everything here is YouTube-only, and stays that way. The player controls
  /// are shared with Jellyfin, so anything that would reach across (the seek
  /// amounts especially) is passed to the YouTube player alone rather than
  /// changed in the shared widget.
  List<Widget> _youtube(
      BuildContext context, Prefs p, PreferencesController c) {
    final l = AppLocalizations.of(context);
    if (!p.youtubeEnabled) {
      return [
        SwitchListTile(
          secondary: const Icon(Icons.smart_display_rounded),
          title: Text(l.prefsYtEnable),
          subtitle: Text(l.prefsYtEnableSub),
          value: p.youtubeEnabled,
          onChanged: (v) => c.edit((x) => x.copyWith(youtubeEnabled: v)),
        ),
      ];
    }

    return [
      SwitchListTile(
        secondary: const Icon(Icons.smart_display_rounded),
        title: Text(l.prefsYtEnable),
        subtitle: Text(l.prefsYtEnableSub),
        value: p.youtubeEnabled,
        onChanged: (v) => c.edit((x) => x.copyWith(youtubeEnabled: v)),
      ),

      SettingsSectionHeader(l.prefsHeaderPlayback),
      SwitchListTile(
        secondary: const Icon(Icons.playlist_play_rounded),
        title: Text(l.prefsYtAutoplay),
        subtitle: Text(l.prefsYtAutoplaySub),
        value: p.youtubeAutoplay,
        onChanged: (v) => c.edit((x) => x.copyWith(youtubeAutoplay: v)),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.thumb_down_outlined),
        title: Text(l.prefsYtShowDislikes),
        subtitle: Text(l.prefsYtShowDislikesSub),
        value: p.youtubeReturnDislikes,
        onChanged: (v) => c.edit((x) => x.copyWith(youtubeReturnDislikes: v)),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.title_rounded),
        title: Text(l.prefsYtDeArrow),
        subtitle: Text(l.prefsYtDeArrowSub),
        value: p.youtubeDeArrow,
        onChanged: (v) => c.edit((x) => x.copyWith(youtubeDeArrow: v)),
      ),
      ListTile(
        leading: const Icon(Icons.high_quality_rounded),
        title: Text(l.prefsYtDefaultQuality),
        subtitle: Text(l.prefsYtDefaultQualitySub),
        trailing: _Dropdown(
          value: p.youtubeQuality,
          options: {
            'auto': l.prefsQualityAuto,
            '2160': '2160p (4K)',
            '1440': '1440p',
            '1080': '1080p',
            '720': '720p',
            '480': '480p',
            '360': '360p',
          },
          onChanged: (v) => c.edit((x) => x.copyWith(youtubeQuality: v)),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.replay_10_rounded),
        title: Text(l.prefsYtSkipBack),
        subtitle: Text(l.prefsYtSkipBackSub),
        trailing: _Dropdown(
          value: '${p.youtubeSeekBackSeconds}',
          options: {
            '5': l.prefsSeconds(5),
            '10': l.prefsSeconds(10),
            '15': l.prefsSeconds(15),
            '20': l.prefsSeconds(20),
            '30': l.prefsSeconds(30),
          },
          onChanged: (v) => c.edit(
              (x) => x.copyWith(youtubeSeekBackSeconds: int.parse(v))),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.forward_30_rounded),
        title: Text(l.prefsYtSkipForward),
        subtitle: Text(l.prefsYtSkipForwardSub),
        trailing: _Dropdown(
          value: '${p.youtubeSeekForwardSeconds}',
          options: {
            '5': l.prefsSeconds(5),
            '10': l.prefsSeconds(10),
            '15': l.prefsSeconds(15),
            '20': l.prefsSeconds(20),
            '30': l.prefsSeconds(30),
            '60': l.prefsSeconds(60),
          },
          onChanged: (v) => c.edit(
              (x) => x.copyWith(youtubeSeekForwardSeconds: int.parse(v))),
        ),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.help_outline_rounded),
        title: Text(l.prefsYtConfirmClearQueue),
        value: p.youtubeConfirmClearQueue,
        onChanged: (v) =>
            c.edit((x) => x.copyWith(youtubeConfirmClearQueue: v)),
      ),

      SettingsSectionHeader(l.prefsHeaderBrowsing),
      ListTile(
        leading: const Icon(Icons.view_list_rounded),
        title: Text(l.prefsYtListMode),
        subtitle: Text(l.prefsYtListModeSub),
        trailing: _Dropdown(
          value: p.youtubeListMode,
          options: {'list': l.prefsListModeList, 'grid': l.prefsListModeGrid},
          onChanged: (v) => c.edit((x) => x.copyWith(youtubeListMode: v)),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.image_rounded),
        title: Text(l.prefsYtThumbnailQuality),
        subtitle: Text(l.prefsYtThumbnailQualitySub),
        trailing: _Dropdown(
          value: p.youtubeThumbnailQuality,
          options: {
            'low': l.prefsQualityLow,
            'medium': l.prefsQualityMedium,
            'high': l.prefsQualityHigh,
            'max': l.prefsQualityMaximum,
          },
          onChanged: (v) =>
              c.edit((x) => x.copyWith(youtubeThumbnailQuality: v)),
        ),
      ),

      SettingsSectionHeader(l.prefsHeaderDownloads),
      const _YoutubeDownloadFolders(),
      ListTile(
        leading: const Icon(Icons.download_rounded),
        title: Text(l.prefsYtDownloadQuality),
        subtitle: Text(l.prefsYtDownloadQualitySub),
        trailing: _Dropdown(
          value: p.youtubeDownloadQuality,
          options: {
            'ask': l.prefsAskEachTime,
            '2160': '2160p (4K)',
            '1440': '1440p',
            '1080': '1080p',
            '720': '720p',
            '480': '480p',
            '360': '360p',
            'audio': l.prefsYtDownloadAudioM4a,
            'mp3-320': 'MP3 (320 kbps)',
            'mp3-256': 'MP3 (256 kbps)',
            'mp3-192': 'MP3 (192 kbps)',
            'mp3-128': 'MP3 (128 kbps)',
          },
          onChanged: (v) =>
              c.edit((x) => x.copyWith(youtubeDownloadQuality: v)),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.movie_creation_outlined),
        title: Text(l.prefsYtVideoContainer),
        subtitle: Text(l.prefsYtVideoContainerSub),
        trailing: _Dropdown(
          value: p.youtubeVideoContainer,
          options: const {'mp4': 'MP4', 'mkv': 'MKV'},
          onChanged: (v) =>
              c.edit((x) => x.copyWith(youtubeVideoContainer: v)),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.refresh_rounded),
        title: Text(l.prefsYtRetries),
        subtitle: Text(l.prefsYtRetriesSub),
        trailing: _Dropdown(
          value: '${p.youtubeDownloadRetries}',
          options: const {'1': '1', '3': '3', '5': '5', '10': '10'},
          onChanged: (v) =>
              c.edit((x) => x.copyWith(youtubeDownloadRetries: int.parse(v))),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.layers_rounded),
        title: Text(l.prefsYtSimultaneous),
        subtitle: Text(l.prefsYtSimultaneousSub),
        trailing: _Dropdown(
          value: '${p.youtubeMaxConcurrentDownloads}',
          options: const {'1': '1', '2': '2', '3': '3', '5': '5'},
          onChanged: (v) => c.edit(
              (x) => x.copyWith(youtubeMaxConcurrentDownloads: int.parse(v))),
        ),
      ),

      SettingsSectionHeader(l.prefsHeaderContent),
      ListTile(
        leading: const Icon(Icons.translate_rounded),
        title: Text(l.prefsYtContentLanguage),
        subtitle: Text(l.prefsYtContentLanguageSub),
        trailing: _Dropdown(
          value: p.youtubeContentLanguage,
          options: {
            'en': l.prefsLanguageEnglish,
            'es': 'Español',
            'fr': 'Français',
            'de': 'Deutsch',
            'it': 'Italiano',
            'pt': 'Português',
            'nl': 'Nederlands',
            'pl': 'Polski',
            'ru': 'Русский',
            'ja': '日本語',
            'ko': '한국어',
            'zh': '中文',
          },
          onChanged: (v) =>
              c.edit((x) => x.copyWith(youtubeContentLanguage: v)),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.public_rounded),
        title: Text(l.prefsYtContentCountry),
        subtitle: Text(l.prefsYtContentCountrySub),
        trailing: _Dropdown(
          value: p.youtubeContentCountry,
          options: const {
            'US': 'United States',
            'GB': 'United Kingdom',
            'CA': 'Canada',
            'AU': 'Australia',
            'IE': 'Ireland',
            'DE': 'Germany',
            'FR': 'France',
            'ES': 'Spain',
            'IT': 'Italy',
            'NL': 'Netherlands',
            'BR': 'Brazil',
            'MX': 'Mexico',
            'IN': 'India',
            'JP': 'Japan',
            'KR': 'South Korea',
          },
          onChanged: (v) =>
              c.edit((x) => x.copyWith(youtubeContentCountry: v)),
        ),
      ),

      SwitchListTile(
        secondary: const Icon(Icons.shield_outlined),
        title: Text(l.prefsYtRestrictedMode),
        subtitle: Text(l.prefsYtRestrictedModeSub),
        value: p.youtubeRestrictedMode,
        onChanged: (v) => c.edit((x) => x.copyWith(youtubeRestrictedMode: v)),
      ),

      const SettingsSectionHeader('SponsorBlock'),
      const _SponsorBlockSettings(),

      SettingsSectionHeader(l.prefsHeaderWatchPage),
      SwitchListTile(
        secondary: const Icon(Icons.comment_outlined),
        title: Text(l.prefsYtShowComments),
        value: p.youtubeShowComments,
        onChanged: (v) => c.edit((x) => x.copyWith(youtubeShowComments: v)),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.playlist_play_rounded),
        title: Text(l.prefsYtShowUpNext),
        subtitle: Text(l.prefsYtShowUpNextSub),
        value: p.youtubeShowRelated,
        onChanged: (v) => c.edit((x) => x.copyWith(youtubeShowRelated: v)),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.notes_rounded),
        title: Text(l.prefsYtShowDescription),
        value: p.youtubeShowDescription,
        onChanged: (v) => c.edit((x) => x.copyWith(youtubeShowDescription: v)),
      ),

      SettingsSectionHeader(l.prefsHeaderHistory),
      SwitchListTile(
        secondary: const Icon(Icons.history_rounded),
        title: Text(l.prefsYtKeepWatchHistory),
        subtitle: Text(l.prefsYtKeepWatchHistorySub),
        value: p.youtubeKeepWatchHistory,
        onChanged: (v) => c.edit((x) => x.copyWith(youtubeKeepWatchHistory: v)),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.play_circle_outline_rounded),
        title: Text(l.prefsYtResumePlayback),
        subtitle: Text(l.prefsYtResumePlaybackSub),
        // The resume position is stored with the watch history, so this can't
        // work without it. Disabled rather than hidden, so the reason is
        // visible instead of the row silently vanishing.
        value: p.youtubeResumePlayback && p.youtubeKeepWatchHistory,
        onChanged: p.youtubeKeepWatchHistory
            ? (v) => c.edit((x) => x.copyWith(youtubeResumePlayback: v))
            : null,
      ),
      SwitchListTile(
        secondary: const Icon(Icons.manage_search_rounded),
        title: Text(l.prefsYtKeepSearchHistory),
        value: p.youtubeKeepSearchHistory,
        onChanged: (v) =>
            c.edit((x) => x.copyWith(youtubeKeepSearchHistory: v)),
      ),
      const _YoutubeClearData(),

      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Text(
          l.prefsYtInfoParagraph,
          style: const TextStyle(fontSize: 12.5, height: 1.4),
        ),
      ),
    ];
  }

  List<Widget> _ratings(
      BuildContext context, Prefs p, PreferencesController c) {
    final l = AppLocalizations.of(context);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        child: Text(
          l.prefsRatingsIntro,
          style: const TextStyle(fontSize: 13),
        ),
      ),
      SwitchListTile(
        secondary: const Text('🍅', style: TextStyle(fontSize: 20)),
        title: Text(l.prefsRtCritics),
        value: p.showRtCritics,
        onChanged: (v) => c.edit((x) => x.copyWith(showRtCritics: v)),
      ),
      SwitchListTile(
        secondary: const Text('🍿', style: TextStyle(fontSize: 20)),
        title: Text(l.prefsRtAudience),
        value: p.showRtAudience,
        onChanged: (v) => c.edit((x) => x.copyWith(showRtAudience: v)),
      ),
      SwitchListTile(
        secondary: const SizedBox(
            width: 40, child: Center(child: ImdbLogo())),
        title: Text(l.prefsImdbRating),
        value: p.showImdbRating,
        onChanged: (v) => c.edit((x) => x.copyWith(showImdbRating: v)),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.star_rounded, color: Colors.amber),
        title: Text(l.prefsCommunityScore),
        subtitle: Text(l.prefsCommunityScoreSub),
        value: p.showCommunityRating,
        onChanged: (v) => c.edit((x) => x.copyWith(showCommunityRating: v)),
      ),
      SettingsSectionHeader(l.prefsHeaderMoreRatings),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Text(
          l.prefsMdbListIntro,
          style: const TextStyle(fontSize: 13),
        ),
      ),
      // The key is a connection like the others: its page tests it.
      ListTile(
        leading: const SizedBox(
          width: 40,
          child: Center(child: Icon(Icons.star_rounded)),
        ),
        title: Text(
          p.mdbListApiKey.isEmpty ? l.prefsMdbConnect : MdbListClient.appName,
        ),
        subtitle: Text(
          p.mdbListApiKey.isEmpty
              ? l.prefsMdbConnectSub
              : l.arrStatusConnected,
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push('/connections/mdblist'),
      ),
      _mdbToggle(l, c, p, 'Letterboxd', const LetterboxdLogo(),
          p.showLetterboxd, (v) => p.copyWith(showLetterboxd: v)),
      _mdbToggle(l, c, p, 'Metacritic', const MetacriticLogo(),
          p.showMetacritic, (v) => p.copyWith(showMetacritic: v)),
      _mdbToggle(l, c, p, l.prefsMetacriticUser, const MetacriticLogo(),
          p.showMetacriticUser, (v) => p.copyWith(showMetacriticUser: v)),
      _mdbToggle(l, c, p, 'Trakt', const TraktLogo(), p.showTrakt,
          (v) => p.copyWith(showTrakt: v)),
      _mdbToggle(l, c, p, 'Roger Ebert',
          const Text('👍', style: TextStyle(fontSize: 18)),
          p.showRogerEbert, (v) => p.copyWith(showRogerEbert: v)),
      _mdbToggle(l, c, p, 'MyAnimeList', const MalLogo(), p.showMyAnimeList,
          (v) => p.copyWith(showMyAnimeList: v)),
    ];
  }

  /// One MDBList source toggle, disabled (greyed) until an API key is entered.
  Widget _mdbToggle(AppLocalizations l, PreferencesController c, Prefs p,
      String title, Widget logo, bool value, Prefs Function(bool) apply) {
    final hasKey = p.mdbListApiKey.isNotEmpty;
    return SwitchListTile(
      secondary: SizedBox(width: 40, child: Center(child: logo)),
      title: Text(title),
      subtitle: hasKey ? null : Text(l.prefsMdbAddKeyToEnable),
      value: value && hasKey,
      onChanged: hasKey ? (v) => c.edit((_) => apply(v)) : null,
    );
  }

  List<Widget> _general(
      BuildContext context, Prefs p, PreferencesController c,
      {bool manage = false}) {
    final l = AppLocalizations.of(context);
    return [
      SettingsSectionHeader(l.prefsHeaderStartup, first: true),
      ListTile(
        leading: const Icon(Icons.launch_rounded),
        title: Text(l.prefsOpenOnStartup),
        subtitle: Text(l.prefsOpenOnStartupSub),
        trailing: _Dropdown(
          value: p.startupScreen,
          options: {
            'home': l.prefsStartupHome,
            'libraries': l.prefsStartupLibraries,
            'livetv': l.prefsStartupLiveTv,
          },
          onChanged: (v) => c.edit((x) => x.copyWith(startupScreen: v)),
        ),
      ),
      SettingsSectionHeader(l.prefsHeaderNotifications),
      // Desktop only: mobile has no system notifications (they go to the in-app
      // bell instead), so a master OS-pop-up switch there would do nothing.
      if (!Platform.isAndroid && !Platform.isIOS)
        SwitchListTile(
          secondary: const Icon(Icons.notifications_active_outlined),
          title: Text(l.prefsDesktopNotifications),
          subtitle: Text(l.prefsDesktopNotificationsSub),
          value: p.desktopNotifications,
          onChanged: (v) => c.edit((x) => x.copyWith(desktopNotifications: v)),
        ),
      SwitchListTile(
        secondary: const Icon(Icons.add_task_rounded),
        title: Text(l.prefsNotifNewRequest),
        subtitle: Text(l.prefsNotifNewRequestSub),
        value: p.notifNewRequest,
        onChanged: (v) => c.edit((x) => x.copyWith(notifNewRequest: v)),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.check_circle_outline_rounded),
        title: Text(l.prefsNotifApproved),
        subtitle: Text(l.prefsNotifApprovedSub),
        value: p.notifSeerrApproved,
        onChanged: (v) => c.edit((x) => x.copyWith(notifSeerrApproved: v)),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.cancel_outlined),
        title: Text(l.prefsNotifDeclined),
        subtitle: Text(l.prefsNotifDeclinedSub),
        value: p.notifSeerrDeclined,
        onChanged: (v) => c.edit((x) => x.copyWith(notifSeerrDeclined: v)),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.movie_filter_outlined),
        title: Text(l.prefsNotifAvailable),
        subtitle: Text(l.prefsNotifAvailableSub),
        value: p.notifSeerrAvailable,
        onChanged: (v) => c.edit((x) => x.copyWith(notifSeerrAvailable: v)),
      ),
      ListTile(
        leading: const Icon(Icons.schedule_rounded),
        title: Text(l.prefsCheckRequestUpdates),
        subtitle: Text(l.prefsCheckRequestUpdatesSub),
        trailing: _Dropdown(
          value: '${p.seerrPollMinutes}',
          options: {
            '0': l.commonOff,
            '1': l.prefsEveryMinute,
            '5': l.prefsEvery5Minutes,
            '15': l.prefsEvery15Minutes,
            '30': l.prefsEvery30Minutes,
          },
          onChanged: (v) =>
              c.edit((x) => x.copyWith(seerrPollMinutes: int.tryParse(v) ?? 5)),
        ),
      ),
      // What Sonarr, Radarr and Lidarr did, once one is connected.
      if (manage) ...[
        SwitchListTile(
          secondary: const Icon(Icons.download_done_rounded),
          title: Text(l.prefsNotifArrImported),
          subtitle: Text(l.prefsNotifArrImportedSub),
          value: p.notifArrImported,
          onChanged: (v) => c.edit((x) => x.copyWith(notifArrImported: v)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.error_outline_rounded),
          title: Text(l.prefsNotifArrFailed),
          subtitle: Text(l.prefsNotifArrFailedSub),
          value: p.notifArrFailed,
          onChanged: (v) => c.edit((x) => x.copyWith(notifArrFailed: v)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.file_download_outlined),
          title: Text(l.prefsNotifArrGrabbed),
          subtitle: Text(l.prefsNotifArrGrabbedSub),
          value: p.notifArrGrabbed,
          onChanged: (v) => c.edit((x) => x.copyWith(notifArrGrabbed: v)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.health_and_safety_outlined),
          title: Text(l.prefsNotifArrHealth),
          subtitle: Text(l.prefsNotifArrHealthSub),
          value: p.notifArrHealth,
          onChanged: (v) => c.edit((x) => x.copyWith(notifArrHealth: v)),
        ),
        ListTile(
          leading: const Icon(Icons.schedule_rounded),
          title: Text(l.prefsCheckArr),
          subtitle: Text(l.prefsCheckArrSub),
          trailing: _Dropdown(
            value: '${p.arrPollMinutes}',
            options: {
              '0': l.commonOff,
              '1': l.prefsEveryMinute,
              '5': l.prefsEvery5Minutes,
              '15': l.prefsEvery15Minutes,
              '30': l.prefsEvery30Minutes,
            },
            onChanged: (v) =>
                c.edit((x) => x.copyWith(arrPollMinutes: int.tryParse(v) ?? 5)),
          ),
        ),
      ],
      SwitchListTile(
        secondary: const Icon(Icons.download_done_rounded),
        title: Text(l.prefsDownloadComplete),
        subtitle: Text(l.prefsDownloadCompleteSub),
        value: p.notifDownloads,
        onChanged: (v) => c.edit((x) => x.copyWith(notifDownloads: v)),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.system_update_rounded),
        title: Text(l.prefsNotifUpdates),
        subtitle: Text(l.prefsNotifUpdatesSub),
        value: p.notifUpdates,
        onChanged: (v) => c.edit((x) => x.copyWith(notifUpdates: v)),
      ),
      SettingsSectionHeader(l.prefsHeaderStorage),
      const _JellyfinDownloadFolder(),
      const _StorageTile(),
    ];
  }

  List<Widget> _appearance(
      BuildContext context, Prefs p, PreferencesController c) {
    final l = AppLocalizations.of(context);
    return [
      ListTile(
        leading: const Icon(Icons.brightness_6_rounded),
        title: Text(l.prefsTheme),
        trailing: SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 'system', label: Text(l.prefsAuto)),
            ButtonSegment(value: 'dark', label: Text(l.prefsThemeDark)),
            ButtonSegment(value: 'light', label: Text(l.prefsThemeLight)),
          ],
          selected: {p.themeMode},
          onSelectionChanged: (s) =>
              c.edit((x) => x.copyWith(themeMode: s.first)),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.palette_rounded),
                const SizedBox(width: 16),
                Text(l.prefsAccentColor,
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final col in _accentColors)
                  _Swatch(
                    color: Color(col),
                    selected: p.accentColor == col,
                    onTap: () => c.edit((x) => x.copyWith(accentColor: col)),
                  ),
                // The current accent, when it's a custom (non-preset) color.
                if (!_accentColors.contains(p.accentColor))
                  _Swatch(
                    color: Color(p.accentColor),
                    selected: true,
                    onTap: () => _pickAccent(context, p, c),
                  ),
                _CustomSwatch(onTap: () => _pickAccent(context, p, c)),
              ],
            ),
          ],
        ),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.dark_mode_rounded),
        title: Text(l.prefsAmoledBlack),
        subtitle: Text(l.prefsAmoledBlackSub),
        value: p.amoled,
        onChanged: (v) => c.edit((x) => x.copyWith(amoled: v)),
      ),
      if (interfaceScaleSupported && !isTvDevice) const _InterfaceSizeTile(),
      SwitchListTile(
        secondary: const Icon(Icons.tv_rounded),
        title: Text(l.prefsForceTvMode),
        subtitle: Text(l.prefsForceTvModeSub),
        value: p.forceTvMode,
        onChanged: (v) => c.edit((x) => x.copyWith(forceTvMode: v)),
      ),
      ListTile(
        leading: const Icon(Icons.star_border_rounded),
        title: Text(l.prefsRatingOnCards),
        subtitle: Text(l.prefsRatingOnCardsSub),
        trailing: _Dropdown(
          value: p.cardRating,
          options: {
            'off': l.commonOff,
            'auto': l.prefsAuto,
            'community': l.prefsCardRatingCommunity,
            'critics': l.prefsCardRatingCritics,
          },
          onChanged: (v) => c.edit((x) => x.copyWith(cardRating: v)),
        ),
      ),
    ];
  }

  /// Opens a color wheel to choose any custom accent color.
  Future<void> _pickAccent(
      BuildContext context, Prefs p, PreferencesController c) async {
    final l = AppLocalizations.of(context);
    var picked = Color(p.accentColor);
    final result = await showDialog<Color>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.prefsCustomAccent),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: Color(p.accentColor),
            onColorChanged: (col) => picked = col,
            paletteType: PaletteType.hueWheel,
            enableAlpha: false,
            labelTypes: const [],
            pickerAreaHeightPercent: 0.75,
            hexInputBar: true,
            portraitOnly: true,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, picked),
              child: Text(l.commonApply)),
        ],
      ),
    );
    if (result != null) {
      // Force fully opaque so the seed color is stable.
      final argb = (result.toARGB32() & 0x00FFFFFF) | 0xFF000000;
      c.edit((x) => x.copyWith(accentColor: argb));
    }
  }

  List<Widget> _home(BuildContext context, Prefs p, PreferencesController c) {
    final l = AppLocalizations.of(context);
    return [
      ListTile(
        leading: const Icon(Icons.view_carousel_rounded),
        title: Text(l.prefsHomeBanner),
        subtitle: Text(l.prefsHomeBannerSub),
        trailing: _Dropdown(
          value: p.homeBanner,
          options: {
            'carousel': l.prefsBannerCarousel,
            'detailed': l.prefsBannerDetailed,
            'hide': l.prefsBannerHidden,
          },
          onChanged: (v) => c.edit((x) => x.copyWith(homeBanner: v)),
        ),
      ),
      const Divider(height: 12),
      ListTile(
        leading: const Icon(Icons.dashboard_customize_rounded),
        title: Text(l.prefsHomeLayout),
        subtitle: Text(l.prefsHomeLayoutSub),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push('/home-layout'),
      ),
      ListTile(
        leading: const Icon(Icons.view_sidebar_rounded),
        title: Text(l.prefsNavLayout),
        subtitle: Text(l.prefsNavLayoutSub),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push('/navigation-layout'),
      ),
    ];
  }

  List<Widget> _player(BuildContext context, Prefs p, PreferencesController c) {
    final l = AppLocalizations.of(context);
    return [
      // Lyrics moved to Audio & Subtitles, where a music feature belongs;
      // leading the Player screen with them pushed the video controls below the
      // fold. Grouped with headers so the long list reads as sections.
      SettingsSectionHeader(l.prefsHeaderPlayback, first: true),
      ListTile(
        leading: const Icon(Icons.aspect_ratio_rounded),
        title: Text(l.prefsVideoFit),
        trailing: _Dropdown(
          value: p.playerFit,
          options: {
            'contain': l.prefsFitContain,
            'cover': l.prefsFitCover,
            'fill': l.prefsFitFill,
          },
          onChanged: (v) => c.edit((x) => x.copyWith(playerFit: v)),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.blur_on_rounded),
        title: Text(l.prefsControlBar),
        subtitle: Text(l.prefsControlBarSub),
        trailing: _Dropdown(
          value: p.playerBarStyle,
          options: {
            'none': l.prefsBarNoGlass,
            'glass': l.prefsBarGlass,
            'dark': l.prefsBarDarkGlass,
          },
          onChanged: (v) => c.edit((x) => x.copyWith(playerBarStyle: v)),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.high_quality_rounded),
        title: Text(l.prefsMaxQuality),
        subtitle: Text(l.prefsMaxQualitySub),
        trailing: _BitrateDropdown(
          value: p.maxBitrateMbps,
          onChanged: (v) => c.edit((x) => x.copyWith(maxBitrateMbps: v)),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.movie_outlined),
        title: Text(l.prefsTrailerQuality),
        subtitle: Text(l.prefsTrailerQualitySub),
        trailing: _Dropdown(
          value: p.trailerQuality,
          options: {
            'auto': l.prefsQualityAuto,
            '2160': '2160p (4K)',
            '1440': '1440p',
            '1080': '1080p',
            '720': '720p',
            '480': '480p',
            '360': '360p',
          },
          onChanged: (v) => c.edit((x) => x.copyWith(trailerQuality: v)),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.speed_rounded),
        title: Text(l.prefsDefaultSpeed),
        subtitle: Text(l.prefsDefaultSpeedSub),
        trailing: _Dropdown(
          value: p.playbackSpeed.toString(),
          options: {
            '0.75': '0.75x',
            '1.0': l.prefsSpeedNormal,
            '1.25': '1.25x',
            '1.5': '1.5x',
            '2.0': '2x',
          },
          onChanged: (v) => c.edit(
              (x) => x.copyWith(playbackSpeed: double.tryParse(v) ?? 1.0)),
        ),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.skip_next_rounded),
        title: Text(l.prefsAutoplayNext),
        value: p.autoplayNext,
        onChanged: (v) => c.edit((x) => x.copyWith(autoplayNext: v)),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.bookmark_outline_rounded),
        title: Text(l.prefsRememberTracks),
        value: p.rememberTracks,
        onChanged: (v) => c.edit((x) => x.copyWith(rememberTracks: v)),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.preview_rounded),
        title: Text(l.prefsPreviewThumbnails),
        subtitle: Text(l.prefsPreviewThumbnailsSub),
        value: p.previewThumbnailsWhileSeeking,
        onChanged: (v) =>
            c.edit((x) => x.copyWith(previewThumbnailsWhileSeeking: v)),
      ),
      SettingsSectionHeader(l.prefsHeaderSkipping),
      SwitchListTile(
        secondary: const Icon(Icons.fast_forward_rounded),
        title: Text(l.prefsAutoSkipIntros),
        subtitle: Text(l.prefsAutoSkipIntrosSub),
        value: p.autoSkipIntro,
        onChanged: (v) => c.edit((x) => x.copyWith(autoSkipIntro: v)),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.fast_forward_rounded),
        title: Text(l.prefsAutoSkipCredits),
        value: p.autoSkipCredits,
        onChanged: (v) => c.edit((x) => x.copyWith(autoSkipCredits: v)),
      ),
      ListTile(
        leading: const Icon(Icons.playlist_play_rounded),
        title: Text(l.prefsUpNextTiming),
        subtitle: Text(l.prefsUpNextTimingSub),
        trailing: _Dropdown(
          value: p.upNextLeadSeconds.toString(),
          options: {
            '0': l.prefsUpNextFullCredits,
            '30': l.prefsUpNextSecondsBefore(30),
            '20': l.prefsUpNextSecondsBefore(20),
            '15': l.prefsUpNextSecondsBefore(15),
            '10': l.prefsUpNextSecondsBefore(10),
            '5': l.prefsUpNextSecondsBefore(5),
          },
          onChanged: (v) => c.edit(
              (x) => x.copyWith(upNextLeadSeconds: int.tryParse(v) ?? 20)),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.view_agenda_outlined),
        title: Text(l.prefsUpNextStyle),
        subtitle: Text(l.prefsUpNextStyleSub),
        trailing: _Dropdown(
          value: p.upNextStyle,
          options: {
            'card': l.prefsUpNextStyleCard,
            'pill': l.prefsUpNextStylePill,
          },
          onChanged: (v) => c.edit((x) => x.copyWith(upNextStyle: v)),
        ),
      ),
      SettingsSectionHeader(l.prefsHeaderAdvanced),
      SwitchListTile(
        secondary: const Icon(Icons.developer_board_rounded),
        title: Text(l.prefsHardwareDecoding),
        subtitle: Text(l.prefsHardwareDecodingSub),
        value: p.hardwareDecoding,
        onChanged: (v) => c.edit((x) => x.copyWith(hardwareDecoding: v)),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.surround_sound_rounded),
        title: Text(l.prefsAudioPassthrough),
        subtitle: Text(l.prefsAudioPassthroughSub),
        value: p.audioPassthrough,
        onChanged: (v) => c.edit((x) => x.copyWith(audioPassthrough: v)),
      ),
      // Android video engine. ExoPlayer (native Media3) tunnels 4K/HDR straight
      // to the display, smooth on low-power TV sticks; media_kit (libmpv) is the
      // long-standing engine.
      if (Platform.isAndroid) ...[
        ListTile(
          leading: const Icon(Icons.smart_display_rounded),
          title: Text(l.prefsPlayerBackend),
          subtitle: Text(l.prefsPlayerBackendSub),
        ),
        for (final (id, label) in [
          ('auto', l.prefsPlayerBackendAuto),
          ('exoplayer', l.prefsPlayerBackendExo),
          ('mediakit', l.prefsPlayerBackendMediaKit),
        ])
          ListTile(
            contentPadding: const EdgeInsets.only(left: 72, right: 24),
            title: Text(label),
            trailing: p.playerBackend == id
                ? Icon(Icons.check_rounded,
                    color: Theme.of(context).colorScheme.primary)
                : null,
            onTap: () => c.edit((x) => x.copyWith(playerBackend: id)),
          ),
      ],
      // Desktop-only smoother motion. Hidden on mobile, where playback runs
      // through the platform mediacodec surface rather than this GL path.
      if (!Platform.isAndroid && !Platform.isIOS)
        SwitchListTile(
          secondary: const Icon(Icons.motion_photos_on_rounded),
          title: Text(l.prefsDisplaySync),
          subtitle: Text(l.prefsDisplaySyncSub),
          value: p.displaySync,
          onChanged: (v) => c.edit((x) => x.copyWith(displaySync: v)),
        ),
    ];
  }

  List<Widget> _audio(BuildContext context, Prefs p, PreferencesController c) {
    final l = AppLocalizations.of(context);
    return [
      SettingsSectionHeader(l.prefsHeaderAudio, first: true),
      ListTile(
        leading: const Icon(Icons.multitrack_audio_rounded),
        title: Text(l.prefsAudioLanguage),
        trailing: _Dropdown(
          value: p.audioLanguage,
          options: _languages(l),
          onChanged: (v) => c.edit((x) => x.copyWith(audioLanguage: v)),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.graphic_eq_rounded),
        title: Text(l.prefsReplayGain),
        subtitle: Text(l.prefsReplayGainSub),
        trailing: _Dropdown(
          value: p.replayGain,
          options: {
            'off': l.prefsReplayGainOff,
            'track': l.prefsReplayGainTrack,
            'album': l.prefsReplayGainAlbum,
          },
          onChanged: (v) => c.edit((x) => x.copyWith(replayGain: v)),
        ),
      ),
      if (p.replayGain != 'off')
        ListTile(
          leading: const Icon(Icons.tune_rounded),
          title: Text(l.prefsReplayGainFallback),
          subtitle: Text(l.prefsReplayGainFallbackSub),
          trailing: SizedBox(
            width: 190,
            child: Row(
              children: [
                Expanded(
                  child: Slider(
                    value: p.replayGainFallback,
                    min: -10,
                    max: 10,
                    divisions: 40,
                    label: '${p.replayGainFallback.toStringAsFixed(1)} dB',
                    onChanged: (v) =>
                        c.edit((x) => x.copyWith(replayGainFallback: v)),
                  ),
                ),
                SizedBox(
                  width: 54,
                  child: Text('${p.replayGainFallback.toStringAsFixed(1)} dB',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              ],
            ),
          ),
        ),
      SettingsSectionHeader(l.prefsHeaderSubtitles),
      ListTile(
        leading: const Icon(Icons.closed_caption_rounded),
        title: Text(l.prefsSubtitleLanguage),
        trailing: _Dropdown(
          value: p.subtitleLanguage,
          options: _subtitleLanguages(l),
          onChanged: (v) => c.edit((x) => x.copyWith(subtitleLanguage: v)),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.format_size_rounded),
        title: Text(l.prefsSubtitleSize),
        subtitle: Slider(
          min: 0.5,
          max: 2.0,
          divisions: 6,
          label: l.prefsPercent((p.subtitleScale * 100).round()),
          value: p.subtitleScale,
          onChanged: (v) => c.edit((x) => x.copyWith(subtitleScale: v)),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.palette_outlined),
        title: Text(l.prefsSubtitleColor),
        trailing: Wrap(
          spacing: 8,
          children: [
            for (final color in _subtitleColors)
              _SubtitleSwatch(
                color: Color(color),
                selected: p.subtitleTextColor == color,
                onTap: () =>
                    c.edit((x) => x.copyWith(subtitleTextColor: color)),
              ),
          ],
        ),
      ),
      ListTile(
        leading: const Icon(Icons.gradient_rounded),
        title: Text(l.prefsSubtitleBackground),
        subtitle: Slider(
          min: 0.0,
          max: 1.0,
          divisions: 10,
          label: l.prefsPercent((p.subtitleBackgroundOpacity * 100).round()),
          value: p.subtitleBackgroundOpacity,
          onChanged: (v) =>
              c.edit((x) => x.copyWith(subtitleBackgroundOpacity: v)),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.vertical_align_bottom_rounded),
        title: Text(l.prefsSubtitlePosition),
        subtitle: Slider(
          min: 60,
          max: 100,
          divisions: 8,
          label: p.subtitlePosition >= 100
              ? l.prefsSubtitlePositionBottom
              : l.prefsSubtitlePositionHigher(100 - p.subtitlePosition),
          value: p.subtitlePosition.toDouble().clamp(60, 100),
          onChanged: (v) =>
              c.edit((x) => x.copyWith(subtitlePosition: v.round())),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        child: Container(
          width: double.infinity,
          height: 72,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            color: Colors.black
                .withValues(alpha: p.subtitleBackgroundOpacity),
            child: Text(
              l.prefsSubtitlePreview,
              style: TextStyle(
                color: Color(p.subtitleTextColor),
                fontSize: 16 * p.subtitleScale,
                shadows: p.subtitleBackgroundOpacity > 0.05
                    ? const []
                    : const [Shadow(blurRadius: 6, color: Colors.black)],
              ),
            ),
          ),
        ),
      ),
      // Lyrics live here rather than under Player: they're a music feature, and
      // this is the audio-domain screen a listener would look on.
      SettingsSectionHeader(l.prefsHeaderLyrics),
      SwitchListTile(
        secondary: const Icon(Icons.lyrics_rounded),
        title: Text(l.prefsShowLyricsAuto),
        subtitle: Text(l.prefsShowLyricsAutoSub),
        value: p.showLyricsAutomatically,
        onChanged: (v) => c.edit((x) => x.copyWith(showLyricsAutomatically: v)),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.travel_explore_rounded),
        title: Text(l.prefsLookUpLyrics),
        subtitle: Text(l.prefsLookUpLyricsSub),
        value: p.lookUpMissingLyrics,
        onChanged: (v) => c.edit((x) => x.copyWith(lookUpMissingLyrics: v)),
      ),
    ];
  }
}

const _subtitleColors = <int>[
  0xFFFFFFFF, // white
  0xFFFFEB3B, // yellow
  0xFF00E5FF, // cyan
  0xFF69F0AE, // green
  0xFFFF8A65, // orange
];

class _SubtitleSwatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _SubtitleSwatch(
      {required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Bigger, focusable target on TV (a 28px dot is hard to aim at / see from a
    // couch); unchanged off TV.
    final size = isTvDevice ? 40.0 : 28.0;
    return TvFocusable(
      onTap: onTap,
      scale: 1.15,
      borderRadius: const BorderRadius.all(Radius.circular(24)),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.black26,
              width: selected ? 3 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _Swatch(
      {required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onTap: onTap,
      scale: 1.15,
      borderRadius: const BorderRadius.all(Radius.circular(20)),
      child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: selected
              ? [
                  BoxShadow(
                      color: color.withValues(alpha: 0.5),
                      blurRadius: 10,
                      spreadRadius: 1)
                ]
              : null,
          border: selected
              ? Border.all(
                  color: Theme.of(context).colorScheme.onSurface, width: 3)
              : null,
        ),
        child: selected
            ? const Icon(Icons.check, size: 18, color: Colors.white)
            : null,
      ),
      ),
    );
  }
}

/// A rainbow "custom color" swatch that opens the color wheel.
class _CustomSwatch extends StatelessWidget {
  final VoidCallback onTap;
  const _CustomSwatch({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onTap: onTap,
      scale: 1.15,
      borderRadius: const BorderRadius.all(Radius.circular(20)),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(colors: [
              Color(0xFFFF5252),
              Color(0xFFFFD600),
              Color(0xFF00C853),
              Color(0xFF00B0FF),
              Color(0xFF7C4DFF),
              Color(0xFFFF5252),
            ]),
          ),
          child: const Icon(Icons.add_rounded, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

/// Clearing YouTube data. Each is confirmed: they're irreversible, and the
/// counts make it obvious what's about to go.
class _YoutubeClearData extends ConsumerWidget {
  const _YoutubeClearData();

  Future<bool> _confirm(BuildContext context, String what) async {
    final l = AppLocalizations.of(context);
    return await confirm(context,
        title: l.prefsClearConfirmTitle(what),
        message: l.prefsClearCannotUndo,
        confirmLabel: l.commonClear,
        destructive: true);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final watch =
        ref.watch(youtubeHistoryProvider).asData?.value.length ?? 0;
    final searches =
        ref.watch(youtubeSearchHistoryProvider).asData?.value.length ?? 0;
    final messenger = ScaffoldMessenger.of(context);

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.delete_outline_rounded),
          title: Text(l.prefsClearWatchHistory),
          subtitle: Text(watch == 0
              ? l.prefsNothingRecorded
              : l.prefsWatchHistoryCount(watch)),
          enabled: watch > 0,
          onTap: watch == 0
              ? null
              : () async {
                  if (!await _confirm(context, l.prefsWhatWatchHistory)) return;
                  await ref.read(youtubeHistoryProvider.notifier).clear();
                  showSnackOn(messenger, l.prefsWatchHistoryCleared,
                      kind: SnackKind.success);
                },
        ),
        ListTile(
          leading: const Icon(Icons.delete_outline_rounded),
          title: Text(l.prefsClearSearchHistory),
          subtitle: Text(searches == 0
              ? l.prefsNothingRecorded
              : l.prefsSearchHistoryCount(searches)),
          enabled: searches > 0,
          onTap: searches == 0
              ? null
              : () async {
                  if (!await _confirm(context, l.prefsWhatSearchHistory)) {
                    return;
                  }
                  await ref.read(youtubeSearchHistoryProvider.notifier).clear();
                  showSnackOn(messenger, l.prefsSearchHistoryCleared,
                      kind: SnackKind.success);
                },
        ),
      ],
    );
  }
}

/// Where downloads go. Video and audio separately, as in NewPipe: audio is
/// usually music, and music belongs with music.
class _YoutubeDownloadFolders extends ConsumerWidget {
  const _YoutubeDownloadFolders();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final p = ref.watch(preferencesProvider).asData?.value ?? const Prefs();
    final c = ref.read(preferencesProvider.notifier);
    // What an unset folder means here: the public folder downloads are
    // published to on Android 11+, the default download folder elsewhere.
    String fallback(bool audio) =>
        ref
            .watch(youtubeDownloadFolderLabelProvider(
                audio ? YtDownloadKind.audio : YtDownloadKind.video))
            .asData
            ?.value ??
        l.prefsDefault;

    // A new folder is for new downloads. When finished downloads would be
    // left behind in the old one, ask once whether to bring them along;
    // nothing moves without a yes.
    Future<void> setFolder(bool audio, String path) async {
      final messenger = ScaffoldMessenger.of(context);
      await c.edit((x) => audio
          ? x.copyWith(youtubeAudioDownloadPath: path)
          : x.copyWith(youtubeVideoDownloadPath: path));
      await ref.read(youtubeDownloadsProvider.future);
      final downloads = ref.read(youtubeDownloadsProvider.notifier);
      final behind = await downloads.leftBehind(audio: audio, custom: path);
      if (behind.isEmpty || !context.mounted) return;
      final move = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.ytMoveDownloadsTitle),
          content: Text(l.ytMoveDownloadsBody(behind.length)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.ytMoveDownloadsKeep),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.ytMoveDownloadsMove),
            ),
          ],
        ),
      );
      if (move != true) return;
      final moved = await downloads.moveTo(behind, audio: audio, custom: path);
      showSnackOn(
        messenger,
        moved == behind.length
            ? l.ytMoveDownloadsDone(moved)
            : l.ytMoveDownloadsPartial(moved, behind.length),
        kind: moved == behind.length ? SnackKind.success : SnackKind.error,
      );
    }

    Future<void> pick(bool audio) async {
      final dir = await FilePicker.getDirectoryPath(
          dialogTitle:
              audio ? l.prefsAudioDownloadFolder : l.prefsVideoDownloadFolder);
      if (dir == null) return;
      await setFolder(audio, dir);
    }

    // Android publishes through MediaStore, which can only write to the
    // phone's main storage; say so up front when the folder is elsewhere,
    // rather than letting downloads quietly land somewhere else.
    final publishes =
        ref.watch(sharedFilesPublishProvider).asData?.value ?? false;
    bool unusable(String value) =>
        publishes && value.isNotEmpty && SharedFiles.relativeDir(value) == null;

    Widget row(String title, String value, bool audio) => ListTile(
          leading: Icon(audio ? Icons.library_music_rounded : Icons.folder_rounded),
          title: Text(title),
          subtitle: Text(
            unusable(value)
                ? '$value\n${l.prefsDownloadFolderUnavailable(SharedFiles.defaultDir(audio: audio))}'
                : value.isEmpty
                    ? fallback(audio)
                    : value,
            maxLines: unusable(value) ? 3 : 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: value.isEmpty
              ? null
              : IconButton(
                  tooltip: l.commonReset,
                  icon: const Icon(Icons.close_rounded),
                  // Back to the default is a folder change too.
                  onPressed: () => setFolder(audio, ''),
                ),
          onTap: () => pick(audio),
        );

    final theme = Theme.of(context);
    return Column(children: [
      row(l.prefsVideoFolder, p.youtubeVideoDownloadPath, false),
      row(l.prefsAudioFolder, p.youtubeAudioDownloadPath, true),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            l.prefsDownloadFolderNote,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    ]);
  }
}

/// Where downloaded Jellyfin media (movies, shows, music, recordings) is
/// saved. Separate from the YouTube video/audio folders above: Jellyfin
/// downloads are an offline library Fathom manages as a unit (art, ratings,
/// and metadata cache all live alongside the media), so one location covers
/// all of it, organized into Movies/TV Shows/Music/Recordings subfolders.
/// Defaults to app-private storage, matching Netflix/Plex-style apps rather
/// than the YouTube folders' real-Downloads-folder default.
class _JellyfinDownloadFolder extends ConsumerWidget {
  const _JellyfinDownloadFolder();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final p = ref.watch(preferencesProvider).asData?.value ?? const Prefs();
    final c = ref.read(preferencesProvider.notifier);
    final path = p.jellyfinDownloadPath;

    Future<void> pick() async {
      final dir = await FilePicker.getDirectoryPath(dialogTitle: l.prefsDownloadLocationPick);
      if (dir == null) return;
      c.edit((x) => x.copyWith(jellyfinDownloadPath: dir));
    }

    return ListTile(
      leading: const Icon(Icons.folder_rounded),
      title: Text(l.prefsDownloadLocation),
      subtitle: Text(
        path.isEmpty ? l.prefsDefault : path,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: path.isEmpty
          ? null
          : IconButton(
              tooltip: l.commonReset,
              icon: const Icon(Icons.close_rounded),
              onPressed: () =>
                  c.edit((x) => x.copyWith(jellyfinDownloadPath: '')),
            ),
      onTap: pick,
    );
  }
}

/// SponsorBlock: the switch, the categories, and the attribution its licence
/// asks for.
class _SponsorBlockSettings extends ConsumerWidget {
  const _SponsorBlockSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final p = ref.watch(preferencesProvider).asData?.value ?? const Prefs();
    final c = ref.read(preferencesProvider.notifier);
    final theme = Theme.of(context);
    final enabled = p.youtubeSponsorBlock;
    final active = p.youtubeSponsorBlockCategories.toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.fast_forward_rounded),
          title: Text(l.prefsSbSkip),
          subtitle: Text(l.prefsSbSkipSub),
          value: enabled,
          onChanged: (v) => c.edit((x) => x.copyWith(youtubeSponsorBlock: v)),
        ),
        if (enabled) ...[
          SwitchListTile(
            secondary: const Icon(Icons.notifications_none_rounded),
            title: Text(l.prefsSbNotify),
            subtitle: Text(l.prefsSbNotifySub),
            value: p.youtubeSponsorBlockNotify,
            onChanged: (v) =>
                c.edit((x) => x.copyWith(youtubeSponsorBlockNotify: v)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
            child: Text(l.prefsSbCategories,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          // Each is separate because they aren't equivalent: skipping a paid ad
          // read is uncontroversial, skipping the creator's outro is taste.
          for (final cat in SponsorCategory.values)
            CheckboxListTile(
              value: active.contains(cat.id),
              title: Text(cat.label),
              subtitle: Text(cat.description),
              onChanged: (on) => c.edit((x) => x.copyWith(
                    youtubeSponsorBlockCategories: [
                      for (final e in SponsorCategory.values)
                        if (e == cat ? (on ?? false) : active.contains(e.id))
                          e.id,
                    ],
                  )),
            ),
          // Attribution, as CC BY-NC-SA asks for. Also honest about what it is:
          // crowdsourced, so coverage is uneven.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Text(
              l.prefsSbAttribution,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ],
    );
  }
}

class _Dropdown extends StatelessWidget {
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;
  const _Dropdown(
      {required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final safe = options.containsKey(value) ? value : options.keys.first;
    return AppDropdown<String>(
        value: safe, options: options, onChanged: onChanged);
  }
}

/// Interface Size (desktop): Automatic, or a fixed size. Automatic shows what
/// it works out to on this display, so picking isn't guesswork.
class _InterfaceSizeTile extends ConsumerWidget {
  const _InterfaceSizeTile();

  static const _sizes = [0.75, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final chosen =
        ref.watch(preferencesProvider).asData?.value.interfaceScale ?? 0;
    final auto = ref.watch(autoInterfaceScaleProvider);
    int percent(double s) => (s * 100).round();
    return ListTile(
      leading: const Icon(Icons.zoom_in_rounded),
      title: Text(l.prefsInterfaceSize),
      subtitle: Text(l.prefsInterfaceSizeSub),
      trailing: AppDropdown<double>(
        value: _sizes.contains(chosen) ? chosen : 0.0,
        options: {
          0.0: l.prefsInterfaceSizeAuto(percent(auto)),
          for (final s in _sizes) s: l.prefsInterfaceSizePercent(percent(s)),
        },
        onChanged: (v) => ref
            .read(preferencesProvider.notifier)
            .edit((x) => x.copyWith(interfaceScale: v)),
      ),
    );
  }
}

class _BitrateDropdown extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _BitrateDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final bitrates = _bitrates(l);
    return AppDropdown<int>(
      value: bitrates.containsKey(value) ? value : 0,
      options: bitrates,
      onChanged: onChanged,
    );
  }
}

/// Shows the on-disk image cache size (posters, backdrops, thumbnails) and a
/// button to clear it. Computed from the cache folder so it reflects reality,
/// not a guess.
class _StorageTile extends StatefulWidget {
  const _StorageTile();

  @override
  State<_StorageTile> createState() => _StorageTileState();
}

class _StorageTileState extends State<_StorageTile> {
  int? _bytes;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    try {
      final tmp = await getTemporaryDirectory();
      final dir = Directory('${tmp.path}/fathomImageCache');
      var total = 0;
      if (dir.existsSync()) {
        await for (final e in dir.list(recursive: true, followLinks: false)) {
          if (e is File) total += await e.length();
        }
      }
      if (mounted) setState(() => _bytes = total);
    } catch (_) {
      if (mounted) setState(() => _bytes = 0);
    }
  }

  Future<void> _clear() async {
    setState(() => _clearing = true);
    try {
      await fathomImageCache.emptyCache();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {}
    await _measure();
    if (mounted) setState(() => _clearing = false);
  }

  String _fmt(int b) {
    if (b >= 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (b >= 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '$b B';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final bytes = _bytes;
    return ListTile(
      leading: const Icon(Icons.sd_storage_outlined),
      title: Text(l.prefsImageCache),
      subtitle: Text(bytes == null
          ? l.prefsCalculating
          : l.prefsImageCacheSub(_fmt(bytes))),
      trailing: TextButton(
        onPressed: (_clearing || bytes == null || bytes == 0) ? null : _clear,
        child: Text(_clearing ? l.prefsClearing : l.commonClear),
      ),
    );
  }
}

