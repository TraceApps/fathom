import 'package:flutter/material.dart';

import '../state/interface_scale.dart';
import '../l10n/generated/app_localizations.dart';

/// One searchable setting: where it lives and how to find it.
///
/// This is the index behind the settings search box. IMPORTANT: whenever a
/// setting is added, renamed, or moved, update its entry here (and add generous
/// [keywords] / synonyms) in the same change, or search will quietly miss it.
class SettingResult {
  /// The setting's visible name.
  final String title;

  /// The section it sits in, e.g. 'Appearance' (shown as the result subtitle).
  final String section;

  /// The section's leading icon (matches the settings hub).
  final IconData icon;

  /// Route to open, and its `extra` argument (a section key for /preferences).
  final String route;
  final Object? extra;

  /// Synonyms and related terms so "dark mode" finds Theme, "cc" finds
  /// Subtitles, "dvr" finds recording, and so on. Titles alone aren't enough.
  final List<String> keywords;

  const SettingResult({
    required this.title,
    required this.section,
    required this.icon,
    required this.route,
    this.extra,
    this.keywords = const [],
  });

  /// True when every whitespace-separated term in [query] appears somewhere in
  /// the title, section, or keywords (AND matching, case-insensitive).
  bool matches(String query) {
    final hay =
        '$title $section ${keywords.join(' ')}'.toLowerCase();
    final terms = query.toLowerCase().split(RegExp(r'\s+'))
      ..removeWhere((t) => t.isEmpty);
    return terms.every(hay.contains);
  }
}

// Section icons, mirroring the settings hub.
const _general = Icons.settings_rounded;
const _appearance = Icons.palette_outlined;
const _home = Icons.dashboard_outlined;
const _player = Icons.play_circle_outline_rounded;
const _audio = Icons.subtitles_outlined;
const _ratings = Icons.star_half_rounded;
const _youtube = Icons.smart_display_rounded;
const _integrations = Icons.travel_explore_rounded;

