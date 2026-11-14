import 'dart:convert';

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Default player key bindings (action -> LogicalKeyboardKey.keyId). Stored
/// overrides are merged on top of these.
Map<String, int> defaultKeyBindings() => {
      'playPause': LogicalKeyboardKey.keyK.keyId,
      'seekBackward': LogicalKeyboardKey.arrowLeft.keyId,
      'seekForward': LogicalKeyboardKey.arrowRight.keyId,
      'volumeUp': LogicalKeyboardKey.arrowUp.keyId,
      'volumeDown': LogicalKeyboardKey.arrowDown.keyId,
      'mute': LogicalKeyboardKey.keyM.keyId,
      'fullscreen': LogicalKeyboardKey.keyF.keyId,
    };

/// Default order of the Seerr Discover rows, matching the Jellyseerr web home.
const kDefaultSeerrRows = <String>[
  'recentlyAdded',
  'recentRequests',
  'trending',
  'popularMovies',
  'movieGenres',
  'upcomingMovies',
  'studios',
  'popularSeries',
  'seriesGenres',
  'upcomingSeries',
  'networks',
];

/// User preferences (appearance + playback), persisted locally.
class Prefs {
  // Appearance
  final String themeMode; // 'system' | 'dark' | 'light'
  final int accentColor; // ARGB
  final bool amoled; // pure-black backgrounds in dark mode
  final bool showGreeting; // time-of-day greeting on Home

  // Playback
  final String audioLanguage; // ISO 639-2 (e.g. 'eng'); '' = server default

  /// ReplayGain normalization for music: 'off', 'track', or 'album'. mpv reads
  /// the REPLAYGAIN_* tags in the files and applies the gain itself; files
  /// without tags fall back to [replayGainFallback].
  final String replayGain;

  /// Gain in dB applied to music with no ReplayGain tags, so an untagged
  /// library isn't left conspicuously louder than a tagged one. 0 = untouched.
  final double replayGainFallback;
  final String subtitleLanguage; // ISO 639-2; '' = none/off
  final double subtitleScale; // 0.5..2.0 relative subtitle size
  final int subtitleTextColor; // ARGB
  final double subtitleBackgroundOpacity; // 0..1 behind subtitle text
  final int subtitlePosition; // mpv sub-pos: 100 = bottom, lower = higher up
  final bool autoplayNext; // auto-play next episode
  final int maxBitrateMbps; // 0 = auto/unlimited
  final double playbackSpeed; // default playback rate

  /// Playback volume, 0-100, shared by every player and remembered between
  /// runs. One app, one pair of speakers: a level set for a late-night episode
  /// should mean the same thing for YouTube and for music.
  ///
  /// Mute is deliberately NOT stored. It's transient — someone walked in — and
  /// starting silent reads as broken rather than as remembered, so only real
  /// levels are kept.
  final double volume;

  /// Open the lyrics view automatically when a song has them. Off shows the
  /// artwork by default with lyrics one tap away, which some prefer.
  final bool showLyricsAutomatically;

  /// When the server has no lyrics for a song, look them up on LrcLib.
  ///
  /// A third-party call (track title and artist go to lrclib.net), so it's a
  /// setting — on by default, since the whole point of the feature is showing
  /// lyrics and LrcLib is a sanctioned open API, not a scrape.
  final bool lookUpMissingLyrics;
  final bool hardwareDecoding; // mpv hwdec on/off
  // Android video backend: 'auto' (ExoPlayer on TV, media_kit elsewhere),
  // 'mediakit' (libmpv), or 'exoplayer' (native Media3 — tunneled 4K/HDR).
  final String playerBackend;
  // mpv video-sync=display-resample + interpolation: paces frames to the
  // monitor refresh instead of libmpv's default audio-clock sync. Smooths
  // judder/stutter on displays whose refresh doesn't divide the content fps.
  // Opt-in (desktop): it can be a no-op or worse on setups already smooth.
  final bool displaySync;
  // Verbose mpv + app logging captured to a file the user can export, so
  // playback/streaming issues can be diagnosed from a real log, not guesswork.
  final bool diagnosticLogging;
  final bool previewThumbnailsWhileSeeking; // hover scrub previews
  final bool desktopNotifications; // downloads / requests
  final bool autoSkipIntro;
  final bool autoSkipCredits;
  // Up Next card timing during the credits segment. 0 = whole credits length
  // (Jellyfin-style: card shows when credits start). >0 = a short countdown
  // that many seconds before the end (Netflix-style progress ring).
  final int upNextLeadSeconds;
  // Up Next presentation: 'card' = poster + title + countdown ring + buttons;
  // 'pill' = compact Netflix-style pill with the countdown as a progress fill.
  final String upNextStyle;
  // Bitstream compressed surround (AC3/E-AC3/DTS/TrueHD, incl. Dolby Atmos)
  // straight to an AV receiver instead of decoding to PCM — the desktop mpv
  // path. Off by default: on plain stereo speakers, passthrough is silence.
  final bool audioPassthrough;
  // Force the TV / 10-foot D-pad interface even when the device doesn't report
  // itself as a television (HTPC, desktop-on-a-TV). Applied at next launch.
  final bool forceTvMode;

  // Home & layout
  final String startupScreen; // 'home' | 'libraries' | 'livetv'
  final String homeBanner; // 'carousel' | 'hide'
  final bool showContinueWatching;
  final bool showNextUp;
  final bool showRecentlyAdded;
  final bool showMyMedia;
  final bool showLibraryLatest; // per-library "Latest in X" rows
  final bool showGenreRows; // editorial genre rows on Home
  final List<String> homeRowOrder; // order of the home rows
  final List<String> navOrder; // order of the sidebar destinations (empty = default)
  final List<String> navHidden; // sidebar destination ids the user hid
  final Map<String, int> keyBindings; // player shortcut overrides

  /// Shows (and films) taken off Continue Watching, keyed "userId|id" with the
  /// time it was removed. The row skips them until there's viewing newer than
  /// that, so watching the show again brings it back by itself. Needed because
  /// that row merges in waiting episodes, which have no resume point for a
  /// server-side removal to clear.
  final Map<String, String> continueWatchingDismissed;
  final String playerFit; // 'contain' | 'cover' | 'fill'
  final String playerBarStyle; // 'none' | 'glass' | 'dark' — control-bar chrome
  final String libraryViewMode; // 'grid' | 'list'
  // Rating badge shown on poster cards: 'off' | 'auto' | 'community' | 'critics'.
  final String cardRating;
  // How big the whole interface draws, as a multiple of the system's own
  // scaling (desktop only). 0 means automatic: follow the system, and on a
  // dense screen left at 100% scaling, size up to match (see InterfaceScale).
  final double interfaceScale;
  // Floating mini-player (YouTube PiP) placement and size, remembered so it
  // reopens where and how you left it. Position is a 0..1 fraction of the free
  // space (1,1 = bottom-right), so it stays put and on-screen across resizes.
  final double miniPlayerX;
  final double miniPlayerY;
  final String miniPlayerSize; // 'small' | 'medium' | 'large'
  final bool rememberTracks;
  // Preferred trailer resolution: 'auto' (up to 1080p) or '2160'/'1440'/'1080'/
  // '720'/'480'/'360'.
  final String trailerQuality;

