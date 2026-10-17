// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Fathom';

  @override
  String get commonClear => 'Clear';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonApply => 'Apply';

  @override
  String get commonReset => 'Reset';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonRemove => 'Remove';

  @override
  String get commonClose => 'Close';

  @override
  String get commonDone => 'Done';

  @override
  String get commonEdit => 'Edit';

  @override
  String get commonAdd => 'Add';

  @override
  String get commonRefresh => 'Refresh';

  @override
  String get commonBack => 'Back';

  @override
  String get commonNext => 'Next';

  @override
  String get commonPrevious => 'Previous';

  @override
  String get commonSignIn => 'Sign In';

  @override
  String get commonSignOut => 'Sign Out';

  @override
  String get commonSearch => 'Search';

  @override
  String get commonOff => 'Off';

  @override
  String get commonOn => 'On';

  @override
  String get commonPlay => 'Play';

  @override
  String get commonPause => 'Pause';

  @override
  String get commonSomethingWrong => 'Something went wrong';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSearchHint => 'Search settings';

  @override
  String settingsNoMatch(String query) {
    return 'No settings match “$query”';
  }

  @override
  String get settingsSectionPreferences => 'Preferences';

  @override
  String get settingsSectionIntegrations => 'Integrations';

  @override
  String get settingsSectionAccount => 'Account';

  @override
  String get settingsSectionAbout => 'About';

  @override
  String get settingsSectionSystem => 'System';

  @override
  String get settingsGeneral => 'General';

  @override
  String get settingsGeneralSubtitle => 'Startup, notifications, storage';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsAppearanceSubtitle => 'Theme, accent color, AMOLED';

  @override
  String get settingsHome => 'Home';

  @override
  String get settingsHomeSubtitle => 'Banner and home rows';

  @override
  String get settingsPlayer => 'Player';

  @override
  String get settingsPlayerSubtitle => 'Video fit, autoplay, skip, quality';

  @override
  String get settingsAudioSubtitles => 'Audio & Subtitles';

  @override
  String get settingsAudioSubtitlesSubtitle => 'Languages, subtitles, lyrics';

  @override
  String get settingsRatings => 'Ratings';

  @override
  String get settingsRatingsSubtitle => 'Rotten Tomatoes, IMDb, community';

  @override
  String get settingsShortcuts => 'Keyboard Shortcuts';

  @override
  String get settingsShortcutsSubtitle => 'View & customize player keys';

  @override
  String get settingsSeerr => 'Seerr';

  @override
  String get settingsSeerrSubtitle => 'Discover & request media';

  @override
  String get settingsYouTube => 'YouTube';

  @override
  String get settingsYouTubeSubtitle => 'Search & watch, ad-free';

  @override
  String get settingsWatchTogether => 'Watch Together';

  @override
  String get settingsWatchTogetherSubtitle =>
      'Sync playback with others, from your profile menu';

  @override
  String get settingsMovieWheel => 'Movie Night Wheel';

  @override
  String get settingsMovieWheelSubtitle =>
      'Can\'t decide? Spin an elimination wheel from Watchlist or Watch Together';

  @override
  String get settingsRadio => 'Internet Radio';

  @override
  String get settingsRadioSubtitle =>
      'Search, save, and play radio stations from the sidebar';

  @override
  String get settingsProfileSubtitle => 'View profile, change picture';

  @override
  String get settingsAccounts => 'Accounts';

  @override
  String get settingsAccountsSubtitle => 'Switch server or user, add account';

  @override
  String get settingsServer => 'Server';

  @override
  String get serverAddressesTitle => 'Server Addresses';

  @override
  String get serverAddressInternalLabel => 'Home Address';

  @override
  String get serverAddressExternalLabel => 'Remote Address';

  @override
  String get serverAddressInternalHint => 'http://192.168.1.10:8096';

  @override
  String get serverAddressExternalHint => 'https://jellyfin.example.com';

  @override
  String get serverAddressHelp =>
      'Fathom uses the Home address on your local network and the Remote address elsewhere, switching automatically. Leave Home blank to always use the Remote address.';

  @override
  String get serverAddressHome => 'Home';

  @override
  String get serverAddressRemote => 'Remote';

  @override
  String get settingsFromTraceApps => 'from TraceApps';

  @override
  String settingsVersion(String version) {
    return 'Version $version';
  }

  @override
  String get settingsUpdates => 'Updates';

  @override
  String get settingsUpdatesSubtitle => 'Check for new versions';

  @override
  String get updatesTitle => 'Updates';

  @override
  String updateCurrentVersion(String version) {
    return 'Current Version: $version';
  }

  @override
  String get updateChannelLabel => 'Update Channel';

  @override
  String get updateChannelStable => 'Stable';

  @override
  String get updateChannelBeta => 'Dev';

  @override
  String get updateChannelHelp =>
      'Dev includes the latest pre-release test builds.';

  @override
  String get updateAutoCheckLabel => 'Automatic Update Checks';

  @override
  String get updateFrequencyLabel => 'How Often';

  @override
  String get updateFrequencyLaunch => 'Every Launch';

  @override
  String get updateFrequencyDaily => 'Daily';

  @override
  String get updateFrequencyWeekly => 'Weekly';

  @override
  String get updateCheckNow => 'Check for Updates';

  @override
  String get updateChecking => 'Checking…';

  @override
  String get updateUpToDate => 'You\'re on the latest version.';

  @override
  String get updateBannerAction => 'View';

  @override
  String get updateBannerCta => 'Tap to view what\'s new and install.';

  @override
  String get updateBannerDismiss => 'Dismiss update banner';

  @override
  String updateAvailableHeadline(String version) {
    return 'Version $version is available';
  }

  @override
  String get updateReleaseNotes => 'Release Notes';

  @override
  String get updateViewOnGitHub => 'View on GitHub';

  @override
  String get updateDownloadInstall => 'Download & Install';

  @override
  String get updateInstallDownloaded => 'Install';

  @override
  String updateDownloading(String percent) {
    return 'Downloading… $percent%';
  }

  @override
  String get updateInstallFailed =>
      'Download failed. Try again, or use View on GitHub.';

  @override
  String get updateCheckFailedNote =>
      'Couldn\'t reach GitHub. Check your connection and try again.';

  @override
  String updateBannerAvailable(String version) {
    return 'Update available: $version';
  }

  @override
  String get updateView => 'View';

  @override
  String updateNotifTitle(String version) {
    return 'Fathom $version is available';
  }

  @override
  String get updateNotifBody => 'Open Updates to download and install.';

  @override
  String get commonDismiss => 'Dismiss';

  @override
  String get settingsSupport => 'Support';

  @override
  String get settingsSupportSubtitle =>
      'Ko-fi, GitHub Sponsors, and free ways to help';

  @override
  String get settingsSponsor => 'GitHub Sponsors';

  @override
  String get supportLead =>
      'Fathom is free and always will be. Support is optional and never unlocks anything.';

  @override
  String get supportOtherWays => 'Other Ways to Help';

  @override
  String get supportStar => 'Star on GitHub';

  @override
  String get supportStarSubtitle =>
      'Stars are how open source projects get found.';

  @override
  String get supportReportBug => 'Report a Bug';

  @override
  String get supportReportBugSubtitle =>
      'A clear report fixes it for everyone who hits the same thing.';

  @override
  String get supportTranslate => 'Help Translate';

  @override
  String get supportTranslateSubtitle => 'Make Fathom usable in your language.';

  @override
  String get settingsLicenses => 'Open Source Licenses';

  @override
  String get settingsLicensesSubtitle => 'The software Fathom is built on';

  @override
  String get settingsSignOut => 'Sign Out';

  @override
  String get prefsSectionGeneral => 'General';

  @override
  String get prefsSectionAppearance => 'Appearance';

  @override
  String get prefsSectionHome => 'Home';

  @override
  String get prefsSectionPlayer => 'Player';

  @override
  String get prefsSectionAudio => 'Audio & Subtitles';

  @override
  String get prefsSectionRatings => 'Ratings';

  @override
  String get prefsSectionYoutube => 'YouTube';

  @override
  String get prefsSettingsFallback => 'Settings';

  @override
  String get prefsLanguageServerDefault => 'Server Default';

  @override
  String get prefsLanguageEnglish => 'English';

  @override
  String get prefsLanguageSpanish => 'Spanish';

  @override
  String get prefsLanguageFrench => 'French';

  @override
  String get prefsLanguageGerman => 'German';

  @override
  String get prefsLanguageItalian => 'Italian';

  @override
  String get prefsLanguageJapanese => 'Japanese';

  @override
  String get prefsLanguageKorean => 'Korean';

  @override
  String get prefsLanguageChinese => 'Chinese';

  @override
  String get prefsLanguagePortuguese => 'Portuguese';

  @override
  String get prefsLanguageRussian => 'Russian';

  @override
  String get prefsLanguageDutch => 'Dutch';

  @override
  String get prefsNone => 'None';

  @override
  String get prefsBitrateAutoMax => 'Auto (max)';

  @override
  String get prefsBitrate2Mobile => '2 Mbps (mobile)';

  @override
  String get prefsHeaderPlayback => 'Playback';

  @override
  String get prefsHeaderBrowsing => 'Browsing';

  @override
  String get prefsHeaderDownloads => 'Downloads';

  @override
  String get prefsHeaderContent => 'Content';

  @override
  String get prefsHeaderWatchPage => 'Watch Page';

  @override
  String get prefsHeaderHistory => 'History';

  @override
  String get prefsHeaderStartup => 'Startup';

  @override
  String get prefsHeaderNotifications => 'Notifications';

  @override
  String get prefsHeaderStorage => 'Storage';

  @override
  String get prefsHeaderMoreRatings => 'More Ratings (MDBList)';

  @override
  String get prefsHeaderSkipping => 'Skipping';

  @override
  String get prefsHeaderAdvanced => 'Advanced';

  @override
  String get prefsHeaderAudio => 'Audio';

  @override
  String get prefsReplayGain => 'Volume Levelling';

  @override
  String get prefsReplayGainSub =>
      'Play every song at a similar loudness, using the levels stored in your files';

  @override
  String get prefsReplayGainOff => 'Off';

  @override
  String get prefsReplayGainTrack => 'Per Track';

  @override
  String get prefsReplayGainAlbum => 'Per Album';

  @override
  String get prefsReplayGainFallback => 'Untagged Music';

  @override
  String get prefsReplayGainFallbackSub =>
      'Adjustment for files with no levels stored in them. Leave at 0 dB to play them untouched.';

  @override
  String get prefsHeaderSubtitles => 'Subtitles';

  @override
  String get prefsHeaderLyrics => 'Lyrics';

  @override
  String get prefsYtEnable => 'Enable YouTube';

  @override
  String get prefsYtEnableSub => 'Adds a YouTube section to the sidebar';

  @override
  String get prefsYtAutoplay => 'Autoplay';

  @override
  String get prefsYtAutoplaySub => 'Play a recommended video when one ends';

  @override
  String get prefsYtShowDislikes => 'Show Dislike Counts';

  @override
  String get prefsYtShowDislikesSub =>
      'Estimated dislikes via Return YouTube Dislike';

  @override
  String get prefsYtDeArrow => 'De-Clickbait Titles';

  @override
  String get prefsYtDeArrowSub =>
      'Crowd-sourced non-clickbait titles via DeArrow';

  @override
  String get prefsYtDefaultQuality => 'Default Quality';

  @override
  String get prefsYtDefaultQualitySub => 'Resolution videos start at';

  @override
  String get prefsQualityAuto => 'Auto (up to 1080p)';

  @override
  String get prefsYtSkipBack => 'Skip Back';

  @override
  String get prefsYtSkipBackSub => 'How far the back button jumps';

  @override
  String prefsSeconds(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seconds',
      one: '1 second',
    );
    return '$_temp0';
  }

  @override
  String get prefsYtSkipForward => 'Skip Forward';

  @override
  String get prefsYtSkipForwardSub => 'How far the forward button jumps';

  @override
  String get prefsYtConfirmClearQueue => 'Confirm Before Clearing Queue';

  @override
  String get prefsYtListMode => 'List View Mode';

  @override
  String get prefsYtListModeSub => 'How videos are laid out';

  @override
  String get prefsListModeList => 'List';

  @override
  String get prefsListModeGrid => 'Grid';

  @override
  String get prefsYtThumbnailQuality => 'Thumbnail Quality';

  @override
  String get prefsYtThumbnailQualitySub =>
      'Lower loads faster and uses less data';

  @override
  String get prefsQualityLow => 'Low';

  @override
  String get prefsQualityMedium => 'Medium';

  @override
  String get prefsQualityHigh => 'High';

  @override
  String get prefsQualityMaximum => 'Maximum';

  @override
  String get prefsYtDownloadQuality => 'Download Quality';

  @override
  String get prefsYtDownloadQualitySub => 'Ask each time, or always use this';

  @override
  String get prefsAskEachTime => 'Ask Each Time';

  @override
  String get prefsYtDownloadAudioM4a => 'Audio (M4A)';

  @override
  String get prefsYtVideoContainer => 'Video Container';

  @override
  String get prefsYtVideoContainerSub =>
      'File type for video downloads (MKV needs ffmpeg)';

  @override
  String get prefsYtRetries => 'Retries';

  @override
  String get prefsYtRetriesSub => 'Attempts per chunk before giving up';

  @override
  String get prefsYtSimultaneous => 'Simultaneous Downloads';

  @override
  String get prefsYtSimultaneousSub =>
      'More at once mostly splits the same bandwidth';

  @override
  String get prefsYtContentLanguage => 'Content Language';

  @override
  String get prefsYtContentLanguageSub => 'Language YouTube returns results in';

  @override
  String get prefsYtContentCountry => 'Content Country';

  @override
  String get prefsYtContentCountrySub => 'Region results are tailored to';

  @override
  String get prefsYtRestrictedMode => 'Restricted Mode';

  @override
  String get prefsYtRestrictedModeSub =>
      'Uses YouTube\'s own filtering of mature content';

  @override
  String get prefsYtShowComments => 'Show Comments';

  @override
  String get prefsYtShowUpNext => 'Show Up Next';

  @override
  String get prefsYtShowUpNextSub =>
      'Related videos beside or below the player';

  @override
  String get prefsYtShowDescription => 'Show Description';

  @override
  String get prefsYtKeepWatchHistory => 'Keep Watch History';

  @override
  String get prefsYtKeepWatchHistorySub =>
      'Off stops recording it, on this device';

  @override
  String get prefsYtResumePlayback => 'Resume Playback';

  @override
  String get prefsYtResumePlaybackSub => 'Pick videos up where you left off';

  @override
  String get prefsYtKeepSearchHistory => 'Keep Search History';

  @override
  String get prefsYtInfoParagraph =>
      'Videos are streamed directly and play in the same player as the rest of the app, so there are no ads. Higher resolutions are decoded on the CPU, so Auto stays at 1080p for smooth playback. Subscriptions, playlists and history are kept on this device: no account is involved, and nothing is sent to YouTube.';

  @override
  String get prefsRatingsIntro =>
      'Choose which scores appear on movie and show pages. Rotten Tomatoes and IMDb figures come from Seerr when it is connected.';

  @override
  String get prefsRtCritics => 'Rotten Tomatoes Critics';

  @override
  String get prefsRtAudience => 'Rotten Tomatoes Audience';

  @override
  String get prefsImdbRating => 'IMDb Rating';

  @override
  String get prefsCommunityScore => 'Community Score';

  @override
  String get prefsCommunityScoreSub =>
      'Jellyfin\'s own rating / TMDB vote average';

  @override
  String get prefsMdbListIntro =>
      'Adds Letterboxd, Metacritic, Trakt and more, and fills in any missing Rotten Tomatoes / IMDb scores above. Needs a free MDBList API key (mdblist.com). Ratings barely change, so results are cached.';

  @override
  String get prefsMdbListApiKey => 'MDBList API Key';

  @override
  String get prefsMdbListApiKeyHint => 'Paste your key from mdblist.com';

  @override
  String get prefsMetacriticUser => 'Metacritic User';

  @override
  String get prefsMdbAddKeyToEnable => 'Add an MDBList API key to enable';

  @override
  String get prefsOpenOnStartup => 'Open on Startup';

  @override
  String get prefsOpenOnStartupSub =>
      'Which screen to show when Fathom launches';

  @override
  String get prefsStartupHome => 'Home';

  @override
  String get prefsStartupLibraries => 'Libraries';

  @override
  String get prefsStartupLiveTv => 'Live TV';

  @override
  String get prefsDesktopNotifications => 'System Notifications';

  @override
  String get prefsDesktopNotificationsSub =>
      'Show system pop-ups on desktop and mobile (the in-app bell always collects)';

  @override
  String get prefsNotifNewRequest => 'New Request';

  @override
  String get prefsNotifNewRequestSub =>
      'When a Seerr request is made (pending approval)';

  @override
  String get prefsNotifApproved => 'Request Approved';

  @override
  String get prefsNotifApprovedSub => 'When a Seerr request is approved';

  @override
  String get prefsNotifDeclined => 'Request Declined';

  @override
  String get prefsNotifDeclinedSub => 'When a Seerr request is declined';

  @override
  String get prefsNotifAvailable => 'Now Available';

  @override
  String get prefsNotifAvailableSub => 'When a requested title has downloaded';

  @override
  String get prefsCheckRequestUpdates => 'Check for Request Updates';

  @override
  String get prefsCheckRequestUpdatesSub =>
      'How often to poll Seerr for status changes';

  @override
  String get prefsEveryMinute => 'Every Minute';

  @override
  String get prefsEvery5Minutes => 'Every 5 Minutes';

  @override
  String get prefsEvery15Minutes => 'Every 15 Minutes';

  @override
  String get prefsEvery30Minutes => 'Every 30 Minutes';

  @override
  String get prefsDownloadComplete => 'Download Complete';

  @override
  String get prefsDownloadCompleteSub =>
      'When a download to this device finishes';

  @override
  String get prefsNotifUpdates => 'Update Available';

  @override
  String get prefsNotifUpdatesSub =>
      'When a new version of Fathom is available';

  @override
  String get prefsTheme => 'Theme';

  @override
  String get prefsAuto => 'Auto';

  @override
  String get prefsThemeDark => 'Dark';

  @override
  String get prefsThemeLight => 'Light';

  @override
  String get prefsAccentColor => 'Accent Color';

  @override
  String get prefsAmoledBlack => 'AMOLED Black';

  @override
  String get prefsAmoledBlackSub => 'Pure-black backgrounds in dark mode';

  @override
  String get prefsInterfaceSize => 'Interface Size';

  @override
  String get prefsInterfaceSizeSub =>
      'Makes everything bigger or smaller. Automatic follows your display.';

  @override
  String prefsInterfaceSizeAuto(int percent) {
    return 'Automatic ($percent%)';
  }

  @override
  String prefsInterfaceSizePercent(int percent) {
    return '$percent%';
  }

  @override
  String get prefsForceTvMode => 'Force TV Mode';

  @override
  String get prefsForceTvModeSub =>
      'Use the 10-foot remote interface even if this device isn\'t a television. Applies after restarting the app.';

  @override
  String get prefsRatingOnCards => 'Rating on Cards';

  @override
  String get prefsRatingOnCardsSub => 'A rating badge on poster cards';

  @override
  String get prefsCardRatingCommunity => 'Community';

  @override
  String get prefsCardRatingCritics => 'Critics';

  @override
  String get prefsCustomAccent => 'Custom Accent';

  @override
  String get prefsHomeBanner => 'Home Banner';

  @override
  String get prefsHomeBannerSub => 'Featured titles at the top of Home';

  @override
  String get prefsBannerCarousel => 'Carousel';

  @override
  String get prefsBannerDetailed => 'Detailed';

  @override
  String get prefsBannerHidden => 'Hidden';

  @override
  String get prefsHomeLayout => 'Home Layout';

  @override
  String get prefsHomeLayoutSub => 'Reorder & toggle the Home rows';

  @override
  String get prefsNavLayout => 'Navigation';

  @override
  String get prefsNavLayoutSub => 'Reorder & hide the sidebar items';

  @override
  String get navLayoutTitle => 'Navigation';

  @override
  String get navLayoutSubtitle =>
      'Drag to reorder. Turn items off to hide them from the sidebar.';

  @override
  String get prefsVideoFit => 'Video Fit';

  @override
  String get prefsFitContain => 'Fit';

  @override
  String get prefsFitCover => 'Fill Screen';

  @override
  String get prefsFitFill => 'Stretch';

  @override
  String get prefsControlBar => 'Control Bar';

  @override
  String get prefsControlBarSub => 'Background behind the playback controls';

  @override
  String get prefsBarNoGlass => 'No Glass';

  @override
  String get prefsBarGlass => 'Glass';

  @override
  String get prefsBarDarkGlass => 'Dark Glass';

  @override
  String get prefsMaxQuality => 'Max Quality';

  @override
  String get prefsMaxQualitySub => 'Cap when the server has to transcode';

  @override
  String get prefsTrailerQuality => 'Trailer Quality';

  @override
  String get prefsTrailerQualitySub => 'Resolution for in-app YouTube trailers';

  @override
  String get prefsDefaultSpeed => 'Default Speed';

  @override
  String get prefsDefaultSpeedSub => 'Playback rate when a video starts';

  @override
  String get prefsSpeedNormal => 'Normal';

  @override
  String get prefsAutoplayNext => 'Autoplay Next Episode';

  @override
  String get prefsRememberTracks => 'Remember Track Selections';

  @override
  String get prefsPreviewThumbnails => 'Preview Thumbnails While Seeking';

  @override
  String get prefsPreviewThumbnailsSub =>
      'Show a thumbnail when hovering the seek bar, where available';

  @override
  String get prefsAutoSkipIntros => 'Auto-Skip Intros';

  @override
  String get prefsAutoSkipIntrosSub =>
      'Needs a Media Segments provider on the server';

  @override
  String get prefsAutoSkipCredits => 'Auto-Skip Credits';

  @override
  String get prefsUpNextTiming => 'Up Next Timing';

  @override
  String get prefsUpNextTimingSub =>
      'How long the Up Next prompt shows before auto-playing the next episode';

  @override
  String get prefsUpNextFullCredits => 'Full credits';

  @override
  String prefsUpNextSecondsBefore(int count) {
    return 'After ${count}s';
  }

  @override
  String get prefsUpNextStyle => 'Up Next Style';

  @override
  String get prefsUpNextStyleSub =>
      'How the next-episode prompt looks during credits';

  @override
  String get prefsUpNextStyleCard => 'Card';

  @override
  String get prefsUpNextStylePill => 'Pill';

  @override
  String get playerUpNextPlayNow => 'Play Now';

  @override
  String get playerUpNextHide => 'Hide';

  @override
  String playerUpNextIn(int seconds) {
    return 'Playing in ${seconds}s';
  }

  @override
  String get prefsHardwareDecoding => 'Hardware Decoding';

  @override
  String get prefsHardwareDecodingSub =>
      'Turn off if some videos glitch or fail';

  @override
  String get prefsAudioPassthrough => 'Audio Passthrough';

  @override
  String get prefsAudioPassthroughSub =>
      'Send Dolby Atmos / DTS to a connected receiver untouched. Only for an AV receiver or soundbar; leave off for regular speakers.';

  @override
  String get prefsDisplaySync => 'Smooth Motion (Display Sync)';

  @override
  String get prefsDisplaySyncSub =>
      'Pace video to your monitor\'s refresh rate to reduce judder and stutter. Try it if playback isn\'t as smooth as another player.';

  @override
  String get prefsDiagnosticLogging => 'Diagnostic Logging';

  @override
  String get prefsDiagnosticLoggingSub =>
      'Capture a verbose playback log to copy into a bug report. Turn on, reproduce the issue, then copy. Slightly slower while on.';

  @override
  String get prefsCopyDiagnostics => 'Copy Diagnostics';

  @override
  String get prefsCopyDiagnosticsSub =>
      'Copy the captured log and system info to the clipboard';

  @override
  String get prefsDiagnosticsCopied => 'Diagnostics copied to clipboard';

  @override
  String get prefsDiagnosticsEmpty =>
      'Play something with logging on first, then copy';

  @override
  String get diagnosticsTitle => 'Diagnostics';

  @override
  String get diagnosticsSubtitle => 'Capture logs to troubleshoot a problem';

  @override
  String get diagnosticsIntro =>
      'Turn on Diagnostic Logging, reproduce the problem, then copy the log into a bug report. Capture covers errors, app activity, and detailed playback info. It stays off until you turn it on, and credentials are removed from anything captured.';

  @override
  String get diagnosticsClear => 'Clear Captured Log';

  @override
  String get diagnosticsCleared => 'Diagnostic log cleared';

  @override
  String get prefsAudioLanguage => 'Audio Language';

  @override
  String get prefsSubtitleLanguage => 'Subtitle Language';

  @override
  String get prefsSubtitleSize => 'Subtitle Size';

  @override
  String prefsPercent(int percent) {
    return '$percent%';
  }

  @override
  String get prefsSubtitleColor => 'Subtitle Color';

  @override
  String get prefsSubtitleBackground => 'Subtitle Background';

  @override
  String get prefsSubtitlePosition => 'Subtitle Position';

  @override
  String get prefsSubtitlePositionBottom => 'Bottom';

  @override
  String prefsSubtitlePositionHigher(int amount) {
    return '$amount higher';
  }

  @override
  String get prefsSubtitlePreview => 'Subtitle preview';

  @override
  String get prefsShowLyricsAuto => 'Show Lyrics Automatically';

  @override
  String get prefsShowLyricsAutoSub =>
      'Open lyrics when a song has them. Artwork stays one tap away.';

  @override
  String get prefsLookUpLyrics => 'Look Up Missing Lyrics Online';

  @override
  String get prefsLookUpLyricsSub =>
      'When your server has none, fetch from LrcLib. Song title and artist are sent to lrclib.net.';

  @override
  String prefsClearConfirmTitle(String what) {
    return 'Clear $what?';
  }

  @override
  String get prefsClearCannotUndo => 'This can\'t be undone.';

  @override
  String get prefsClearWatchHistory => 'Clear Watch History';

  @override
  String get prefsNothingRecorded => 'Nothing recorded';

  @override
  String prefsWatchHistoryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count videos, including resume positions',
      one: '1 video, including resume positions',
    );
    return '$_temp0';
  }

  @override
  String get prefsWhatWatchHistory => 'watch history';

  @override
  String get prefsWatchHistoryCleared => 'Watch history cleared.';

  @override
  String get prefsClearSearchHistory => 'Clear Search History';

  @override
  String prefsSearchHistoryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count searches',
      one: '1 search',
    );
    return '$_temp0';
  }

  @override
  String get prefsWhatSearchHistory => 'search history';

  @override
  String get prefsSearchHistoryCleared => 'Search history cleared.';

  @override
  String get prefsAudioDownloadFolder => 'Audio Download Folder';

  @override
  String get prefsVideoDownloadFolder => 'Video Download Folder';

  @override
  String get prefsVideoFolder => 'Video Folder';

  @override
  String get prefsAudioFolder => 'Audio Folder';

  @override
  String get prefsDefault => 'Default';

  @override
  String get prefsDownloadLocation => 'Download Location';

  @override
  String get prefsDownloadLocationPick => 'Choose Download Location';

  @override
  String get prefsSbSkip => 'Skip Sponsor Segments';

  @override
  String get prefsSbSkipSub =>
      'Skips ad reads inside the video. Not YouTube\'s ads — those never reach this app.';

  @override
  String get prefsSbNotify => 'Say When Something Is Skipped';

  @override
  String get prefsSbNotifySub => 'With an Undo, in case it was wrong';

  @override
  String get prefsSbCategories => 'Categories';

  @override
  String get prefsSbAttribution =>
      'Segment data comes from SponsorBlock (sponsor.ajay.app), crowdsourced and licensed CC BY-NC-SA 4.0. Coverage depends on people having submitted timestamps for a video, so it is dense on some channels and absent on others. Video ids are sent to SponsorBlock\'s servers while this is on.';

  @override
  String get prefsImageCache => 'Image Cache';

  @override
  String get prefsCalculating => 'Calculating…';

  @override
  String prefsImageCacheSub(String size) {
    return 'Posters, backdrops and thumbnails · $size';
  }

  @override
  String get prefsClearing => 'Clearing…';

  @override
  String get profileTitle => 'Profile';

  @override
  String get profilePictureUpdated => 'Profile picture updated';

  @override
  String get profilePictureRemoved => 'Profile picture removed';

  @override
  String get profileChangePhoto => 'Change Photo';

  @override
  String get profileRemovePhoto => 'Remove Photo';

  @override
  String get profileChangePassword => 'Change Password';

  @override
  String get profileCurrentPassword => 'Current Password';

  @override
  String get profileNewPassword => 'New Password';

  @override
  String get profileConfirmPassword => 'Confirm New Password';

  @override
  String get profilePasswordMismatch => 'The new passwords don\'t match.';

  @override
  String get profileAdminNeedsPassword =>
      'Administrator accounts must have a password and can\'t be left blank.';

  @override
  String get profileNoPasswordTitle => 'Remove Your Password?';

  @override
  String get profileNoPasswordBody =>
      'Leaving the new password blank removes your password. Anyone with access to your account will be able to sign in without one.';

  @override
  String get profileNoPasswordConfirm => 'Remove Password';

  @override
  String get profilePasswordChanged => 'Password changed.';

  @override
  String get accountTitle => 'Accounts';

  @override
  String get accountAdd => 'Add Account';

  @override
  String get accountAddSubtitle => 'Sign in to another server or user';

  @override
  String get seerrIntro =>
      'Connect your Seerr instance to discover and request media.';

  @override
  String get seerrServerUrl => 'Server URL';

  @override
  String get seerrApiKeySegment => 'API Key';

  @override
  String get seerrApiKeyLabel => 'API Key';

  @override
  String get seerrApiKeyHelper =>
      'Requests are made as the admin (auto-approved).';

  @override
  String get seerrSaveTest => 'Save & Test';

  @override
  String get seerrSignedIn => 'Signed in';

  @override
  String get seerrRequestsAttributed => 'Requests are attributed to you.';

  @override
  String get seerrSignInHelp =>
      'Sign in with your Jellyfin username and password. Requests are made as you, following your Seerr permissions.';

  @override
  String get seerrUsernameLabel => 'Jellyfin Username';

  @override
  String get seerrPasswordLabel => 'Password';

  @override
  String get seerrDisconnected => 'Seerr disconnected';

  @override
  String get seerrConnected => 'Connected to Seerr';

  @override
  String get seerrSavedTestFailed => 'Saved, but the connection test failed';

  @override
  String get seerrEnterCredentials =>
      'Enter the server URL, username and password.';

  @override
  String get seerrEnterCredentialsLocal =>
      'Enter the server URL, email and password.';

  @override
  String get seerrLoginWithJellyfin => 'Login with Jellyfin';

  @override
  String get seerrLoginWithSeerr => 'Login with Seerr';

  @override
  String get seerrLocalSignInHelp =>
      'Sign in with a Seerr account (email and password) created directly in Seerr, not through Jellyfin.';

  @override
  String get seerrEmailLabel => 'Email';

  @override
  String seerrSignedInAs(String name) {
    return 'Signed in as $name';
  }

  @override
  String get seerrSignedOut => 'Signed out';

  @override
  String get shortcutsTitle => 'Keyboard Shortcuts';

  @override
  String get shortcutsHelp =>
      'Space and media keys always play/pause; Esc exits fullscreen. Tap a shortcut to reassign it.';

  @override
  String get shortcutsPressKey => 'Press a Key';

  @override
  String get shortcutsWaiting => 'Waiting for a key press…';

  @override
  String get shortcutsPlayPause => 'Play / Pause';

  @override
  String get shortcutsSeekBackward => 'Seek Backward 10s';

  @override
  String get shortcutsSeekForward => 'Seek Forward 10s';

  @override
  String get shortcutsVolumeUp => 'Volume Up';

  @override
  String get shortcutsVolumeDown => 'Volume Down';

  @override
  String get shortcutsMute => 'Mute';

  @override
  String get shortcutsFullscreen => 'Fullscreen';

  @override
  String get homeLayoutTitle => 'Home Layout';

  @override
  String get homeLayoutContinueWatching => 'Continue Watching';

  @override
  String get homeLayoutNextUp => 'Next Up';

  @override
  String get homeLayoutRecentlyAdded => 'Recently Added';

  @override
  String get homeLayoutMyMedia => 'My Media';

  @override
  String get homeLayoutLatestByLibrary => 'Latest by Library';

  @override
  String get homeLayoutLatestByLibrarySubtitle =>
      'Show a \"Latest in…\" row for each movie & show library';

  @override
  String get homeLayoutGenreRows => 'Genre Rows';

  @override
  String get homeLayoutGenreRowsSubtitle =>
      'Editorial rows by genre for browsing variety';

  @override
  String get playerLoading => 'Loading…';

  @override
  String get playerTuningIn => 'Tuning in…';

  @override
  String get playerSubtitles => 'Subtitles';

  @override
  String get playerAudio => 'Audio';

  @override
  String get playerQuality => 'Quality';

  @override
  String playerQualityLabel(String label) {
    return 'Quality ($label)';
  }

  @override
  String get playerChapters => 'Chapters';

  @override
  String get playerPlaybackSpeed => 'Playback Speed';

  @override
  String get playerMore => 'More';

  @override
  String get playerSettings => 'Settings';

  @override
  String get playerPlaybackInfo => 'Playback Info';

  @override
  String get playerPlayPause => 'Play / Pause';

  @override
  String playerSeekBack(int seconds) {
    return 'Back ${seconds}s';
  }

  @override
  String playerSeekForward(int seconds) {
    return 'Forward ${seconds}s';
  }

  @override
  String get playerStatPlayMethod => 'Play Method';

  @override
  String get playerStatVideo => 'Video';

  @override
  String get playerStatAudio => 'Audio';

  @override
  String get playerStatGeneral => 'General';

  @override
  String get playerStatResolution => 'Resolution';

  @override
  String get playerStatCodec => 'Codec';

  @override
  String get playerStatFrameRate => 'Frame Rate';

  @override
  String get playerStatBitrate => 'Bitrate';

  @override
  String get playerStatDecoder => 'Decoder';

  @override
  String get playerStatDroppedFrames => 'Dropped Frames';

  @override
  String get playerStatChannels => 'Channels';

  @override
  String get playerStatSampleRate => 'Sample Rate';

  @override
  String get playerStatContainer => 'Container';

  @override
  String get playerStatBuffer => 'Buffer';

  @override
  String get playerStatAvSync => 'A/V Sync';

  @override
  String get playerStatHardware => 'Hardware';

  @override
  String get playerStatSoftware => 'Software';

  @override
  String get playerPlayMethodDirect => 'Direct Play';

  @override
  String get playerPlayMethodTranscode => 'Transcoding';

  @override
  String get playerPlayMethodDownloaded => 'Direct Play (Downloaded)';

  @override
  String get playerPlayMethodAdaptive => 'Adaptive (DASH)';

  @override
  String get playerPlayMethodMuxed => 'Muxed Stream';

  @override
  String get playerMute => 'Mute';

  @override
  String get playerUnmute => 'Unmute';

  @override
  String get playerVolume => 'Volume';

  @override
  String get playerMiniplayer => 'Miniplayer';

  @override
  String get playerTheaterMode => 'Theater Mode';

  @override
  String get playerDefaultView => 'Default View';

  @override
  String get playerFullscreen => 'Fullscreen';

  @override
  String get playerExitFullscreen => 'Exit Fullscreen';

  @override
  String get playerBadgeLive => 'LIVE';

  @override
  String get playerBadgeRec => 'REC';

  @override
  String get playerAuto => 'Auto';

  @override
  String get playerNone => 'None';

  @override
  String get playerSpeedNormal => 'Normal';

  @override
  String get playerChapter => 'Chapter';

  @override
  String playerChapterNumbered(int number) {
    return 'Chapter $number';
  }

  @override
  String playerTrackNumber(String id) {
    return 'Track $id';
  }

  @override
  String get playerSubtitleSearch => 'Search Subtitles Online';

  @override
  String playerSubtitleSearchIn(String language) {
    return 'Online Subtitles: $language';
  }

  @override
  String get playerSubtitleSearchLanguage => 'Change Language';

  @override
  String playerSubtitleSearchEmptyIn(String language) {
    return 'No $language subtitles found for this title';
  }

  @override
  String get playerSubtitleSearchTitle => 'Online Subtitles';

  @override
  String get playerSubtitleHashMatch => 'Matches your file';

  @override
  String playerSubtitleDownloads(int count) {
    return '$count downloads';
  }

  @override
  String get playerSubtitleDownloading => 'Downloading subtitle';

  @override
  String get playerSubtitleDownloaded => 'Subtitle added';

  @override
  String get playerSubtitleForced => 'Forced';

  @override
  String get playerSubtitlePicture => 'Picture';

  @override
  String get playerSubtitleFile => 'External';

  @override
  String playerSubtitleNumber(String id) {
    return 'Subtitle $id';
  }

  @override
  String playerPlaybackError(String error) {
    return 'Playback error: $error';
  }

  @override
  String playerPlaybackFailed(String error) {
    return 'Playback failed: $error';
  }

  @override
  String playerQualityChangeFailed(String error) {
    return 'Could not change quality: $error';
  }

  @override
  String get playerVideoSlowStart => 'This video is taking too long to start.';

  @override
  String get playerChannelSlowStart =>
      'This channel is taking too long to start. The tuner may be busy, or the server needs to transcode this stream.';

  @override
  String get playerVideoUnplayable => 'This video could not be played.';

  @override
  String get playerSkipIntro => 'Skip Intro';

  @override
  String get playerSkipRecap => 'Skip Recap';

  @override
  String get playerSkipCredits => 'Skip Credits';

  @override
  String get playerYoutubeLoadFailed => 'Could not load this video.';

  @override
  String playerSkippedSegment(String category, int seconds) {
    return 'Skipped $category (${seconds}s)';
  }

  @override
  String playerSkipSegment(String category) {
    return 'Skip: $category';
  }

  @override
  String get playerUndo => 'Undo';

  @override
  String get playerTrailer => 'Trailer';

  @override
  String playerTitleTrailer(String title) {
    return '$title — Trailer';
  }

  @override
  String get playerOpenInBrowser => 'Open in Browser';

  @override
  String get playerNothingPlaying => 'Nothing playing.';

  @override
  String get playerNowPlaying => 'Now Playing';

  @override
  String get playerQueue => 'Queue';

  @override
  String get playerUpNext => 'Up Next';

  @override
  String get playerAddFavorite => 'Add Favorite';

  @override
  String get playerRemoveFavorite => 'Remove Favorite';

  @override
  String get playerShowArtwork => 'Show Artwork';

  @override
  String get playerShowLyrics => 'Show Lyrics';

  @override
  String get playerRecord => 'Record';

  @override
  String get playerRecordingProgram => 'Recording this program';

  @override
  String get playerRecordingEveryEpisode => 'Recording every episode';

  @override
  String get playerStopRecordingTitle => 'Stop Recording?';

  @override
  String get playerStopRecordingBody =>
      'This program and the rest of the series are set to record.';

  @override
  String get playerKeepRecording => 'Keep Recording';

  @override
  String get playerStopThisProgram => 'Stop This Program';

  @override
  String get playerStopSeries => 'Stop Series';

  @override
  String get playerRecordingTapSeries => 'Recording · tap to record the series';

  @override
  String get playerRecordingSeriesTapStop =>
      'Recording the series · tap to stop';

  @override
  String get playerRecordSeries => 'Record Series';

  @override
  String get playerRecordingSet => 'Recording set';

  @override
  String get playerSeriesRecordingSet => 'Series recording set';

  @override
  String get playerPadding => 'Padding';

  @override
  String get playerStartBefore => 'Start Before';

  @override
  String get playerStopAfter => 'Stop After';

  @override
  String get playerMinutesSuffix => 'min';

  @override
  String get playerPopOut => 'Pop Out to Desktop';

  @override
  String get playerBackToApp => 'Back to App';

  @override
  String get actionRemoveFromContinueWatching =>
      'Remove from Continue Watching';

  @override
  String get actionShowDetails => 'Show Details';

  @override
  String get actionDeleteSeries => 'Delete Series';

  @override
  String get actionDeleteSeason => 'Delete Season';

  @override
  String get actionDeleteEpisode => 'Delete Episode';

  @override
  String get actionDeleteMovie => 'Delete Movie';

  @override
  String get detailResume => 'Resume';

  @override
  String get detailPlayFromStart => 'Play from Start';

  @override
  String get detailMarkWatched => 'Mark Watched';

  @override
  String get detailMarkUnwatched => 'Mark Unwatched';

  @override
  String get detailAddFavorite => 'Add to Favorites';

  @override
  String get detailRemoveFavorite => 'Remove from Favorites';

  @override
  String get detailAddToWatchlist => 'Add to Watchlist';

  @override
  String get detailRemoveFromWatchlist => 'Remove from Watchlist';

  @override
  String get detailSeries => 'Series';

  @override
  String get detailMovie => 'Movie';

  @override
  String get detailSpecials => 'Specials';

  @override
  String detailSeasonNumber(int number) {
    return 'Season $number';
  }

  @override
  String get detailEpisodes => 'Episodes';

  @override
  String detailRuntimeMinutes(int minutes) {
    return '${minutes}m';
  }

  @override
  String get detailDownload => 'Download';

  @override
  String get downloadAll => 'Download All';

  @override
  String get downloadsTvShows => 'TV Shows';

  @override
  String get downloadsTracks => 'Tracks';

  @override
  String downloadEpisodeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodes',
      one: '1 episode',
    );
    return '$_temp0';
  }

  @override
  String get downloadsCancelAll => 'Cancel All';

  @override
  String get downloadsCancelAllConfirm => 'Cancel all downloads in progress?';

  @override
  String get downloadCancel => 'Cancel';

  @override
  String get detailDownloading => 'Downloading';

  @override
  String get detailDownloadingTooltip => 'Downloading…';

  @override
  String get detailDownloaded => 'Downloaded';

  @override
  String get detailDownloadedTooltip => 'Downloaded — tap to remove';

  @override
  String get detailDownloadFailedTooltip => 'Download failed — retry';

  @override
  String get detailRemoveDownload => 'Remove Download';

  @override
  String detailRemoveOfflineCopy(String title) {
    return 'Remove the offline copy of \"$title\"?';
  }

  @override
  String get detailCastAction => 'Play On';

  @override
  String get detailPlayOnAnotherDevice => 'Play on Another Device';

  @override
  String get detailPlayOnAnotherDeviceTitle => 'Play on Another Device';

  @override
  String get detailNoControllableDevices => 'No controllable devices found';

  @override
  String get detailDevice => 'Device';

  @override
  String detailPlayingOn(String device) {
    return 'Playing on $device';
  }

  @override
  String get detailAddToPlaylist => 'Add to Playlist';

  @override
  String get detailRefreshMetadata => 'Refresh Metadata';

  @override
  String get detailMetadataRefreshStarted => 'Metadata refresh started';

  @override
  String get detailDeleteItem => 'Delete Item';

  @override
  String detailDeleteConfirm(String title) {
    return 'Permanently delete \"$title\" from the server? This cannot be undone.';
  }

  @override
  String detailDeleted(String title) {
    return 'Deleted \"$title\"';
  }

  @override
  String get detailCastCrew => 'Cast & Crew';

  @override
  String get detailNextUp => 'Next Up';

  @override
  String detailResumeCode(String code) {
    return 'Resume $code';
  }

  @override
  String detailPlayCode(String code) {
    return 'Play $code';
  }

  @override
  String detailResumeFrom(String time) {
    return 'Resume from $time';
  }

  @override
  String get detailWatchTrailer => 'Watch Trailer';

  @override
  String get detailTrailer => 'Trailer';

  @override
  String get detailExtras => 'Extras';

  @override
  String get extraTypeTrailer => 'Trailer';

  @override
  String get extraTypeBehindTheScenes => 'Behind the Scenes';

  @override
  String get extraTypeDeletedScene => 'Deleted Scene';

  @override
  String get extraTypeInterview => 'Interview';

  @override
  String get extraTypeScene => 'Scene';

  @override
  String get extraTypeFeaturette => 'Featurette';

  @override
  String get extraTypeShort => 'Short';

  @override
  String get extraTypeClip => 'Clip';

  @override
  String get extraTypeSample => 'Sample';

  @override
  String get detailMoreLikeThis => 'More Like This';

  @override
  String get detailWatch => 'Watch';

  @override
  String get detailManage => 'Manage';

  @override
  String get detailViewAll => 'View All';

  @override
  String get detailSeasons => 'Seasons';

  @override
  String get detailCollection => 'Collection';

  @override
  String get detailRecommendations => 'Recommendations';

  @override
  String get detailSimilar => 'Similar';

  @override
  String get detailStatusAvailable => 'Available';

  @override
  String get detailStatusPartiallyAvailable => 'Partially Available';

  @override
  String get detailStatusProcessing => 'Processing';

  @override
  String get detailStatusPending => 'Pending';

  @override
  String get detailStatusNotRequested => 'Not Requested';

  @override
  String get detailRequest => 'Request';

  @override
  String get detailRequested => 'Requested';

  @override
  String get detailViewRequest => 'View Request';

  @override
  String get detailApprove => 'Approve';

  @override
  String get detailDecline => 'Decline';

  @override
  String get detailRequestMore => 'Request More';

  @override
  String detailApprovedTitle(String title) {
    return 'Approved $title';
  }

  @override
  String detailDeclinedTitle(String title) {
    return 'Declined $title';
  }

  @override
  String detailEpisodeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodes',
      one: '$count episode',
    );
    return '$_temp0';
  }

  @override
  String detailPartOfCollection(String name) {
    return 'Part of the $name';
  }

  @override
  String detailEstimatedAgo(String time) {
    return 'Estimated $time ago';
  }

  @override
  String detailEstimatedIn(String time) {
    return 'Estimated in $time';
  }

  @override
  String get detailRecordingCanceled => 'Recording canceled';

  @override
  String get detailWatchNow => 'Watch Now';

  @override
  String get detailWatchChannel => 'Watch Channel';

  @override
  String get detailCancelRecording => 'Cancel Recording';

  @override
  String get detailRecord => 'Record…';

  @override
  String get detailAppearances => 'Appearances';

  @override
  String get detailAll => 'All';

  @override
  String get detailMovies => 'Movies';

  @override
  String get detailNoAppearances => 'No appearances to show.';

  @override
  String detailAlsoKnownAs(String names) {
    return 'Also known as: $names';
  }

  @override
  String get detailReadMore => 'Read More';

  @override
  String get detailReadLess => 'Read Less';

  @override
  String detailBorn(String date) {
    return 'Born $date';
  }

  @override
  String get detailNoEpisodes => 'No episodes to show.';

  @override
  String get detailCast => 'Cast';

  @override
  String get detailCrew => 'Crew';

  @override
  String get detailNoTitlesFound => 'No titles found';

  @override
  String get detailRequestSeries => 'Request Series';

  @override
  String get detailRequestMovie => 'Request Movie';

  @override
  String get detailAutoApprove =>
      'This request will be approved automatically.';

  @override
  String get detailRequestIn4k => 'Request in 4K';

  @override
  String get detailRequest4kSubtitle => 'use the 4K server and its defaults';

  @override
  String get detailAdvanced => 'Advanced';

  @override
  String get detailDestinationServer => 'Destination Server';

  @override
  String get detailQualityProfile => 'Quality Profile';

  @override
  String detailProfileDefault(String name) {
    return '$name (Default)';
  }

  @override
  String get detailRootFolder => 'Root Folder';

  @override
  String get detailLanguageProfile => 'Language Profile';

  @override
  String get detailTags => 'Tags';

  @override
  String get detailRequestAs => 'Request As';

  @override
  String get detailAllSeasonsRequested => 'All seasons will be requested.';

  @override
  String get detailColSeason => 'SEASON';

  @override
  String get detailColEpisodes => '# OF EPISODES';

  @override
  String get detailColStatus => 'STATUS';

  @override
  String detailRequestedTitle(String title) {
    return 'Requested $title.';
  }

  @override
  String get detailSelectSeasons => 'Select Season(s)';

  @override
  String get detailDismiss => 'Dismiss';

  @override
  String detailManageKind(String kind) {
    return 'Manage $kind';
  }

  @override
  String get detailRequests => 'Requests';

  @override
  String detailRetryingTitle(String title) {
    return 'Retrying $title';
  }

  @override
  String detailDeletedRequestTitle(String title) {
    return 'Deleted request for $title';
  }

  @override
  String get detailDeleteRequest => 'Delete Request';

  @override
  String get detailRemoveRequestConfirm => 'Remove this request?';

  @override
  String get detailMarkAvailable => 'Mark as Available';

  @override
  String detailMarkedAvailableTitle(String title) {
    return 'Marked $title as available';
  }

  @override
  String get detailClearData => 'Clear Data';

  @override
  String detailClearDataConfirm(String kind) {
    return 'This will irreversibly remove all data for this $kind, including any requests.';
  }

  @override
  String detailClearedDataTitle(String title) {
    return 'Cleared data for $title';
  }

  @override
  String detailClearDataNote(String kind) {
    return '* This will irreversibly remove all data for this $kind, including any requests. If this item exists in your Jellyfin library, the media information will be recreated during the next scan.';
  }

  @override
  String get detailKindMovieLower => 'movie';

  @override
  String get detailKindSeriesLower => 'series';

  @override
  String get detailStatusDeclined => 'Declined';

  @override
  String get detailStatusFailed => 'Failed';

  @override
  String get detailStatusApproved => 'Approved';

  @override
  String get detailSomeone => 'Someone';

  @override
  String get detailDeleteRequestTooltip => 'Delete Request';

  @override
  String detailSeasonList(String seasons) {
    return 'Season $seasons';
  }

  @override
  String get detailEditRequest => 'Edit Request';

  @override
  String detailRequestPending(String name) {
    return '$name\'s request is pending approval.';
  }

  @override
  String get detailNoEditableOptions =>
      'No editable options are available for this request.';

  @override
  String get detailSelectTags => 'Select Tags';

  @override
  String get detailAddSlider => 'Add Slider';

  @override
  String get detailTitle => 'Title';

  @override
  String get detailSliderTitleHint =>
      'optional, defaults to the genre or keyword';

  @override
  String get detailType => 'Type';

  @override
  String get detailMovieGenre => 'Movie Genre';

  @override
  String get detailTvGenre => 'TV Genre';

  @override
  String get detailKeyword => 'Keyword';

  @override
  String get detailKeywordHint => 'e.g. Christmas, zombie, heist';

  @override
  String get detailGenre => 'Genre';

  @override
  String get browseLibraries => 'Libraries';

  @override
  String get browseGenres => 'Genres';

  @override
  String get browseStudios => 'Studios';

  @override
  String get browseArtists => 'Artists';

  @override
  String get browseFavorites => 'Favorites';

  @override
  String selectionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selected',
      one: '1 selected',
    );
    return '$_temp0';
  }

  @override
  String get selectionSelectAll => 'Select All';

  @override
  String selectionMarkedWatched(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Marked $count as watched',
      one: 'Marked 1 as watched',
    );
    return '$_temp0';
  }

  @override
  String selectionMarkedUnwatched(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Marked $count as unwatched',
      one: 'Marked 1 as unwatched',
    );
    return '$_temp0';
  }

  @override
  String selectionFavorited(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Added $count to favorites',
      one: 'Added 1 to favorites',
    );
    return '$_temp0';
  }

  @override
  String selectionUnfavorited(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Removed $count from favorites',
      one: 'Removed 1 from favorites',
    );
    return '$_temp0';
  }

  @override
  String selectionDeleteTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $count items?',
      one: 'Delete 1 item?',
    );
    return '$_temp0';
  }

  @override
  String get selectionDeleteBody =>
      'This removes the files from your server. It cannot be undone.';

  @override
  String selectionDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Deleted $count items',
      one: 'Deleted 1 item',
    );
    return '$_temp0';
  }

  @override
  String get actionSelect => 'Select';

  @override
  String get browseWatchlist => 'Watchlist';

  @override
  String get browsePlaylists => 'Playlists';

  @override
  String get browseDownloads => 'Downloads';

  @override
  String get browseDiscover => 'Discover';

  @override
  String get browseRequests => 'Requests';

  @override
  String get browseContinueWatching => 'Continue Watching';

  @override
  String get autoHome => 'Home';

  @override
  String get autoLibrary => 'Library';

  @override
  String get autoShuffleAll => 'Shuffle All';

  @override
  String get autoFavoritesMix => 'Favorites Mix';

  @override
  String get autoRecentlyPlayed => 'Recently Played';

  @override
  String get autoRecentlyAdded => 'Recently Added';

  @override
  String get autoGenres => 'Genres';

  @override
  String get autoRadio => 'Radio';

  @override
  String get autoRadioFavorites => 'Favorites';

  @override
  String get autoRadioOther => 'Other';

  @override
  String get autoPlaylists => 'Playlists';

  @override
  String get autoAlbums => 'Albums';

  @override
  String get autoArtists => 'Artists';

  @override
  String get autoFavoriteSongs => 'Favorite Songs';

  @override
  String get autoYoutube => 'YouTube';

  @override
  String get autoYoutubeWhatsNew => 'What\'s New';

  @override
  String get autoYoutubePlaylists => 'Your Playlists';

  @override
  String get autoYoutubeSubscriptions => 'Subscriptions';

  @override
  String get browseNextUp => 'Next Up';

  @override
  String get browseRecentlyAdded => 'Recently Added';

  @override
  String get browseMyMedia => 'My Media';

  @override
  String browseLatestIn(String library) {
    return 'Latest in $library';
  }

  @override
  String browseCouldNotLoad(String title) {
    return 'Could not load $title';
  }

  @override
  String get browseNothingHereYet => 'Nothing here yet.';

  @override
  String get browseNoLibraries => 'No libraries';

  @override
  String get browseNoGenres => 'No genres';

  @override
  String get browseNoStudios => 'No studios';

  @override
  String get browseNoArtists => 'No artists';

  @override
  String get browseNoAlbums => 'No albums';

  @override
  String get browseNoFavorites => 'No favorites yet';

  @override
  String get browseNoWatchlist => 'Your watchlist is empty';

  @override
  String get browseLibraryEmpty => 'This library is empty';

  @override
  String get browseCollectionEmpty => 'This collection is empty';

  @override
  String get browseNoResults => 'No results';

  @override
  String get browseTryDifferentSearch => 'Try a different search.';

  @override
  String get browseSearchLibraryTitle => 'Search Your Library';

  @override
  String get browseSearchLibraryMessage =>
      'Movies, shows, episodes, music and more.';

  @override
  String get browseSearchHint => 'Search movies, shows, music…';

  @override
  String get browseRecentSearches => 'Recent Searches';

  @override
  String get browseSuggested => 'Suggested';

  @override
  String get browseAll => 'All';

  @override
  String get browseMovies => 'Movies';

  @override
  String get browseShows => 'Shows';

  @override
  String get browseEpisodes => 'Episodes';

  @override
  String get browseMusic => 'Music';

  @override
  String get browseTvShows => 'TV Shows';

  @override
  String get browseFilter => 'Filter';

  @override
  String get browseFilters => 'Filters';

  @override
  String get browseUnwatched => 'Unwatched';

  @override
  String get browseGenre => 'Genre';

  @override
  String get browseAscending => 'Ascending';

  @override
  String get browseDescending => 'Descending';

  @override
  String get browseListView => 'List View';

  @override
  String get browseGridView => 'Grid View';

  @override
  String get browseSortBy => 'Sort by';

  @override
  String browseItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '$count item',
    );
    return '$_temp0';
  }

  @override
  String get browseSortName => 'Name';

  @override
  String get browseSortDateAdded => 'Date Added';

  @override
  String get browseSortReleaseDate => 'Release Date';

  @override
  String get browseSortRating => 'Rating';

  @override
  String get browseSortRandom => 'Random';

  @override
  String browseNothingInGenre(String genre) {
    return 'Nothing in $genre';
  }

  @override
  String browseNothingFromStudio(String studio) {
    return 'Nothing from $studio';
  }

  @override
  String browseTitlesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count titles',
      one: '$count title',
    );
    return '$_temp0';
  }

  @override
  String get browseShuffle => 'Shuffle';

  @override
  String get browseMore => 'More';

  @override
  String get browsePlayNext => 'Play Next';

  @override
  String get browseAddToQueue => 'Add to Queue';

  @override
  String browseSongsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count songs',
      one: '$count song',
    );
    return '$_temp0';
  }

  @override
  String browseMinutesShort(int min) {
    return '$min min';
  }

  @override
  String get browseDetails => 'Details';

  @override
  String get browseInMyList => 'In My List';

  @override
  String get browseAddToMyList => 'Add to My List';

  @override
  String get browseConnectSeerr => 'Connect Seerr';

  @override
  String get browseConnectSeerrMessage =>
      'Add your Seerr URL and API key to discover and request.';

  @override
  String get browseSetUp => 'Set Up';

  @override
  String get browseCustomizeDiscover => 'Customize Discover';

  @override
  String get browseSettings => 'Settings';

  @override
  String get browseRecentRequests => 'Recent Requests';

  @override
  String get browseTrending => 'Trending';

  @override
  String get browsePopularMovies => 'Popular Movies';

  @override
  String get browseMovieGenres => 'Movie Genres';

  @override
  String get browseUpcomingMovies => 'Upcoming Movies';

  @override
  String get browsePopularSeries => 'Popular Series';

  @override
  String get browseSeriesGenres => 'Series Genres';

  @override
  String get browseUpcomingSeries => 'Upcoming Series';

  @override
  String get browseNetworks => 'Networks';

  @override
  String get browseSeeAll => 'See All';

  @override
  String get browseNothingToShow => 'Nothing to show';

  @override
  String get browseSortPopularity => 'Popularity';

  @override
  String get browseSortNewest => 'Newest';

  @override
  String get browseSortTopRated => 'Top Rated';

  @override
  String get browseSort => 'Sort';

  @override
  String get browseAddSlider => 'Add Slider';

  @override
  String get browseReorderHint =>
      'Drag the handle or use the arrows to reorder. Toggle a row off to hide it from Discover.';

  @override
  String get browseCustomSlider => 'Custom Slider';

  @override
  String get browseMoveUp => 'Move Up';

  @override
  String get browseMoveDown => 'Move Down';

  @override
  String get browseDeleteSlider => 'Delete Slider';

  @override
  String get browseSeerrSearchHint => 'Search movies & TV to request';

  @override
  String get browseSearchSeerrTitle => 'Search Seerr';

  @override
  String get browseSearchSeerrMessage =>
      'Find any movie or show to request it.';

  @override
  String get browseDeclined => 'Declined';

  @override
  String get browseFailed => 'Failed';

  @override
  String get browseAvailable => 'Available';

  @override
  String get browsePartiallyAvailable => 'Partially Available';

  @override
  String get browseProcessing => 'Processing';

  @override
  String get browsePending => 'Pending';

  @override
  String get browseApproved => 'Approved';

  @override
  String get browseCompleted => 'Completed';

  @override
  String get browseUnavailable => 'Unavailable';

  @override
  String get browseDeleted => 'Deleted';

  @override
  String get browseSortMostRecent => 'Most Recent';

  @override
  String get browseSortLastModified => 'Last Modified';

  @override
  String get browseToggleSortDirection => 'Toggle Sort Direction';

  @override
  String get browseApprove => 'Approve';

  @override
  String get browseDecline => 'Decline';

  @override
  String get browseEditRequest => 'Edit Request';

  @override
  String get browseDeleteRequest => 'Delete Request';

  @override
  String browseRemoveFromService(String service) {
    return 'Remove from $service';
  }

  @override
  String get browseThisSeries => 'this series';

  @override
  String get browseThisMovie => 'this movie';

  @override
  String get browseSeasonLabel => 'Season';

  @override
  String get browseStatus => 'Status';

  @override
  String get browseRequested => 'Requested';

  @override
  String get browseModified => 'Modified';

  @override
  String get browseProfile => 'Profile';

  @override
  String get browseSeasons => 'Seasons';

  @override
  String browseSeriesNumber(int id) {
    return 'Series #$id';
  }

  @override
  String browseMovieNumber(int id) {
    return 'Movie #$id';
  }

  @override
  String browseApprovedTitle(String title) {
    return 'Approved $title';
  }

  @override
  String browseDeclinedTitle(String title) {
    return 'Declined $title';
  }

  @override
  String browseRetryingTitle(String title) {
    return 'Retrying $title';
  }

  @override
  String browseDeletedRequestFor(String title) {
    return 'Deleted request for $title';
  }

  @override
  String browseRemovedFromService(String title, String service) {
    return 'Removed $title from $service';
  }

  @override
  String get browseDone => 'Done';

  @override
  String get browseRequestUpdated => 'Request updated';

  @override
  String browseConfirmUndone(String action) {
    return '$action? This cannot be undone.';
  }

  @override
  String get browseNoRequests => 'No requests';

  @override
  String get browseNoRequestsMessage =>
      'Requests you make will appear here to track.';

  @override
  String browseDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '$count day ago',
    );
    return '$_temp0';
  }

  @override
  String browseHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours ago',
      one: '$count hour ago',
    );
    return '$_temp0';
  }

  @override
  String browseMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes ago',
      one: '$count minute ago',
    );
    return '$_temp0';
  }

  @override
  String get browseJustNow => 'just now';

  @override
  String browseAgoBy(String ago) {
    return '$ago by';
  }

  @override
  String get ytSubscriptions => 'Subscriptions';

  @override
  String get ytListen => 'Listen';

  @override
  String get ytPlayAudio => 'Play audio';

  @override
  String get ytWatchVideo => 'Watch video';

  @override
  String get ytListenAll => 'Listen to all';

  @override
  String get ytSomeUnavailable =>
      'Some videos are unavailable (age-restricted or private).';

  @override
  String get ytQueueEmpty =>
      'Nothing up next. A related track plays automatically when this one ends.';

  @override
  String get ytWhatsNew => 'What\'s New';

  @override
  String get ytPlaylists => 'Playlists';

  @override
  String get ytDownloadPill => 'YouTube Download';

  @override
  String get ytDownloads => 'Downloads';

  @override
  String get ytHistory => 'History';

  @override
  String get ytVideos => 'Videos';

  @override
  String get ytChannels => 'Channels';

  @override
  String get ytFilters => 'Filters';

  @override
  String get ytSearchYoutube => 'Search YouTube';

  @override
  String get ytSearchVideos => 'Search Videos';

  @override
  String get ytSearchVideosMessage =>
      'Videos play in-app, with no ads. Switch to Channels or Playlists above to search those instead.';

  @override
  String get ytSearchChannels => 'Search Channels';

  @override
  String get ytSearchChannelsMessage =>
      'Find a channel by name and subscribe straight from the results.';

  @override
  String get ytSearchPlaylists => 'Search Playlists';

  @override
  String get ytSearchPlaylistsMessage =>
      'Open a playlist to see everything in it.';

  @override
  String get ytRecentSearches => 'Recent Searches';

  @override
  String get ytSearchFilters => 'Search Filters';

  @override
  String get ytSortBy => 'Sort By';

  @override
  String get ytSortRelevance => 'Relevance';

  @override
  String get ytUploadDate => 'Upload Date';

  @override
  String get ytSortViewCount => 'View Count';

  @override
  String get ytSortRating => 'Rating';

  @override
  String get ytUploadAnyTime => 'Any Time';

  @override
  String get ytUploadLastHour => 'Last Hour';

  @override
  String get ytUploadToday => 'Today';

  @override
  String get ytUploadThisWeek => 'This Week';

  @override
  String get ytUploadThisMonth => 'This Month';

  @override
  String get ytUploadThisYear => 'This Year';

  @override
  String get ytLength => 'Length';

  @override
  String get ytLengthAny => 'Any Length';

  @override
  String get ytLengthUnder4 => 'Under 4 Minutes';

  @override
  String get ytLength4To20 => '4 to 20 Minutes';

  @override
  String get ytLengthOver20 => 'Over 20 Minutes';

  @override
  String get ytNoResults => 'No results';

  @override
  String get ytImportSubscriptions => 'Import Subscriptions';

  @override
  String get ytImport => 'Import';

  @override
  String get ytExport => 'Export';

  @override
  String get ytExportSubscriptions => 'Export Subscriptions';

  @override
  String get ytNoSubscriptionsTitle => 'No subscriptions yet';

  @override
  String get ytNoSubscriptionsMessage =>
      'Search for a channel, or open one from any video, and hit Subscribe. Or import from Google Takeout or a NewPipe backup. Subscriptions are kept on this device, with no account needed.';

  @override
  String get ytImportNotFound =>
      'No subscriptions found. Use YouTube\'s subscriptions.csv from Google Takeout, or a NewPipe backup.';

  @override
  String ytAlreadySubscribedAll(int count) {
    return 'Already subscribed to all $count.';
  }

  @override
  String ytAddedOfTotal(int added, int total) {
    return 'Added $added of $total.';
  }

  @override
  String ytExportedSubscriptions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Exported $count subscriptions.',
      one: 'Exported $count subscription.',
    );
    return '$_temp0';
  }

  @override
  String ytChannelCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count channels',
      one: '$count channel',
    );
    return '$_temp0';
  }

  @override
  String get ytOptions => 'Options';

  @override
  String get ytChannelFallback => 'Channel';

  @override
  String get ytFeedGroups => 'Feed Groups';

  @override
  String get ytUnsubscribe => 'Unsubscribe';

  @override
  String get ytFeedEmptyMessage =>
      'Subscribe to a channel and its newest uploads land here.';

  @override
  String get ytNothingNew => 'Nothing new';

  @override
  String get ytAll => 'All';

  @override
  String get ytNewFeedGroup => 'New Feed Group';

  @override
  String get ytName => 'Name';

  @override
  String get ytFeedGroupHint => 'Music, News, Podcasts…';

  @override
  String get ytNewGroup => 'New Group';

  @override
  String ytFeedGroupsDescription(String channel) {
    return '$channel\nGroups filter What\'s New to the channels you pick.';
  }

  @override
  String get ytCreate => 'Create';

  @override
  String get ytNewPlaylist => 'New Playlist';

  @override
  String get ytNoPlaylistsTitle => 'No playlists yet';

  @override
  String get ytNoPlaylistsMessage =>
      'Make one here, or use the menu on any video and pick Add to Playlist. You can also save someone else\'s playlist from search. Everything is kept on this device.';

  @override
  String get ytYourPlaylists => 'Your Playlists';

  @override
  String get ytSaved => 'Saved';

  @override
  String get ytRenamePlaylist => 'Rename Playlist';

  @override
  String get ytRename => 'Rename';

  @override
  String get ytNoDownloadsTitle => 'No downloads';

  @override
  String ytDownloadsEmptyFfmpeg(String path) {
    return 'Use the menu on any video and pick Download. Files are saved to $path.';
  }

  @override
  String get ytDownloadsEmptyNoFfmpeg =>
      'Use the menu on any video and pick Download. ffmpeg is not installed, so video is limited to 360p — audio downloads are unaffected.';

  @override
  String get ytDownloadsFolder => 'your Downloads folder';

  @override
  String get ytDownloadWaiting => 'Waiting';

  @override
  String get ytDownloadingAudio => 'Downloading audio';

  @override
  String get ytDownloadingVideo => 'Downloading video';

  @override
  String get ytDownloadMerging => 'Merging video and audio';

  @override
  String get ytDownloadSaved => 'Saved';

  @override
  String get ytFailed => 'Failed';

  @override
  String get ytDownloadCancelled => 'Cancelled';

  @override
  String get ytShowInFolder => 'Show in Folder';

  @override
  String get prefsDownloadFolderNote =>
      'New downloads go here. If you already have downloads, you\'ll be asked whether to move them too.';

  @override
  String get ytMoveDownloadsTitle => 'Move Existing Downloads?';

  @override
  String ytMoveDownloadsBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count downloads are in your old folder. Move them here too?',
      one: '1 download is in your old folder. Move it here too?',
    );
    return '$_temp0';
  }

  @override
  String get ytMoveDownloadsKeep => 'Keep Them Where They Are';

  @override
  String get ytMoveDownloadsMove => 'Move Them';

  @override
  String ytMoveDownloadsDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Moved $count downloads.',
      one: 'Moved 1 download.',
    );
    return '$_temp0';
  }

  @override
  String ytMoveDownloadsPartial(int moved, int total) {
    return 'Moved $moved of $total downloads. The rest couldn\'t be moved and stayed where they were.';
  }

  @override
  String prefsDownloadFolderUnavailable(String folder) {
    return 'Fathom can\'t save here, so downloads go to $folder.';
  }

  @override
  String get ytOpenWith => 'Open With';

  @override
  String get ytShareFile => 'Share';

  @override
  String get ytOpenFileFailed => 'No app on this device can open that file.';

  @override
  String get ytRemoveFromList => 'Remove from List';

  @override
  String get ytDeleteFile => 'Delete File';

  @override
  String get ytNothingWatchedTitle => 'Nothing watched yet';

  @override
  String get ytHistoryEmptyMessage =>
      'Videos you watch show up here, and pick up where you left off. History is kept on this device.';

  @override
  String get ytClearHistory => 'Clear History';

  @override
  String get ytClearHistoryConfirm =>
      'This removes every watched video and its saved position.';

  @override
  String get ytSelectDownloads => 'Select';

  @override
  String get ytSelectAll => 'Select All';

  @override
  String ytNSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selected',
      one: '1 selected',
    );
    return '$_temp0';
  }

  @override
  String ytDeleteSelectedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $count downloads?',
      one: 'Delete download?',
    );
    return '$_temp0';
  }

  @override
  String get ytDeleteSelectedConfirm =>
      'This removes the downloaded files from your device. They can be downloaded again later.';

  @override
  String get ytRemoveFromHistory => 'Remove from History';

  @override
  String get ytUpNext => 'Up Next';

  @override
  String get ytAutoplay => 'Autoplay';

  @override
  String get ytUpNextInQueue => 'Up Next in Queue';

  @override
  String get ytClearQueueTitle => 'Clear Queue?';

  @override
  String ytClearQueueConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'This removes all $count queued videos.',
      one: 'This removes all $count queued video.',
    );
    return '$_temp0';
  }

  @override
  String get ytNothingQueued => 'Nothing queued.';

  @override
  String get ytRemoveFromQueue => 'Remove from Queue';

  @override
  String get ytComments => 'Comments';

  @override
  String get ytCommentsUnavailable => 'Comments are unavailable.';

  @override
  String get ytShortUnavailable => 'Couldn\'t load this Short.';

  @override
  String ytCommentsCount(String count) {
    return 'Comments  ·  $count';
  }

  @override
  String get ytShowMoreComments => 'Show More Comments';

  @override
  String ytReplies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count replies',
      one: '$count reply',
    );
    return '$_temp0';
  }

  @override
  String get ytCouldNotLoadReplies => 'Could not load replies';

  @override
  String get ytShowMore => 'Show More';

  @override
  String get ytShowLess => 'Show Less';

  @override
  String get ytNoUploads => 'No uploads';

  @override
  String ytNothingInTab(String tab) {
    return 'Nothing in $tab';
  }

  @override
  String get ytPlaylistFallback => 'Playlist';

  @override
  String get ytSavePlaylist => 'Save Playlist';

  @override
  String get ytNothingInPlaylist => 'Nothing in this playlist';

  @override
  String get ytPlaylistNotFound => 'Playlist not found';

  @override
  String get ytMyPlaylistEmptyTitle => 'Nothing here yet';

  @override
  String get ytMyPlaylistEmptyMessage =>
      'Use the menu on any video and pick Add to Playlist.';

  @override
  String get ytRemoveFromPlaylist => 'Remove from Playlist';

  @override
  String get ytLinkCopied => 'Link copied to clipboard.';

  @override
  String get ytCouldNotOpenBrowser => 'Couldn\'t open a browser.';

  @override
  String get ytPlayNext => 'Play Next';

  @override
  String get ytQueued => 'Queued';

  @override
  String get ytAddToQueue => 'Add to Queue';

  @override
  String ytQueueCount(int count) {
    return 'Queue ($count)';
  }

  @override
  String get ytDownloaded => 'Downloaded';

  @override
  String get ytDownloading => 'Downloading';

  @override
  String get ytDownload => 'Download';

  @override
  String get ytCopyLink => 'Copy Link';

  @override
  String get ytOpenInBrowser => 'Open in Browser';

  @override
  String get ytSavedToPlaylist => 'Saved to Playlist';

  @override
  String get ytAddToPlaylist => 'Add to Playlist';

  @override
  String get ytDownloadInProgress =>
      'Downloading. Progress is in the Downloads tab.';

  @override
  String get ytType => 'Type';

  @override
  String get ytVideo => 'Video';

  @override
  String get ytAudio => 'Audio';

  @override
  String get ytContainer => 'Container';

  @override
  String get ytQuality => 'Quality';

  @override
  String get ytFormat => 'Format';

  @override
  String get ytBitrate => 'Bitrate';

  @override
  String ytSummaryMp3(int bitrate) {
    return 'MP3 at $bitrate kbps, converted with ffmpeg.';
  }

  @override
  String get ytSummaryM4a =>
      'M4A, YouTube\'s original audio with no conversion.';

  @override
  String ytSummaryMerged(int height, String box) {
    return '${height}p $box, merged from separate video and audio.';
  }

  @override
  String ytSummaryRemuxMkv(int height) {
    return '${height}p, remuxed into MKV.';
  }

  @override
  String ytSummarySingle(int height, String box) {
    return '${height}p $box, a single stream.';
  }

  @override
  String get ytFfmpegNote =>
      'ffmpeg not found, so only M4A audio can be downloaded, plus 360p MP4 for videos YouTube still offers as a single file. Install ffmpeg for MP3, MKV and higher resolutions.';

  @override
  String get ytSubscribed => 'Subscribed';

  @override
  String get ytSubscribe => 'Subscribe';

  @override
  String get ytGoToChannel => 'Go to Channel';

  @override
  String get ytSaveToPlaylist => 'Save to Playlist';

  @override
  String get ytTickToAdd =>
      'Tick a playlist to add this video. Untick to remove it.';

  @override
  String get ytNoPlaylistsDevice =>
      'No playlists yet. Playlists are kept on this device.';

  @override
  String ytPlaylistSavedSubtitle(String count) {
    return '$count  ·  Saved — untick to remove';
  }

  @override
  String get ytDownloadsScreenEmptyMessage =>
      'Download a movie or episode to watch it offline.';

  @override
  String get ytAvailableOffline => 'Available Offline';

  @override
  String get appEnterUsername => 'Please enter your username.';

  @override
  String appUnexpectedError(String error) {
    return 'Unexpected error: $error';
  }

  @override
  String get appQuickConnectNotEnabled =>
      'Quick Connect is not enabled on this server.';

  @override
  String get appUsername => 'Username';

  @override
  String get appPassword => 'Password';

  @override
  String get appOr => 'or';

  @override
  String get appUseQuickConnect => 'Use Quick Connect';

  @override
  String get appQuickConnect => 'Quick Connect';

  @override
  String get appQuickConnectInstructions =>
      'Open Quick Connect on a device where you are already signed in to Jellyfin, then enter this code.';

  @override
  String get appWaitingForApproval => 'Waiting for approval…';

  @override
  String get appConnectToServer => 'Connect to your Jellyfin server';

  @override
  String get appServerAddress => 'Server Address';

  @override
  String get appConnect => 'Connect';

  @override
  String get searchPlayerBackend => 'Video Player Engine';

  @override
  String get prefsPlayerBackend => 'Video Player (Android)';

  @override
  String get prefsPlayerBackendSub =>
      'ExoPlayer plays 4K/HDR smoothly on TV; media_kit is the classic engine.';

  @override
  String get prefsPlayerBackendAuto => 'Automatic (ExoPlayer on TV)';

  @override
  String get prefsPlayerBackendExo => 'ExoPlayer (native, 4K/HDR)';

  @override
  String get prefsPlayerBackendMediaKit => 'media_kit (libmpv)';

  @override
  String get appFindServers => 'Find Servers on My Network';

  @override
  String get appScanningServers => 'Searching your network…';

  @override
  String get appNoServersFound =>
      'No servers found. Enter the address above instead.';

  @override
  String get appTagline => 'Dive into your media';

  @override
  String get appNavHome => 'Home';

  @override
  String get appNavLibraries => 'Libraries';

  @override
  String get appNavFavorites => 'Favorites';

  @override
  String get appNavWatchlist => 'Watchlist';

  @override
  String get appNavLiveTv => 'Live TV';

  @override
  String get appNavMore => 'More';

  @override
  String get appNavRadio => 'Radio';

  @override
  String get radioTitle => 'Radio';

  @override
  String get radioNowPlaying => 'Radio';

  @override
  String get radioLiveStream => 'Live Stream';

  @override
  String get radioSearchDirectory => 'Search Directory';

  @override
  String get radioTabMyStations => 'My Stations';

  @override
  String get radioTabBrowse => 'Browse';

  @override
  String get radioStop => 'Stop';

  @override
  String get radioRewind => 'Rewind 15 seconds';

  @override
  String get radioSkip => 'Skip 15 seconds';

  @override
  String get radioPreviousStation => 'Previous Station';

  @override
  String get radioNextStation => 'Next Station';

  @override
  String get radioGroupOptions => 'Group Options';

  @override
  String get radioRenameGroup => 'Rename Group';

  @override
  String get radioDeleteGroup => 'Delete Group';

  @override
  String radioDeleteGroupBody(String group) {
    return 'Stations in \"$group\" move to Other. The stations themselves aren\'t removed.';
  }

  @override
  String get radioSearchHint => 'Search stations…';

  @override
  String get radioSearchPrompt => 'Search for a station to add';

  @override
  String get radioNoResults => 'No stations found';

  @override
  String get radioNoStations => 'No saved stations yet';

  @override
  String get radioNoStationsSub =>
      'Search the directory or add a station by URL';

  @override
  String get radioFavorites => 'Favorites';

  @override
  String get radioUngrouped => 'Other';

  @override
  String get radioAddByUrl => 'Add by URL';

  @override
  String get radioAdd => 'Add';

  @override
  String radioAdded(String name) {
    return 'Added $name';
  }

  @override
  String get radioFavorite => 'Add to Favorites';

  @override
  String get radioUnfavorite => 'Remove from Favorites';

  @override
  String get radioSetGroup => 'Set Group';

  @override
  String get radioGroup => 'Group';

  @override
  String get radioStationName => 'Station Name';

  @override
  String get radioStreamUrl => 'Stream URL';

  @override
  String get radioLogoUrl => 'Logo URL (Optional)';

  @override
  String get radioGenre => 'Genre (Optional)';

  @override
  String get radioHomepage => 'Homepage (Optional)';

  @override
  String get appServerUnreachableOffline =>
      'Server unreachable. You are offline.';

  @override
  String get appDownloads => 'Downloads';

  @override
  String get appNotifications => 'Notifications';

  @override
  String get appClearAll => 'Clear All';

  @override
  String get appNoNotifications => 'No notifications';

  @override
  String get appDismiss => 'Dismiss';

  @override
  String get appTimeNow => 'now';

  @override
  String appTimeMinutes(int count) {
    return '${count}m';
  }

  @override
  String appTimeHours(int count) {
    return '${count}h';
  }

  @override
  String appTimeDays(int count) {
    return '${count}d';
  }

  @override
  String get appCreateGroup => 'Create Group';

  @override
  String get appGroupName => 'Group Name';

  @override
  String get appCreate => 'Create';

  @override
  String get appGroupCreated => 'Group created';

  @override
  String get appOtherGroups => 'Other Groups';

  @override
  String get appOpenGroups => 'Open Groups';

  @override
  String get appNoOtherGroups => 'No other groups on this server.';

  @override
  String get appNoActiveGroups =>
      'No active groups yet. Create one above, or ask a friend to create one so it appears here.';

  @override
  String get appWatchTogether => 'Watch Together';

  @override
  String appCouldntLoadGroups(String message) {
    return 'Couldn\'t load groups. $message';
  }

  @override
  String get appSyncPlayIntro =>
      'Watch in sync with others on this server. Create a group or join one below, then everyone opens the same title to keep playback aligned.';

  @override
  String get appWatchTogetherGroup => 'Watch Together Group';

  @override
  String get appGroupConnected =>
      'Connected. Playback will sync while you watch together.';

  @override
  String appMembers(int count) {
    return 'Members ($count)';
  }

  @override
  String get appLeaveGroup => 'Leave Group';

  @override
  String get appLeaveGroupHint =>
      'Leaving turns off Watch Together for you; others stay in the group.';

  @override
  String get appNoOneWatching => 'No one watching yet';

  @override
  String appWatchingList(int count, String names) {
    return '$count watching · $names';
  }

  @override
  String get appGroup => 'Group';

  @override
  String get appJoin => 'Join';

  @override
  String get appInAGroup => 'In a group';

  @override
  String get appActive => 'Active';

  @override
  String get appNewPlaylist => 'New Playlist';

  @override
  String get appPlaylistName => 'Playlist Name';

  @override
  String appCreatedNamed(String name) {
    return 'Created \"$name\"';
  }

  @override
  String get appPlaylists => 'Playlists';

  @override
  String get appNoPlaylists => 'No playlists';

  @override
  String get appNoPlaylistsMessage =>
      'Create a playlist, then add movies, shows, or songs.';

  @override
  String appRemovedNamed(String name) {
    return 'Removed \"$name\"';
  }

  @override
  String get appDeletePlaylist => 'Delete Playlist';

  @override
  String appDeletePlaylistConfirm(String name) {
    return 'Delete \"$name\"? The items stay in your library.';
  }

  @override
  String appDeletedNamed(String name) {
    return 'Deleted \"$name\"';
  }

  @override
  String get appEmptyPlaylist => 'Empty playlist';

  @override
  String get appEmptyPlaylistMessage =>
      'Add items from any movie, show, or song page.';

  @override
  String appItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '$count item',
    );
    return '$_temp0';
  }

  @override
  String appAddedToNamed(String playlist) {
    return 'Added to \"$playlist\"';
  }

  @override
  String get appAddToPlaylist => 'Add to Playlist';

  @override
  String get appNoPlaylistsYet => 'No playlists yet.';

  @override
  String get adminTitle => 'Server Admin';

  @override
  String get adminSearchHint => 'Search server settings';

  @override
  String adminNoMatch(String query) {
    return 'No settings match “$query”';
  }

  @override
  String get adminSectionServerConfig => 'Server Configuration';

  @override
  String get adminSectionContentAccess => 'Content & Access';

  @override
  String get adminSectionLiveTv => 'Live TV';

  @override
  String get adminSectionMaintenance => 'Maintenance';

  @override
  String get adminSectionExtensions => 'Extensions';

  @override
  String get adminGeneralTitle => 'General';

  @override
  String get adminGeneralSubtitle => 'Name, language, display, resume';

  @override
  String get adminPlaybackTitle => 'Playback';

  @override
  String get adminPlaybackSubtitle => 'Transcoding & hardware acceleration';

  @override
  String get adminBrandingTitle => 'Branding';

  @override
  String get adminBrandingSubtitle => 'Splash, login message & custom CSS';

  @override
  String get adminNetworkingTitle => 'Networking';

  @override
  String get adminNetworkingSubtitle => 'Remote access, published URL, ports';

  @override
  String get adminBackupsTitle => 'Backups';

  @override
  String get adminBackupsSubtitle =>
      'Create and restore snapshots of the server';

  @override
  String get adminBackupsHelp =>
      'Create and restore snapshots of your server. A backup can include the database, metadata, subtitles, and trickplay images, and is stored on the server.';

  @override
  String get adminBackupsNone => 'No backups yet';

  @override
  String get adminBackupsUnsupported =>
      'This server does not offer backups. They need a newer version of Jellyfin.';

  @override
  String get adminBackupCreate => 'Create Backup';

  @override
  String get adminBackupDisclaimer =>
      'Depending on the size of your library, a backup can take a while.';

  @override
  String get adminBackupDatabase => 'Database';

  @override
  String get adminBackupMetadata => 'Metadata';

  @override
  String get adminBackupSubtitles => 'Subtitles';

  @override
  String get adminBackupTrickplay => 'Trickplay';

  @override
  String get adminBackupInProgress => 'Backup in progress';

  @override
  String get adminBackupCreated => 'Backup created';

  @override
  String get adminBackupTasksRunning => 'Scheduled tasks are running';

  @override
  String adminBackupTasksRunningBody(String tasks) {
    return 'It is best to wait for these to finish, or stop them, before backing up:\n\n$tasks';
  }

  @override
  String get adminBackupDetails => 'Backup Details';

  @override
  String get adminBackupPath => 'Path';

  @override
  String get adminBackupServerVersion => 'Server Version';

  @override
  String get adminBackupIncludes => 'Includes';

  @override
  String get adminBackupPathCopied => 'Path copied';

  @override
  String get adminBackupRestore => 'Restore';

  @override
  String get adminBackupRestoreTitle => 'Restore This Backup?';

  @override
  String adminBackupRestoreBody(String version) {
    return 'The server restarts and is unusable until the restore finishes, and anything added or changed since this backup was made is lost.\n\nOnly restore a backup onto the same Jellyfin version it was made on ($version). Restoring onto a different version is unsupported and can leave the server unusable.';
  }

  @override
  String get adminBackupRestoring => 'Restore in progress';

  @override
  String get adminBackupRestoringBody =>
      'Waiting for the server to come back. This can take several minutes.';

  @override
  String get adminBackupRestored => 'Restore complete';

  @override
  String get adminApiKeysTitle => 'API Keys';

  @override
  String get adminApiKeysSubtitle => 'App access tokens';

  @override
  String get adminLibrariesTitle => 'Libraries';

  @override
  String get adminLibrariesSubtitle => 'Media folders and scans';

  @override
  String get adminUsersTitle => 'Users';

  @override
  String get adminUsersSubtitle => 'Accounts and permissions';

  @override
  String get adminDevicesTitle => 'Devices';

  @override
  String get adminDevicesSubtitle => 'Registered client devices';

  @override
  String get adminSessionsTitle => 'Active Sessions';

  @override
  String get adminSessionsSubtitle => 'Who is connected now';

  @override
  String get adminLiveTvTitle => 'Live TV';

  @override
  String get adminLiveTvSubtitle => 'Tuners and TV guide';

  @override
  String get adminDvrTitle => 'DVR';

  @override
  String get adminDvrSubtitle => 'Scheduled, series & recordings';

  @override
  String get adminTasksTitle => 'Scheduled Tasks';

  @override
  String get adminTasksSubtitle => 'Run and review background jobs';

  @override
  String get adminActivityTitle => 'Activity Log';

  @override
  String get adminActivitySubtitle => 'Recent server events';

  @override
  String get adminLogsTitle => 'Logs';

  @override
  String get adminLogsSubtitle => 'Server log files';

  @override
  String get adminSystemTitle => 'System';

  @override
  String get adminSystemSubtitle => 'Server info, restart & shutdown';

  @override
  String get adminPluginsTitle => 'Plugins';

  @override
  String get adminPluginsSubtitle => 'Installed, catalog & repositories';

  @override
  String get adminNothingHere => 'Nothing here.';

  @override
  String get adminRestartServerConfirmTitle => 'Restart Server?';

  @override
  String get adminShutDownServerConfirmTitle => 'Shut Down Server?';

  @override
  String get adminRestartServerConfirmBody =>
      'The Jellyfin server will restart.';

  @override
  String get adminShutDownServerConfirmBody =>
      'The Jellyfin server will shut down and become unreachable.';

  @override
  String get adminRestart => 'Restart';

  @override
  String get adminShutDown => 'Shut Down';

  @override
  String get adminRestartRequested => 'Restart requested';

  @override
  String get adminShutdownRequested => 'Shutdown requested';

  @override
  String get adminServerLabel => 'Server';

  @override
  String get adminVersionLabel => 'Version';

  @override
  String get adminOperatingSystemLabel => 'Operating System';

  @override
  String get adminArchitectureLabel => 'Architecture';

  @override
  String get adminCreateUser => 'Create User';

  @override
  String get adminUsername => 'Username';

  @override
  String get adminPassword => 'Password';

  @override
  String get adminPasswordOptional => 'Password (optional)';

  @override
  String get adminCreate => 'Create';

  @override
  String adminCreatedUser(String name) {
    return 'Created \"$name\"';
  }

  @override
  String get adminUser => 'User';

  @override
  String get adminUserAdministrator => 'Administrator';

  @override
  String get adminUserDisabled => 'Disabled';

  @override
  String get adminScanAllLibraries => 'Scan All Libraries';

  @override
  String get adminScanThisLibrary => 'Scan This Library';

  @override
  String get adminLibraryScanStarted => 'Library scan started';

  @override
  String adminScanningLibrary(String name) {
    return 'Scanning $name';
  }

  @override
  String get adminLibraryFallback => 'library';

  @override
  String get adminCollectionTypeMixed => 'mixed';

  @override
  String adminLibrarySubtitle(String type, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count folders',
      one: '1 folder',
    );
    return '$type · $_temp0';
  }

  @override
  String get adminRunNow => 'Run Now';

  @override
  String adminTaskStarted(String name) {
    return 'Started: $name';
  }

  @override
  String get adminSendMessage => 'Send Message';

  @override
  String get adminMessageHint => 'Message';

  @override
  String get adminSend => 'Send';

  @override
  String adminMessageFrom(String name) {
    return 'Message from $name';
  }

  @override
  String get adminMessageSent => 'Message sent';

  @override
  String get adminUnknownUser => 'Unknown';

  @override
  String get adminServerName => 'Server Name';

  @override
  String get adminSectionServer => 'Server';

  @override
  String get adminSectionMetadata => 'Metadata';

  @override
  String get adminPreferredMetadataLanguage => 'Preferred Metadata Language';

  @override
  String get adminMetadataLanguageHint => 'e.g. en';

  @override
  String get adminCountry => 'Country';

  @override
  String get adminCountryHint => 'e.g. US';

  @override
  String get adminSectionLibraryDisplay => 'Library Display';

  @override
  String get adminShowFolderView => 'Show Folder View';

  @override
  String get adminShowFolderViewSubtitle => 'Add a plain folder browse view';

  @override
  String get adminSaveMetadataHidden => 'Save Metadata as Hidden Files';

  @override
  String get adminExternalContentSuggestions =>
      'External Content in Suggestions';

  @override
  String get adminSectionResume => 'Resume';

  @override
  String get adminMinResumePct => 'Minimum Resume %';

  @override
  String get adminMaxResumePct => 'Maximum Resume %';

  @override
  String get adminMinResumeDuration => 'Minimum Resume Duration (s)';

  @override
  String get adminSectionAccess => 'Access';

  @override
  String get adminQuickConnect => 'Quick Connect';

  @override
  String get adminQuickConnectSubtitle =>
      'Let users sign in with a code from an already-authorized device';

  @override
  String get adminSplashScreen => 'Splash Screen';

  @override
  String get adminSplashHint =>
      'Custom images should be 16:9, at least 1920x1080.';

  @override
  String get adminUpload => 'Upload';

  @override
  String get adminEnableSplashImage => 'Enable Splash Screen Image';

  @override
  String get adminLoginDisclaimer => 'Login Disclaimer';

  @override
  String get adminLoginDisclaimerHelper =>
      'Shown at the bottom of the sign-in page';

  @override
  String get adminCustomCss => 'Custom CSS';

  @override
  String get adminSectionHardwareAccel => 'Hardware Acceleration';

  @override
  String get adminAcceleration => 'Acceleration';

  @override
  String get adminAccelNone => 'None';

  @override
  String get adminEnableHwEncoding => 'Enable Hardware Encoding';

  @override
  String get adminEnableToneMapping => 'Enable Tone Mapping';

  @override
  String get adminEnableVppToneMapping => 'Enable VPP Tone Mapping';

  @override
  String get adminAllowHevcEncoding => 'Allow HEVC Encoding';

  @override
  String get adminAllowAv1Encoding => 'Allow AV1 Encoding';

  @override
  String get adminSectionEncoding => 'Encoding';

  @override
  String get adminEncoderPreset => 'Encoder Preset';

  @override
  String get adminPresetAuto => 'Auto';

  @override
  String get adminH264Crf => 'H.264 CRF';

  @override
  String get adminH265Crf => 'H.265 CRF';

  @override
  String get adminTranscodeThreadCount => 'Transcode Thread Count (0 = auto)';

  @override
  String get adminEnableSubtitleExtraction => 'Enable Subtitle Extraction';

  @override
  String get adminSectionThrottling => 'Throttling';

  @override
  String get adminThrottleTranscodes => 'Throttle Transcodes';

  @override
  String get adminThrottleTranscodesSubtitle =>
      'Pause transcoding when far enough ahead';

  @override
  String get adminThrottleDelay => 'Throttle Delay (s)';

  @override
  String get adminSectionTrickplay => 'Trickplay';

  @override
  String get adminTrickplayHwGeneration => 'Hardware Accelerated Generation';

  @override
  String get adminTrickplayHwEncoding => 'Hardware Accelerated Encoding';

  @override
  String get adminKeyframeOnlyExtraction => 'Keyframe-Only Extraction';

  @override
  String get adminKeyframeOnlyExtractionSubtitle =>
      'Faster, less precise scrubbing';

  @override
  String get adminScanBehavior => 'Scan Behavior';

  @override
  String get adminScanBehaviorNonBlocking => 'Non-Blocking (during scan)';

  @override
  String get adminScanBehaviorBlocking => 'Blocking (before scan finishes)';

  @override
  String get adminProcessPriority => 'Process Priority';

  @override
  String get adminPriorityHigh => 'High';

  @override
  String get adminPriorityAboveNormal => 'Above Normal';

  @override
  String get adminPriorityNormal => 'Normal';

  @override
  String get adminPriorityBelowNormal => 'Below Normal';

  @override
  String get adminPriorityIdle => 'Idle';

  @override
  String get adminInterval => 'Interval (ms)';

  @override
  String get adminWidthResolutions => 'Width Resolutions';

  @override
  String get adminWidthResolutionsHint => 'comma-separated, e.g. 320';

  @override
  String get adminTileWidth => 'Tile Width (thumbnails)';

  @override
  String get adminTileHeight => 'Tile Height (thumbnails)';

  @override
  String get adminJpegQuality => 'JPEG Quality (0-100)';

  @override
  String get adminProcessThreads => 'Process Threads (0 = auto)';

  @override
  String get adminGenerateTrickplayNow => 'Generate Trickplay Images Now';

  @override
  String get adminTrickplayGenerateHint =>
      'Save first, then generate. This runs in the background and can take a while on large libraries.';

  @override
  String get adminNoTrickplayTask => 'No trickplay task found on the server';

  @override
  String get adminGeneratingTrickplay =>
      'Generating trickplay images (runs in the background)';

  @override
  String get adminSectionPaths => 'Paths';

  @override
  String get adminTranscodingTempPath => 'Transcoding Temp Path';

  @override
  String get adminHintLeaveBlankDefault => 'Leave blank for default';

  @override
  String get adminSectionRemoteAccess => 'Remote Access';

  @override
  String get adminAllowRemoteConnections => 'Allow Remote Connections';

  @override
  String get adminBaseUrl => 'Base URL';

  @override
  String get adminSectionHttps => 'HTTPS';

  @override
  String get adminEnableHttps => 'Enable HTTPS';

  @override
  String get adminRequireHttps => 'Require HTTPS';

  @override
  String get adminCertificatePath => 'Certificate Path';

  @override
  String get adminCertificatePathHint => 'PFX file on the server';

  @override
  String get adminCertificatePassword => 'Certificate Password';

  @override
  String get adminSectionPorts => 'Ports';

  @override
  String get adminHttpPort => 'HTTP Port';

  @override
  String get adminHttpsPort => 'HTTPS Port';

  @override
  String get adminPublicHttpPort => 'Public HTTP Port';

  @override
  String get adminPublicHttpsPort => 'Public HTTPS Port';

  @override
  String get adminSectionDiscovery => 'Discovery';

  @override
  String get adminEnableUpnp => 'Enable UPnP';

  @override
  String get adminEnableAutodiscovery => 'Enable Autodiscovery';

  @override
  String get adminSectionAdvanced => 'Advanced';

  @override
  String get adminEnableIpv6 => 'Enable IPv6';

  @override
  String get adminKnownProxies => 'Known Proxies';

  @override
  String get adminKnownProxiesHint => 'comma-separated, for reverse proxies';

  @override
  String get adminLanNetworks => 'LAN Networks';

  @override
  String get adminLanNetworksHint =>
      'comma-separated CIDR, e.g. 192.168.1.0/24';

  @override
  String get adminNewApiKey => 'New API Key';

  @override
  String get adminAppName => 'App Name';

  @override
  String get adminRevokeApiKeyConfirm => 'Revoke API Key?';

  @override
  String get adminRevokeApiKeyBody => 'Apps using this key will lose access.';

  @override
  String get adminRevoke => 'Revoke';

  @override
  String get adminNewKey => 'New Key';

  @override
  String get adminNoApiKeys => 'No API keys.';

  @override
  String get adminNoLogFiles => 'No log files.';

  @override
  String get adminTabInstalled => 'Installed';

  @override
  String get adminTabCatalog => 'Catalog';

  @override
  String get adminTabRepositories => 'Repositories';

  @override
  String get adminUninstall => 'Uninstall';

  @override
  String adminUninstallConfirm(String name) {
    return 'Uninstall $name?';
  }

  @override
  String get adminUninstallBody =>
      'The plugin will be removed. A server restart may be required.';

  @override
  String adminUninstalledPlugin(String name) {
    return 'Uninstalled $name';
  }

  @override
  String get adminNoPlugins => 'No plugins installed.';

  @override
  String get adminInstall => 'Install';

  @override
  String get adminInstallLatest => 'Install Latest';

  @override
  String adminInstallingPlugin(String name) {
    return 'Installing $name. A restart may be required.';
  }

  @override
  String get adminNoPackages =>
      'No packages available. Add a repository to browse plugins.';

  @override
  String get adminAddRepository => 'Add Repository';

  @override
  String get adminName => 'Name';

  @override
  String get adminManifestUrl => 'Manifest URL';

  @override
  String get adminNoRepositories => 'No repositories configured.';

  @override
  String adminPluginVersion(String version) {
    return 'Version $version';
  }

  @override
  String get adminConfigJson => 'Configuration (JSON)';

  @override
  String get adminConfigJsonHint =>
      'Advanced: edit this plugin’s raw configuration.';

  @override
  String get adminPluginSettings => 'Settings';

  @override
  String get adminPluginSettingsHint => 'Edit this plugin’s configuration.';

  @override
  String get adminEditAsJson => 'Edit as JSON';

  @override
  String get adminNoEntries => 'No entries';

  @override
  String get adminAdvancedJson => 'Advanced (JSON)';

  @override
  String get adminSaveConfiguration => 'Save Configuration';

  @override
  String get adminNoEditableConfig =>
      'This plugin has no editable configuration.';

  @override
  String get adminInvalidJson => 'Configuration is not valid JSON.';

  @override
  String adminPackageBy(String owner) {
    return 'by $owner';
  }

  @override
  String get adminVersions => 'Versions';

  @override
  String get adminType => 'Type';

  @override
  String get adminAddTuner => 'Add Tuner';

  @override
  String get adminEditTuner => 'Edit Tuner';

  @override
  String get adminM3uTuner => 'M3U Tuner';

  @override
  String get adminM3uUrl => 'M3U URL';

  @override
  String get adminDeviceUrl => 'Device URL';

  @override
  String get adminFriendlyName => 'Friendly Name';

  @override
  String get adminHintOptional => 'Optional';

  @override
  String get adminAddGuideProvider => 'Add Guide Provider';

  @override
  String get adminXmltvSubtitle => 'A guide file or URL';

  @override
  String get adminScdSubtitle => 'Sign in and pick your lineup';

  @override
  String get adminEditXmltvGuide => 'Edit XMLTV Guide';

  @override
  String get adminAddXmltvGuide => 'Add XMLTV Guide';

  @override
  String get adminXmltvPathLabel => 'XMLTV File Path or URL';

  @override
  String adminRemoveConfirm(String what) {
    return 'Remove $what?';
  }

  @override
  String get adminWhatTuner => 'this tuner';

  @override
  String get adminWhatGuideProvider => 'this guide provider';

  @override
  String get adminRemoveFromServerBody =>
      'This removes it from the server, not just from this client.';

  @override
  String get adminNoTuners => 'No tuners configured.';

  @override
  String get adminNoGuideProviders => 'No guide providers configured.';

  @override
  String get adminTabTuners => 'Tuners';

  @override
  String get adminTabTvGuide => 'TV Guide';

  @override
  String get adminTabRecording => 'Recording';

  @override
  String get adminSectionGuide => 'Guide';

  @override
  String get adminGuideDays => 'Guide Days';

  @override
  String get adminGuideDaysHelper =>
      'How many days of guide data to keep. Blank means auto.';

  @override
  String get adminSectionRecordingPaths => 'Recording Paths';

  @override
  String get adminRecordingPath => 'Recording Path';

  @override
  String get adminMovieRecordingPath => 'Movie Recording Path';

  @override
  String get adminSeriesRecordingPath => 'Series Recording Path';

  @override
  String get adminSectionPadding => 'Padding';

  @override
  String get adminPrePadding => 'Pre-padding (seconds)';

  @override
  String get adminPostPadding => 'Post-padding (seconds)';

  @override
  String get adminSectionOptions => 'Options';

  @override
  String get adminRecordingSubfolders => 'Recording Subfolders';

  @override
  String get adminSaveRecordingNfo => 'Save Recording NFO';

  @override
  String get adminSaveRecordingImages => 'Save Recording Images';

  @override
  String get adminStartBefore => 'Start Before';

  @override
  String get adminStopAfter => 'Stop After';

  @override
  String get adminSeriesFallback => 'Series';

  @override
  String get adminTabScheduled => 'Scheduled';

  @override
  String get adminTabSeries => 'Series';

  @override
  String get adminTabRecorded => 'Recorded';

  @override
  String get adminNoScheduledRecordings => 'No scheduled recordings.';

  @override
  String get adminNoSeriesRules => 'No series rules.';

  @override
  String adminSeriesPad(int pre, int post) {
    return 'Pad ${pre}m / ${post}m';
  }

  @override
  String get adminNoRecordings => 'No recordings.';

  @override
  String get adminNoDevices => 'No devices.';

  @override
  String get adminPostalCode => 'Postal Code';

  @override
  String get adminFindLineups => 'Find Lineups';

  @override
  String get adminLineup => 'Lineup';

  @override
  String get adminEnableAllTuners => 'Enable All Tuners';

  @override
  String get adminNoLineups => 'No lineups found for that postal code.';

  @override
  String get adminAllowServerManagement => 'Allow Server Management';

  @override
  String get adminAllowServerManagementSub => 'Full administrator access';

  @override
  String get adminDisableUser => 'Disable This User';

  @override
  String get adminDisableUserSub => 'Blocks sign-in';

  @override
  String get adminHideFromLogin => 'Hide From Login Screen';

  @override
  String get adminAllowCollectionMgmt => 'Allow Collection Management';

  @override
  String get adminAllowSubtitleMgmt => 'Allow Subtitle Management';

  @override
  String get adminAllowMediaPlayback => 'Allow Media Playback';

  @override
  String get adminAllowAudioTranscoding => 'Allow Audio Transcoding';

  @override
  String get adminAllowVideoTranscoding => 'Allow Video Transcoding';

  @override
  String get adminAllowRemuxing => 'Allow Playback Requiring Conversion';

  @override
  String get adminAllowDownloads => 'Allow Downloads';

  @override
  String get adminAllowDeleting => 'Allow Deleting Content';

  @override
  String get adminAllowLiveTvAccess => 'Allow Live TV Access';

  @override
  String get adminAllowLiveTvMgmt => 'Allow Live TV / DVR Management';

  @override
  String get adminAllowRemoteControlOthers => 'Allow Remote Control of Others';

  @override
  String get adminAllowBeingControlled => 'Allow Being Remote Controlled';

  @override
  String get adminTabProfile => 'Profile';

  @override
  String get adminTabAccess => 'Access';

  @override
  String get adminTabParental => 'Parental';

  @override
  String get adminTabPassword => 'Password';

  @override
  String get adminSectionManagement => 'Management';

  @override
  String get adminSectionPlayback => 'Playback';

  @override
  String get adminSectionRemote => 'Remote';

  @override
  String get adminSectionLimits => 'Limits';

  @override
  String get adminMaxSimultaneousStreams => 'Max Simultaneous Streams';

  @override
  String get adminHintZeroUnlimited => '0 = unlimited';

  @override
  String get adminFailedLoginsBeforeLockout => 'Failed Logins Before Lockout';

  @override
  String get adminFailedLoginsHint => '0 = default, -1 = never';

  @override
  String get adminRemoteStreamingLimit => 'Remote Streaming Limit';

  @override
  String get adminSectionChannels => 'Channels';

  @override
  String get adminAccessAllLibraries => 'Access All Libraries';

  @override
  String get adminAccessAllDevices => 'Access All Devices';

  @override
  String get adminForceRemoteTranscoding =>
      'Force Transcoding of Remote Sources';

  @override
  String get adminForceRemoteTranscodingSub => 'Such as Live TV';

  @override
  String get adminSectionDeletion => 'Allow Media Deletion From';

  @override
  String get adminDeleteFromAll => 'All Libraries';

  @override
  String get adminSectionSyncPlay => 'SyncPlay';

  @override
  String get adminSyncPlayAccess => 'SyncPlay Access';

  @override
  String get adminSyncPlayCreateAndJoin => 'Create and Join Groups';

  @override
  String get adminSyncPlayJoin => 'Join Groups Only';

  @override
  String get adminSyncPlayNone => 'Disabled for This User';

  @override
  String get adminSectionSignIn => 'Sign-In';

  @override
  String get adminAuthProvider => 'Authentication Provider';

  @override
  String get adminPasswordResetProvider => 'Password Reset Provider';

  @override
  String get adminDeviceAccessHelp =>
      'This only applies to devices that can be uniquely identified, and does not block browser access. Limiting devices stops this user signing in on a new device until it is approved here.';

  @override
  String get adminChannelAccessHelp => 'Choose the channels this user can see.';

  @override
  String get adminRatingHelp =>
      'Content rated higher than this is hidden from this user.';

  @override
  String get adminBlockUnratedHelp =>
      'Hide items of these kinds that have no rating, or a rating the server does not recognise.';

  @override
  String get adminUnratedBooks => 'Books';

  @override
  String get adminUnratedChannels => 'Channels';

  @override
  String get adminUnratedLiveTv => 'Live TV';

  @override
  String get adminUnratedMovies => 'Movies';

  @override
  String get adminUnratedMusic => 'Music';

  @override
  String get adminUnratedTrailers => 'Trailers';

  @override
  String get adminUnratedShows => 'Shows';

  @override
  String get adminUnratedOther => 'Other';

  @override
  String get adminAllowedTags => 'Allow Items With Tags';

  @override
  String get adminAllowedTagsHelp =>
      'Only show media with at least one of these tags.';

  @override
  String get adminBlockedTags => 'Block Items With Tags';

  @override
  String get adminBlockedTagsHelp =>
      'Hide media with at least one of these tags.';

  @override
  String get adminAddTag => 'Add Tag';

  @override
  String get adminTag => 'Tag';

  @override
  String get adminAccessSchedule => 'Access Schedule';

  @override
  String get adminAccessScheduleHelp =>
      'Limit this user to certain days and hours. With no schedule, access is not limited.';

  @override
  String get adminAddSchedule => 'Add Schedule';

  @override
  String get adminScheduleDay => 'Day';

  @override
  String get adminScheduleStart => 'Start Time';

  @override
  String get adminScheduleEnd => 'End Time';

  @override
  String get adminEveryDay => 'Every Day';

  @override
  String get adminWeekdays => 'Weekdays';

  @override
  String get adminWeekends => 'Weekends';

  @override
  String get adminAccessAllChannels => 'Access All Channels';

  @override
  String get adminSectionMaxRating => 'Maximum Allowed Rating';

  @override
  String get adminMaxParentalRating => 'Max Parental Rating';

  @override
  String get adminRatingNone => 'None (unrestricted)';

  @override
  String get adminBlockUnrated => 'Block Items With No Rating';

  @override
  String get adminSetResetPassword => 'Set / Reset Password';

  @override
  String get adminDeleteUser => 'Delete User';

  @override
  String get adminSetPassword => 'Set Password';

  @override
  String get adminNewPasswordHint => 'New password (blank = clear)';

  @override
  String get adminSet => 'Set';

  @override
  String get adminPasswordUpdated => 'Password updated';

  @override
  String adminDeleteUserConfirm(String name) {
    return 'Permanently delete \"$name\"?';
  }

  @override
  String adminDeletedUser(String name) {
    return 'Deleted \"$name\"';
  }

  @override
  String get adminSaved => 'Saved';

  @override
  String get miscCollapseSidebar => 'Collapse';

  @override
  String get miscExpandSidebar => 'Expand';

  @override
  String get miscNotifications => 'Notifications';

  @override
  String get miscBrowse => 'Browse';

  @override
  String get miscNavPlaylists => 'Playlists';

  @override
  String get miscNavGenres => 'Genres';

  @override
  String get miscNavStudios => 'Studios';

  @override
  String get miscNavArtists => 'Artists';

  @override
  String get miscAccount => 'Account';

  @override
  String get miscWatchTogether => 'Watch Together';

  @override
  String get miscInAGroup => 'In a group';

  @override
  String get miscQuickConnect => 'Quick Connect';

  @override
  String get miscSettings => 'Settings';

  @override
  String get miscAdministration => 'Administration';

  @override
  String get miscDeviceApproved => 'Device approved';

  @override
  String get miscCodeNotApproved => 'That code could not be approved.';

  @override
  String get miscEnterCodePrompt =>
      'Enter the code shown on the device you are signing in on.';

  @override
  String get miscCode => 'Code';

  @override
  String get miscApprove => 'Approve';

  @override
  String get miscCouldntLoad => 'Could not load this row.';

  @override
  String miscYearsAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count years ago',
      one: '1 year ago',
    );
    return '$_temp0';
  }

  @override
  String miscMonthsAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count months ago',
      one: '1 month ago',
    );
    return '$_temp0';
  }

  @override
  String miscDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String miscHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours ago',
      one: '1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String get miscJustNow => 'Just now';

  @override
  String miscVideoCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count videos',
      one: '1 video',
    );
    return '$_temp0';
  }

  @override
  String get miscSegmentIntro => 'Intro';

  @override
  String get miscSegmentRecap => 'Recap';

  @override
  String get miscSegmentOutro => 'Outro';

  @override
  String get miscSegmentPreview => 'Preview';

  @override
  String get miscSegmentCommercial => 'Commercial';

  @override
  String get miscSegmentUnknown => 'Unknown';

  @override
  String get miscSeerrStatusReturningSeries => 'Returning Series';

  @override
  String get miscSeerrStatusEnded => 'Ended';

  @override
  String get miscSeerrStatusReleased => 'Released';

  @override
  String get miscSeerrStatusInProduction => 'In Production';

  @override
  String get miscSeerrStatusPostProduction => 'Post Production';

  @override
  String get miscSeerrStatusPlanned => 'Planned';

  @override
  String get miscSeerrStatusRumored => 'Rumored';

  @override
  String get miscSeerrStatusCanceled => 'Canceled';

  @override
  String get miscSeerrStatusPilot => 'Pilot';

  @override
  String get extraLiveTvTitle => 'Live TV';

  @override
  String get extraTabGuide => 'Guide';

  @override
  String get extraTabChannels => 'Channels';

  @override
  String get extraTabRecordings => 'Recordings';

  @override
  String get extraNoRecordings => 'No recordings yet';

  @override
  String get extraNoRecordingsHint => 'Schedule one from the Guide.';

  @override
  String get extraNoChannelsFound => 'No channels found';

  @override
  String get extraBadgeRec => 'REC';

  @override
  String get extraBadgeLive => 'LIVE';

  @override
  String get extraSeeAll => 'See All';

  @override
  String get extraMore => 'More';

  @override
  String get miscVideoShort => 'Short';

  @override
  String miscViews(String count) {
    return '$count views';
  }

  @override
  String get searchOpenOnStartup => 'Open on Startup';

  @override
  String get searchDesktopNotifications => 'System Notifications';

  @override
  String get searchNewRequest => 'New Request';

  @override
  String get searchRequestApproved => 'Request Approved';

  @override
  String get searchRequestDeclined => 'Request Declined';

  @override
  String get searchNowAvailable => 'Now Available';

  @override
  String get searchCheckForRequestUpdates => 'Check for Request Updates';

  @override
  String get searchDownloadComplete => 'Download Complete';

  @override
  String get searchImageCache => 'Image Cache';

  @override
  String get searchDownloadLocation => 'Download Location';

  @override
  String get searchTheme => 'Theme';

  @override
  String get searchAmoledBlack => 'AMOLED Black';

  @override
  String get searchInterfaceSize => 'Interface Size';

  @override
  String get searchRatingOnCards => 'Rating on Cards';

  @override
  String get searchAccentColor => 'Accent Color';

  @override
  String get searchHomeBanner => 'Home Banner';

  @override
  String get searchHomeLayout => 'Home Layout';

  @override
  String get searchVideoFit => 'Video Fit';

  @override
  String get searchControlBar => 'Control Bar';

  @override
  String get searchMaxQuality => 'Max Quality';

  @override
  String get searchTrailerQuality => 'Trailer Quality';

  @override
  String get searchDefaultSpeed => 'Default Speed';

  @override
  String get searchAutoplayNextEpisode => 'Autoplay Next Episode';

  @override
  String get searchRememberTrackSelections => 'Remember Track Selections';

  @override
  String get searchPreviewThumbnailsWhileSeeking =>
      'Preview Thumbnails While Seeking';

  @override
  String get searchAutoSkipIntros => 'Auto-Skip Intros';

  @override
  String get searchAutoSkipCredits => 'Auto-Skip Credits';

  @override
  String get searchUpNextTiming => 'Up Next Timing';

  @override
  String get searchUpNextStyle => 'Up Next Style';

  @override
  String get searchHardwareDecoding => 'Hardware Decoding';

  @override
  String get searchAudioLanguage => 'Audio Language';

  @override
  String get searchSubtitleLanguage => 'Subtitle Language';

  @override
  String get searchSubtitleSize => 'Subtitle Size';

  @override
  String get searchSubtitleColor => 'Subtitle Color';

  @override
  String get searchSubtitleBackground => 'Subtitle Background';

  @override
  String get searchSubtitlePosition => 'Subtitle Position';

  @override
  String get searchShowLyricsAutomatically => 'Show Lyrics Automatically';

  @override
  String get searchLookUpMissingLyricsOnline => 'Look Up Missing Lyrics Online';

  @override
  String get searchRottenTomatoesCritics => 'Rotten Tomatoes Critics';

  @override
  String get searchRottenTomatoesAudience => 'Rotten Tomatoes Audience';

  @override
  String get searchImdbRating => 'IMDb Rating';

  @override
  String get searchCommunityScore => 'Community Score';

  @override
  String get searchMoreRatingsMdblist => 'More Ratings (MDBList)';

  @override
  String get searchEnableYouTube => 'Enable YouTube';

  @override
  String get searchAutoplay => 'Autoplay';

  @override
  String get searchShowDislikeCounts => 'Show Dislike Counts';

  @override
  String get searchDeClickbaitTitles => 'De-Clickbait Titles';

  @override
  String get searchDefaultQuality => 'Default Quality';

  @override
  String get searchSkipBack => 'Skip Back';

  @override
  String get searchSkipForward => 'Skip Forward';

  @override
  String get searchListViewMode => 'List View Mode';

  @override
  String get searchThumbnailQuality => 'Thumbnail Quality';

  @override
  String get searchDownloadQuality => 'Download Quality';

  @override
  String get searchVideoContainer => 'Video Container';

  @override
  String get searchContentLanguage => 'Content Language';

  @override
  String get searchContentCountry => 'Content Country';

  @override
  String get searchRestrictedMode => 'Restricted Mode';

  @override
  String get searchShowComments => 'Show Comments';

  @override
  String get searchShowUpNext => 'Show Up Next';

  @override
  String get searchShowDescription => 'Show Description';

  @override
  String get searchKeepWatchHistory => 'Keep Watch History';

  @override
  String get searchResumePlayback => 'Resume Playback';

  @override
  String get searchKeepSearchHistory => 'Keep Search History';

  @override
  String get searchSkipSponsorSegments => 'Skip Sponsor Segments';

  @override
  String get searchClearWatchHistory => 'Clear Watch History';

  @override
  String get searchClearSearchHistory => 'Clear Search History';

  @override
  String get searchConfirmBeforeClearingQueue =>
      'Confirm Before Clearing Queue';

  @override
  String get searchDownloadRetries => 'Download Retries';

  @override
  String get searchSimultaneousDownloads => 'Simultaneous Downloads';

  @override
  String get searchDownloadFolders => 'Download Folders';

  @override
  String get searchSayWhenSomethingIsSkipped => 'Say When Something Is Skipped';

  @override
  String get searchWatchTogether => 'Watch Together';

  @override
  String get searchGeneral => 'General';

  @override
  String get searchAppearance => 'Appearance';

  @override
  String get searchHome => 'Home';

  @override
  String get searchPlayer => 'Player';

  @override
  String get searchAudioSubtitles => 'Audio & Subtitles';

  @override
  String get searchRatings => 'Ratings';

  @override
  String get searchSeerrConnection => 'Seerr Sign-in';

  @override
  String get searchYouTube => 'YouTube';

  @override
  String get searchIntegrations => 'Integrations';

  @override
  String get searchServerName => 'Server Name';

  @override
  String get searchPreferredMetadataLanguage => 'Preferred Metadata Language';

  @override
  String get searchCountry => 'Country';

  @override
  String get searchQuickConnect => 'Quick Connect';

  @override
  String get searchShowFolderView => 'Show Folder View';

  @override
  String get searchResumeThresholds => 'Resume Thresholds';

  @override
  String get searchPlayback => 'Playback';

  @override
  String get searchHardwareAcceleration => 'Hardware Acceleration';

  @override
  String get searchEnableHardwareEncoding => 'Enable Hardware Encoding';

  @override
  String get searchAllowHevcAv1Encoding => 'Allow HEVC / AV1 Encoding';

  @override
  String get searchEncoderPreset => 'Encoder Preset';

  @override
  String get searchEncodingThreadCount => 'Encoding Thread Count';

  @override
  String get searchToneMapping => 'Tone Mapping';

  @override
  String get searchSubtitleExtraction => 'Subtitle Extraction';

  @override
  String get searchTrickplay => 'Trickplay';

  @override
  String get searchTranscodeThrottling => 'Transcode Throttling';

  @override
  String get searchBranding => 'Branding';

  @override
  String get searchLoginMessage => 'Login Message';

  @override
  String get searchCustomCss => 'Custom CSS';

  @override
  String get searchSplashScreenImage => 'Splash Screen Image';

  @override
  String get searchNetworking => 'Networking';

  @override
  String get searchAllowRemoteConnections => 'Allow Remote Connections';

  @override
  String get searchPublishedServerUrl => 'Published Server URL';

  @override
  String get searchHttpHttpsPorts => 'HTTP / HTTPS Ports';

  @override
  String get searchEnableHttps => 'Enable HTTPS';

  @override
  String get searchCertificatePathPassword => 'Certificate Path & Password';

  @override
  String get searchEnableUpnp => 'Enable UPnP';

  @override
  String get searchEnableIpv6 => 'Enable IPv6';

  @override
  String get searchKnownProxies => 'Known Proxies';

  @override
  String get searchLanNetworks => 'LAN Networks';

  @override
  String get searchAutodiscovery => 'Autodiscovery';

  @override
  String get searchApiKeys => 'API Keys';

  @override
  String get searchLibraries => 'Libraries';

  @override
  String get searchUsers => 'Users';

  @override
  String get searchDevices => 'Devices';

  @override
  String get searchActiveSessions => 'Active Sessions';

  @override
  String get searchLiveTv => 'Live TV';

  @override
  String get searchDvr => 'DVR';

  @override
  String get searchScheduledTasks => 'Scheduled Tasks';

  @override
  String get searchActivityLog => 'Activity Log';

  @override
  String get searchLogs => 'Logs';

  @override
  String get searchSystem => 'System';

  @override
  String get searchPlugins => 'Plugins';

  @override
  String get searchServerConfiguration => 'Server Configuration';

  @override
  String get searchContentAccess => 'Content & Access';

  @override
  String get searchMaintenance => 'Maintenance';

  @override
  String get searchExtensions => 'Extensions';

  @override
  String get notifDownloadComplete => 'Download complete';

  @override
  String get castTo => 'Cast to';

  @override
  String get castAction => 'Cast';

  @override
  String get castSearching => 'Searching for devices…';

  @override
  String get castFailed => 'Couldn\'t start casting';

  @override
  String get castDisconnect => 'Disconnect';

  @override
  String get castStop => 'Stop Casting';

  @override
  String castConnectedTo(String device) {
    return 'Casting to $device';
  }

  @override
  String castConnecting(String device) {
    return 'Connecting to $device…';
  }

  @override
  String get notifDownloading => 'Downloading';

  @override
  String get notifDownloadFailed => 'Download failed';

  @override
  String get notifNewRequest => 'New request';

  @override
  String notifPendingApproval(String title) {
    return '$title · pending approval';
  }

  @override
  String notifNowAvailable(String title) {
    return '$title is now available';
  }

  @override
  String get notifNowAvailableBody => 'Downloaded and ready to watch';

  @override
  String get notifRequestApproved => 'Request approved';

  @override
  String get notifRequestDeclined => 'Request declined';

  @override
  String get notifRequestUpdate => 'Request update';

  @override
  String get notifAMovie => 'A movie';

  @override
  String get notifAShow => 'A TV show';

  @override
  String get settingsBackup => 'Backup & Restore';

  @override
  String get settingsBackupSubtitle => 'Export or import your app settings';

  @override
  String get backupTitle => 'Backup & Restore';

  @override
  String get backupIntro =>
      'Move your app settings and server addresses between devices. Passwords and API keys are never exported, so you\'ll sign in again after importing.';

  @override
  String get backupExportTitle => 'Export Settings';

  @override
  String get backupExportSub => 'Save your settings to a file.';

  @override
  String get backupExportSubShare => 'Share your settings as a file.';

  @override
  String get backupExportSubject => 'Fathom settings';

  @override
  String backupSavedTo(Object path) {
    return 'Saved to $path';
  }

  @override
  String get backupImportTitle => 'Import Settings';

  @override
  String get backupImportSub =>
      'Restore from a file, replacing your current settings.';

  @override
  String get backupImportConfirmTitle => 'Import settings?';

  @override
  String get backupImportConfirmBody =>
      'Your current settings will be replaced, and you\'ll sign in to your server again.';

  @override
  String get backupImportAction => 'Import';

  @override
  String get backupImported => 'Settings imported.';

  @override
  String backupImportedWithServers(Object servers) {
    return 'Settings imported. Sign in to reconnect: $servers';
  }

  @override
  String get backupInvalid =>
      'That file is not a valid Fathom settings backup.';

  @override
  String backupFailed(Object error) {
    return 'Backup failed: $error';
  }

  @override
  String get backupImportChoose => 'Choose what to import';

  @override
  String get backupGroupAppearance => 'Appearance';

  @override
  String get backupGroupPlayer => 'Player';

  @override
  String get backupGroupYoutube => 'YouTube';

  @override
  String get backupGroupGeneral => 'General';

  @override
  String get backupGroupRadio => 'Internet Radio';

  @override
  String get backupGroupServers => 'Servers';

  @override
  String get tvVoiceUnavailable =>
      'Voice input isn\'t available on this device';

  @override
  String get wheelTitle => 'Movie Night Wheel';

  @override
  String get wheelNeedsWatchlist =>
      'Search your library above to add titles, or put a few on your Watchlist.';

  @override
  String get wheelSetupHint => 'Pick at least two titles, then spin.';

  @override
  String wheelStartWith(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Start with $count Titles',
      one: 'Start with 1 Title',
    );
    return '$_temp0';
  }

  @override
  String get wheelNeedTwo => 'Pick at Least 2 Titles';

  @override
  String wheelRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Left',
      one: '1 Left',
    );
    return '$_temp0';
  }

  @override
  String get wheelTapToSpin => 'Tap or flick the wheel to spin';

  @override
  String wheelEliminated(String name) {
    return '$name is out!';
  }

  @override
  String get wheelWinnerLabel => 'TONIGHT\'S PICK';

  @override
  String get wheelSpinAgain => 'Spin Again';

  @override
  String get wheelPressToSpin => 'Press OK to spin';

  @override
  String get wheelModeLast => 'Last One Standing';

  @override
  String get wheelModeSingle => 'Single Spin';

  @override
  String get wheelModeBest3 => 'Best of 3';

  @override
  String get wheelModeLastHint =>
      'Each spin knocks one title out until one is left.';

  @override
  String get wheelModeSingleHint =>
      'One spin. Wherever it lands is tonight\'s pick.';

  @override
  String get wheelModeBest3Hint =>
      'The first title the wheel lands on twice wins.';

  @override
  String get wheelSearchLabel => 'Add from Your Library';

  @override
  String get wheelSearchHint => 'Search movies and shows';

  @override
  String get wheelNoResults => 'No matches';

  @override
  String get wheelAdded => 'Added';

  @override
  String get wheelWatched => 'Watched';

  @override
  String get wheelFilterUnwatched => 'Unwatched';

  @override
  String get wheelFilterUnder2h => 'Under 2 Hours';

  @override
  String get wheelFilterGenre => 'Genre';

  @override
  String get wheelFilterAllGenres => 'All Genres';

  @override
  String get wheelSelectAll => 'Select All';

  @override
  String get wheelSelectNone => 'Select None';

  @override
  String get wheelNothingMatches => 'Nothing matches these filters.';

  @override
  String get wheelUndo => 'Undo';

  @override
  String wheelSpinOf(int current, int total) {
    return 'Spin $current of $total';
  }

  @override
  String get wheelTiebreak => 'Tiebreaker: This Spin Decides It';

  @override
  String get wheelSingleHeader => 'One Spin Decides It';

  @override
  String wheelScored(String name) {
    return '$name scores!';
  }

  @override
  String get wheelMute => 'Mute Sounds';

  @override
  String get wheelUnmute => 'Unmute Sounds';

  @override
  String get wheelPlayForGroup => 'Play for Group';

  @override
  String get wheelGroupHint =>
      'Everyone in your Watch Together group will start watching.';

  @override
  String get sleepTimer => 'Sleep Timer';

  @override
  String sleepTimerMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Minutes',
      one: '1 Minute',
    );
    return '$_temp0';
  }

  @override
  String get sleepTimerEndOfTrack => 'End of Track';

  @override
  String get sleepTimerEndOfEpisode => 'End of Episode';

  @override
  String get sleepTimerEndOfVideo => 'End of Video';

  @override
  String sleepTimerStopsIn(String time) {
    return 'Stops in $time';
  }

  @override
  String get sleepTimerAfterThis => 'Stops at the end of this one';

  @override
  String get sleepTimerTurnOff => 'Turn Off';

  @override
  String get commonRepeat => 'Repeat';

  @override
  String get commonMoreOptions => 'More Options';

  @override
  String get loginShowPassword => 'Show Password';

  @override
  String get loginHidePassword => 'Hide Password';

  @override
  String a11yWheel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Movie Night Wheel with $count titles',
      one: 'Movie Night Wheel with 1 title',
    );
    return '$_temp0';
  }

  @override
  String get a11ySpin => 'Spin';

  @override
  String a11yWinner(String name) {
    return 'Tonight\'s pick: $name';
  }
}