/// Every searchable user setting. Grouped by section for upkeep.
List<SettingResult> userSettingsIndex(AppLocalizations l) => <SettingResult>[
  // General — Startup
  SettingResult(title: l.searchOpenOnStartup, section: l.searchGeneral, icon: _general, route: '/preferences', extra: 'general', keywords: ['startup', 'launch', 'start screen', 'default screen', 'boot']),
  // General — Notifications
  SettingResult(title: l.searchDesktopNotifications, section: l.searchGeneral, icon: _general, route: '/preferences', extra: 'general', keywords: ['notification', 'notify', 'alerts', 'popup', 'toast', 'os', 'system', 'bell', 'background', 'push']),
  SettingResult(title: l.searchNewRequest, section: l.searchGeneral, icon: _general, route: '/preferences', extra: 'general', keywords: ['notification', 'seerr', 'request', 'pending', 'approval', 'new']),
  SettingResult(title: l.prefsNotifUpdates, section: l.searchGeneral, icon: _general, route: '/preferences', extra: 'general', keywords: ['notification', 'update', 'version', 'upgrade', 'available', 'new version']),
  SettingResult(title: l.searchRequestApproved, section: l.searchGeneral, icon: _general, route: '/preferences', extra: 'general', keywords: ['notification', 'seerr', 'request', 'approved']),
  SettingResult(title: l.searchRequestDeclined, section: l.searchGeneral, icon: _general, route: '/preferences', extra: 'general', keywords: ['notification', 'seerr', 'request', 'declined', 'rejected']),
  SettingResult(title: l.searchNowAvailable, section: l.searchGeneral, icon: _general, route: '/preferences', extra: 'general', keywords: ['notification', 'seerr', 'request', 'available', 'downloaded', 'ready']),
  SettingResult(title: l.searchCheckForRequestUpdates, section: l.searchGeneral, icon: _general, route: '/preferences', extra: 'general', keywords: ['seerr', 'poll', 'interval', 'refresh', 'status', 'updates', 'requests']),
  // Integrations — Seerr connection / sign-in
  SettingResult(title: l.searchSeerrConnection, section: l.settingsSectionIntegrations, icon: _integrations, route: '/seerr-settings', keywords: ['seerr', 'jellyseerr', 'overseerr', 'connect', 'connection', 'login', 'log in', 'sign in', 'signin', 'account', 'jellyfin', 'local', 'api key', 'apikey', 'token', 'email', 'password', 'url', 'server', 'requests']),
  // Integrations: Sonarr and Radarr connections
  SettingResult(title: l.settingsArr, section: l.settingsSectionIntegrations, icon: Icons.dns_rounded, route: '/arr-settings', keywords: ['sonarr', 'radarr', 'arr', 'servarr', 'shows', 'series', 'movies', 'calendar', 'queue', 'downloads', 'api key', 'apikey', 'connect', 'connection', 'url', 'server']),
  // System — updates, backup, diagnostics
  SettingResult(title: l.settingsUpdates, section: l.settingsSectionSystem, icon: Icons.system_update_alt_rounded, route: '/updates', keywords: ['update', 'updates', 'upgrade', 'auto update', 'auto-update', 'version', 'new version', 'release', 'check for updates', 'download', 'channel', 'dev', 'beta', 'stable', 'latest', 'frequency', 'daily', 'weekly', 'launch', 'how often']),
  SettingResult(title: l.settingsBackup, section: l.settingsSectionSystem, icon: Icons.settings_backup_restore_rounded, route: '/backup', keywords: ['backup', 'restore', 'export', 'import', 'settings', 'save settings', 'transfer', 'migrate', 'move', 'sync', 'json', 'share', 'download settings']),
  SettingResult(title: l.settingsSupport, section: l.settingsSectionAbout, icon: Icons.volunteer_activism_rounded, route: '/support', keywords: ['support', 'donate', 'donation', 'sponsor', 'github sponsors', 'ko-fi', 'kofi', 'tip', 'star', 'report a bug', 'bug', 'translate', 'translation', 'help']),
  SettingResult(title: l.diagnosticsTitle, section: l.settingsSectionSystem, icon: Icons.bug_report_rounded, route: '/diagnostics', keywords: ['diagnostic', 'diagnostics', 'log', 'logging', 'verbose', 'debug', 'troubleshoot', 'troubleshooting', 'bug report', 'mpv log', 'copy log', 'crash', 'issue']),
  SettingResult(title: l.profileChangePassword, section: l.settingsSectionSystem, icon: Icons.password_rounded, route: '/profile', keywords: ['password', 'change password', 'reset password', 'passcode', 'credentials', 'account', 'profile', 'security', 'login', 'sign in']),
  SettingResult(title: l.searchDownloadComplete, section: l.searchGeneral, icon: _general, route: '/preferences', extra: 'general', keywords: ['notification', 'download', 'complete', 'finished', 'youtube']),
  // General — Storage
  SettingResult(title: l.searchImageCache, section: l.searchGeneral, icon: _general, route: '/preferences', extra: 'general', keywords: ['cache', 'storage', 'clear cache', 'disk', 'data', 'space', 'thumbnails', 'posters']),
  SettingResult(title: l.searchDownloadLocation, section: l.searchGeneral, icon: _general, route: '/preferences', extra: 'general', keywords: ['download', 'location', 'folder', 'path', 'directory', 'storage', 'movies', 'tv', 'music', 'recordings', 'jellyfin']),

  // Appearance
  SettingResult(title: l.searchTheme, section: l.searchAppearance, icon: _appearance, route: '/preferences', extra: 'appearance', keywords: ['dark', 'light', 'mode', 'system', 'appearance', 'color scheme']),
  SettingResult(title: l.searchAmoledBlack, section: l.searchAppearance, icon: _appearance, route: '/preferences', extra: 'appearance', keywords: ['amoled', 'oled', 'pure black', 'true black', 'dark']),
  if (interfaceScaleSupported) SettingResult(title: l.searchInterfaceSize, section: l.searchAppearance, icon: _appearance, route: '/preferences', extra: 'appearance', keywords: ['interface size', 'size', 'scale', 'scaling', 'zoom', 'bigger', 'smaller', 'larger', 'tiny', '4k', 'hidpi', 'high dpi', 'text size', 'font size', 'display']),
  SettingResult(title: l.prefsForceTvMode, section: l.searchAppearance, icon: _appearance, route: '/preferences', extra: 'appearance', keywords: ['tv', 'television', 'leanback', 'remote', 'd-pad', 'dpad', '10-foot', 'couch', 'htpc', 'force', 'android tv']),
  SettingResult(title: l.searchRatingOnCards, section: l.searchAppearance, icon: _appearance, route: '/preferences', extra: 'appearance', keywords: ['rating', 'cards', 'poster', 'badge', 'rotten tomatoes', 'community', 'star', 'critics', 'imdb']),
  SettingResult(title: l.searchAccentColor, section: l.searchAppearance, icon: _appearance, route: '/preferences', extra: 'appearance', keywords: ['accent', 'color', 'colour', 'highlight', 'tint', 'theme color', 'custom accent']),

  // Home
  SettingResult(title: l.searchHomeBanner, section: l.searchHome, icon: _home, route: '/preferences', extra: 'home', keywords: ['banner', 'hero', 'featured', 'spotlight']),
  SettingResult(title: l.searchHomeLayout, section: l.searchHome, icon: _home, route: '/preferences', extra: 'home', keywords: ['layout', 'rows', 'reorder', 'sections', 'customize home']),
  SettingResult(title: l.navLayoutTitle, section: l.searchHome, icon: Icons.view_sidebar_rounded, route: '/navigation-layout', keywords: ['navigation', 'sidebar', 'nav', 'rail', 'reorder', 'hide', 'menu', 'tabs', 'bottom bar', 'destinations', 'order', 'move']),

  // Player
  SettingResult(title: l.searchVideoFit, section: l.searchPlayer, icon: _player, route: '/preferences', extra: 'player', keywords: ['fit', 'contain', 'cover', 'fill', 'aspect', 'zoom', 'stretch']),
  SettingResult(title: l.searchControlBar, section: l.searchPlayer, icon: _player, route: '/preferences', extra: 'player', keywords: ['control bar', 'glass', 'frosted', 'blur', 'chrome', 'dark glass', 'no glass', 'controls background', 'transparency']),
  SettingResult(title: l.searchMaxQuality, section: l.searchPlayer, icon: _player, route: '/preferences', extra: 'player', keywords: ['quality', 'bitrate', 'resolution', 'transcode', 'cap', 'max']),
  SettingResult(title: l.searchTrailerQuality, section: l.searchPlayer, icon: _player, route: '/preferences', extra: 'player', keywords: ['trailer', 'quality', 'resolution']),
  SettingResult(title: l.searchDefaultSpeed, section: l.searchPlayer, icon: _player, route: '/preferences', extra: 'player', keywords: ['speed', 'playback rate', 'fast', 'slow', 'x']),
  SettingResult(title: l.searchAutoplayNextEpisode, section: l.searchPlayer, icon: _player, route: '/preferences', extra: 'player', keywords: ['autoplay', 'next', 'episode', 'binge', 'continue']),
  SettingResult(title: l.searchRememberTrackSelections, section: l.searchPlayer, icon: _player, route: '/preferences', extra: 'player', keywords: ['track', 'audio', 'subtitle', 'remember', 'default track']),
  SettingResult(title: l.searchPreviewThumbnailsWhileSeeking, section: l.searchPlayer, icon: _player, route: '/preferences', extra: 'player', keywords: ['thumbnail', 'preview', 'trickplay', 'scrub', 'seek', 'hover']),
  SettingResult(title: l.searchAutoSkipIntros, section: l.searchPlayer, icon: _player, route: '/preferences', extra: 'player', keywords: ['skip', 'intro', 'opening', 'media segments']),
  SettingResult(title: l.searchAutoSkipCredits, section: l.searchPlayer, icon: _player, route: '/preferences', extra: 'player', keywords: ['skip', 'credits', 'outro', 'ending', 'media segments']),
  SettingResult(title: l.searchUpNextTiming, section: l.searchPlayer, icon: _player, route: '/preferences', extra: 'player', keywords: ['up next', 'next episode', 'countdown', 'credits', 'autoplay', 'netflix', 'binge', 'card']),
  SettingResult(title: l.searchUpNextStyle, section: l.searchPlayer, icon: _player, route: '/preferences', extra: 'player', keywords: ['up next', 'next episode', 'style', 'card', 'pill', 'netflix', 'progress', 'countdown']),
  SettingResult(title: l.searchHardwareDecoding, section: l.searchPlayer, icon: _player, route: '/preferences', extra: 'player', keywords: ['hardware', 'hwdec', 'gpu', 'decode', 'acceleration', 'glitch']),
  SettingResult(title: l.prefsAudioPassthrough, section: l.searchPlayer, icon: _player, route: '/preferences', extra: 'player', keywords: ['audio', 'passthrough', 'atmos', 'dolby', 'dts', 'surround', 'receiver', 'bitstream', 'spdif', 'hdmi', 'ac3', 'eac3', 'truehd', 'avr']),
  SettingResult(title: l.searchPlayerBackend, section: l.searchPlayer, icon: _player, route: '/preferences', extra: 'player', keywords: ['exoplayer', 'exo', 'media_kit', 'mediakit', 'libmpv', 'backend', 'engine', 'hdr', '4k', 'tunneling', 'android tv']),
  SettingResult(title: l.prefsDisplaySync, section: l.searchPlayer, icon: _player, route: '/preferences', extra: 'player', keywords: ['smooth', 'motion', 'display sync', 'vsync', 'judder', 'stutter', 'tearing', 'refresh', 'frame pacing', 'interpolation']),

  // Audio & Subtitles
  SettingResult(title: l.searchAudioLanguage, section: l.searchAudioSubtitles, icon: _audio, route: '/preferences', extra: 'audio', keywords: ['audio', 'language', 'dub', 'track', 'default audio']),
  SettingResult(title: l.prefsReplayGain, section: l.searchAudioSubtitles, icon: _audio, route: '/preferences', extra: 'audio', keywords: ['replaygain', 'replay gain', 'volume', 'loudness', 'normalize', 'normalise', 'levelling', 'leveling', 'gain', 'music', 'quiet', 'loud']),
  SettingResult(title: l.searchSubtitleLanguage, section: l.searchAudioSubtitles, icon: _audio, route: '/preferences', extra: 'audio', keywords: ['subtitle', 'caption', 'cc', 'language', 'subs']),
  SettingResult(title: l.searchSubtitleSize, section: l.searchAudioSubtitles, icon: _audio, route: '/preferences', extra: 'audio', keywords: ['subtitle', 'caption', 'size', 'scale', 'font', 'text size']),
  SettingResult(title: l.searchSubtitleColor, section: l.searchAudioSubtitles, icon: _audio, route: '/preferences', extra: 'audio', keywords: ['subtitle', 'caption', 'color', 'colour', 'text color']),
  SettingResult(title: l.searchSubtitleBackground, section: l.searchAudioSubtitles, icon: _audio, route: '/preferences', extra: 'audio', keywords: ['subtitle', 'caption', 'background', 'box', 'shadow', 'opacity']),
  SettingResult(title: l.searchSubtitlePosition, section: l.searchAudioSubtitles, icon: _audio, route: '/preferences', extra: 'audio', keywords: ['subtitle', 'caption', 'position', 'placement', 'vertical']),
  SettingResult(title: l.searchShowLyricsAutomatically, section: l.searchAudioSubtitles, icon: _audio, route: '/preferences', extra: 'audio', keywords: ['lyrics', 'music', 'karaoke', 'synced']),
  SettingResult(title: l.searchLookUpMissingLyricsOnline, section: l.searchAudioSubtitles, icon: _audio, route: '/preferences', extra: 'audio', keywords: ['lyrics', 'online', 'fetch', 'lrclib', 'music']),

  // Ratings
  SettingResult(title: l.searchRottenTomatoesCritics, section: l.searchRatings, icon: _ratings, route: '/preferences', extra: 'ratings', keywords: ['rotten tomatoes', 'rt', 'critics', 'tomatometer', 'rating']),
  SettingResult(title: l.searchRottenTomatoesAudience, section: l.searchRatings, icon: _ratings, route: '/preferences', extra: 'ratings', keywords: ['rotten tomatoes', 'rt', 'audience', 'popcorn', 'rating']),
  SettingResult(title: l.searchImdbRating, section: l.searchRatings, icon: _ratings, route: '/preferences', extra: 'ratings', keywords: ['imdb', 'rating', 'score']),
  SettingResult(title: l.searchCommunityScore, section: l.searchRatings, icon: _ratings, route: '/preferences', extra: 'ratings', keywords: ['community', 'jellyfin', 'tmdb', 'vote', 'average', 'rating']),
  SettingResult(title: l.searchMoreRatingsMdblist, section: l.searchRatings, icon: _ratings, route: '/preferences', extra: 'ratings', keywords: ['mdblist', 'api key', 'letterboxd', 'metacritic', 'metacritic user', 'trakt', 'roger ebert', 'myanimelist', 'mal', 'rating', 'sources']),

  // YouTube
  SettingResult(title: l.searchEnableYouTube, section: l.searchYouTube, icon: _youtube, route: '/preferences', extra: 'youtube', keywords: ['youtube', 'enable', 'sidebar']),
  SettingResult(title: l.searchAutoplay, section: l.searchYouTube, icon: _youtube, route: '/preferences', extra: 'youtube', keywords: ['youtube', 'autoplay', 'next', 'recommended']),
  SettingResult(title: l.searchShowDislikeCounts, section: l.searchYouTube, icon: _youtube, route: '/preferences', extra: 'youtube', keywords: ['youtube', 'dislike', 'return youtube dislike', 'ryd', 'votes']),
  SettingResult(title: l.searchDeClickbaitTitles, section: l.searchYouTube, icon: _youtube, route: '/preferences', extra: 'youtube', keywords: ['youtube', 'dearrow', 'clickbait', 'titles', 'thumbnails']),
  SettingResult(title: l.searchDefaultQuality, section: l.searchYouTube, icon: _youtube, route: '/preferences', extra: 'youtube', keywords: ['youtube', 'quality', 'resolution', 'default']),
  SettingResult(title: l.searchSkipBack, section: l.searchYouTube, icon: _youtube, route: '/preferences', extra: 'youtube', keywords: ['youtube', 'skip', 'rewind', 'seek back', 'seconds']),
  SettingResult(title: l.searchSkipForward, section: l.searchYouTube, icon: _youtube, route: '/preferences', extra: 'youtube', keywords: ['youtube', 'skip', 'forward', 'seek', 'seconds']),
  SettingResult(title: l.searchListViewMode, section: l.searchYouTube, icon: _youtube, route: '/preferences', extra: 'youtube', keywords: ['youtube', 'list', 'grid', 'layout', 'view']),
  SettingResult(title: l.searchThumbnailQuality, section: l.searchYouTube, icon: _youtube, route: '/preferences', extra: 'youtube', keywords: ['youtube', 'thumbnail', 'quality', 'data']),
  SettingResult(title: l.searchDownloadQuality, section: l.searchYouTube, icon: _youtube, route: '/preferences', extra: 'youtube', keywords: ['youtube', 'download', 'quality', 'offline', 'mp3', 'audio', 'm4a', 'format', 'bitrate']),
  SettingResult(title: l.searchVideoContainer, section: l.searchYouTube, icon: _youtube, route: '/preferences', extra: 'youtube', keywords: ['youtube', 'download', 'video', 'container', 'mp4', 'mkv', 'format']),
  SettingResult(title: l.searchContentLanguage, section: l.searchYouTube, icon: _youtube, route: '/preferences', extra: 'youtube', keywords: ['youtube', 'language', 'region', 'results']),
  SettingResult(title: l.searchContentCountry, section: l.searchYouTube, icon: _youtube, route: '/preferences', extra: 'youtube', keywords: ['youtube', 'country', 'region', 'locale']),
  SettingResult(title: l.searchRestrictedMode, section: l.searchYouTube, icon: _youtube, route: '/preferences', extra: 'youtube', keywords: ['youtube', 'restricted', 'safe', 'mature', 'filter', 'safety']),
  SettingResult(title: l.searchShowComments, section: l.searchYouTube, icon: _youtube, route: '/preferences', extra: 'youtube', keywords: ['youtube', 'comments']),
  SettingResult(title: l.searchShowUpNext, section: l.searchYouTube, icon: _youtube, route: '/preferences', extra: 'youtube', keywords: ['youtube', 'up next', 'related', 'recommended']),
  SettingResult(title: l.searchShowDescription, section: l.searchYouTube, icon: _youtube, route: '/preferences', extra: 'youtube', keywords: ['youtube', 'description']),
  SettingResult(title: l.searchKeepWatchHistory, section: l.searchYouTube, icon: _youtube, route: '/preferences', extra: 'youtube', keywords: ['youtube', 'history', 'watch history', 'privacy']),
  SettingResult(title: l.searchResumePlayback, section: l.searchYouTube, icon: _youtube, route: '/preferences', extra: 'youtube', keywords: ['youtube', 'resume', 'continue', 'position']),
  SettingResult(title: l.searchKeepSearchHistory, section: l.searchYouTube, icon: _youtube, route: '/preferences', extra: 'youtube', keywords: ['youtube', 'search history', 'privacy']),
  SettingResult(title: l.searchSkipSponsorSegments, section: l.searchYouTube, icon: _youtube, route: '/preferences', extra: 'youtube', keywords: ['youtube', 'sponsorblock', 'sponsor', 'skip', 'ads', 'segments', 'intro', 'outro']),
  SettingResult(title: l.searchClearWatchHistory, section: l.searchYouTube, icon: _youtube, route: '/preferences', extra: 'youtube', keywords: ['youtube', 'clear', 'delete', 'history', 'wipe']),
  SettingResult(title: l.searchClearSearchHistory, section: l.searchYouTube, icon: _youtube, route: '/preferences', extra: 'youtube', keywords: ['youtube', 'clear', 'delete', 'search history', 'wipe']),
  SettingResult(title: l.searchConfirmBeforeClearingQueue, section: l.searchYouTube, icon: _youtube, route: '/preferences', extra: 'youtube', keywords: ['youtube', 'confirm', 'queue', 'clear queue', 'prompt']),
  SettingResult(title: l.searchDownloadRetries, section: l.searchYouTube, icon: _youtube, route: '/preferences', extra: 'youtube', keywords: ['youtube', 'download', 'retries', 'retry', 'attempts']),
  SettingResult(title: l.searchSimultaneousDownloads, section: l.searchYouTube, icon: _youtube, route: '/preferences', extra: 'youtube', keywords: ['youtube', 'simultaneous', 'concurrent', 'downloads', 'parallel']),
  SettingResult(title: l.searchDownloadFolders, section: l.searchYouTube, icon: _youtube, route: '/preferences', extra: 'youtube', keywords: ['youtube', 'download', 'folder', 'location', 'path', 'directory', 'video', 'audio']),
  SettingResult(title: l.searchSayWhenSomethingIsSkipped, section: l.searchYouTube, icon: _youtube, route: '/preferences', extra: 'youtube', keywords: ['youtube', 'sponsorblock', 'skipped', 'notify', 'toast', 'undo']),
  // Integrations
  SettingResult(title: l.searchWatchTogether, section: l.searchIntegrations, icon: Icons.groups_rounded, route: '/settings', keywords: ['syncplay', 'sync play', 'watch together', 'watch party', 'group', 'together', 'enable', 'shared playback', 'sync']),
  SettingResult(title: l.settingsRadio, section: l.searchIntegrations, icon: Icons.radio_rounded, route: '/settings', keywords: ['radio', 'internet radio', 'stations', 'station', 'stream', 'icy', 'shoutcast', 'icecast', 'fm', 'am', 'enable', 'music']),
  SettingResult(title: l.settingsMovieWheel, section: l.searchIntegrations, icon: Icons.movie_filter_rounded, route: '/settings', keywords: ['wheel', 'movie wheel', 'movie night', 'spin', 'decide', 'elimination', 'random', 'randomize', 'picker', 'enable', 'watchlist', 'watch together', 'syncplay']),
];