  // Watch Together (SyncPlay): surfaces the entry in the profile menu.
  final bool syncPlayEnabled;
  // Movie Night Wheel: elimination-style picker on Watchlist/SyncPlay.
  final bool movieWheelEnabled;
  // 'last' (last one standing), 'single' (one spin picks), 'best3'.
  final String movieWheelMode;
  final bool movieWheelSound;
  // Stored as the titles left UNCHECKED, so anything newly added to the
  // Watchlist since the last spin starts out selected.
  final List<String> movieWheelDeselected;
  // Library titles added to the wheel on top of the Watchlist.
  final List<String> movieWheelExtras;

  // Internet radio: shows the Radio section in the sidebar. Off by default —
  // this is primarily a Jellyfin client, so radio is an opt-in integration.
  final bool radioEnabled;

  // Notifications (Seerr request status + downloads). Each gates whether that
  // event notifies at all; the existing [desktopNotifications] gates the OS
  // toast on top, while the in-app bell always collects them.
  final bool notifNewRequest;
  final bool notifSeerrApproved;
  final bool notifSeerrDeclined;
  final bool notifSeerrAvailable;
  final bool notifDownloads;
  final bool notifUpdates;

  /// How often (minutes) to poll Seerr for request status changes. 0 = off.
  final int seerrPollMinutes;

  // YouTube
  final bool youtubeEnabled; // shows the YouTube section in the sidebar
  final bool youtubeAutoplay; // auto-play a recommended video when one ends
  final bool youtubeReturnDislikes; // show dislike counts (returnyoutubedislike)
  final bool youtubeDeArrow; // de-clickbait titles via DeArrow
  final String youtubeQuality;

  /// Language and country sent to YouTube (InnerTube hl/gl).
  ///
  /// Hardcoded to en/US before, so results and titles were American English for
  /// everyone regardless of where they are. YouTube-only: Jellyfin has its own
  /// server-side metadata language.
  final String youtubeContentLanguage; // e.g. 'en', 'de'
  final String youtubeContentCountry; // e.g. 'US', 'DE'

  /// How far the YouTube player's skip buttons jump, in seconds. The Jellyfin
  /// player keeps the standard 10/30 — these controls are shared, and this must
  /// not reach across to it.
  final int youtubeSeekBackSeconds;
  final int youtubeSeekForwardSeconds;

  /// Recording what you watch and search on YouTube. Off means it isn't
  /// written at all, not merely hidden. Jellyfin's history is the server's.
  final bool youtubeKeepWatchHistory;
  final bool youtubeKeepSearchHistory;

  /// Resume part-watched YouTube videos where you left off. Depends on watch
  /// history: the position is stored with it.
  final bool youtubeResumePlayback;

  /// Sections on the YouTube watch page.
  final bool youtubeShowComments;
  final bool youtubeShowRelated;
  final bool youtubeShowDescription;

  /// Ask before emptying the YouTube play queue.
  final bool youtubeConfirmClearQueue;

  /// How YouTube lists are laid out: 'list' or 'grid'.
  final String youtubeListMode;

  /// Thumbnail resolution to request: 'low' | 'medium' | 'high' | 'max'.
  /// YouTube serves the same still at several sizes, from ~3KB to ~65KB.
  final String youtubeThumbnailQuality;

  /// YouTube's own Restricted Mode (InnerTube user.enableSafetyMode). Filtering
  /// happens server-side, so it's YouTube's judgement, not a local guess.
  final bool youtubeRestrictedMode;

  /// Where downloads land. Empty means the default (Downloads/Fathom).
  ///
  /// Video and audio are separate, as in NewPipe: audio downloads are usually
  /// music, and music belongs with music rather than mixed in with videos.
  final String youtubeVideoDownloadPath;
  final String youtubeAudioDownloadPath;
  final String jellyfinDownloadPath;

  /// Quality offered first in the download sheet.
  final String youtubeDownloadQuality; // 'ask' | '2160'..'360' | 'audio' | 'mp3-320'..
  final String youtubeVideoContainer; // 'mp4' | 'mkv'

  /// Attempts per chunk before a download gives up. A long download over a
  /// flaky connection shouldn't be lost to one failed chunk.
  final int youtubeDownloadRetries;

  /// How many downloads run at once. NewPipe calls this limiting the queue;
  /// several at once mostly just divides the same bandwidth.
  final int youtubeMaxConcurrentDownloads;

  /// Skip in-video sponsor segments using SponsorBlock.
  ///
  /// Off by default, and opt-in on purpose: it sends the video id to a
  /// third-party service, and the data is CC BY-NC-SA. Not YouTube's ads —
  /// those never reach us — but the creator's own ad reads.
  final bool youtubeSponsorBlock;

  /// Which SponsorBlock categories to skip. Skipping a paid ad read is
  /// uncontroversial; skipping the creator's outro or "filler" is taste, so
  /// each is separate and the defaults are conservative.
  final List<String> youtubeSponsorBlockCategories;

  /// Say when something was skipped. On by default: silently jumping the video
  /// is indistinguishable from a bug or a bad seek.
  final bool youtubeSponsorBlockNotify; // same scale as trailerQuality

  // Ratings shown on detail pages
  final bool showRtCritics; // Rotten Tomatoes critics score
  final bool showRtAudience; // Rotten Tomatoes audience score
  final bool showImdbRating; // IMDb rating
  final bool showCommunityRating; // Jellyfin/TMDB community score
  // Extra rating sources, from MDBList (needs mdbListApiKey).
  final bool showLetterboxd;
  final bool showMetacritic;
  final bool showMetacriticUser;
  final bool showTrakt;
  final bool showRogerEbert;
  final bool showMyAnimeList;
  final String mdbListApiKey;

  // Seerr
  final List<String> recentSearches;
  final String seerrUrl;
  final String seerrApiKey;

  /// How the Seerr client authenticates: 'apikey' (admin key) or 'cookie'
  /// (signed in with Jellyfin credentials, so requests are attributed to you).
  final String seerrAuthMode;
  final String seerrCookie; // session cookie when signed in

  // Sonarr and Radarr (the Arr section). Empty URL means not connected.
  final String sonarrUrl;
  final String sonarrApiKey;
  final String radarrUrl;
  final String radarrApiKey;
  // What Add starts with for a new show / movie (ArrAddDefaults as JSON).
  final Map<String, dynamic> sonarrAddDefaults;
  final Map<String, dynamic> radarrAddDefaults;