// Admin section icons, mirroring the Server Admin hub.
const _aGeneral = Icons.tune_rounded;
const _aPlayback = Icons.play_circle_outline_rounded;
const _aBranding = Icons.brush_rounded;
const _aNetwork = Icons.lan_rounded;
const _aKeys = Icons.key_rounded;
const _aLibraries = Icons.video_library_rounded;
const _aUsers = Icons.people_alt_rounded;
const _aDevices = Icons.devices_other_rounded;
const _aSessions = Icons.wifi_tethering_rounded;
const _aLiveTv = Icons.live_tv_rounded;
const _aDvr = Icons.fiber_dvr_rounded;
const _aTasks = Icons.schedule_rounded;
const _aActivity = Icons.history_rounded;
const _aLogs = Icons.description_outlined;
const _aBackups = Icons.inventory_2_outlined;
const _aSystem = Icons.dns_rounded;
const _aPlugins = Icons.extension_rounded;

/// Searchable server-admin settings. Same upkeep rule as [userSettingsIndex]:
/// add or amend an entry (with synonyms) whenever an admin setting changes.
List<SettingResult> adminSettingsIndex(AppLocalizations l) => <SettingResult>[
  // General
  SettingResult(title: l.searchGeneral, section: l.searchServerConfiguration, icon: _aGeneral, route: '/admin/general', keywords: ['name', 'language', 'display', 'resume', 'metadata', 'country']),
  SettingResult(title: l.searchServerName, section: l.searchGeneral, icon: _aGeneral, route: '/admin/general', keywords: ['server name', 'title']),
  SettingResult(title: l.searchPreferredMetadataLanguage, section: l.searchGeneral, icon: _aGeneral, route: '/admin/general', keywords: ['metadata', 'language', 'preferred']),
  SettingResult(title: l.searchCountry, section: l.searchGeneral, icon: _aGeneral, route: '/admin/general', keywords: ['country', 'region', 'metadata']),
  SettingResult(title: l.searchQuickConnect, section: l.searchGeneral, icon: _aGeneral, route: '/admin/general', keywords: ['quick connect', 'code', 'login', 'pairing']),
  SettingResult(title: l.searchShowFolderView, section: l.searchGeneral, icon: _aGeneral, route: '/admin/general', keywords: ['folder view', 'library display']),
  SettingResult(title: l.searchResumeThresholds, section: l.searchGeneral, icon: _aGeneral, route: '/admin/general', keywords: ['resume', 'min', 'max', 'played', 'watched', 'percentage']),

  // Playback / transcoding
  SettingResult(title: l.searchPlayback, section: l.searchServerConfiguration, icon: _aPlayback, route: '/admin/playback', keywords: ['transcoding', 'transcode', 'hardware', 'acceleration', 'encoding', 'trickplay']),
  SettingResult(title: l.searchHardwareAcceleration, section: l.searchPlayback, icon: _aPlayback, route: '/admin/playback', keywords: ['hardware', 'acceleration', 'hwaccel', 'vaapi', 'nvenc', 'qsv', 'quicksync', 'gpu', 'transcode']),
  SettingResult(title: l.searchEnableHardwareEncoding, section: l.searchPlayback, icon: _aPlayback, route: '/admin/playback', keywords: ['hardware', 'encoding', 'encode', 'gpu']),
  SettingResult(title: l.searchAllowHevcAv1Encoding, section: l.searchPlayback, icon: _aPlayback, route: '/admin/playback', keywords: ['hevc', 'h265', 'av1', 'encoding', 'codec']),
  SettingResult(title: l.searchEncoderPreset, section: l.searchPlayback, icon: _aPlayback, route: '/admin/playback', keywords: ['encoder', 'preset', 'speed', 'quality', 'transcode']),
  SettingResult(title: l.searchEncodingThreadCount, section: l.searchPlayback, icon: _aPlayback, route: '/admin/playback', keywords: ['thread', 'cpu', 'cores', 'encoding']),
  SettingResult(title: l.searchToneMapping, section: l.searchPlayback, icon: _aPlayback, route: '/admin/playback', keywords: ['tone mapping', 'hdr', 'vpp', 'color']),
  SettingResult(title: l.searchSubtitleExtraction, section: l.searchPlayback, icon: _aPlayback, route: '/admin/playback', keywords: ['subtitle', 'extraction', 'burn']),
  SettingResult(title: l.searchTrickplay, section: l.searchPlayback, icon: _aPlayback, route: '/admin/playback', keywords: ['trickplay', 'scrub', 'preview', 'thumbnails', 'generate']),
  SettingResult(title: l.searchTranscodeThrottling, section: l.searchPlayback, icon: _aPlayback, route: '/admin/playback', keywords: ['throttle', 'throttling', 'transcode']),

  // Branding
  SettingResult(title: l.searchBranding, section: l.searchServerConfiguration, icon: _aBranding, route: '/admin/branding', keywords: ['branding', 'splash', 'login message', 'custom css']),
  SettingResult(title: l.searchLoginMessage, section: l.searchBranding, icon: _aBranding, route: '/admin/branding', keywords: ['login', 'message', 'disclaimer', 'welcome']),
  SettingResult(title: l.searchCustomCss, section: l.searchBranding, icon: _aBranding, route: '/admin/branding', keywords: ['css', 'custom', 'style', 'theme']),
  SettingResult(title: l.searchSplashScreenImage, section: l.searchBranding, icon: _aBranding, route: '/admin/branding', keywords: ['splash', 'image', 'screen']),

  // Networking
  SettingResult(title: l.searchNetworking, section: l.searchServerConfiguration, icon: _aNetwork, route: '/admin/network', keywords: ['network', 'remote', 'access', 'url', 'ports', 'https', 'proxy']),
  SettingResult(title: l.searchAllowRemoteConnections, section: l.searchNetworking, icon: _aNetwork, route: '/admin/network', keywords: ['remote', 'access', 'external', 'wan']),
  SettingResult(title: l.searchPublishedServerUrl, section: l.searchNetworking, icon: _aNetwork, route: '/admin/network', keywords: ['base url', 'published', 'domain', 'address', 'external url']),
  SettingResult(title: l.searchHttpHttpsPorts, section: l.searchNetworking, icon: _aNetwork, route: '/admin/network', keywords: ['port', 'http', 'https', 'public port', 'internal port', '8096', '8920']),
  SettingResult(title: l.searchEnableHttps, section: l.searchNetworking, icon: _aNetwork, route: '/admin/network', keywords: ['https', 'ssl', 'tls', 'certificate', 'secure']),
  SettingResult(title: l.searchCertificatePathPassword, section: l.searchNetworking, icon: _aNetwork, route: '/admin/network', keywords: ['certificate', 'pfx', 'ssl', 'tls', 'password']),
  SettingResult(title: l.searchEnableUpnp, section: l.searchNetworking, icon: _aNetwork, route: '/admin/network', keywords: ['upnp', 'port forwarding', 'router']),
  SettingResult(title: l.searchEnableIpv6, section: l.searchNetworking, icon: _aNetwork, route: '/admin/network', keywords: ['ipv6']),
  SettingResult(title: l.searchKnownProxies, section: l.searchNetworking, icon: _aNetwork, route: '/admin/network', keywords: ['proxy', 'reverse proxy', 'known proxies', 'forwarded']),
  SettingResult(title: l.searchLanNetworks, section: l.searchNetworking, icon: _aNetwork, route: '/admin/network', keywords: ['lan', 'local network', 'subnet']),
  SettingResult(title: l.searchAutodiscovery, section: l.searchNetworking, icon: _aNetwork, route: '/admin/network', keywords: ['autodiscovery', 'discovery', 'dlna']),

  // Content & access
  SettingResult(title: l.searchApiKeys, section: l.searchServerConfiguration, icon: _aKeys, route: '/admin/apikeys', keywords: ['api', 'keys', 'tokens', 'access']),
  SettingResult(title: l.searchLibraries, section: l.searchContentAccess, icon: _aLibraries, route: '/admin/libraries', keywords: ['library', 'media', 'folders', 'scan', 'refresh']),
  SettingResult(title: l.searchUsers, section: l.searchContentAccess, icon: _aUsers, route: '/admin/users', keywords: ['users', 'accounts', 'permissions', 'password', 'create user']),
  SettingResult(title: l.searchDevices, section: l.searchContentAccess, icon: _aDevices, route: '/admin/devices', keywords: ['devices', 'clients', 'registered']),
  SettingResult(title: l.searchActiveSessions, section: l.searchContentAccess, icon: _aSessions, route: '/admin/sessions', keywords: ['sessions', 'connected', 'now playing', 'send message']),

  // Live TV
  SettingResult(title: l.searchLiveTv, section: l.searchLiveTv, icon: _aLiveTv, route: '/admin/livetv', keywords: ['live tv', 'tuner', 'guide', 'xmltv', 'schedules direct', 'hdhomerun', 'm3u']),
  SettingResult(title: l.searchDvr, section: l.searchLiveTv, icon: _aDvr, route: '/admin/dvr', keywords: ['dvr', 'recording', 'scheduled', 'series', 'timers']),

  // Maintenance
  SettingResult(title: l.searchScheduledTasks, section: l.searchMaintenance, icon: _aTasks, route: '/admin/tasks', keywords: ['tasks', 'scheduled', 'jobs', 'scan', 'background', 'cron']),
  SettingResult(title: l.searchActivityLog, section: l.searchMaintenance, icon: _aActivity, route: '/admin/activity', keywords: ['activity', 'events', 'log', 'history']),
  SettingResult(title: l.searchLogs, section: l.searchMaintenance, icon: _aLogs, route: '/admin/logs', keywords: ['logs', 'log files', 'debug', 'ffmpeg']),
  SettingResult(title: l.adminBackupsTitle, section: l.searchMaintenance, icon: _aBackups, route: '/admin/backups', keywords: ['backup', 'backups', 'restore', 'snapshot', 'database', 'migrate']),
  SettingResult(title: l.searchSystem, section: l.searchMaintenance, icon: _aSystem, route: '/admin/system', keywords: ['system', 'server info', 'restart', 'shutdown', 'version']),

  // Extensions
  SettingResult(title: l.searchPlugins, section: l.searchExtensions, icon: _aPlugins, route: '/admin/plugins', keywords: ['plugins', 'catalog', 'repositories', 'install', 'extensions']),
];

/// Filters an index to entries matching [query], keeping list order.
List<SettingResult> searchSettings(
    List<SettingResult> index, String query) {
  final q = query.trim();
  if (q.isEmpty) return const [];
  return index.where((e) => e.matches(q)).toList();
}