  /// Manual Import's last folders per app ("sonarr" / "radarr": newest
  /// first) and its Move or Copy choice ("mode").
  final Map<String, dynamic> arrImport;

  /// Order of the Seerr Discover rows, and which are hidden. Matches the
  /// Jellyseerr web home, and is reorderable + toggleable from the Discover
  /// customize screen.
  final List<String> seerrRowOrder;
  final List<String> seerrHiddenRows;

  /// User-created Discover sliders (genre or keyword), each a map with
  /// id/title/type/data. Stored locally, so no admin access is needed.
  final List<Map<String, dynamic>> seerrCustomSliders;

  // In-app update checking (GitHub Releases).
  final String updateChannel; // 'stable' or 'beta' (include pre-releases)
  final bool updateCheckOnStartup; // master on/off for automatic checks
  final String updateCheckFrequency; // 'launch' | 'daily' | 'weekly'
  final int updateLastCheck; // epoch ms of the last check, for throttling
  final String updateNotifiedVersion; // version we already posted an update notification for
  final String updateBannerDismissedVersion; // version whose update banner the user dismissed

  const Prefs({
    this.themeMode = 'system',
    this.accentColor = 0xFF6C8CFF,
    this.amoled = false,
    this.showGreeting = true,
    this.audioLanguage = '',
    this.subtitleLanguage = '',
    this.subtitleScale = 1.0,
    this.subtitleTextColor = 0xFFFFFFFF,
    this.subtitleBackgroundOpacity = 0.0,
    this.subtitlePosition = 100,
    this.autoplayNext = true,
    this.maxBitrateMbps = 0,
    this.playbackSpeed = 1.0,
    this.volume = 100,
    this.showLyricsAutomatically = true,
    this.lookUpMissingLyrics = true,
    this.hardwareDecoding = true,
    this.playerBackend = 'auto',
    this.displaySync = false,
    this.diagnosticLogging = false,
    this.previewThumbnailsWhileSeeking = true,
    this.desktopNotifications = true,
    this.autoSkipIntro = false,
    this.autoSkipCredits = false,
    this.upNextLeadSeconds = 20,
    this.upNextStyle = 'card',
    this.audioPassthrough = false,
    this.replayGain = 'off',
    this.replayGainFallback = 0,
    this.forceTvMode = false,
    this.startupScreen = 'home',
    this.homeBanner = 'carousel',
    this.showContinueWatching = true,
    this.showNextUp = true,
    this.showRecentlyAdded = true,
    this.showMyMedia = true,
    this.showLibraryLatest = true,
    this.showGenreRows = true,
    this.homeRowOrder = const [
      'continueWatching',
      'nextUp',
      'recentlyAdded',
      'myMedia'
    ],
    this.navOrder = const [],
    this.navHidden = const [],
    this.keyBindings = const {},
    this.continueWatchingDismissed = const {},
    this.playerFit = 'contain',
    this.playerBarStyle = 'glass',
    this.libraryViewMode = 'grid',
    this.cardRating = 'off',
    this.interfaceScale = 0,
    this.miniPlayerX = 1.0,
    this.miniPlayerY = 1.0,
    this.miniPlayerSize = 'medium',
    this.rememberTracks = true,
    this.trailerQuality = 'auto',
    this.syncPlayEnabled = true,
    this.movieWheelEnabled = true,
    this.movieWheelMode = 'last',
    this.movieWheelSound = true,
    this.movieWheelDeselected = const [],
    this.movieWheelExtras = const [],
    this.radioEnabled = false,
    this.notifNewRequest = true,
    this.notifSeerrApproved = true,
    this.notifSeerrDeclined = true,
    this.notifSeerrAvailable = true,
    this.notifDownloads = true,
    this.notifUpdates = true,
    this.seerrPollMinutes = 5,
    this.youtubeEnabled = false,
    this.youtubeAutoplay = true,
    this.youtubeReturnDislikes = true,
    this.youtubeDeArrow = false,
    this.youtubeQuality = 'auto',
    this.youtubeContentLanguage = 'en',
    this.youtubeContentCountry = 'US',
    this.youtubeSeekBackSeconds = 10,
    this.youtubeSeekForwardSeconds = 30,
    this.youtubeKeepWatchHistory = true,
    this.youtubeKeepSearchHistory = true,
    this.youtubeResumePlayback = true,
    this.youtubeShowComments = true,
    this.youtubeShowRelated = true,
    this.youtubeShowDescription = true,
    this.youtubeConfirmClearQueue = true,
    this.youtubeListMode = 'list',
    this.youtubeThumbnailQuality = 'high',
    this.youtubeRestrictedMode = false,
    this.youtubeVideoDownloadPath = '',
    this.youtubeAudioDownloadPath = '',
    this.jellyfinDownloadPath = '',
    this.youtubeDownloadQuality = 'ask',
    this.youtubeVideoContainer = 'mp4',
    this.youtubeDownloadRetries = 3,
    this.youtubeMaxConcurrentDownloads = 2,
    this.youtubeSponsorBlock = false,
    this.youtubeSponsorBlockCategories = const ['sponsor', 'selfpromo'],
    this.youtubeSponsorBlockNotify = true,
    this.showRtCritics = true,
    this.showRtAudience = true,
    this.showImdbRating = true,
    this.showCommunityRating = true,
    this.showLetterboxd = false,
    this.showMetacritic = false,
    this.showMetacriticUser = false,
    this.showTrakt = false,
    this.showRogerEbert = false,
    this.showMyAnimeList = false,
    this.mdbListApiKey = '',
    this.recentSearches = const [],
    this.seerrUrl = '',
    this.seerrApiKey = '',
    this.seerrAuthMode = 'apikey',
    this.seerrCookie = '',
    this.sonarrUrl = '',
    this.sonarrApiKey = '',
    this.radarrUrl = '',
    this.radarrApiKey = '',
    this.sonarrAddDefaults = const {},
    this.radarrAddDefaults = const {},
    this.arrImport = const {},
    this.seerrRowOrder = kDefaultSeerrRows,
    this.seerrHiddenRows = const [],
    this.seerrCustomSliders = const [],
    this.updateChannel = 'stable',
    this.updateCheckOnStartup = true,
    this.updateCheckFrequency = 'launch',
    this.updateLastCheck = 0,
    this.updateNotifiedVersion = '',
    this.updateBannerDismissedVersion = '',
  });

  /// Player key bindings with any user overrides applied over the defaults.
  Map<String, int> get effectiveKeys => {...defaultKeyBindings(), ...keyBindings};

  Prefs copyWith({
    String? themeMode,
    int? accentColor,
    bool? amoled,
    bool? showGreeting,
    String? audioLanguage,
    String? subtitleLanguage,
    double? subtitleScale,
    int? subtitleTextColor,
    double? subtitleBackgroundOpacity,
    int? subtitlePosition,
    bool? autoplayNext,
    int? maxBitrateMbps,
    double? playbackSpeed,
    double? volume,
    bool? showLyricsAutomatically,
    bool? lookUpMissingLyrics,
    bool? hardwareDecoding,
    String? playerBackend,
    bool? displaySync,
    bool? diagnosticLogging,
    bool? previewThumbnailsWhileSeeking,
    bool? desktopNotifications,
    bool? autoSkipIntro,
    bool? autoSkipCredits,
    int? upNextLeadSeconds,
    String? upNextStyle,
    bool? audioPassthrough,
    String? replayGain,
    double? replayGainFallback,
    bool? forceTvMode,
    String? startupScreen,
    String? homeBanner,
    bool? showContinueWatching,
    bool? showNextUp,
    bool? showRecentlyAdded,
    bool? showMyMedia,
    bool? showLibraryLatest,
    bool? showGenreRows,
    List<String>? homeRowOrder,
    List<String>? navOrder,
    List<String>? navHidden,
    Map<String, int>? keyBindings,
    Map<String, String>? continueWatchingDismissed,
    String? playerFit,
    String? playerBarStyle,
    String? libraryViewMode,
    String? cardRating,
    double? interfaceScale,
    double? miniPlayerX,
    double? miniPlayerY,
    String? miniPlayerSize,
    bool? rememberTracks,
    String? trailerQuality,
    bool? syncPlayEnabled,
    bool? movieWheelEnabled,
    String? movieWheelMode,
    bool? movieWheelSound,
    List<String>? movieWheelDeselected,
    List<String>? movieWheelExtras,
    bool? radioEnabled,
    bool? notifNewRequest,
    bool? notifSeerrApproved,
    bool? notifSeerrDeclined,
    bool? notifSeerrAvailable,
    bool? notifDownloads,
    bool? notifUpdates,
    int? seerrPollMinutes,
    bool? youtubeEnabled,
    bool? youtubeAutoplay,
    bool? youtubeReturnDislikes,
    bool? youtubeDeArrow,
    String? youtubeQuality,
    String? youtubeContentLanguage,
    String? youtubeContentCountry,
    int? youtubeSeekBackSeconds,
    int? youtubeSeekForwardSeconds,
    bool? youtubeKeepWatchHistory,
    bool? youtubeKeepSearchHistory,
    bool? youtubeResumePlayback,
    bool? youtubeShowComments,
    bool? youtubeShowRelated,
    bool? youtubeShowDescription,
    bool? youtubeConfirmClearQueue,
    String? youtubeListMode,
    String? youtubeThumbnailQuality,
    bool? youtubeRestrictedMode,
    String? youtubeVideoDownloadPath,
    String? youtubeAudioDownloadPath,
    String? jellyfinDownloadPath,
    String? youtubeDownloadQuality,
    String? youtubeVideoContainer,
    int? youtubeDownloadRetries,
    int? youtubeMaxConcurrentDownloads,
    bool? youtubeSponsorBlock,
    List<String>? youtubeSponsorBlockCategories,
    bool? youtubeSponsorBlockNotify,
    bool? showRtCritics,
    bool? showRtAudience,
    bool? showImdbRating,
    bool? showCommunityRating,
    bool? showLetterboxd,
    bool? showMetacritic,
    bool? showMetacriticUser,
    bool? showTrakt,
    bool? showRogerEbert,
    bool? showMyAnimeList,
    String? mdbListApiKey,
    List<String>? recentSearches,
    String? seerrUrl,
    String? seerrApiKey,
    String? seerrAuthMode,
    String? seerrCookie,
    String? sonarrUrl,
    String? sonarrApiKey,
    String? radarrUrl,
    String? radarrApiKey,
    Map<String, dynamic>? sonarrAddDefaults,
    Map<String, dynamic>? radarrAddDefaults,
    Map<String, dynamic>? arrImport,
    List<String>? seerrRowOrder,
    List<String>? seerrHiddenRows,
    List<Map<String, dynamic>>? seerrCustomSliders,
    String? updateChannel,
    bool? updateCheckOnStartup,
    String? updateCheckFrequency,
    int? updateLastCheck,
    String? updateNotifiedVersion,
    String? updateBannerDismissedVersion,
  }) =>
      Prefs(
        themeMode: themeMode ?? this.themeMode,
        accentColor: accentColor ?? this.accentColor,
        amoled: amoled ?? this.amoled,
        showGreeting: showGreeting ?? this.showGreeting,
        audioLanguage: audioLanguage ?? this.audioLanguage,
        subtitleLanguage: subtitleLanguage ?? this.subtitleLanguage,
        subtitleScale: subtitleScale ?? this.subtitleScale,
        subtitleTextColor: subtitleTextColor ?? this.subtitleTextColor,
        subtitleBackgroundOpacity:
            subtitleBackgroundOpacity ?? this.subtitleBackgroundOpacity,
        subtitlePosition: subtitlePosition ?? this.subtitlePosition,
        autoplayNext: autoplayNext ?? this.autoplayNext,
        maxBitrateMbps: maxBitrateMbps ?? this.maxBitrateMbps,
        playbackSpeed: playbackSpeed ?? this.playbackSpeed,
        volume: volume ?? this.volume,
        showLyricsAutomatically:
            showLyricsAutomatically ?? this.showLyricsAutomatically,
        lookUpMissingLyrics:
            lookUpMissingLyrics ?? this.lookUpMissingLyrics,
        hardwareDecoding: hardwareDecoding ?? this.hardwareDecoding,
        playerBackend: playerBackend ?? this.playerBackend,
        displaySync: displaySync ?? this.displaySync,
        diagnosticLogging: diagnosticLogging ?? this.diagnosticLogging,
        previewThumbnailsWhileSeeking:
            previewThumbnailsWhileSeeking ?? this.previewThumbnailsWhileSeeking,
        desktopNotifications: desktopNotifications ?? this.desktopNotifications,
        autoSkipIntro: autoSkipIntro ?? this.autoSkipIntro,
        autoSkipCredits: autoSkipCredits ?? this.autoSkipCredits,
        upNextLeadSeconds: upNextLeadSeconds ?? this.upNextLeadSeconds,
        upNextStyle: upNextStyle ?? this.upNextStyle,
        audioPassthrough: audioPassthrough ?? this.audioPassthrough,
        replayGain: replayGain ?? this.replayGain,
        replayGainFallback: replayGainFallback ?? this.replayGainFallback,
        forceTvMode: forceTvMode ?? this.forceTvMode,
        startupScreen: startupScreen ?? this.startupScreen,
        homeBanner: homeBanner ?? this.homeBanner,
        showContinueWatching:
            showContinueWatching ?? this.showContinueWatching,
        showNextUp: showNextUp ?? this.showNextUp,
        showRecentlyAdded: showRecentlyAdded ?? this.showRecentlyAdded,
        showMyMedia: showMyMedia ?? this.showMyMedia,
        showLibraryLatest: showLibraryLatest ?? this.showLibraryLatest,
        showGenreRows: showGenreRows ?? this.showGenreRows,
        homeRowOrder: homeRowOrder ?? this.homeRowOrder,
        navOrder: navOrder ?? this.navOrder,
        navHidden: navHidden ?? this.navHidden,
        keyBindings: keyBindings ?? this.keyBindings,
        continueWatchingDismissed:
            continueWatchingDismissed ?? this.continueWatchingDismissed,
        playerFit: playerFit ?? this.playerFit,
        playerBarStyle: playerBarStyle ?? this.playerBarStyle,
        libraryViewMode: libraryViewMode ?? this.libraryViewMode,
        cardRating: cardRating ?? this.cardRating,
        interfaceScale: interfaceScale ?? this.interfaceScale,
        miniPlayerX: miniPlayerX ?? this.miniPlayerX,
        miniPlayerY: miniPlayerY ?? this.miniPlayerY,
        miniPlayerSize: miniPlayerSize ?? this.miniPlayerSize,
        rememberTracks: rememberTracks ?? this.rememberTracks,
        trailerQuality: trailerQuality ?? this.trailerQuality,
        syncPlayEnabled: syncPlayEnabled ?? this.syncPlayEnabled,
        movieWheelEnabled: movieWheelEnabled ?? this.movieWheelEnabled,
        movieWheelMode: movieWheelMode ?? this.movieWheelMode,
        movieWheelSound: movieWheelSound ?? this.movieWheelSound,
        movieWheelDeselected: movieWheelDeselected ?? this.movieWheelDeselected,
        movieWheelExtras: movieWheelExtras ?? this.movieWheelExtras,
        radioEnabled: radioEnabled ?? this.radioEnabled,
        notifNewRequest: notifNewRequest ?? this.notifNewRequest,
        notifSeerrApproved: notifSeerrApproved ?? this.notifSeerrApproved,
        notifSeerrDeclined: notifSeerrDeclined ?? this.notifSeerrDeclined,
        notifSeerrAvailable: notifSeerrAvailable ?? this.notifSeerrAvailable,
        notifDownloads: notifDownloads ?? this.notifDownloads,
        notifUpdates: notifUpdates ?? this.notifUpdates,
        seerrPollMinutes: seerrPollMinutes ?? this.seerrPollMinutes,
        youtubeEnabled: youtubeEnabled ?? this.youtubeEnabled,
        youtubeAutoplay: youtubeAutoplay ?? this.youtubeAutoplay,
        youtubeReturnDislikes:
            youtubeReturnDislikes ?? this.youtubeReturnDislikes,
        youtubeDeArrow: youtubeDeArrow ?? this.youtubeDeArrow,
        youtubeQuality: youtubeQuality ?? this.youtubeQuality,
        youtubeContentLanguage: youtubeContentLanguage ?? this.youtubeContentLanguage,
        youtubeContentCountry: youtubeContentCountry ?? this.youtubeContentCountry,
        youtubeSeekBackSeconds: youtubeSeekBackSeconds ?? this.youtubeSeekBackSeconds,
        youtubeSeekForwardSeconds: youtubeSeekForwardSeconds ?? this.youtubeSeekForwardSeconds,
        youtubeKeepWatchHistory: youtubeKeepWatchHistory ?? this.youtubeKeepWatchHistory,
        youtubeKeepSearchHistory: youtubeKeepSearchHistory ?? this.youtubeKeepSearchHistory,
        youtubeResumePlayback: youtubeResumePlayback ?? this.youtubeResumePlayback,
        youtubeShowComments: youtubeShowComments ?? this.youtubeShowComments,
        youtubeShowRelated: youtubeShowRelated ?? this.youtubeShowRelated,
        youtubeShowDescription: youtubeShowDescription ?? this.youtubeShowDescription,
        youtubeConfirmClearQueue:
            youtubeConfirmClearQueue ?? this.youtubeConfirmClearQueue,
        youtubeListMode: youtubeListMode ?? this.youtubeListMode,
        youtubeThumbnailQuality:
            youtubeThumbnailQuality ?? this.youtubeThumbnailQuality,
        youtubeRestrictedMode:
            youtubeRestrictedMode ?? this.youtubeRestrictedMode,
        youtubeVideoDownloadPath:
            youtubeVideoDownloadPath ?? this.youtubeVideoDownloadPath,
        youtubeAudioDownloadPath:
            youtubeAudioDownloadPath ?? this.youtubeAudioDownloadPath,
        jellyfinDownloadPath: jellyfinDownloadPath ?? this.jellyfinDownloadPath,
        youtubeDownloadQuality:
            youtubeDownloadQuality ?? this.youtubeDownloadQuality,
        youtubeVideoContainer:
            youtubeVideoContainer ?? this.youtubeVideoContainer,
        youtubeDownloadRetries:
            youtubeDownloadRetries ?? this.youtubeDownloadRetries,
        youtubeMaxConcurrentDownloads: youtubeMaxConcurrentDownloads ??
            this.youtubeMaxConcurrentDownloads,
        youtubeSponsorBlock: youtubeSponsorBlock ?? this.youtubeSponsorBlock,
        youtubeSponsorBlockCategories: youtubeSponsorBlockCategories ??
            this.youtubeSponsorBlockCategories,
        youtubeSponsorBlockNotify:
            youtubeSponsorBlockNotify ?? this.youtubeSponsorBlockNotify,
        showRtCritics: showRtCritics ?? this.showRtCritics,
        showRtAudience: showRtAudience ?? this.showRtAudience,
        showImdbRating: showImdbRating ?? this.showImdbRating,
        showCommunityRating: showCommunityRating ?? this.showCommunityRating,
        showLetterboxd: showLetterboxd ?? this.showLetterboxd,
        showMetacritic: showMetacritic ?? this.showMetacritic,
        showMetacriticUser: showMetacriticUser ?? this.showMetacriticUser,
        showTrakt: showTrakt ?? this.showTrakt,
        showRogerEbert: showRogerEbert ?? this.showRogerEbert,
        showMyAnimeList: showMyAnimeList ?? this.showMyAnimeList,
        mdbListApiKey: mdbListApiKey ?? this.mdbListApiKey,
        recentSearches: recentSearches ?? this.recentSearches,
        seerrUrl: seerrUrl ?? this.seerrUrl,
        seerrApiKey: seerrApiKey ?? this.seerrApiKey,
        seerrAuthMode: seerrAuthMode ?? this.seerrAuthMode,
        seerrCookie: seerrCookie ?? this.seerrCookie,
        sonarrUrl: sonarrUrl ?? this.sonarrUrl,
        sonarrApiKey: sonarrApiKey ?? this.sonarrApiKey,
        radarrUrl: radarrUrl ?? this.radarrUrl,
        radarrApiKey: radarrApiKey ?? this.radarrApiKey,
        sonarrAddDefaults: sonarrAddDefaults ?? this.sonarrAddDefaults,
        radarrAddDefaults: radarrAddDefaults ?? this.radarrAddDefaults,
        arrImport: arrImport ?? this.arrImport,
        seerrRowOrder: seerrRowOrder ?? this.seerrRowOrder,
        seerrHiddenRows: seerrHiddenRows ?? this.seerrHiddenRows,
        seerrCustomSliders: seerrCustomSliders ?? this.seerrCustomSliders,
        updateChannel: updateChannel ?? this.updateChannel,
        updateCheckOnStartup: updateCheckOnStartup ?? this.updateCheckOnStartup,
        updateCheckFrequency:
            updateCheckFrequency ?? this.updateCheckFrequency,
        updateLastCheck: updateLastCheck ?? this.updateLastCheck,
        updateNotifiedVersion:
            updateNotifiedVersion ?? this.updateNotifiedVersion,
        updateBannerDismissedVersion: updateBannerDismissedVersion ??
            this.updateBannerDismissedVersion,
      );

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode,
        'accentColor': accentColor,
        'amoled': amoled,
        'showGreeting': showGreeting,
        'audioLanguage': audioLanguage,
        'subtitleLanguage': subtitleLanguage,
        'subtitleScale': subtitleScale,
        'subtitleTextColor': subtitleTextColor,
        'subtitleBackgroundOpacity': subtitleBackgroundOpacity,
        'subtitlePosition': subtitlePosition,
        'autoplayNext': autoplayNext,
        'maxBitrateMbps': maxBitrateMbps,
        'playbackSpeed': playbackSpeed,
        'volume': volume,
        'showLyricsAutomatically': showLyricsAutomatically,
        'lookUpMissingLyrics': lookUpMissingLyrics,
        'hardwareDecoding': hardwareDecoding,
        'playerBackend': playerBackend,
        'displaySync': displaySync,
        'diagnosticLogging': diagnosticLogging,
        'previewThumbnailsWhileSeeking': previewThumbnailsWhileSeeking,
        'desktopNotifications': desktopNotifications,
        'autoSkipIntro': autoSkipIntro,
        'autoSkipCredits': autoSkipCredits,
        'upNextLeadSeconds': upNextLeadSeconds,
        'upNextStyle': upNextStyle,
        'audioPassthrough': audioPassthrough,
        'replayGain': replayGain,
        'replayGainFallback': replayGainFallback,
        'forceTvMode': forceTvMode,
        'startupScreen': startupScreen,
        'homeBanner': homeBanner,
        'showContinueWatching': showContinueWatching,
        'showNextUp': showNextUp,
        'showRecentlyAdded': showRecentlyAdded,
        'showMyMedia': showMyMedia,
        'showLibraryLatest': showLibraryLatest,
        'showGenreRows': showGenreRows,
        'homeRowOrder': homeRowOrder,
        'navOrder': navOrder,
        'navHidden': navHidden,
        'keyBindings': keyBindings.map((k, v) => MapEntry(k, v)),
        'continueWatchingDismissed': continueWatchingDismissed,
        'playerFit': playerFit,
        'playerBarStyle': playerBarStyle,
        'libraryViewMode': libraryViewMode,
        'cardRating': cardRating,
        'interfaceScale': interfaceScale,
        'miniPlayerX': miniPlayerX,
        'miniPlayerY': miniPlayerY,
        'miniPlayerSize': miniPlayerSize,
        'rememberTracks': rememberTracks,
        'trailerQuality': trailerQuality,
        'syncPlayEnabled': syncPlayEnabled,
        'movieWheelEnabled': movieWheelEnabled,
        'movieWheelMode': movieWheelMode,
        'movieWheelSound': movieWheelSound,
        'movieWheelDeselected': movieWheelDeselected,
        'movieWheelExtras': movieWheelExtras,
        'radioEnabled': radioEnabled,
        'notifNewRequest': notifNewRequest,
        'notifSeerrApproved': notifSeerrApproved,
        'notifSeerrDeclined': notifSeerrDeclined,
        'notifSeerrAvailable': notifSeerrAvailable,
        'notifDownloads': notifDownloads,
        'notifUpdates': notifUpdates,
        'seerrPollMinutes': seerrPollMinutes,
        'youtubeEnabled': youtubeEnabled,
        'youtubeAutoplay': youtubeAutoplay,
        'youtubeReturnDislikes': youtubeReturnDislikes,
        'youtubeDeArrow': youtubeDeArrow,
        'youtubeQuality': youtubeQuality,
        'youtubeContentLanguage': youtubeContentLanguage,
        'youtubeContentCountry': youtubeContentCountry,
        'youtubeSeekBackSeconds': youtubeSeekBackSeconds,
        'youtubeSeekForwardSeconds': youtubeSeekForwardSeconds,
        'youtubeKeepWatchHistory': youtubeKeepWatchHistory,
        'youtubeKeepSearchHistory': youtubeKeepSearchHistory,
        'youtubeResumePlayback': youtubeResumePlayback,
        'youtubeShowComments': youtubeShowComments,
        'youtubeShowRelated': youtubeShowRelated,
        'youtubeShowDescription': youtubeShowDescription,
        'youtubeConfirmClearQueue': youtubeConfirmClearQueue,
        'youtubeListMode': youtubeListMode,
        'youtubeThumbnailQuality': youtubeThumbnailQuality,
        'youtubeRestrictedMode': youtubeRestrictedMode,
        'youtubeVideoDownloadPath': youtubeVideoDownloadPath,
        'youtubeAudioDownloadPath': youtubeAudioDownloadPath,
        'jellyfinDownloadPath': jellyfinDownloadPath,
        'youtubeDownloadQuality': youtubeDownloadQuality,
        'youtubeVideoContainer': youtubeVideoContainer,
        'youtubeDownloadRetries': youtubeDownloadRetries,
        'youtubeMaxConcurrentDownloads': youtubeMaxConcurrentDownloads,
        'youtubeSponsorBlock': youtubeSponsorBlock,
        'youtubeSponsorBlockCategories': youtubeSponsorBlockCategories,
        'youtubeSponsorBlockNotify': youtubeSponsorBlockNotify,
        'showRtCritics': showRtCritics,
        'showRtAudience': showRtAudience,
        'showImdbRating': showImdbRating,
        'showCommunityRating': showCommunityRating,
        'showLetterboxd': showLetterboxd,
        'showMetacritic': showMetacritic,
        'showMetacriticUser': showMetacriticUser,
        'showTrakt': showTrakt,
        'showRogerEbert': showRogerEbert,
        'showMyAnimeList': showMyAnimeList,
        'mdbListApiKey': mdbListApiKey,
        'recentSearches': recentSearches,
        'seerrUrl': seerrUrl,
        'seerrApiKey': seerrApiKey,
        'seerrAuthMode': seerrAuthMode,
        'seerrCookie': seerrCookie,
        'sonarrUrl': sonarrUrl,
        'sonarrApiKey': sonarrApiKey,
        'radarrUrl': radarrUrl,
        'radarrApiKey': radarrApiKey,
        'sonarrAddDefaults': sonarrAddDefaults,
        'radarrAddDefaults': radarrAddDefaults,
        'arrImport': arrImport,
        'seerrRowOrder': seerrRowOrder,
        'seerrHiddenRows': seerrHiddenRows,
        'seerrCustomSliders': seerrCustomSliders,
        'updateChannel': updateChannel,
        'updateCheckOnStartup': updateCheckOnStartup,
        'updateCheckFrequency': updateCheckFrequency,
        'updateLastCheck': updateLastCheck,
        'updateNotifiedVersion': updateNotifiedVersion,
        'updateBannerDismissedVersion': updateBannerDismissedVersion,
      };

  factory Prefs.fromJson(Map<String, dynamic> j) => Prefs(
        themeMode: j['themeMode'] as String? ?? 'system',
        accentColor: (j['accentColor'] as num?)?.toInt() ?? 0xFF6C8CFF,
        amoled: j['amoled'] as bool? ?? false,
        showGreeting: j['showGreeting'] as bool? ?? true,
        audioLanguage: j['audioLanguage'] as String? ?? '',
        replayGain: j['replayGain'] as String? ?? 'off',
        replayGainFallback:
            (j['replayGainFallback'] as num?)?.toDouble() ?? 0,
        subtitleLanguage: j['subtitleLanguage'] as String? ?? '',
        subtitleScale: (j['subtitleScale'] as num?)?.toDouble() ?? 1.0,
        subtitleTextColor:
            (j['subtitleTextColor'] as num?)?.toInt() ?? 0xFFFFFFFF,
        subtitleBackgroundOpacity:
            (j['subtitleBackgroundOpacity'] as num?)?.toDouble() ?? 0.0,
        subtitlePosition: (j['subtitlePosition'] as num?)?.toInt() ?? 100,
        autoplayNext: j['autoplayNext'] as bool? ?? true,
        maxBitrateMbps: (j['maxBitrateMbps'] as num?)?.toInt() ?? 0,
        playbackSpeed: (j['playbackSpeed'] as num?)?.toDouble() ?? 1.0,
        // Clamped on read: a corrupt or hand-edited value shouldn't make the
        // app permanently silent or blow the speakers.
        volume: ((j['volume'] as num?)?.toDouble() ?? 100).clamp(0.0, 100.0),
        showLyricsAutomatically:
            j['showLyricsAutomatically'] as bool? ?? true,
        lookUpMissingLyrics: j['lookUpMissingLyrics'] as bool? ?? true,
        hardwareDecoding: j['hardwareDecoding'] as bool? ?? true,
        playerBackend: j['playerBackend'] as String? ?? 'auto',
        displaySync: j['displaySync'] as bool? ?? false,
        diagnosticLogging: j['diagnosticLogging'] as bool? ?? false,
        previewThumbnailsWhileSeeking:
            j['previewThumbnailsWhileSeeking'] as bool? ?? true,
        desktopNotifications: j['desktopNotifications'] as bool? ?? true,
        autoSkipIntro: j['autoSkipIntro'] as bool? ?? false,
        autoSkipCredits: j['autoSkipCredits'] as bool? ?? false,
        upNextLeadSeconds: (j['upNextLeadSeconds'] as num?)?.toInt() ?? 20,
        upNextStyle: j['upNextStyle'] as String? ?? 'card',
        audioPassthrough: j['audioPassthrough'] as bool? ?? false,
        forceTvMode: j['forceTvMode'] as bool? ?? false,
        startupScreen: j['startupScreen'] as String? ?? 'home',
        homeBanner: j['homeBanner'] as String? ?? 'carousel',
        showContinueWatching: j['showContinueWatching'] as bool? ?? true,
        showNextUp: j['showNextUp'] as bool? ?? true,
        showRecentlyAdded: j['showRecentlyAdded'] as bool? ?? true,
        showMyMedia: j['showMyMedia'] as bool? ?? true,
        showLibraryLatest: j['showLibraryLatest'] as bool? ?? true,
        showGenreRows: j['showGenreRows'] as bool? ?? true,
        homeRowOrder: (j['homeRowOrder'] as List?)?.cast<String>() ??
            const ['continueWatching', 'recentlyAdded', 'myMedia'],
        navOrder: (j['navOrder'] as List?)?.cast<String>() ?? const [],
        navHidden: (j['navHidden'] as List?)?.cast<String>() ?? const [],
        keyBindings: (j['keyBindings'] as Map?)
                ?.map((k, v) => MapEntry('$k', (v as num).toInt())) ??
            const {},
        continueWatchingDismissed: (j['continueWatchingDismissed'] as Map?)
                ?.map((k, v) => MapEntry('$k', '$v')) ??
            const {},
        playerFit: j['playerFit'] as String? ?? 'contain',
        playerBarStyle: j['playerBarStyle'] as String? ?? 'glass',
        libraryViewMode: j['libraryViewMode'] as String? ?? 'grid',
        cardRating: j['cardRating'] as String? ?? 'off',
        interfaceScale: (j['interfaceScale'] as num?)?.toDouble() ?? 0,
        miniPlayerX: (j['miniPlayerX'] as num?)?.toDouble() ?? 1.0,
        miniPlayerY: (j['miniPlayerY'] as num?)?.toDouble() ?? 1.0,
        miniPlayerSize: j['miniPlayerSize'] as String? ?? 'medium',
        rememberTracks: j['rememberTracks'] as bool? ?? true,
        trailerQuality: j['trailerQuality'] as String? ?? 'auto',
        syncPlayEnabled: j['syncPlayEnabled'] as bool? ?? true,
        movieWheelEnabled: j['movieWheelEnabled'] as bool? ?? true,
        movieWheelMode: j['movieWheelMode'] as String? ?? 'last',
        movieWheelSound: j['movieWheelSound'] as bool? ?? true,
        movieWheelDeselected:
            (j['movieWheelDeselected'] as List?)?.cast<String>() ?? const [],
        movieWheelExtras:
            (j['movieWheelExtras'] as List?)?.cast<String>() ?? const [],
        radioEnabled: j['radioEnabled'] as bool? ?? false,
        notifNewRequest: j['notifNewRequest'] as bool? ?? true,
        notifSeerrApproved: j['notifSeerrApproved'] as bool? ?? true,
        notifSeerrDeclined: j['notifSeerrDeclined'] as bool? ?? true,
        notifSeerrAvailable: j['notifSeerrAvailable'] as bool? ?? true,
        notifDownloads: j['notifDownloads'] as bool? ?? true,
        notifUpdates: j['notifUpdates'] as bool? ?? true,
        seerrPollMinutes: (j['seerrPollMinutes'] as num?)?.toInt() ?? 5,
        youtubeEnabled: j['youtubeEnabled'] as bool? ?? false,
        youtubeAutoplay: j['youtubeAutoplay'] as bool? ?? true,
        youtubeReturnDislikes:
            j['youtubeReturnDislikes'] as bool? ?? true,
        youtubeDeArrow: j['youtubeDeArrow'] as bool? ?? false,
        youtubeQuality: j['youtubeQuality'] as String? ?? 'auto',
        youtubeContentLanguage: j['youtubeContentLanguage'] as String? ?? 'en',
        youtubeContentCountry: j['youtubeContentCountry'] as String? ?? 'US',
        youtubeSeekBackSeconds: (j['youtubeSeekBackSeconds'] as num?)?.toInt() ?? 10,
        youtubeSeekForwardSeconds: (j['youtubeSeekForwardSeconds'] as num?)?.toInt() ?? 30,
        youtubeKeepWatchHistory: j['youtubeKeepWatchHistory'] as bool? ?? true,
        youtubeKeepSearchHistory: j['youtubeKeepSearchHistory'] as bool? ?? true,
        youtubeResumePlayback: j['youtubeResumePlayback'] as bool? ?? true,
        youtubeShowComments: j['youtubeShowComments'] as bool? ?? true,
        youtubeShowRelated: j['youtubeShowRelated'] as bool? ?? true,
        youtubeShowDescription: j['youtubeShowDescription'] as bool? ?? true,
        youtubeConfirmClearQueue:
            j['youtubeConfirmClearQueue'] as bool? ?? true,
        youtubeListMode: j['youtubeListMode'] as String? ?? 'list',
        youtubeThumbnailQuality:
            j['youtubeThumbnailQuality'] as String? ?? 'high',
        youtubeRestrictedMode: j['youtubeRestrictedMode'] as bool? ?? false,
        youtubeVideoDownloadPath:
            j['youtubeVideoDownloadPath'] as String? ?? '',
        youtubeAudioDownloadPath:
            j['youtubeAudioDownloadPath'] as String? ?? '',
        jellyfinDownloadPath: j['jellyfinDownloadPath'] as String? ?? '',
        youtubeDownloadQuality: j['youtubeDownloadQuality'] as String? ?? 'ask',
        youtubeVideoContainer:
            j['youtubeVideoContainer'] as String? ?? 'mp4',
        youtubeDownloadRetries:
            (j['youtubeDownloadRetries'] as num?)?.toInt() ?? 3,
        youtubeMaxConcurrentDownloads:
            (j['youtubeMaxConcurrentDownloads'] as num?)?.toInt() ?? 2,
        youtubeSponsorBlock: j['youtubeSponsorBlock'] as bool? ?? false,
        youtubeSponsorBlockCategories: [
          ...(j['youtubeSponsorBlockCategories'] as List? ??
                  const ['sponsor', 'selfpromo'])
              .whereType<String>(),
        ],
        youtubeSponsorBlockNotify:
            j['youtubeSponsorBlockNotify'] as bool? ?? true,
        showRtCritics: j['showRtCritics'] as bool? ?? true,
        showRtAudience: j['showRtAudience'] as bool? ?? true,
        showImdbRating: j['showImdbRating'] as bool? ?? true,
        showCommunityRating: j['showCommunityRating'] as bool? ?? true,
        showLetterboxd: j['showLetterboxd'] as bool? ?? false,
        showMetacritic: j['showMetacritic'] as bool? ?? false,
        showMetacriticUser: j['showMetacriticUser'] as bool? ?? false,
        showTrakt: j['showTrakt'] as bool? ?? false,
        showRogerEbert: j['showRogerEbert'] as bool? ?? false,
        showMyAnimeList: j['showMyAnimeList'] as bool? ?? false,
        mdbListApiKey: j['mdbListApiKey'] as String? ?? '',
        recentSearches:
            (j['recentSearches'] as List?)?.cast<String>() ?? const [],
        seerrUrl: j['seerrUrl'] as String? ?? '',
        seerrApiKey: j['seerrApiKey'] as String? ?? '',
        seerrAuthMode: j['seerrAuthMode'] as String? ?? 'apikey',
        seerrCookie: j['seerrCookie'] as String? ?? '',
        sonarrUrl: j['sonarrUrl'] as String? ?? '',
        sonarrApiKey: j['sonarrApiKey'] as String? ?? '',
        radarrUrl: j['radarrUrl'] as String? ?? '',
        radarrApiKey: j['radarrApiKey'] as String? ?? '',
        sonarrAddDefaults: j['sonarrAddDefaults'] is Map
            ? Map<String, dynamic>.from(j['sonarrAddDefaults'] as Map)
            : const {},
        arrImport: j['arrImport'] is Map
            ? Map<String, dynamic>.from(j['arrImport'] as Map)
            : const {},
        radarrAddDefaults: j['radarrAddDefaults'] is Map
            ? Map<String, dynamic>.from(j['radarrAddDefaults'] as Map)
            : const {},
        seerrRowOrder: (j['seerrRowOrder'] as List?)?.cast<String>() ??
            kDefaultSeerrRows,
        seerrHiddenRows:
            (j['seerrHiddenRows'] as List?)?.cast<String>() ?? const [],
        seerrCustomSliders: [
          for (final e in (j['seerrCustomSliders'] as List?) ?? const [])
            if (e is Map) Map<String, dynamic>.from(e),
        ],
        updateChannel: j['updateChannel'] as String? ?? 'stable',
        updateCheckOnStartup: j['updateCheckOnStartup'] as bool? ?? true,
        updateCheckFrequency:
            j['updateCheckFrequency'] as String? ?? 'launch',
        updateLastCheck: (j['updateLastCheck'] as num?)?.toInt() ?? 0,
        updateNotifiedVersion: j['updateNotifiedVersion'] as String? ?? '',
        updateBannerDismissedVersion:
            j['updateBannerDismissedVersion'] as String? ?? '',
      );
}

class PreferencesController extends AsyncNotifier<Prefs> {
  static const _key = 'fathom_prefs';

  @override
  Future<Prefs> build() async {
    final raw = await ref.read(secureStorageProvider).read(key: _key);
    if (raw == null) return const Prefs();
    try {
      return Prefs.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const Prefs();
    }
  }

  Future<void> edit(Prefs Function(Prefs) change) async {
    final current = state.asData?.value ?? const Prefs();
    final next = change(current);
    await ref
        .read(secureStorageProvider)
        .write(key: _key, value: jsonEncode(next.toJson()));
    state = AsyncData(next);
  }
}

final preferencesProvider =
    AsyncNotifierProvider<PreferencesController, Prefs>(
        PreferencesController.new);
