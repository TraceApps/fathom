import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// The application name. Usually left untranslated.
  ///
  /// In en, this message translates to:
  /// **'Fathom'**
  String get appName;

  /// Generic label/tooltip for clearing an input.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get commonClear;

  /// Generic dialog/button: dismiss without acting.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// Generic button: persist changes.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// Generic button: confirm/apply a choice.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get commonApply;

  /// Generic button/tooltip: restore defaults.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get commonReset;

  /// Generic button: try a failed action again.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// Generic button: delete something.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// Generic button/tooltip: remove an item.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get commonRemove;

  /// Generic button/tooltip: close a panel or window.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// Generic button: finish/confirm.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// Generic button/tooltip: edit an item.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// Generic button: add an item.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get commonAdd;

  /// Generic button/tooltip: refresh/reload.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get commonRefresh;

  /// Generic tooltip: go back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// Generic button/tooltip: go to the next item.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get commonNext;

  /// Generic button/tooltip: go to the previous item.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get commonPrevious;

  /// Generic button: sign in / log in.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get commonSignIn;

  /// Generic button: sign out / log out.
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get commonSignOut;

  /// Generic label/hint: search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get commonSearch;

  /// Generic value: a feature is turned off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get commonOff;

  /// Generic value: a feature is turned on.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get commonOn;

  /// Generic button/tooltip: start playback.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get commonPlay;

  /// Generic button/tooltip: pause playback.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get commonPause;

  /// Generic error message when an action fails.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get commonSomethingWrong;

  /// App bar title of the Settings screen.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Placeholder text in the settings search field.
  ///
  /// In en, this message translates to:
  /// **'Search settings'**
  String get settingsSearchHint;

  /// Empty-state shown when a settings search returns nothing.
  ///
  /// In en, this message translates to:
  /// **'No settings match “{query}”'**
  String settingsNoMatch(String query);

  /// Section header grouping app preference categories.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get settingsSectionPreferences;

  /// Section header grouping external integrations (Seerr, YouTube, Watch Together).
  ///
  /// In en, this message translates to:
  /// **'Integrations'**
  String get settingsSectionIntegrations;

  /// Section header grouping account/server rows.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsSectionAccount;

  /// Section header grouping app info rows.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsSectionAbout;

  /// Section header grouping app-maintenance rows: updates, backup, diagnostics.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsSectionSystem;

  /// No description provided for @settingsGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsGeneral;

  /// No description provided for @settingsGeneralSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Startup, notifications, storage'**
  String get settingsGeneralSubtitle;

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsAppearanceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Theme, accent color, AMOLED'**
  String get settingsAppearanceSubtitle;

  /// No description provided for @settingsHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get settingsHome;

  /// No description provided for @settingsHomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Banner and home rows'**
  String get settingsHomeSubtitle;

  /// No description provided for @settingsPlayer.
  ///
  /// In en, this message translates to:
  /// **'Player'**
  String get settingsPlayer;

  /// No description provided for @settingsPlayerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Video fit, autoplay, skip, quality'**
  String get settingsPlayerSubtitle;

  /// No description provided for @settingsAudioSubtitles.
  ///
  /// In en, this message translates to:
  /// **'Audio & Subtitles'**
  String get settingsAudioSubtitles;

  /// No description provided for @settingsAudioSubtitlesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Languages, subtitles, lyrics'**
  String get settingsAudioSubtitlesSubtitle;

  /// No description provided for @settingsRatings.
  ///
  /// In en, this message translates to:
  /// **'Ratings'**
  String get settingsRatings;

  /// No description provided for @settingsRatingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Rotten Tomatoes, IMDb, community'**
  String get settingsRatingsSubtitle;

  /// No description provided for @settingsShortcuts.
  ///
  /// In en, this message translates to:
  /// **'Keyboard Shortcuts'**
  String get settingsShortcuts;

  /// No description provided for @settingsShortcutsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View & customize player keys'**
  String get settingsShortcutsSubtitle;

  /// No description provided for @settingsSeerr.
  ///
  /// In en, this message translates to:
  /// **'Seerr'**
  String get settingsSeerr;

  /// No description provided for @settingsSeerrSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Discover & request media'**
  String get settingsSeerrSubtitle;

  /// No description provided for @settingsYouTube.
  ///
  /// In en, this message translates to:
  /// **'YouTube'**
  String get settingsYouTube;

  /// No description provided for @settingsYouTubeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Search & watch, ad-free'**
  String get settingsYouTubeSubtitle;

  /// No description provided for @settingsWatchTogether.
  ///
  /// In en, this message translates to:
  /// **'Watch Together'**
  String get settingsWatchTogether;

  /// No description provided for @settingsWatchTogetherSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sync playback with others, from your profile menu'**
  String get settingsWatchTogetherSubtitle;

  /// Settings toggle for the Movie Night Wheel feature.
  ///
  /// In en, this message translates to:
  /// **'Movie Night Wheel'**
  String get settingsMovieWheel;

  /// Subtitle under the Movie Night Wheel settings toggle.
  ///
  /// In en, this message translates to:
  /// **'Can\'t decide? Spin an elimination wheel from Watchlist or Watch Together'**
  String get settingsMovieWheelSubtitle;

  /// No description provided for @settingsRadio.
  ///
  /// In en, this message translates to:
  /// **'Internet Radio'**
  String get settingsRadio;

  /// No description provided for @settingsRadioSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Search, save, and play radio stations from the sidebar'**
  String get settingsRadioSubtitle;

  /// No description provided for @settingsProfileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View profile, change picture'**
  String get settingsProfileSubtitle;

  /// No description provided for @settingsAccounts.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get settingsAccounts;

  /// No description provided for @settingsAccountsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Switch server or user, add account'**
  String get settingsAccountsSubtitle;

  /// No description provided for @settingsServer.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get settingsServer;

  /// No description provided for @serverAddressesTitle.
  ///
  /// In en, this message translates to:
  /// **'Server Addresses'**
  String get serverAddressesTitle;

  /// No description provided for @serverAddressInternalLabel.
  ///
  /// In en, this message translates to:
  /// **'Home Address'**
  String get serverAddressInternalLabel;

  /// No description provided for @serverAddressExternalLabel.
  ///
  /// In en, this message translates to:
  /// **'Remote Address'**
  String get serverAddressExternalLabel;

  /// No description provided for @serverAddressInternalHint.
  ///
  /// In en, this message translates to:
  /// **'http://192.168.1.10:8096'**
  String get serverAddressInternalHint;

  /// No description provided for @serverAddressExternalHint.
  ///
  /// In en, this message translates to:
  /// **'https://jellyfin.example.com'**
  String get serverAddressExternalHint;

  /// No description provided for @serverAddressHelp.
  ///
  /// In en, this message translates to:
  /// **'Fathom uses the Home address on your local network and the Remote address elsewhere, switching automatically. Leave Home blank to always use the Remote address.'**
  String get serverAddressHelp;

  /// No description provided for @serverAddressHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get serverAddressHome;

  /// No description provided for @serverAddressRemote.
  ///
  /// In en, this message translates to:
  /// **'Remote'**
  String get serverAddressRemote;

  /// Byline under the app name in the About section, naming who makes Fathom. Opens the TraceApps site. Keep the name TraceApps as is.
  ///
  /// In en, this message translates to:
  /// **'from TraceApps'**
  String get settingsFromTraceApps;

  /// App version row subtitle on the About section.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String settingsVersion(String version);

  /// About-section row title opening the update checker.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get settingsUpdates;

  /// About-section row subtitle for the update checker.
  ///
  /// In en, this message translates to:
  /// **'Check for new versions'**
  String get settingsUpdatesSubtitle;

  /// Title of the Updates screen.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get updatesTitle;

  /// Shows the running app version on the Updates screen.
  ///
  /// In en, this message translates to:
  /// **'Current Version: {version}'**
  String updateCurrentVersion(String version);

  /// Label above the stable/dev update channel selector.
  ///
  /// In en, this message translates to:
  /// **'Update Channel'**
  String get updateChannelLabel;

  /// Update channel option: stable releases only.
  ///
  /// In en, this message translates to:
  /// **'Stable'**
  String get updateChannelStable;

  /// Update channel option: include the latest pre-release dev builds.
  ///
  /// In en, this message translates to:
  /// **'Dev'**
  String get updateChannelBeta;

  /// Helper text under the update channel selector.
  ///
  /// In en, this message translates to:
  /// **'Dev includes the latest pre-release test builds.'**
  String get updateChannelHelp;

  /// Master toggle: automatically check for app updates.
  ///
  /// In en, this message translates to:
  /// **'Automatic Update Checks'**
  String get updateAutoCheckLabel;

  /// Label above the update-check frequency picker.
  ///
  /// In en, this message translates to:
  /// **'How Often'**
  String get updateFrequencyLabel;

  /// Update-check frequency: check each time the app starts.
  ///
  /// In en, this message translates to:
  /// **'Every Launch'**
  String get updateFrequencyLaunch;

  /// Update-check frequency: at most once a day.
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get updateFrequencyDaily;

  /// Update-check frequency: at most once a week.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get updateFrequencyWeekly;

  /// Button that checks for updates immediately.
  ///
  /// In en, this message translates to:
  /// **'Check for Updates'**
  String get updateCheckNow;

  /// Button label while an update check is in progress.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get updateChecking;

  /// Shown when no newer release is available.
  ///
  /// In en, this message translates to:
  /// **'You\'re on the latest version.'**
  String get updateUpToDate;

  /// Button on the update banner that opens the Updates screen.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get updateBannerAction;

  /// Subtitle line on the update banner, below the headline.
  ///
  /// In en, this message translates to:
  /// **'Tap to view what\'s new and install.'**
  String get updateBannerCta;

  /// Tooltip on the update banner's close button.
  ///
  /// In en, this message translates to:
  /// **'Dismiss update banner'**
  String get updateBannerDismiss;

  /// Headline on the Updates screen when a newer release exists.
  ///
  /// In en, this message translates to:
  /// **'Version {version} is available'**
  String updateAvailableHeadline(String version);

  /// Label above the release notes text on the Updates screen.
  ///
  /// In en, this message translates to:
  /// **'Release Notes'**
  String get updateReleaseNotes;

  /// Button that opens the release page in the browser to download. 'GitHub' is a brand name.
  ///
  /// In en, this message translates to:
  /// **'View on GitHub'**
  String get updateViewOnGitHub;

  /// Button that downloads the new version and installs it in place.
  ///
  /// In en, this message translates to:
  /// **'Download & Install'**
  String get updateDownloadInstall;

  /// Android: the update is already downloaded, so the button only opens the system installer.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get updateInstallDownloaded;

  /// Progress label while the update downloads.
  ///
  /// In en, this message translates to:
  /// **'Downloading… {percent}%'**
  String updateDownloading(String percent);

  /// Shown when the in-app download/install fails.
  ///
  /// In en, this message translates to:
  /// **'Download failed. Try again, or use View on GitHub.'**
  String get updateInstallFailed;

  /// Shown when the update check fails (offline / rate-limited).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach GitHub. Check your connection and try again.'**
  String get updateCheckFailedNote;

  /// Top-of-app banner text when a newer release is available.
  ///
  /// In en, this message translates to:
  /// **'Update available: {version}'**
  String updateBannerAvailable(String version);

  /// Banner button that opens the Updates screen.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get updateView;

  /// Notification title when a newer version is first detected. 'Fathom' is the app name.
  ///
  /// In en, this message translates to:
  /// **'Fathom {version} is available'**
  String updateNotifTitle(String version);

  /// Notification body prompting the user to open the Updates screen.
  ///
  /// In en, this message translates to:
  /// **'Open Updates to download and install.'**
  String get updateNotifBody;

  /// Generic dismiss action, e.g. hiding a banner.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get commonDismiss;

  /// No description provided for @settingsSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get settingsSupport;

  /// No description provided for @settingsSupportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Ko-fi, GitHub Sponsors, and free ways to help'**
  String get settingsSupportSubtitle;

  /// Button on the Support page that opens the GitHub Sponsors page. GitHub Sponsors is a product name; keep it as is.
  ///
  /// In en, this message translates to:
  /// **'GitHub Sponsors'**
  String get settingsSponsor;

  /// No description provided for @supportLead.
  ///
  /// In en, this message translates to:
  /// **'Fathom is free and always will be. Support is optional and never unlocks anything.'**
  String get supportLead;

  /// No description provided for @supportOtherWays.
  ///
  /// In en, this message translates to:
  /// **'Other Ways to Help'**
  String get supportOtherWays;

  /// No description provided for @supportStar.
  ///
  /// In en, this message translates to:
  /// **'Star on GitHub'**
  String get supportStar;

  /// No description provided for @supportStarSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Stars are how open source projects get found.'**
  String get supportStarSubtitle;

  /// No description provided for @supportReportBug.
  ///
  /// In en, this message translates to:
  /// **'Report a Bug'**
  String get supportReportBug;

  /// No description provided for @supportReportBugSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A clear report fixes it for everyone who hits the same thing.'**
  String get supportReportBugSubtitle;

  /// No description provided for @supportTranslate.
  ///
  /// In en, this message translates to:
  /// **'Help Translate'**
  String get supportTranslate;

  /// No description provided for @supportTranslateSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Make Fathom usable in your language.'**
  String get supportTranslateSubtitle;

  /// No description provided for @settingsLicenses.
  ///
  /// In en, this message translates to:
  /// **'Open Source Licenses'**
  String get settingsLicenses;

  /// No description provided for @settingsLicensesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The software Fathom is built on'**
  String get settingsLicensesSubtitle;

  /// No description provided for @settingsSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get settingsSignOut;

  /// Settings category AppBar title: general settings.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get prefsSectionGeneral;

  /// Settings category AppBar title: appearance settings.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get prefsSectionAppearance;

  /// Settings category AppBar title: Home screen settings.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get prefsSectionHome;

  /// Settings category AppBar title: video player settings.
  ///
  /// In en, this message translates to:
  /// **'Player'**
  String get prefsSectionPlayer;

  /// Settings category AppBar title: audio and subtitle settings.
  ///
  /// In en, this message translates to:
  /// **'Audio & Subtitles'**
  String get prefsSectionAudio;

  /// Settings category AppBar title: ratings settings.
  ///
  /// In en, this message translates to:
  /// **'Ratings'**
  String get prefsSectionRatings;

  /// Settings category AppBar title: YouTube settings (brand name).
  ///
  /// In en, this message translates to:
  /// **'YouTube'**
  String get prefsSectionYoutube;

  /// Fallback AppBar title when the settings section is unknown.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get prefsSettingsFallback;

  /// Audio language option: use the Jellyfin server's default language.
  ///
  /// In en, this message translates to:
  /// **'Server Default'**
  String get prefsLanguageServerDefault;

  /// Language name: English.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get prefsLanguageEnglish;

  /// Language name: Spanish.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get prefsLanguageSpanish;

  /// Language name: French.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get prefsLanguageFrench;

  /// Language name: German.
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get prefsLanguageGerman;

  /// Language name: Italian.
  ///
  /// In en, this message translates to:
  /// **'Italian'**
  String get prefsLanguageItalian;

  /// Language name: Japanese.
  ///
  /// In en, this message translates to:
  /// **'Japanese'**
  String get prefsLanguageJapanese;

  /// Language name: Korean.
  ///
  /// In en, this message translates to:
  /// **'Korean'**
  String get prefsLanguageKorean;

  /// Language name: Chinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get prefsLanguageChinese;

  /// Language name: Portuguese.
  ///
  /// In en, this message translates to:
  /// **'Portuguese'**
  String get prefsLanguagePortuguese;

  /// Language name: Russian.
  ///
  /// In en, this message translates to:
  /// **'Russian'**
  String get prefsLanguageRussian;

  /// Language name: Dutch.
  ///
  /// In en, this message translates to:
  /// **'Dutch'**
  String get prefsLanguageDutch;

  /// Subtitle language option: no subtitles.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get prefsNone;

  /// Max-quality bitrate cap option: no cap, use the maximum available.
  ///
  /// In en, this message translates to:
  /// **'Auto (max)'**
  String get prefsBitrateAutoMax;

  /// Max-quality bitrate cap option: 2 Mbps, suitable for mobile connections.
  ///
  /// In en, this message translates to:
  /// **'2 Mbps (mobile)'**
  String get prefsBitrate2Mobile;

  /// Settings section header: playback options.
  ///
  /// In en, this message translates to:
  /// **'Playback'**
  String get prefsHeaderPlayback;

  /// Settings section header: browsing options.
  ///
  /// In en, this message translates to:
  /// **'Browsing'**
  String get prefsHeaderBrowsing;

  /// Settings section header: download options.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get prefsHeaderDownloads;

  /// Settings section header: content region and language options.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get prefsHeaderContent;

  /// Settings section header: video watch-page options.
  ///
  /// In en, this message translates to:
  /// **'Watch Page'**
  String get prefsHeaderWatchPage;

  /// Settings section header: watch and search history options.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get prefsHeaderHistory;

  /// Settings section header: app startup options.
  ///
  /// In en, this message translates to:
  /// **'Startup'**
  String get prefsHeaderStartup;

  /// Settings section header: notification options.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get prefsHeaderNotifications;

  /// Settings section header: on-device storage options.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get prefsHeaderStorage;

  /// Settings section header for additional rating sources provided via MDBList.
  ///
  /// In en, this message translates to:
  /// **'More Ratings (MDBList)'**
  String get prefsHeaderMoreRatings;

  /// Settings section header: auto-skip intro/credits options.
  ///
  /// In en, this message translates to:
  /// **'Skipping'**
  String get prefsHeaderSkipping;

  /// Settings section header: advanced player options.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get prefsHeaderAdvanced;

  /// Settings section header: audio options.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get prefsHeaderAudio;

  /// Setting: ReplayGain mode for music (off / per track / per album).
  ///
  /// In en, this message translates to:
  /// **'Volume Levelling'**
  String get prefsReplayGain;

  /// Subtitle for the volume levelling setting.
  ///
  /// In en, this message translates to:
  /// **'Play every song at a similar loudness, using the levels stored in your files'**
  String get prefsReplayGainSub;

  /// Volume levelling option: no adjustment.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get prefsReplayGainOff;

  /// Volume levelling option: level each song on its own.
  ///
  /// In en, this message translates to:
  /// **'Per Track'**
  String get prefsReplayGainTrack;

  /// Volume levelling option: keep an album's own quiet and loud songs relative to each other.
  ///
  /// In en, this message translates to:
  /// **'Per Album'**
  String get prefsReplayGainAlbum;

  /// Setting: gain applied to files that carry no ReplayGain tags.
  ///
  /// In en, this message translates to:
  /// **'Untagged Music'**
  String get prefsReplayGainFallback;

  /// Subtitle for the untagged-music gain setting.
  ///
  /// In en, this message translates to:
  /// **'Adjustment for files with no levels stored in them. Leave at 0 dB to play them untouched.'**
  String get prefsReplayGainFallbackSub;

  /// Settings section header: subtitle options.
  ///
  /// In en, this message translates to:
  /// **'Subtitles'**
  String get prefsHeaderSubtitles;

  /// Settings section header: lyrics options.
  ///
  /// In en, this message translates to:
  /// **'Lyrics'**
  String get prefsHeaderLyrics;

  /// Toggle title: enable the YouTube feature.
  ///
  /// In en, this message translates to:
  /// **'Enable YouTube'**
  String get prefsYtEnable;

  /// Toggle subtitle for enabling YouTube.
  ///
  /// In en, this message translates to:
  /// **'Adds a YouTube section to the sidebar'**
  String get prefsYtEnableSub;

  /// YouTube toggle title: autoplay.
  ///
  /// In en, this message translates to:
  /// **'Autoplay'**
  String get prefsYtAutoplay;

  /// YouTube autoplay toggle subtitle.
  ///
  /// In en, this message translates to:
  /// **'Play a recommended video when one ends'**
  String get prefsYtAutoplaySub;

  /// YouTube toggle title: show dislike counts.
  ///
  /// In en, this message translates to:
  /// **'Show Dislike Counts'**
  String get prefsYtShowDislikes;

  /// YouTube dislike-count toggle subtitle (Return YouTube Dislike is a service name).
  ///
  /// In en, this message translates to:
  /// **'Estimated dislikes via Return YouTube Dislike'**
  String get prefsYtShowDislikesSub;

  /// YouTube toggle title: replace clickbait titles.
  ///
  /// In en, this message translates to:
  /// **'De-Clickbait Titles'**
  String get prefsYtDeArrow;

  /// YouTube de-clickbait toggle subtitle (DeArrow is a service name).
  ///
  /// In en, this message translates to:
  /// **'Crowd-sourced non-clickbait titles via DeArrow'**
  String get prefsYtDeArrowSub;

  /// YouTube setting title: default video resolution.
  ///
  /// In en, this message translates to:
  /// **'Default Quality'**
  String get prefsYtDefaultQuality;

  /// YouTube default-quality setting subtitle.
  ///
  /// In en, this message translates to:
  /// **'Resolution videos start at'**
  String get prefsYtDefaultQualitySub;

  /// Video quality option: automatic, capped at 1080p.
  ///
  /// In en, this message translates to:
  /// **'Auto (up to 1080p)'**
  String get prefsQualityAuto;

  /// YouTube setting title: how far the back button jumps.
  ///
  /// In en, this message translates to:
  /// **'Skip Back'**
  String get prefsYtSkipBack;

  /// YouTube skip-back setting subtitle.
  ///
  /// In en, this message translates to:
  /// **'How far the back button jumps'**
  String get prefsYtSkipBackSub;

  /// A duration in seconds, used for seek-amount options.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 second} other{{count} seconds}}'**
  String prefsSeconds(int count);

  /// YouTube setting title: how far the forward button jumps.
  ///
  /// In en, this message translates to:
  /// **'Skip Forward'**
  String get prefsYtSkipForward;

  /// YouTube skip-forward setting subtitle.
  ///
  /// In en, this message translates to:
  /// **'How far the forward button jumps'**
  String get prefsYtSkipForwardSub;

  /// YouTube toggle title: ask for confirmation before clearing the play queue.
  ///
  /// In en, this message translates to:
  /// **'Confirm Before Clearing Queue'**
  String get prefsYtConfirmClearQueue;

  /// YouTube setting title: how video lists are laid out.
  ///
  /// In en, this message translates to:
  /// **'List View Mode'**
  String get prefsYtListMode;

  /// YouTube list-view-mode setting subtitle.
  ///
  /// In en, this message translates to:
  /// **'How videos are laid out'**
  String get prefsYtListModeSub;

  /// List layout option: single-column list.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get prefsListModeList;

  /// List layout option: multi-column grid.
  ///
  /// In en, this message translates to:
  /// **'Grid'**
  String get prefsListModeGrid;

  /// YouTube setting title: thumbnail image quality.
  ///
  /// In en, this message translates to:
  /// **'Thumbnail Quality'**
  String get prefsYtThumbnailQuality;

  /// YouTube thumbnail-quality setting subtitle.
  ///
  /// In en, this message translates to:
  /// **'Lower loads faster and uses less data'**
  String get prefsYtThumbnailQualitySub;

  /// Thumbnail quality option: low.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get prefsQualityLow;

  /// Thumbnail quality option: medium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get prefsQualityMedium;

  /// Thumbnail quality option: high.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get prefsQualityHigh;

  /// Thumbnail quality option: maximum.
  ///
  /// In en, this message translates to:
  /// **'Maximum'**
  String get prefsQualityMaximum;

  /// YouTube setting title: download quality.
  ///
  /// In en, this message translates to:
  /// **'Download Quality'**
  String get prefsYtDownloadQuality;

  /// YouTube download-quality setting subtitle.
  ///
  /// In en, this message translates to:
  /// **'Ask each time, or always use this'**
  String get prefsYtDownloadQualitySub;

  /// Download quality option: prompt on every download.
  ///
  /// In en, this message translates to:
  /// **'Ask Each Time'**
  String get prefsAskEachTime;

  /// Download quality option: audio-only in M4A format.
  ///
  /// In en, this message translates to:
  /// **'Audio (M4A)'**
  String get prefsYtDownloadAudioM4a;

  /// YouTube setting title: video download file container format.
  ///
  /// In en, this message translates to:
  /// **'Video Container'**
  String get prefsYtVideoContainer;

  /// YouTube video-container setting subtitle.
  ///
  /// In en, this message translates to:
  /// **'File type for video downloads (MKV needs ffmpeg)'**
  String get prefsYtVideoContainerSub;

  /// YouTube setting title: download retry count.
  ///
  /// In en, this message translates to:
  /// **'Retries'**
  String get prefsYtRetries;

  /// YouTube retries setting subtitle.
  ///
  /// In en, this message translates to:
  /// **'Attempts per chunk before giving up'**
  String get prefsYtRetriesSub;

  /// YouTube setting title: number of concurrent downloads.
  ///
  /// In en, this message translates to:
  /// **'Simultaneous Downloads'**
  String get prefsYtSimultaneous;

  /// YouTube simultaneous-downloads setting subtitle.
  ///
  /// In en, this message translates to:
  /// **'More at once mostly splits the same bandwidth'**
  String get prefsYtSimultaneousSub;

  /// YouTube setting title: content result language.
  ///
  /// In en, this message translates to:
  /// **'Content Language'**
  String get prefsYtContentLanguage;

  /// YouTube content-language setting subtitle.
  ///
  /// In en, this message translates to:
  /// **'Language YouTube returns results in'**
  String get prefsYtContentLanguageSub;

  /// YouTube setting title: content result region.
  ///
  /// In en, this message translates to:
  /// **'Content Country'**
  String get prefsYtContentCountry;

  /// YouTube content-country setting subtitle.
  ///
  /// In en, this message translates to:
  /// **'Region results are tailored to'**
  String get prefsYtContentCountrySub;

  /// YouTube toggle title: restricted (safe) mode.
  ///
  /// In en, this message translates to:
  /// **'Restricted Mode'**
  String get prefsYtRestrictedMode;

  /// YouTube restricted-mode toggle subtitle.
  ///
  /// In en, this message translates to:
  /// **'Uses YouTube\'s own filtering of mature content'**
  String get prefsYtRestrictedModeSub;

  /// YouTube toggle title: show comments on the watch page.
  ///
  /// In en, this message translates to:
  /// **'Show Comments'**
  String get prefsYtShowComments;

  /// YouTube toggle title: show the up-next / related videos list.
  ///
  /// In en, this message translates to:
  /// **'Show Up Next'**
  String get prefsYtShowUpNext;

  /// YouTube show-up-next toggle subtitle.
  ///
  /// In en, this message translates to:
  /// **'Related videos beside or below the player'**
  String get prefsYtShowUpNextSub;

  /// YouTube toggle title: show the video description.
  ///
  /// In en, this message translates to:
  /// **'Show Description'**
  String get prefsYtShowDescription;

  /// YouTube toggle title: record watch history.
  ///
  /// In en, this message translates to:
  /// **'Keep Watch History'**
  String get prefsYtKeepWatchHistory;

  /// YouTube keep-watch-history toggle subtitle.
  ///
  /// In en, this message translates to:
  /// **'Off stops recording it, on this device'**
  String get prefsYtKeepWatchHistorySub;

  /// YouTube toggle title: resume videos where you left off.
  ///
  /// In en, this message translates to:
  /// **'Resume Playback'**
  String get prefsYtResumePlayback;

  /// YouTube resume-playback toggle subtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick videos up where you left off'**
  String get prefsYtResumePlaybackSub;

  /// YouTube toggle title: record search history.
  ///
  /// In en, this message translates to:
  /// **'Keep Search History'**
  String get prefsYtKeepSearchHistory;

  /// Explanatory paragraph at the bottom of the YouTube settings screen.
  ///
  /// In en, this message translates to:
  /// **'Videos are streamed directly and play in the same player as the rest of the app, so there are no ads. Higher resolutions are decoded on the CPU, so Auto stays at 1080p for smooth playback. Subscriptions, playlists and history are kept on this device: no account is involved, and nothing is sent to YouTube.'**
  String get prefsYtInfoParagraph;

  /// Intro paragraph at the top of the Ratings settings screen.
  ///
  /// In en, this message translates to:
  /// **'Choose which scores appear on movie and show pages. Rotten Tomatoes and IMDb figures come from Seerr when it is connected.'**
  String get prefsRatingsIntro;

  /// Ratings toggle title: Rotten Tomatoes critics score.
  ///
  /// In en, this message translates to:
  /// **'Rotten Tomatoes Critics'**
  String get prefsRtCritics;

  /// Ratings toggle title: Rotten Tomatoes audience score.
  ///
  /// In en, this message translates to:
  /// **'Rotten Tomatoes Audience'**
  String get prefsRtAudience;

  /// Ratings toggle title: IMDb rating.
  ///
  /// In en, this message translates to:
  /// **'IMDb Rating'**
  String get prefsImdbRating;

  /// Ratings toggle title: community score.
  ///
  /// In en, this message translates to:
  /// **'Community Score'**
  String get prefsCommunityScore;

  /// Community-score toggle subtitle.
  ///
  /// In en, this message translates to:
  /// **'Jellyfin\'s own rating / TMDB vote average'**
  String get prefsCommunityScoreSub;

  /// Explanatory paragraph for the MDBList extra-ratings section.
  ///
  /// In en, this message translates to:
  /// **'Adds Letterboxd, Metacritic, Trakt and more, and fills in any missing Rotten Tomatoes / IMDb scores above. Needs a free MDBList API key (mdblist.com). Ratings barely change, so results are cached.'**
  String get prefsMdbListIntro;

  /// Text field label for the MDBList API key.
  ///
  /// In en, this message translates to:
  /// **'MDBList API Key'**
  String get prefsMdbListApiKey;

  /// Text field hint for the MDBList API key.
  ///
  /// In en, this message translates to:
  /// **'Paste your key from mdblist.com'**
  String get prefsMdbListApiKeyHint;

  /// Ratings toggle title: Metacritic user score.
  ///
  /// In en, this message translates to:
  /// **'Metacritic User'**
  String get prefsMetacriticUser;

  /// Subtitle shown on an MDBList rating toggle when no API key is set.
  ///
  /// In en, this message translates to:
  /// **'Add an MDBList API key to enable'**
  String get prefsMdbAddKeyToEnable;

  /// General setting title: which screen opens on launch.
  ///
  /// In en, this message translates to:
  /// **'Open on Startup'**
  String get prefsOpenOnStartup;

  /// Open-on-startup setting subtitle (Fathom is the app name).
  ///
  /// In en, this message translates to:
  /// **'Which screen to show when Fathom launches'**
  String get prefsOpenOnStartupSub;

  /// Startup screen option: Home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get prefsStartupHome;

  /// Startup screen option: Libraries.
  ///
  /// In en, this message translates to:
  /// **'Libraries'**
  String get prefsStartupLibraries;

  /// Startup screen option: Live TV.
  ///
  /// In en, this message translates to:
  /// **'Live TV'**
  String get prefsStartupLiveTv;

  /// General toggle title: OS system notifications (desktop and mobile).
  ///
  /// In en, this message translates to:
  /// **'System Notifications'**
  String get prefsDesktopNotifications;

  /// System-notifications toggle subtitle.
  ///
  /// In en, this message translates to:
  /// **'Show system pop-ups on desktop and mobile (the in-app bell always collects)'**
  String get prefsDesktopNotificationsSub;

  /// Notification toggle title: a new Seerr request was made.
  ///
  /// In en, this message translates to:
  /// **'New Request'**
  String get prefsNotifNewRequest;

  /// New-request notification toggle subtitle.
  ///
  /// In en, this message translates to:
  /// **'When a Seerr request is made (pending approval)'**
  String get prefsNotifNewRequestSub;

  /// Notification toggle title: a Seerr request was approved.
  ///
  /// In en, this message translates to:
  /// **'Request Approved'**
  String get prefsNotifApproved;

  /// Request-approved notification toggle subtitle.
  ///
  /// In en, this message translates to:
  /// **'When a Seerr request is approved'**
  String get prefsNotifApprovedSub;

  /// Notification toggle title: a Seerr request was declined.
  ///
  /// In en, this message translates to:
  /// **'Request Declined'**
  String get prefsNotifDeclined;

  /// Request-declined notification toggle subtitle.
  ///
  /// In en, this message translates to:
  /// **'When a Seerr request is declined'**
  String get prefsNotifDeclinedSub;

  /// Notification toggle title: a requested title is now available.
  ///
  /// In en, this message translates to:
  /// **'Now Available'**
  String get prefsNotifAvailable;

  /// Now-available notification toggle subtitle.
  ///
  /// In en, this message translates to:
  /// **'When a requested title has downloaded'**
  String get prefsNotifAvailableSub;

  /// General setting title: how often to poll Seerr for request status.
  ///
  /// In en, this message translates to:
  /// **'Check for Request Updates'**
  String get prefsCheckRequestUpdates;

  /// Check-for-request-updates setting subtitle.
  ///
  /// In en, this message translates to:
  /// **'How often to poll Seerr for status changes'**
  String get prefsCheckRequestUpdatesSub;

  /// Poll-interval option: once a minute.
  ///
  /// In en, this message translates to:
  /// **'Every Minute'**
  String get prefsEveryMinute;

  /// Poll-interval option: every 5 minutes.
  ///
  /// In en, this message translates to:
  /// **'Every 5 Minutes'**
  String get prefsEvery5Minutes;

  /// Poll-interval option: every 15 minutes.
  ///
  /// In en, this message translates to:
  /// **'Every 15 Minutes'**
  String get prefsEvery15Minutes;

  /// Poll-interval option: every 30 minutes.
  ///
  /// In en, this message translates to:
  /// **'Every 30 Minutes'**
  String get prefsEvery30Minutes;

  /// Notification toggle title: a download finished.
  ///
  /// In en, this message translates to:
  /// **'Download Complete'**
  String get prefsDownloadComplete;

  /// Download-complete notification toggle subtitle.
  ///
  /// In en, this message translates to:
  /// **'When a download to this device finishes'**
  String get prefsDownloadCompleteSub;

  /// Notification toggle title: a new app version is available.
  ///
  /// In en, this message translates to:
  /// **'Update Available'**
  String get prefsNotifUpdates;

  /// Update-available notification toggle subtitle.
  ///
  /// In en, this message translates to:
  /// **'When a new version of Fathom is available'**
  String get prefsNotifUpdatesSub;

  /// Appearance setting title: light/dark theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get prefsTheme;

  /// Option meaning automatic: theme follows the system, or the rating source is chosen automatically.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get prefsAuto;

  /// Theme option: dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get prefsThemeDark;

  /// Theme option: light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get prefsThemeLight;

  /// Appearance setting title: accent color.
  ///
  /// In en, this message translates to:
  /// **'Accent Color'**
  String get prefsAccentColor;

  /// Appearance toggle title: pure-black AMOLED backgrounds.
  ///
  /// In en, this message translates to:
  /// **'AMOLED Black'**
  String get prefsAmoledBlack;

  /// AMOLED-black toggle subtitle.
  ///
  /// In en, this message translates to:
  /// **'Pure-black backgrounds in dark mode'**
  String get prefsAmoledBlackSub;

  /// Setting (desktop): how big the whole interface is drawn, for high-resolution screens.
  ///
  /// In en, this message translates to:
  /// **'Interface Size'**
  String get prefsInterfaceSize;

  /// Interface Size setting subtitle.
  ///
  /// In en, this message translates to:
  /// **'Makes everything bigger or smaller. Automatic follows your display.'**
  String get prefsInterfaceSizeSub;

  /// Interface Size option: follow the display, showing the size it works out to, such as 150%.
  ///
  /// In en, this message translates to:
  /// **'Automatic ({percent}%)'**
  String prefsInterfaceSizeAuto(int percent);

  /// An Interface Size option as a percentage, such as 125%.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String prefsInterfaceSizePercent(int percent);

  /// Toggle title: force the 10-foot D-pad interface.
  ///
  /// In en, this message translates to:
  /// **'Force TV Mode'**
  String get prefsForceTvMode;

  /// Force TV mode toggle subtitle.
  ///
  /// In en, this message translates to:
  /// **'Use the 10-foot remote interface even if this device isn\'t a television. Applies after restarting the app.'**
  String get prefsForceTvModeSub;

  /// Appearance setting title: rating badge on poster cards.
  ///
  /// In en, this message translates to:
  /// **'Rating on Cards'**
  String get prefsRatingOnCards;

  /// Rating-on-cards setting subtitle.
  ///
  /// In en, this message translates to:
  /// **'A rating badge on poster cards'**
  String get prefsRatingOnCardsSub;

  /// Card rating option: community score.
  ///
  /// In en, this message translates to:
  /// **'Community'**
  String get prefsCardRatingCommunity;

  /// Card rating option: critics score.
  ///
  /// In en, this message translates to:
  /// **'Critics'**
  String get prefsCardRatingCritics;

  /// Dialog title for choosing a custom accent color.
  ///
  /// In en, this message translates to:
  /// **'Custom Accent'**
  String get prefsCustomAccent;

  /// Home setting title: featured banner style.
  ///
  /// In en, this message translates to:
  /// **'Home Banner'**
  String get prefsHomeBanner;

  /// Home-banner setting subtitle.
  ///
  /// In en, this message translates to:
  /// **'Featured titles at the top of Home'**
  String get prefsHomeBannerSub;

  /// Home banner option: rotating carousel.
  ///
  /// In en, this message translates to:
  /// **'Carousel'**
  String get prefsBannerCarousel;

  /// Home banner option: single detailed banner.
  ///
  /// In en, this message translates to:
  /// **'Detailed'**
  String get prefsBannerDetailed;

  /// Home banner option: hidden.
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get prefsBannerHidden;

  /// Home setting title: opens the Home layout editor.
  ///
  /// In en, this message translates to:
  /// **'Home Layout'**
  String get prefsHomeLayout;

  /// Home-layout setting subtitle.
  ///
  /// In en, this message translates to:
  /// **'Reorder & toggle the Home rows'**
  String get prefsHomeLayoutSub;

  /// Setting title: opens the sidebar/nav customization editor.
  ///
  /// In en, this message translates to:
  /// **'Navigation'**
  String get prefsNavLayout;

  /// Navigation-layout setting subtitle.
  ///
  /// In en, this message translates to:
  /// **'Reorder & hide the sidebar items'**
  String get prefsNavLayoutSub;

  /// Navigation customization screen title.
  ///
  /// In en, this message translates to:
  /// **'Navigation'**
  String get navLayoutTitle;

  /// Navigation customization screen subtitle.
  ///
  /// In en, this message translates to:
  /// **'Drag to reorder. Turn items off to hide them from the sidebar.'**
  String get navLayoutSubtitle;

  /// Player setting title: how video fills the screen.
  ///
  /// In en, this message translates to:
  /// **'Video Fit'**
  String get prefsVideoFit;

  /// Video fit option: contain (letterbox to fit).
  ///
  /// In en, this message translates to:
  /// **'Fit'**
  String get prefsFitContain;

  /// Video fit option: cover (crop to fill).
  ///
  /// In en, this message translates to:
  /// **'Fill Screen'**
  String get prefsFitCover;

  /// Video fit option: stretch to fill.
  ///
  /// In en, this message translates to:
  /// **'Stretch'**
  String get prefsFitFill;

  /// Player setting title: playback control bar background.
  ///
  /// In en, this message translates to:
  /// **'Control Bar'**
  String get prefsControlBar;

  /// Control-bar setting subtitle.
  ///
  /// In en, this message translates to:
  /// **'Background behind the playback controls'**
  String get prefsControlBarSub;

  /// Control bar option: no frosted-glass background.
  ///
  /// In en, this message translates to:
  /// **'No Glass'**
  String get prefsBarNoGlass;

  /// Control bar option: frosted-glass background.
  ///
  /// In en, this message translates to:
  /// **'Glass'**
  String get prefsBarGlass;

  /// Control bar option: dark frosted-glass background.
  ///
  /// In en, this message translates to:
  /// **'Dark Glass'**
  String get prefsBarDarkGlass;

  /// Player setting title: maximum transcode quality cap.
  ///
  /// In en, this message translates to:
  /// **'Max Quality'**
  String get prefsMaxQuality;

  /// Max-quality setting subtitle.
  ///
  /// In en, this message translates to:
  /// **'Cap when the server has to transcode'**
  String get prefsMaxQualitySub;

  /// Player setting title: in-app trailer resolution.
  ///
  /// In en, this message translates to:
  /// **'Trailer Quality'**
  String get prefsTrailerQuality;

  /// Trailer-quality setting subtitle.
  ///
  /// In en, this message translates to:
  /// **'Resolution for in-app YouTube trailers'**
  String get prefsTrailerQualitySub;

  /// Player setting title: default playback speed.
  ///
  /// In en, this message translates to:
  /// **'Default Speed'**
  String get prefsDefaultSpeed;

  /// Default-speed setting subtitle.
  ///
  /// In en, this message translates to:
  /// **'Playback rate when a video starts'**
  String get prefsDefaultSpeedSub;

  /// Playback speed option: normal (1x).
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get prefsSpeedNormal;

  /// Player toggle title: autoplay the next episode.
  ///
  /// In en, this message translates to:
  /// **'Autoplay Next Episode'**
  String get prefsAutoplayNext;

  /// Player toggle title: remember audio/subtitle track selections.
  ///
  /// In en, this message translates to:
  /// **'Remember Track Selections'**
  String get prefsRememberTracks;

  /// Player toggle title: show preview thumbnails while seeking.
  ///
  /// In en, this message translates to:
  /// **'Preview Thumbnails While Seeking'**
  String get prefsPreviewThumbnails;

  /// Preview-thumbnails toggle subtitle.
  ///
  /// In en, this message translates to:
  /// **'Show a thumbnail when hovering the seek bar, where available'**
  String get prefsPreviewThumbnailsSub;

  /// Player toggle title: automatically skip intros.
  ///
  /// In en, this message translates to:
  /// **'Auto-Skip Intros'**
  String get prefsAutoSkipIntros;

  /// Auto-skip-intros toggle subtitle.
  ///
  /// In en, this message translates to:
  /// **'Needs a Media Segments provider on the server'**
  String get prefsAutoSkipIntrosSub;

  /// Player toggle title: automatically skip credits.
  ///
  /// In en, this message translates to:
  /// **'Auto-Skip Credits'**
  String get prefsAutoSkipCredits;

  /// Player setting title: when the Up Next card appears during credits.
  ///
  /// In en, this message translates to:
  /// **'Up Next Timing'**
  String get prefsUpNextTiming;

  /// Player setting subtitle for Up Next timing.
  ///
  /// In en, this message translates to:
  /// **'How long the Up Next prompt shows before auto-playing the next episode'**
  String get prefsUpNextTimingSub;

  /// Up Next timing option: stay for the whole credits, auto-play at the end (Jellyfin-style).
  ///
  /// In en, this message translates to:
  /// **'Full credits'**
  String get prefsUpNextFullCredits;

  /// Up Next timing option: auto-play the next episode this many seconds after the credits start.
  ///
  /// In en, this message translates to:
  /// **'After {count}s'**
  String prefsUpNextSecondsBefore(int count);

  /// Player setting title: how the Up Next prompt is presented.
  ///
  /// In en, this message translates to:
  /// **'Up Next Style'**
  String get prefsUpNextStyle;

  /// Player setting subtitle for Up Next style.
  ///
  /// In en, this message translates to:
  /// **'How the next-episode prompt looks during credits'**
  String get prefsUpNextStyleSub;

  /// Up Next style option: a card with poster, title and countdown ring.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get prefsUpNextStyleCard;

  /// Up Next style option: a compact pill with the countdown as a progress fill (Netflix-style).
  ///
  /// In en, this message translates to:
  /// **'Pill'**
  String get prefsUpNextStylePill;

  /// Up Next card button: start the next episode immediately.
  ///
  /// In en, this message translates to:
  /// **'Play Now'**
  String get playerUpNextPlayNow;

  /// Up Next card button: dismiss the card.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get playerUpNextHide;

  /// Up Next card countdown text; seconds until the next episode auto-plays.
  ///
  /// In en, this message translates to:
  /// **'Playing in {seconds}s'**
  String playerUpNextIn(int seconds);

  /// Player toggle title: hardware video decoding.
  ///
  /// In en, this message translates to:
  /// **'Hardware Decoding'**
  String get prefsHardwareDecoding;

  /// Hardware-decoding toggle subtitle.
  ///
  /// In en, this message translates to:
  /// **'Turn off if some videos glitch or fail'**
  String get prefsHardwareDecodingSub;

  /// Advanced playback toggle title: bitstream surround audio to a receiver.
  ///
  /// In en, this message translates to:
  /// **'Audio Passthrough'**
  String get prefsAudioPassthrough;

  /// Audio-passthrough toggle subtitle.
  ///
  /// In en, this message translates to:
  /// **'Send Dolby Atmos / DTS to a connected receiver untouched. Only for an AV receiver or soundbar; leave off for regular speakers.'**
  String get prefsAudioPassthroughSub;

  /// Player toggle title: pace video to the display refresh.
  ///
  /// In en, this message translates to:
  /// **'Smooth Motion (Display Sync)'**
  String get prefsDisplaySync;

  /// Display-sync toggle subtitle.
  ///
  /// In en, this message translates to:
  /// **'Pace video to your monitor\'s refresh rate to reduce judder and stutter. Try it if playback isn\'t as smooth as another player.'**
  String get prefsDisplaySyncSub;

  /// Player toggle title: capture a verbose playback log.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic Logging'**
  String get prefsDiagnosticLogging;

  /// Diagnostic-logging toggle subtitle.
  ///
  /// In en, this message translates to:
  /// **'Capture a verbose playback log to copy into a bug report. Turn on, reproduce the issue, then copy. Slightly slower while on.'**
  String get prefsDiagnosticLoggingSub;

  /// Action title: copy the captured diagnostic report to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy Diagnostics'**
  String get prefsCopyDiagnostics;

  /// Copy-diagnostics action subtitle.
  ///
  /// In en, this message translates to:
  /// **'Copy the captured log and system info to the clipboard'**
  String get prefsCopyDiagnosticsSub;

  /// Snackbar shown after copying diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics copied to clipboard'**
  String get prefsDiagnosticsCopied;

  /// Snackbar shown when there is no captured diagnostic log yet.
  ///
  /// In en, this message translates to:
  /// **'Play something with logging on first, then copy'**
  String get prefsDiagnosticsEmpty;

  /// Title of the app-wide Diagnostics/troubleshooting screen.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagnosticsTitle;

  /// Settings About-row subtitle for Diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Capture logs to troubleshoot a problem'**
  String get diagnosticsSubtitle;

  /// Explanatory paragraph at the top of the Diagnostics screen.
  ///
  /// In en, this message translates to:
  /// **'Turn on Diagnostic Logging, reproduce the problem, then copy the log into a bug report. Capture covers errors, app activity, and detailed playback info. It stays off until you turn it on, and credentials are removed from anything captured.'**
  String get diagnosticsIntro;

  /// Action to empty the diagnostics buffer.
  ///
  /// In en, this message translates to:
  /// **'Clear Captured Log'**
  String get diagnosticsClear;

  /// Snackbar shown after clearing the diagnostics buffer.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic log cleared'**
  String get diagnosticsCleared;

  /// Audio setting title: preferred audio language.
  ///
  /// In en, this message translates to:
  /// **'Audio Language'**
  String get prefsAudioLanguage;

  /// Subtitle setting title: preferred subtitle language.
  ///
  /// In en, this message translates to:
  /// **'Subtitle Language'**
  String get prefsSubtitleLanguage;

  /// Subtitle setting title: text size.
  ///
  /// In en, this message translates to:
  /// **'Subtitle Size'**
  String get prefsSubtitleSize;

  /// A percentage value shown on a slider label.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String prefsPercent(int percent);

  /// Subtitle setting title: text color.
  ///
  /// In en, this message translates to:
  /// **'Subtitle Color'**
  String get prefsSubtitleColor;

  /// Subtitle setting title: background opacity.
  ///
  /// In en, this message translates to:
  /// **'Subtitle Background'**
  String get prefsSubtitleBackground;

  /// Subtitle setting title: vertical position.
  ///
  /// In en, this message translates to:
  /// **'Subtitle Position'**
  String get prefsSubtitlePosition;

  /// Subtitle position slider label at the lowest position.
  ///
  /// In en, this message translates to:
  /// **'Bottom'**
  String get prefsSubtitlePositionBottom;

  /// Subtitle position slider label: how far above the bottom the subtitles sit.
  ///
  /// In en, this message translates to:
  /// **'{amount} higher'**
  String prefsSubtitlePositionHigher(int amount);

  /// Sample text shown in the subtitle style preview box.
  ///
  /// In en, this message translates to:
  /// **'Subtitle preview'**
  String get prefsSubtitlePreview;

  /// Lyrics toggle title: open lyrics automatically.
  ///
  /// In en, this message translates to:
  /// **'Show Lyrics Automatically'**
  String get prefsShowLyricsAuto;

  /// Show-lyrics-automatically toggle subtitle.
  ///
  /// In en, this message translates to:
  /// **'Open lyrics when a song has them. Artwork stays one tap away.'**
  String get prefsShowLyricsAutoSub;

  /// Lyrics toggle title: fetch missing lyrics from the internet.
  ///
  /// In en, this message translates to:
  /// **'Look Up Missing Lyrics Online'**
  String get prefsLookUpLyrics;

  /// Look-up-missing-lyrics toggle subtitle (LrcLib / lrclib.net is a service).
  ///
  /// In en, this message translates to:
  /// **'When your server has none, fetch from LrcLib. Song title and artist are sent to lrclib.net.'**
  String get prefsLookUpLyricsSub;

  /// Confirmation dialog title before clearing some data.
  ///
  /// In en, this message translates to:
  /// **'Clear {what}?'**
  String prefsClearConfirmTitle(String what);

  /// Confirmation dialog body warning the action is irreversible.
  ///
  /// In en, this message translates to:
  /// **'This can\'t be undone.'**
  String get prefsClearCannotUndo;

  /// List tile title: clear YouTube watch history.
  ///
  /// In en, this message translates to:
  /// **'Clear Watch History'**
  String get prefsClearWatchHistory;

  /// Subtitle shown when there is no history to clear.
  ///
  /// In en, this message translates to:
  /// **'Nothing recorded'**
  String get prefsNothingRecorded;

  /// Subtitle showing how many videos are in the watch history.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 video, including resume positions} other{{count} videos, including resume positions}}'**
  String prefsWatchHistoryCount(int count);

  /// Noun inserted into the clear-confirmation dialog title, e.g. 'Clear watch history?'.
  ///
  /// In en, this message translates to:
  /// **'watch history'**
  String get prefsWhatWatchHistory;

  /// Snackbar confirming the watch history was cleared.
  ///
  /// In en, this message translates to:
  /// **'Watch history cleared.'**
  String get prefsWatchHistoryCleared;

  /// List tile title: clear YouTube search history.
  ///
  /// In en, this message translates to:
  /// **'Clear Search History'**
  String get prefsClearSearchHistory;

  /// Subtitle showing how many searches are in the search history.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 search} other{{count} searches}}'**
  String prefsSearchHistoryCount(int count);

  /// Noun inserted into the clear-confirmation dialog title, e.g. 'Clear search history?'.
  ///
  /// In en, this message translates to:
  /// **'search history'**
  String get prefsWhatSearchHistory;

  /// Snackbar confirming the search history was cleared.
  ///
  /// In en, this message translates to:
  /// **'Search history cleared.'**
  String get prefsSearchHistoryCleared;

  /// Directory-picker dialog title for the audio download folder.
  ///
  /// In en, this message translates to:
  /// **'Audio Download Folder'**
  String get prefsAudioDownloadFolder;

  /// Directory-picker dialog title for the video download folder.
  ///
  /// In en, this message translates to:
  /// **'Video Download Folder'**
  String get prefsVideoDownloadFolder;

  /// List tile title: video download folder.
  ///
  /// In en, this message translates to:
  /// **'Video Folder'**
  String get prefsVideoFolder;

  /// List tile title: audio download folder.
  ///
  /// In en, this message translates to:
  /// **'Audio Folder'**
  String get prefsAudioFolder;

  /// Shown when a download folder uses the default location.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get prefsDefault;

  /// List tile title: where downloaded Jellyfin media (movies, shows, music, recordings) is saved.
  ///
  /// In en, this message translates to:
  /// **'Download Location'**
  String get prefsDownloadLocation;

  /// Directory-picker dialog title for the Jellyfin download location.
  ///
  /// In en, this message translates to:
  /// **'Choose Download Location'**
  String get prefsDownloadLocationPick;

  /// SponsorBlock toggle title: skip sponsor segments.
  ///
  /// In en, this message translates to:
  /// **'Skip Sponsor Segments'**
  String get prefsSbSkip;

  /// SponsorBlock skip toggle subtitle.
  ///
  /// In en, this message translates to:
  /// **'Skips ad reads inside the video. Not YouTube\'s ads — those never reach this app.'**
  String get prefsSbSkipSub;

  /// SponsorBlock toggle title: notify when a segment is skipped.
  ///
  /// In en, this message translates to:
  /// **'Say When Something Is Skipped'**
  String get prefsSbNotify;

  /// SponsorBlock notify toggle subtitle.
  ///
  /// In en, this message translates to:
  /// **'With an Undo, in case it was wrong'**
  String get prefsSbNotifySub;

  /// Header above the SponsorBlock category checkboxes.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get prefsSbCategories;

  /// SponsorBlock attribution and licensing paragraph.
  ///
  /// In en, this message translates to:
  /// **'Segment data comes from SponsorBlock (sponsor.ajay.app), crowdsourced and licensed CC BY-NC-SA 4.0. Coverage depends on people having submitted timestamps for a video, so it is dense on some channels and absent on others. Video ids are sent to SponsorBlock\'s servers while this is on.'**
  String get prefsSbAttribution;

  /// Storage list tile title: on-disk image cache.
  ///
  /// In en, this message translates to:
  /// **'Image Cache'**
  String get prefsImageCache;

  /// Placeholder shown while the image cache size is being measured.
  ///
  /// In en, this message translates to:
  /// **'Calculating…'**
  String get prefsCalculating;

  /// Image cache subtitle showing what is cached and its size (e.g. '1.2 GB').
  ///
  /// In en, this message translates to:
  /// **'Posters, backdrops and thumbnails · {size}'**
  String prefsImageCacheSub(String size);

  /// Button label while the image cache is being cleared.
  ///
  /// In en, this message translates to:
  /// **'Clearing…'**
  String get prefsClearing;

  /// AppBar title for the user profile screen.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// Snackbar after the profile photo is uploaded.
  ///
  /// In en, this message translates to:
  /// **'Profile picture updated'**
  String get profilePictureUpdated;

  /// Snackbar after the profile photo is deleted.
  ///
  /// In en, this message translates to:
  /// **'Profile picture removed'**
  String get profilePictureRemoved;

  /// Button to pick and upload a new profile photo.
  ///
  /// In en, this message translates to:
  /// **'Change Photo'**
  String get profileChangePhoto;

  /// Button to delete the current profile photo.
  ///
  /// In en, this message translates to:
  /// **'Remove Photo'**
  String get profileRemovePhoto;

  /// Button and dialog title for the user changing their own password.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get profileChangePassword;

  /// Field label for the user's existing password.
  ///
  /// In en, this message translates to:
  /// **'Current Password'**
  String get profileCurrentPassword;

  /// Field label for the new password.
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get profileNewPassword;

  /// Field label to re-enter the new password.
  ///
  /// In en, this message translates to:
  /// **'Confirm New Password'**
  String get profileConfirmPassword;

  /// Error shown when the new password and its confirmation differ.
  ///
  /// In en, this message translates to:
  /// **'The new passwords don\'t match.'**
  String get profilePasswordMismatch;

  /// Error shown when an administrator tries to set a blank password; the server does not allow this.
  ///
  /// In en, this message translates to:
  /// **'Administrator accounts must have a password and can\'t be left blank.'**
  String get profileAdminNeedsPassword;

  /// Title of the confirmation dialog when the new password field is left blank.
  ///
  /// In en, this message translates to:
  /// **'Remove Your Password?'**
  String get profileNoPasswordTitle;

  /// Body of the confirmation dialog when the new password field is left blank.
  ///
  /// In en, this message translates to:
  /// **'Leaving the new password blank removes your password. Anyone with access to your account will be able to sign in without one.'**
  String get profileNoPasswordBody;

  /// Confirm button on the blank-password warning dialog.
  ///
  /// In en, this message translates to:
  /// **'Remove Password'**
  String get profileNoPasswordConfirm;

  /// Confirmation after the password is changed.
  ///
  /// In en, this message translates to:
  /// **'Password changed.'**
  String get profilePasswordChanged;

  /// AppBar title for the accounts (server/user switcher) screen.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get accountTitle;

  /// List tile title to sign in to another server or user.
  ///
  /// In en, this message translates to:
  /// **'Add Account'**
  String get accountAdd;

  /// Subtitle under the Add Account tile.
  ///
  /// In en, this message translates to:
  /// **'Sign in to another server or user'**
  String get accountAddSubtitle;

  /// Intro line on the Seerr settings screen.
  ///
  /// In en, this message translates to:
  /// **'Connect your Seerr instance to discover and request media.'**
  String get seerrIntro;

  /// Field label for the Seerr server URL.
  ///
  /// In en, this message translates to:
  /// **'Server URL'**
  String get seerrServerUrl;

  /// Segmented button label for API-key authentication mode.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get seerrApiKeySegment;

  /// Field label for the Seerr admin API key.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get seerrApiKeyLabel;

  /// Helper text under the API key field.
  ///
  /// In en, this message translates to:
  /// **'Requests are made as the admin (auto-approved).'**
  String get seerrApiKeyHelper;

  /// Button to save the Seerr API key and test the connection.
  ///
  /// In en, this message translates to:
  /// **'Save & Test'**
  String get seerrSaveTest;

  /// Card title shown when signed in to Seerr with credentials.
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get seerrSignedIn;

  /// Card subtitle explaining requests are made as the signed-in user.
  ///
  /// In en, this message translates to:
  /// **'Requests are attributed to you.'**
  String get seerrRequestsAttributed;

  /// Helper text above the Seerr sign-in form.
  ///
  /// In en, this message translates to:
  /// **'Sign in with your Jellyfin username and password. Requests are made as you, following your Seerr permissions.'**
  String get seerrSignInHelp;

  /// Field label for the Jellyfin username used to sign in to Seerr.
  ///
  /// In en, this message translates to:
  /// **'Jellyfin Username'**
  String get seerrUsernameLabel;

  /// Field label for the password used to sign in to Seerr.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get seerrPasswordLabel;

  /// Snackbar when the Seerr URL is cleared.
  ///
  /// In en, this message translates to:
  /// **'Seerr disconnected'**
  String get seerrDisconnected;

  /// Snackbar when the Seerr connection test succeeds.
  ///
  /// In en, this message translates to:
  /// **'Connected to Seerr'**
  String get seerrConnected;

  /// Snackbar when Seerr settings are saved but the connection test failed.
  ///
  /// In en, this message translates to:
  /// **'Saved, but the connection test failed'**
  String get seerrSavedTestFailed;

  /// Snackbar prompting the user to fill in all sign-in fields.
  ///
  /// In en, this message translates to:
  /// **'Enter the server URL, username and password.'**
  String get seerrEnterCredentials;

  /// Snackbar prompting the user to fill in all local sign-in fields (email instead of username).
  ///
  /// In en, this message translates to:
  /// **'Enter the server URL, email and password.'**
  String get seerrEnterCredentialsLocal;

  /// Sign-in method button: use the Jellyfin account. 'Jellyfin' is a brand name.
  ///
  /// In en, this message translates to:
  /// **'Login with Jellyfin'**
  String get seerrLoginWithJellyfin;

  /// Sign-in method button: use a local Seerr account (email + password created in Seerr). 'Seerr' is a brand name.
  ///
  /// In en, this message translates to:
  /// **'Login with Seerr'**
  String get seerrLoginWithSeerr;

  /// Helper text above the local Seerr sign-in form.
  ///
  /// In en, this message translates to:
  /// **'Sign in with a Seerr account (email and password) created directly in Seerr, not through Jellyfin.'**
  String get seerrLocalSignInHelp;

  /// Field label for the email used to sign in to a local Seerr account.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get seerrEmailLabel;

  /// Snackbar after a successful Seerr sign-in.
  ///
  /// In en, this message translates to:
  /// **'Signed in as {name}'**
  String seerrSignedInAs(String name);

  /// Snackbar after signing out of Seerr.
  ///
  /// In en, this message translates to:
  /// **'Signed out'**
  String get seerrSignedOut;

  /// AppBar title for the keyboard shortcuts screen.
  ///
  /// In en, this message translates to:
  /// **'Keyboard Shortcuts'**
  String get shortcutsTitle;

  /// Helper text explaining fixed and reassignable keyboard shortcuts.
  ///
  /// In en, this message translates to:
  /// **'Space and media keys always play/pause; Esc exits fullscreen. Tap a shortcut to reassign it.'**
  String get shortcutsHelp;

  /// Title of the dialog that captures a key press to rebind a shortcut.
  ///
  /// In en, this message translates to:
  /// **'Press a Key'**
  String get shortcutsPressKey;

  /// Body of the key-capture dialog while waiting for input.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a key press…'**
  String get shortcutsWaiting;

  /// Player action label: toggle play/pause.
  ///
  /// In en, this message translates to:
  /// **'Play / Pause'**
  String get shortcutsPlayPause;

  /// Player action label: seek backward 10 seconds.
  ///
  /// In en, this message translates to:
  /// **'Seek Backward 10s'**
  String get shortcutsSeekBackward;

  /// Player action label: seek forward 10 seconds.
  ///
  /// In en, this message translates to:
  /// **'Seek Forward 10s'**
  String get shortcutsSeekForward;

  /// Player action label: increase volume.
  ///
  /// In en, this message translates to:
  /// **'Volume Up'**
  String get shortcutsVolumeUp;

  /// Player action label: decrease volume.
  ///
  /// In en, this message translates to:
  /// **'Volume Down'**
  String get shortcutsVolumeDown;

  /// Player action label: mute audio.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get shortcutsMute;

  /// Player action label: toggle fullscreen.
  ///
  /// In en, this message translates to:
  /// **'Fullscreen'**
  String get shortcutsFullscreen;

  /// AppBar title for the Home screen layout editor.
  ///
  /// In en, this message translates to:
  /// **'Home Layout'**
  String get homeLayoutTitle;

  /// Home row title: resume in-progress items.
  ///
  /// In en, this message translates to:
  /// **'Continue Watching'**
  String get homeLayoutContinueWatching;

  /// Home row title: the next episode to watch.
  ///
  /// In en, this message translates to:
  /// **'Next Up'**
  String get homeLayoutNextUp;

  /// Home row title: recently added items.
  ///
  /// In en, this message translates to:
  /// **'Recently Added'**
  String get homeLayoutRecentlyAdded;

  /// Home row title: the user's libraries.
  ///
  /// In en, this message translates to:
  /// **'My Media'**
  String get homeLayoutMyMedia;

  /// Toggle title for per-library latest rows.
  ///
  /// In en, this message translates to:
  /// **'Latest by Library'**
  String get homeLayoutLatestByLibrary;

  /// Subtitle for the Latest by Library toggle.
  ///
  /// In en, this message translates to:
  /// **'Show a \"Latest in…\" row for each movie & show library'**
  String get homeLayoutLatestByLibrarySubtitle;

  /// Toggle title for editorial genre rows.
  ///
  /// In en, this message translates to:
  /// **'Genre Rows'**
  String get homeLayoutGenreRows;

  /// Subtitle for the Genre Rows toggle.
  ///
  /// In en, this message translates to:
  /// **'Editorial rows by genre for browsing variety'**
  String get homeLayoutGenreRowsSubtitle;

  /// Centered overlay text shown while an on-demand video is starting up.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get playerLoading;

  /// Centered overlay text shown while a live TV channel is starting up.
  ///
  /// In en, this message translates to:
  /// **'Tuning in…'**
  String get playerTuningIn;

  /// Player control tooltip and track-picker sheet title for the subtitle/caption menu.
  ///
  /// In en, this message translates to:
  /// **'Subtitles'**
  String get playerSubtitles;

  /// Player control tooltip and track-picker sheet title for the audio track menu.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get playerAudio;

  /// Sheet title for the streaming quality picker.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get playerQuality;

  /// Player control tooltip for the quality button, showing the current quality rendition in parentheses.
  ///
  /// In en, this message translates to:
  /// **'Quality ({label})'**
  String playerQualityLabel(String label);

  /// Player control tooltip and sheet title for the chapter list.
  ///
  /// In en, this message translates to:
  /// **'Chapters'**
  String get playerChapters;

  /// Player control tooltip and sheet title for the playback speed picker.
  ///
  /// In en, this message translates to:
  /// **'Playback Speed'**
  String get playerPlaybackSpeed;

  /// Tooltip for the overflow (more options) menu button in the narrow player control bar.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get playerMore;

  /// Tooltip for the player's settings gear menu (chapters, speed, playback info).
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get playerSettings;

  /// Menu item / title for the playback details (stats) overlay.
  ///
  /// In en, this message translates to:
  /// **'Playback Info'**
  String get playerPlaybackInfo;

  /// Player control tooltip: toggle play/pause.
  ///
  /// In en, this message translates to:
  /// **'Play / Pause'**
  String get playerPlayPause;

  /// Player control tooltip: seek backward by N seconds.
  ///
  /// In en, this message translates to:
  /// **'Back {seconds}s'**
  String playerSeekBack(int seconds);

  /// Player control tooltip: seek forward by N seconds.
  ///
  /// In en, this message translates to:
  /// **'Forward {seconds}s'**
  String playerSeekForward(int seconds);

  /// Playback stats label: how the server delivers the stream (direct play vs transcode).
  ///
  /// In en, this message translates to:
  /// **'Play Method'**
  String get playerStatPlayMethod;

  /// Playback stats section heading for the video stream.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get playerStatVideo;

  /// Playback stats section heading for the audio stream.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get playerStatAudio;

  /// Playback stats section heading for container/buffer info.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get playerStatGeneral;

  /// Playback stats label: video pixel dimensions.
  ///
  /// In en, this message translates to:
  /// **'Resolution'**
  String get playerStatResolution;

  /// Playback stats label: the video or audio codec.
  ///
  /// In en, this message translates to:
  /// **'Codec'**
  String get playerStatCodec;

  /// Playback stats label: video frames per second.
  ///
  /// In en, this message translates to:
  /// **'Frame Rate'**
  String get playerStatFrameRate;

  /// Playback stats label: the stream bitrate.
  ///
  /// In en, this message translates to:
  /// **'Bitrate'**
  String get playerStatBitrate;

  /// Playback stats label: which decode path is active (hardware or software).
  ///
  /// In en, this message translates to:
  /// **'Decoder'**
  String get playerStatDecoder;

  /// Playback stats label: dropped frame counts (decoder / output).
  ///
  /// In en, this message translates to:
  /// **'Dropped Frames'**
  String get playerStatDroppedFrames;

  /// Playback stats label: audio channel count / layout.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get playerStatChannels;

  /// Playback stats label: audio sample rate.
  ///
  /// In en, this message translates to:
  /// **'Sample Rate'**
  String get playerStatSampleRate;

  /// Playback stats label: the media container/file format.
  ///
  /// In en, this message translates to:
  /// **'Container'**
  String get playerStatContainer;

  /// Playback stats label: seconds of demuxer buffer ahead.
  ///
  /// In en, this message translates to:
  /// **'Buffer'**
  String get playerStatBuffer;

  /// Playback stats label: audio/video sync offset in seconds.
  ///
  /// In en, this message translates to:
  /// **'A/V Sync'**
  String get playerStatAvSync;

  /// Playback stats value: hardware video decoding is active.
  ///
  /// In en, this message translates to:
  /// **'Hardware'**
  String get playerStatHardware;

  /// Playback stats value: software video decoding is active.
  ///
  /// In en, this message translates to:
  /// **'Software'**
  String get playerStatSoftware;

  /// Play method value: the file plays as-is with no server transcoding.
  ///
  /// In en, this message translates to:
  /// **'Direct Play'**
  String get playerPlayMethodDirect;

  /// Play method value: the server is transcoding the stream.
  ///
  /// In en, this message translates to:
  /// **'Transcoding'**
  String get playerPlayMethodTranscode;

  /// Play method value: playing a locally downloaded copy.
  ///
  /// In en, this message translates to:
  /// **'Direct Play (Downloaded)'**
  String get playerPlayMethodDownloaded;

  /// Play method value (YouTube): separate high-quality video and audio streams.
  ///
  /// In en, this message translates to:
  /// **'Adaptive (DASH)'**
  String get playerPlayMethodAdaptive;

  /// Play method value (YouTube): a single combined video+audio stream (fallback).
  ///
  /// In en, this message translates to:
  /// **'Muxed Stream'**
  String get playerPlayMethodMuxed;

  /// Tooltip for the volume mute button.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get playerMute;

  /// Tooltip for the volume button when audio is muted; tapping restores sound.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get playerUnmute;

  /// Tooltip for the volume button that opens a volume slider popover.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get playerVolume;

  /// Player control tooltip: minimize the video into the floating mini player (picture-in-picture).
  ///
  /// In en, this message translates to:
  /// **'Miniplayer'**
  String get playerMiniplayer;

  /// Player control tooltip: switch to theater mode (a wider in-page player with the side rail hidden).
  ///
  /// In en, this message translates to:
  /// **'Theater Mode'**
  String get playerTheaterMode;

  /// Player control tooltip: leave theater mode and return to the default view.
  ///
  /// In en, this message translates to:
  /// **'Default View'**
  String get playerDefaultView;

  /// Player control tooltip: enter fullscreen.
  ///
  /// In en, this message translates to:
  /// **'Fullscreen'**
  String get playerFullscreen;

  /// Player control tooltip: leave fullscreen.
  ///
  /// In en, this message translates to:
  /// **'Exit Fullscreen'**
  String get playerExitFullscreen;

  /// Badge on the live-edge button of the player seek bar; conventionally left untranslated but exposed for translators to decide.
  ///
  /// In en, this message translates to:
  /// **'LIVE'**
  String get playerBadgeLive;

  /// Badge shown while the live channel on screen is being recorded; conventionally left untranslated but exposed for translators to decide.
  ///
  /// In en, this message translates to:
  /// **'REC'**
  String get playerBadgeRec;

  /// Label for the automatic option in quality and audio/subtitle track pickers (bandwidth-aware or default choice).
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get playerAuto;

  /// Label for the 'no audio track' option in the audio track picker.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get playerNone;

  /// Label for the 1x (normal) option in the playback speed picker.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get playerSpeedNormal;

  /// Fallback label for an unnamed chapter marker on the seek bar.
  ///
  /// In en, this message translates to:
  /// **'Chapter'**
  String get playerChapter;

  /// Fallback title for an unnamed chapter in the chapter list, numbered by position.
  ///
  /// In en, this message translates to:
  /// **'Chapter {number}'**
  String playerChapterNumbered(int number);

  /// Fallback label for an audio track that has no title or language, identified by its track id.
  ///
  /// In en, this message translates to:
  /// **'Track {id}'**
  String playerTrackNumber(String id);

  /// Subtitle menu row that searches the server's subtitle providers.
  ///
  /// In en, this message translates to:
  /// **'Search Subtitles Online'**
  String get playerSubtitleSearch;

  /// Title of the online subtitle results sheet, naming the language searched.
  ///
  /// In en, this message translates to:
  /// **'Online Subtitles: {language}'**
  String playerSubtitleSearchIn(String language);

  /// Row in the online subtitle results that searches a different language.
  ///
  /// In en, this message translates to:
  /// **'Change Language'**
  String get playerSubtitleSearchLanguage;

  /// Shown when the server's providers return nothing for a language.
  ///
  /// In en, this message translates to:
  /// **'No {language} subtitles found for this title'**
  String playerSubtitleSearchEmptyIn(String language);

  /// Title of the sheet listing subtitles found online.
  ///
  /// In en, this message translates to:
  /// **'Online Subtitles'**
  String get playerSubtitleSearchTitle;

  /// Tag on a search result whose timing matches this exact release.
  ///
  /// In en, this message translates to:
  /// **'Matches your file'**
  String get playerSubtitleHashMatch;

  /// How many times a subtitle has been downloaded from the provider.
  ///
  /// In en, this message translates to:
  /// **'{count} downloads'**
  String playerSubtitleDownloads(int count);

  /// Progress message while the server fetches a subtitle.
  ///
  /// In en, this message translates to:
  /// **'Downloading subtitle'**
  String get playerSubtitleDownloading;

  /// Confirmation after the server saved a downloaded subtitle.
  ///
  /// In en, this message translates to:
  /// **'Subtitle added'**
  String get playerSubtitleDownloaded;

  /// Tag on a subtitle track that only captions foreign-language dialogue.
  ///
  /// In en, this message translates to:
  /// **'Forced'**
  String get playerSubtitleForced;

  /// Tag on a subtitle track made of images rather than text (Blu-ray PGS, DVD VobSub).
  ///
  /// In en, this message translates to:
  /// **'Picture'**
  String get playerSubtitlePicture;

  /// Tag on a subtitle track stored in its own file beside the video, rather than inside it. Matches the wording Jellyfin itself uses.
  ///
  /// In en, this message translates to:
  /// **'External'**
  String get playerSubtitleFile;

  /// Fallback label for a subtitle track that has no title or language, identified by its track id.
  ///
  /// In en, this message translates to:
  /// **'Subtitle {id}'**
  String playerSubtitleNumber(String id);

  /// Error overlay message when the player reports a playback error.
  ///
  /// In en, this message translates to:
  /// **'Playback error: {error}'**
  String playerPlaybackError(String error);

  /// Error overlay message when opening or playing the item failed.
  ///
  /// In en, this message translates to:
  /// **'Playback failed: {error}'**
  String playerPlaybackFailed(String error);

  /// Error overlay message when switching streaming quality mid-playback failed.
  ///
  /// In en, this message translates to:
  /// **'Could not change quality: {error}'**
  String playerQualityChangeFailed(String error);

  /// Error overlay message when an on-demand video has not started after a timeout.
  ///
  /// In en, this message translates to:
  /// **'This video is taking too long to start.'**
  String get playerVideoSlowStart;

  /// Error overlay message when a live TV channel has not started after a timeout.
  ///
  /// In en, this message translates to:
  /// **'This channel is taking too long to start. The tuner may be busy, or the server needs to transcode this stream.'**
  String get playerChannelSlowStart;

  /// Error overlay message when a video could not be played even after a transcode retry.
  ///
  /// In en, this message translates to:
  /// **'This video could not be played.'**
  String get playerVideoUnplayable;

  /// Button label to skip the intro segment of an episode.
  ///
  /// In en, this message translates to:
  /// **'Skip Intro'**
  String get playerSkipIntro;

  /// Button label to skip a 'Previously on...' recap segment.
  ///
  /// In en, this message translates to:
  /// **'Skip Recap'**
  String get playerSkipRecap;

  /// Button label to skip the closing credits segment.
  ///
  /// In en, this message translates to:
  /// **'Skip Credits'**
  String get playerSkipCredits;

  /// Error message shown when a YouTube video's streams could not be resolved.
  ///
  /// In en, this message translates to:
  /// **'Could not load this video.'**
  String get playerYoutubeLoadFailed;

  /// Snackbar after auto-skipping a SponsorBlock segment; category is the segment type (e.g. sponsor), seconds is its length.
  ///
  /// In en, this message translates to:
  /// **'Skipped {category} ({seconds}s)'**
  String playerSkippedSegment(String category, int seconds);

  /// Tooltip on a seek-bar marker for a skippable SponsorBlock segment; category is the segment type.
  ///
  /// In en, this message translates to:
  /// **'Skip: {category}'**
  String playerSkipSegment(String category);

  /// Snackbar action to jump back to the start of a segment that was auto-skipped.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get playerUndo;

  /// Default title for a trailer player when no title is provided.
  ///
  /// In en, this message translates to:
  /// **'Trailer'**
  String get playerTrailer;

  /// Title for a trailer player, appending a Trailer suffix to the item title.
  ///
  /// In en, this message translates to:
  /// **'{title} — Trailer'**
  String playerTitleTrailer(String title);

  /// Button to open a YouTube video in an external browser when it cannot be played in-app.
  ///
  /// In en, this message translates to:
  /// **'Open in Browser'**
  String get playerOpenInBrowser;

  /// Empty state on the now-playing screen when no audio track is loaded.
  ///
  /// In en, this message translates to:
  /// **'Nothing playing.'**
  String get playerNothingPlaying;

  /// App bar title of the full-screen now-playing (music) screen.
  ///
  /// In en, this message translates to:
  /// **'Now Playing'**
  String get playerNowPlaying;

  /// Tooltip for the button that opens the playback queue sheet.
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get playerQueue;

  /// Heading for the up-next queue sheet and the compact up-next pill.
  ///
  /// In en, this message translates to:
  /// **'Up Next'**
  String get playerUpNext;

  /// Tooltip for the favorite (heart) toggle when the current track is not a favorite.
  ///
  /// In en, this message translates to:
  /// **'Add Favorite'**
  String get playerAddFavorite;

  /// Tooltip for the favorite (heart) toggle when the current track is a favorite.
  ///
  /// In en, this message translates to:
  /// **'Remove Favorite'**
  String get playerRemoveFavorite;

  /// Tooltip to flip the now-playing view from lyrics back to album artwork.
  ///
  /// In en, this message translates to:
  /// **'Show Artwork'**
  String get playerShowArtwork;

  /// Tooltip to flip the now-playing view from album artwork to lyrics.
  ///
  /// In en, this message translates to:
  /// **'Show Lyrics'**
  String get playerShowLyrics;

  /// Record button/dialog title and confirm action for scheduling a Live TV recording.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get playerRecord;

  /// Snackbar confirming a single-program recording was set from the live record button.
  ///
  /// In en, this message translates to:
  /// **'Recording this program'**
  String get playerRecordingProgram;

  /// Snackbar confirming a whole-series recording was set from the live record button.
  ///
  /// In en, this message translates to:
  /// **'Recording every episode'**
  String get playerRecordingEveryEpisode;

  /// Title of the dialog asking whether to stop an active recording.
  ///
  /// In en, this message translates to:
  /// **'Stop Recording?'**
  String get playerStopRecordingTitle;

  /// Body of the stop-recording dialog explaining the current recording state.
  ///
  /// In en, this message translates to:
  /// **'This program and the rest of the series are set to record.'**
  String get playerStopRecordingBody;

  /// Dialog action to dismiss without stopping the recording.
  ///
  /// In en, this message translates to:
  /// **'Keep Recording'**
  String get playerKeepRecording;

  /// Dialog action to cancel the recording for just the current program.
  ///
  /// In en, this message translates to:
  /// **'Stop This Program'**
  String get playerStopThisProgram;

  /// Dialog action to cancel the recording for the whole series.
  ///
  /// In en, this message translates to:
  /// **'Stop Series'**
  String get playerStopSeries;

  /// Tooltip on the live record button when the current program is recording; tapping records the whole series.
  ///
  /// In en, this message translates to:
  /// **'Recording · tap to record the series'**
  String get playerRecordingTapSeries;

  /// Tooltip on the live record button when the series is recording; tapping stops it.
  ///
  /// In en, this message translates to:
  /// **'Recording the series · tap to stop'**
  String get playerRecordingSeriesTapStop;

  /// Dialog action to schedule a whole-series recording.
  ///
  /// In en, this message translates to:
  /// **'Record Series'**
  String get playerRecordSeries;

  /// Snackbar confirming a single-program recording was scheduled from the record dialog.
  ///
  /// In en, this message translates to:
  /// **'Recording set'**
  String get playerRecordingSet;

  /// Snackbar confirming a whole-series recording was scheduled from the record dialog.
  ///
  /// In en, this message translates to:
  /// **'Series recording set'**
  String get playerSeriesRecordingSet;

  /// Section label in the record dialog for the pre/post recording padding fields.
  ///
  /// In en, this message translates to:
  /// **'Padding'**
  String get playerPadding;

  /// Label for the field setting how many minutes early a recording starts.
  ///
  /// In en, this message translates to:
  /// **'Start Before'**
  String get playerStartBefore;

  /// Label for the field setting how many minutes late a recording stops.
  ///
  /// In en, this message translates to:
  /// **'Stop After'**
  String get playerStopAfter;

  /// Suffix (abbreviation for minutes) shown inside the recording padding input fields.
  ///
  /// In en, this message translates to:
  /// **'min'**
  String get playerMinutesSuffix;

  /// Tooltip for the button that pops the mini video out into a separate always-on-top desktop window.
  ///
  /// In en, this message translates to:
  /// **'Pop Out to Desktop'**
  String get playerPopOut;

  /// Tooltip for the button that returns the popped-out desktop video back into the app window.
  ///
  /// In en, this message translates to:
  /// **'Back to App'**
  String get playerBackToApp;

  /// Item menu action: drop the item from the Continue Watching row by clearing its resume position.
  ///
  /// In en, this message translates to:
  /// **'Remove from Continue Watching'**
  String get actionRemoveFromContinueWatching;

  /// Context-menu row: open the item's detail page.
  ///
  /// In en, this message translates to:
  /// **'Show Details'**
  String get actionShowDetails;

  /// Context-menu row: delete a whole series (all episodes).
  ///
  /// In en, this message translates to:
  /// **'Delete Series'**
  String get actionDeleteSeries;

  /// Context-menu row: delete a whole season.
  ///
  /// In en, this message translates to:
  /// **'Delete Season'**
  String get actionDeleteSeason;

  /// Context-menu row: delete a single episode.
  ///
  /// In en, this message translates to:
  /// **'Delete Episode'**
  String get actionDeleteEpisode;

  /// Context-menu row: delete a movie.
  ///
  /// In en, this message translates to:
  /// **'Delete Movie'**
  String get actionDeleteMovie;

  /// Play button label/tooltip when a title can resume from a saved position.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get detailResume;

  /// Button/tooltip: start playback from the beginning instead of resuming.
  ///
  /// In en, this message translates to:
  /// **'Play from Start'**
  String get detailPlayFromStart;

  /// Tooltip: mark this item as watched.
  ///
  /// In en, this message translates to:
  /// **'Mark Watched'**
  String get detailMarkWatched;

  /// Tooltip: mark this item as not watched.
  ///
  /// In en, this message translates to:
  /// **'Mark Unwatched'**
  String get detailMarkUnwatched;

  /// Tooltip: add this item to favorites.
  ///
  /// In en, this message translates to:
  /// **'Add to Favorites'**
  String get detailAddFavorite;

  /// Tooltip: remove this item from favorites.
  ///
  /// In en, this message translates to:
  /// **'Remove from Favorites'**
  String get detailRemoveFavorite;

  /// Tooltip/menu row: add this item to the Watchlist.
  ///
  /// In en, this message translates to:
  /// **'Add to Watchlist'**
  String get detailAddToWatchlist;

  /// Tooltip/menu row: remove this item from the Watchlist.
  ///
  /// In en, this message translates to:
  /// **'Remove from Watchlist'**
  String get detailRemoveFromWatchlist;

  /// Media type label for a TV series.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get detailSeries;

  /// Media type label for a movie.
  ///
  /// In en, this message translates to:
  /// **'Movie'**
  String get detailMovie;

  /// Name of the season 0 / specials group in an episode list.
  ///
  /// In en, this message translates to:
  /// **'Specials'**
  String get detailSpecials;

  /// Label for a numbered season in the season picker.
  ///
  /// In en, this message translates to:
  /// **'Season {number}'**
  String detailSeasonNumber(int number);

  /// Heading over the episode list.
  ///
  /// In en, this message translates to:
  /// **'Episodes'**
  String get detailEpisodes;

  /// Compact runtime in minutes, e.g. 42m.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m'**
  String detailRuntimeMinutes(int minutes);

  /// Button/tooltip to download an item for offline viewing.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get detailDownload;

  /// Row in the series download picker that downloads every episode.
  ///
  /// In en, this message translates to:
  /// **'Download All'**
  String get downloadAll;

  /// TV Shows section header in the downloaded library.
  ///
  /// In en, this message translates to:
  /// **'TV Shows'**
  String get downloadsTvShows;

  /// Header above a downloaded music album's track list.
  ///
  /// In en, this message translates to:
  /// **'Tracks'**
  String get downloadsTracks;

  /// Episode count under a downloaded show's poster.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 episode} other{{count} episodes}}'**
  String downloadEpisodeCount(int count);

  /// App bar action on the Downloads screen that cancels or removes every download.
  ///
  /// In en, this message translates to:
  /// **'Cancel All'**
  String get downloadsCancelAll;

  /// Confirmation body when cancelling every in-progress download at once.
  ///
  /// In en, this message translates to:
  /// **'Cancel all downloads in progress?'**
  String get downloadsCancelAllConfirm;

  /// Button to cancel an in-progress download (vs Remove for a finished one).
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get downloadCancel;

  /// Button label while a download is in progress.
  ///
  /// In en, this message translates to:
  /// **'Downloading'**
  String get detailDownloading;

  /// Tooltip while a download is in progress.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get detailDownloadingTooltip;

  /// Button label when an item is downloaded.
  ///
  /// In en, this message translates to:
  /// **'Downloaded'**
  String get detailDownloaded;

  /// Tooltip on a downloaded item: tap to remove the offline copy.
  ///
  /// In en, this message translates to:
  /// **'Downloaded — tap to remove'**
  String get detailDownloadedTooltip;

  /// Tooltip when a download failed; tapping retries.
  ///
  /// In en, this message translates to:
  /// **'Download failed — retry'**
  String get detailDownloadFailedTooltip;

  /// Title of the confirm dialog for removing an offline copy.
  ///
  /// In en, this message translates to:
  /// **'Remove Download'**
  String get detailRemoveDownload;

  /// Confirm-dialog body for removing an offline download.
  ///
  /// In en, this message translates to:
  /// **'Remove the offline copy of \"{title}\"?'**
  String detailRemoveOfflineCopy(String title);

  /// Button label to cast/play the item on another device.
  ///
  /// In en, this message translates to:
  /// **'Play On'**
  String get detailCastAction;

  /// Tooltip for the cast-to-another-device action.
  ///
  /// In en, this message translates to:
  /// **'Play on Another Device'**
  String get detailPlayOnAnotherDevice;

  /// Title of the device-picker bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'Play on Another Device'**
  String get detailPlayOnAnotherDeviceTitle;

  /// Snackbar when no remote-controllable playback devices are available.
  ///
  /// In en, this message translates to:
  /// **'No controllable devices found'**
  String get detailNoControllableDevices;

  /// Fallback name for a playback device with no reported name.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get detailDevice;

  /// Snackbar after starting playback on a remote device.
  ///
  /// In en, this message translates to:
  /// **'Playing on {device}'**
  String detailPlayingOn(String device);

  /// Menu action to add the item to a playlist.
  ///
  /// In en, this message translates to:
  /// **'Add to Playlist'**
  String get detailAddToPlaylist;

  /// Menu action to refresh an item's metadata on the server.
  ///
  /// In en, this message translates to:
  /// **'Refresh Metadata'**
  String get detailRefreshMetadata;

  /// Snackbar confirming a metadata refresh was started.
  ///
  /// In en, this message translates to:
  /// **'Metadata refresh started'**
  String get detailMetadataRefreshStarted;

  /// Title of the confirm dialog for deleting an item from the server.
  ///
  /// In en, this message translates to:
  /// **'Delete Item'**
  String get detailDeleteItem;

  /// Confirm-dialog body for permanently deleting an item.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete \"{title}\" from the server? This cannot be undone.'**
  String detailDeleteConfirm(String title);

  /// Snackbar confirming an item was deleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted \"{title}\"'**
  String detailDeleted(String title);

  /// Section heading for the cast and crew list.
  ///
  /// In en, this message translates to:
  /// **'Cast & Crew'**
  String get detailCastCrew;

  /// Section heading for the next-up episode of a series.
  ///
  /// In en, this message translates to:
  /// **'Next Up'**
  String get detailNextUp;

  /// Play button label resuming a specific episode, e.g. Resume S1:E2.
  ///
  /// In en, this message translates to:
  /// **'Resume {code}'**
  String detailResumeCode(String code);

  /// Play button label for a specific episode, e.g. Play S1:E2.
  ///
  /// In en, this message translates to:
  /// **'Play {code}'**
  String detailPlayCode(String code);

  /// Play button label showing the saved resume timecode.
  ///
  /// In en, this message translates to:
  /// **'Resume from {time}'**
  String detailResumeFrom(String time);

  /// Tooltip for the trailer button.
  ///
  /// In en, this message translates to:
  /// **'Watch Trailer'**
  String get detailWatchTrailer;

  /// Button label for the trailer action.
  ///
  /// In en, this message translates to:
  /// **'Trailer'**
  String get detailTrailer;

  /// Detail page section: a title's bonus material.
  ///
  /// In en, this message translates to:
  /// **'Extras'**
  String get detailExtras;

  /// Extra kind label.
  ///
  /// In en, this message translates to:
  /// **'Trailer'**
  String get extraTypeTrailer;

  /// Extra kind label.
  ///
  /// In en, this message translates to:
  /// **'Behind the Scenes'**
  String get extraTypeBehindTheScenes;

  /// Extra kind label.
  ///
  /// In en, this message translates to:
  /// **'Deleted Scene'**
  String get extraTypeDeletedScene;

  /// Extra kind label.
  ///
  /// In en, this message translates to:
  /// **'Interview'**
  String get extraTypeInterview;

  /// Extra kind label.
  ///
  /// In en, this message translates to:
  /// **'Scene'**
  String get extraTypeScene;

  /// Extra kind label.
  ///
  /// In en, this message translates to:
  /// **'Featurette'**
  String get extraTypeFeaturette;

  /// Extra kind label.
  ///
  /// In en, this message translates to:
  /// **'Short'**
  String get extraTypeShort;

  /// Extra kind label.
  ///
  /// In en, this message translates to:
  /// **'Clip'**
  String get extraTypeClip;

  /// Extra kind label.
  ///
  /// In en, this message translates to:
  /// **'Sample'**
  String get extraTypeSample;

  /// Section heading for a row of similar titles.
  ///
  /// In en, this message translates to:
  /// **'More Like This'**
  String get detailMoreLikeThis;

  /// Button/tooltip to watch a title that is available on the server.
  ///
  /// In en, this message translates to:
  /// **'Watch'**
  String get detailWatch;

  /// Button/tooltip to open the request-management panel.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get detailManage;

  /// Button to view the full cast and crew.
  ///
  /// In en, this message translates to:
  /// **'View All'**
  String get detailViewAll;

  /// Section heading for a series' season list.
  ///
  /// In en, this message translates to:
  /// **'Seasons'**
  String get detailSeasons;

  /// Fallback name for a movie collection.
  ///
  /// In en, this message translates to:
  /// **'Collection'**
  String get detailCollection;

  /// Section heading for recommended titles.
  ///
  /// In en, this message translates to:
  /// **'Recommendations'**
  String get detailRecommendations;

  /// Section heading for similar titles.
  ///
  /// In en, this message translates to:
  /// **'Similar'**
  String get detailSimilar;

  /// Status label: the title is available on the server.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get detailStatusAvailable;

  /// Status label: some of the title is available.
  ///
  /// In en, this message translates to:
  /// **'Partially Available'**
  String get detailStatusPartiallyAvailable;

  /// Status label: the request is being processed.
  ///
  /// In en, this message translates to:
  /// **'Processing'**
  String get detailStatusProcessing;

  /// Status label: the request is pending approval.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get detailStatusPending;

  /// Status label: the title has not been requested.
  ///
  /// In en, this message translates to:
  /// **'Not Requested'**
  String get detailStatusNotRequested;

  /// Button label to request a title via Jellyseerr.
  ///
  /// In en, this message translates to:
  /// **'Request'**
  String get detailRequest;

  /// Button/status label: the title has already been requested.
  ///
  /// In en, this message translates to:
  /// **'Requested'**
  String get detailRequested;

  /// Manager control to view/act on a pending request.
  ///
  /// In en, this message translates to:
  /// **'View Request'**
  String get detailViewRequest;

  /// Action to approve a request.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get detailApprove;

  /// Action to decline a request.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get detailDecline;

  /// Action to request further seasons of a series.
  ///
  /// In en, this message translates to:
  /// **'Request More'**
  String get detailRequestMore;

  /// Snackbar after approving a request.
  ///
  /// In en, this message translates to:
  /// **'Approved {title}'**
  String detailApprovedTitle(String title);

  /// Snackbar after declining a request.
  ///
  /// In en, this message translates to:
  /// **'Declined {title}'**
  String detailDeclinedTitle(String title);

  /// Episode count for a season.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} episode} other{{count} episodes}}'**
  String detailEpisodeCount(int count);

  /// Banner linking to the movie's collection/franchise.
  ///
  /// In en, this message translates to:
  /// **'Part of the {name}'**
  String detailPartOfCollection(String name);

  /// Download estimate that has passed, e.g. Estimated 5 min ago.
  ///
  /// In en, this message translates to:
  /// **'Estimated {time} ago'**
  String detailEstimatedAgo(String time);

  /// Estimated time until a download finishes, e.g. Estimated in 5 min.
  ///
  /// In en, this message translates to:
  /// **'Estimated in {time}'**
  String detailEstimatedIn(String time);

  /// Snackbar confirming a scheduled recording was canceled.
  ///
  /// In en, this message translates to:
  /// **'Recording canceled'**
  String get detailRecordingCanceled;

  /// Button to watch a program that is airing now.
  ///
  /// In en, this message translates to:
  /// **'Watch Now'**
  String get detailWatchNow;

  /// Button to watch the live channel for a program.
  ///
  /// In en, this message translates to:
  /// **'Watch Channel'**
  String get detailWatchChannel;

  /// Button to cancel a scheduled recording.
  ///
  /// In en, this message translates to:
  /// **'Cancel Recording'**
  String get detailCancelRecording;

  /// Button to schedule a recording of a program.
  ///
  /// In en, this message translates to:
  /// **'Record…'**
  String get detailRecord;

  /// Heading for the list of a person's film/TV appearances.
  ///
  /// In en, this message translates to:
  /// **'Appearances'**
  String get detailAppearances;

  /// Filter option: show all appearances (movies and series).
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get detailAll;

  /// Filter option: show only movies.
  ///
  /// In en, this message translates to:
  /// **'Movies'**
  String get detailMovies;

  /// Empty state when a person has no appearances.
  ///
  /// In en, this message translates to:
  /// **'No appearances to show.'**
  String get detailNoAppearances;

  /// A person's alternative names.
  ///
  /// In en, this message translates to:
  /// **'Also known as: {names}'**
  String detailAlsoKnownAs(String names);

  /// Toggle to expand a truncated biography.
  ///
  /// In en, this message translates to:
  /// **'Read More'**
  String get detailReadMore;

  /// Toggle to collapse an expanded biography.
  ///
  /// In en, this message translates to:
  /// **'Read Less'**
  String get detailReadLess;

  /// A person's birth date (place of birth, when known, is appended separately).
  ///
  /// In en, this message translates to:
  /// **'Born {date}'**
  String detailBorn(String date);

  /// Empty state for a season with no episodes.
  ///
  /// In en, this message translates to:
  /// **'No episodes to show.'**
  String get detailNoEpisodes;

  /// Heading for the cast list on the full-credits page.
  ///
  /// In en, this message translates to:
  /// **'Cast'**
  String get detailCast;

  /// Heading for the crew list on the full-credits page.
  ///
  /// In en, this message translates to:
  /// **'Crew'**
  String get detailCrew;

  /// Empty state when a person's filmography has no titles.
  ///
  /// In en, this message translates to:
  /// **'No titles found'**
  String get detailNoTitlesFound;

  /// Header of the request dialog for a TV series.
  ///
  /// In en, this message translates to:
  /// **'Request Series'**
  String get detailRequestSeries;

  /// Header of the request dialog for a movie.
  ///
  /// In en, this message translates to:
  /// **'Request Movie'**
  String get detailRequestMovie;

  /// Notice that the request will be auto-approved.
  ///
  /// In en, this message translates to:
  /// **'This request will be approved automatically.'**
  String get detailAutoApprove;

  /// Toggle to request the 4K version of a title.
  ///
  /// In en, this message translates to:
  /// **'Request in 4K'**
  String get detailRequestIn4k;

  /// Subtitle explaining the Request in 4K toggle.
  ///
  /// In en, this message translates to:
  /// **'use the 4K server and its defaults'**
  String get detailRequest4kSubtitle;

  /// Heading for the advanced request options.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get detailAdvanced;

  /// Label for the destination server dropdown.
  ///
  /// In en, this message translates to:
  /// **'Destination Server'**
  String get detailDestinationServer;

  /// Label for the quality profile dropdown.
  ///
  /// In en, this message translates to:
  /// **'Quality Profile'**
  String get detailQualityProfile;

  /// Dropdown entry marking a profile as the server default.
  ///
  /// In en, this message translates to:
  /// **'{name} (Default)'**
  String detailProfileDefault(String name);

  /// Label for the root folder dropdown.
  ///
  /// In en, this message translates to:
  /// **'Root Folder'**
  String get detailRootFolder;

  /// Label for the language profile dropdown.
  ///
  /// In en, this message translates to:
  /// **'Language Profile'**
  String get detailLanguageProfile;

  /// Label for the tags selector.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get detailTags;

  /// Label for the dropdown choosing which user to request as.
  ///
  /// In en, this message translates to:
  /// **'Request As'**
  String get detailRequestAs;

  /// Note shown when no per-season choice is available.
  ///
  /// In en, this message translates to:
  /// **'All seasons will be requested.'**
  String get detailAllSeasonsRequested;

  /// Season table column header (uppercase).
  ///
  /// In en, this message translates to:
  /// **'SEASON'**
  String get detailColSeason;

  /// Season table column header for episode count (uppercase).
  ///
  /// In en, this message translates to:
  /// **'# OF EPISODES'**
  String get detailColEpisodes;

  /// Season table column header for status (uppercase).
  ///
  /// In en, this message translates to:
  /// **'STATUS'**
  String get detailColStatus;

  /// Snackbar after submitting a request.
  ///
  /// In en, this message translates to:
  /// **'Requested {title}.'**
  String detailRequestedTitle(String title);

  /// Disabled submit-button label prompting the user to pick seasons.
  ///
  /// In en, this message translates to:
  /// **'Select Season(s)'**
  String get detailSelectSeasons;

  /// Accessibility label for dismissing the Manage panel barrier.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get detailDismiss;

  /// Title of the Manage panel, e.g. Manage Movie / Manage Series.
  ///
  /// In en, this message translates to:
  /// **'Manage {kind}'**
  String detailManageKind(String kind);

  /// Heading for the list of requests in the Manage panel.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get detailRequests;

  /// Snackbar after retrying a failed request.
  ///
  /// In en, this message translates to:
  /// **'Retrying {title}'**
  String detailRetryingTitle(String title);

  /// Snackbar after deleting a request.
  ///
  /// In en, this message translates to:
  /// **'Deleted request for {title}'**
  String detailDeletedRequestTitle(String title);

  /// Title of the confirm dialog for deleting a request.
  ///
  /// In en, this message translates to:
  /// **'Delete Request'**
  String get detailDeleteRequest;

  /// Confirm-dialog body for removing a request.
  ///
  /// In en, this message translates to:
  /// **'Remove this request?'**
  String get detailRemoveRequestConfirm;

  /// Advanced action to mark a title as available.
  ///
  /// In en, this message translates to:
  /// **'Mark as Available'**
  String get detailMarkAvailable;

  /// Snackbar after marking a title available.
  ///
  /// In en, this message translates to:
  /// **'Marked {title} as available'**
  String detailMarkedAvailableTitle(String title);

  /// Advanced action / dialog title to clear all Jellyseerr data for a title.
  ///
  /// In en, this message translates to:
  /// **'Clear Data'**
  String get detailClearData;

  /// Confirm-dialog body for clearing a title's data.
  ///
  /// In en, this message translates to:
  /// **'This will irreversibly remove all data for this {kind}, including any requests.'**
  String detailClearDataConfirm(String kind);

  /// Snackbar after clearing a title's data.
  ///
  /// In en, this message translates to:
  /// **'Cleared data for {title}'**
  String detailClearedDataTitle(String title);

  /// Footnote under the Clear Data action explaining its effect.
  ///
  /// In en, this message translates to:
  /// **'* This will irreversibly remove all data for this {kind}, including any requests. If this item exists in your Jellyfin library, the media information will be recreated during the next scan.'**
  String detailClearDataNote(String kind);

  /// Lowercase media type 'movie', for use inside a sentence.
  ///
  /// In en, this message translates to:
  /// **'movie'**
  String get detailKindMovieLower;

  /// Lowercase media type 'series', for use inside a sentence.
  ///
  /// In en, this message translates to:
  /// **'series'**
  String get detailKindSeriesLower;

  /// Request status: declined.
  ///
  /// In en, this message translates to:
  /// **'Declined'**
  String get detailStatusDeclined;

  /// Request status: failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get detailStatusFailed;

  /// Request status: approved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get detailStatusApproved;

  /// Fallback requester name when the requester is unknown.
  ///
  /// In en, this message translates to:
  /// **'Someone'**
  String get detailSomeone;

  /// Tooltip on the delete-request button.
  ///
  /// In en, this message translates to:
  /// **'Delete Request'**
  String get detailDeleteRequestTooltip;

  /// Label listing the requested season numbers, e.g. Season 1, 2.
  ///
  /// In en, this message translates to:
  /// **'Season {seasons}'**
  String detailSeasonList(String seasons);

  /// Header of the edit-request dialog.
  ///
  /// In en, this message translates to:
  /// **'Edit Request'**
  String get detailEditRequest;

  /// Line under the edit dialog header noting whose request is pending.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s request is pending approval.'**
  String detailRequestPending(String name);

  /// Shown when a request has no editable advanced options.
  ///
  /// In en, this message translates to:
  /// **'No editable options are available for this request.'**
  String get detailNoEditableOptions;

  /// Placeholder for the multi-select tags field.
  ///
  /// In en, this message translates to:
  /// **'Select Tags'**
  String get detailSelectTags;

  /// Title of the dialog to add a custom Discover slider.
  ///
  /// In en, this message translates to:
  /// **'Add Slider'**
  String get detailAddSlider;

  /// Label for the slider title text field.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get detailTitle;

  /// Hint for the optional slider title field.
  ///
  /// In en, this message translates to:
  /// **'optional, defaults to the genre or keyword'**
  String get detailSliderTitleHint;

  /// Label for the slider type selector.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get detailType;

  /// Slider type option: a movie genre.
  ///
  /// In en, this message translates to:
  /// **'Movie Genre'**
  String get detailMovieGenre;

  /// Slider type option: a TV genre.
  ///
  /// In en, this message translates to:
  /// **'TV Genre'**
  String get detailTvGenre;

  /// Slider type option / field label: a keyword search.
  ///
  /// In en, this message translates to:
  /// **'Keyword'**
  String get detailKeyword;

  /// Example hint for the keyword field.
  ///
  /// In en, this message translates to:
  /// **'e.g. Christmas, zombie, heist'**
  String get detailKeywordHint;

  /// Label for the genre dropdown; also the fallback slider title.
  ///
  /// In en, this message translates to:
  /// **'Genre'**
  String get detailGenre;

  /// Title of the Libraries hub screen.
  ///
  /// In en, this message translates to:
  /// **'Libraries'**
  String get browseLibraries;

  /// Genres screen title and browse-bar link.
  ///
  /// In en, this message translates to:
  /// **'Genres'**
  String get browseGenres;

  /// Studios screen title, browse-bar link, and Discover row title.
  ///
  /// In en, this message translates to:
  /// **'Studios'**
  String get browseStudios;

  /// Artists screen title and browse-bar link.
  ///
  /// In en, this message translates to:
  /// **'Artists'**
  String get browseArtists;

  /// Favorites screen title, browse-bar link, and library filter chip.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get browseFavorites;

  /// How many items are selected in a grid.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 selected} other{{count} selected}}'**
  String selectionCount(int count);

  /// Selects every item currently shown in the grid.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get selectionSelectAll;

  /// Result message after marking a selection watched.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Marked 1 as watched} other{Marked {count} as watched}}'**
  String selectionMarkedWatched(int count);

  /// Result message after marking a selection unwatched.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Marked 1 as unwatched} other{Marked {count} as unwatched}}'**
  String selectionMarkedUnwatched(int count);

  /// Result message after favoriting a selection.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Added 1 to favorites} other{Added {count} to favorites}}'**
  String selectionFavorited(int count);

  /// Result message after unfavoriting a selection.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Removed 1 from favorites} other{Removed {count} from favorites}}'**
  String selectionUnfavorited(int count);

  /// Confirmation title for deleting a selection.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Delete 1 item?} other{Delete {count} items?}}'**
  String selectionDeleteTitle(int count);

  /// Confirmation body for deleting a selection.
  ///
  /// In en, this message translates to:
  /// **'This removes the files from your server. It cannot be undone.'**
  String get selectionDeleteBody;

  /// Result message after deleting a selection.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Deleted 1 item} other{Deleted {count} items}}'**
  String selectionDeleted(int count);

  /// Item menu action: start selecting several items in the grid.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get actionSelect;

  /// Watchlist screen title and nav destination label.
  ///
  /// In en, this message translates to:
  /// **'Watchlist'**
  String get browseWatchlist;

  /// Browse-bar link to playlists.
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get browsePlaylists;

  /// Browse-bar link to downloads.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get browseDownloads;

  /// Seerr Discover tab label.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get browseDiscover;

  /// Seerr Requests tab label.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get browseRequests;

  /// Home row title: items in progress.
  ///
  /// In en, this message translates to:
  /// **'Continue Watching'**
  String get browseContinueWatching;

  /// Android Auto top-level tab: a quick-start mix of shortcuts.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get autoHome;

  /// Android Auto top-level tab: the full Jellyfin music library.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get autoLibrary;

  /// Android Auto Home action: play a random shuffle of the whole music library.
  ///
  /// In en, this message translates to:
  /// **'Shuffle All'**
  String get autoShuffleAll;

  /// Android Auto Home action: shuffle-play favorite songs.
  ///
  /// In en, this message translates to:
  /// **'Favorites Mix'**
  String get autoFavoritesMix;

  /// Android Auto browse shortcut: songs played recently.
  ///
  /// In en, this message translates to:
  /// **'Recently Played'**
  String get autoRecentlyPlayed;

  /// Android Auto browse shortcut: newest albums.
  ///
  /// In en, this message translates to:
  /// **'Recently Added'**
  String get autoRecentlyAdded;

  /// Android Auto browse category: music genres.
  ///
  /// In en, this message translates to:
  /// **'Genres'**
  String get autoGenres;

  /// Android Auto browse category: internet-radio favorite stations.
  ///
  /// In en, this message translates to:
  /// **'Radio'**
  String get autoRadio;

  /// Android Auto radio sub-folder: favorite stations.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get autoRadioFavorites;

  /// Android Auto radio sub-folder: stations not in any group.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get autoRadioOther;

  /// Android Auto browse category: the user's music playlists.
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get autoPlaylists;

  /// Android Auto browse category: recently added music albums.
  ///
  /// In en, this message translates to:
  /// **'Albums'**
  String get autoAlbums;

  /// Android Auto browse category: music artists.
  ///
  /// In en, this message translates to:
  /// **'Artists'**
  String get autoArtists;

  /// Android Auto browse category: songs the user has favorited.
  ///
  /// In en, this message translates to:
  /// **'Favorite Songs'**
  String get autoFavoriteSongs;

  /// Android Auto browse category: YouTube audio.
  ///
  /// In en, this message translates to:
  /// **'YouTube'**
  String get autoYoutube;

  /// Android Auto browse subcategory: newest uploads from followed YouTube channels.
  ///
  /// In en, this message translates to:
  /// **'What\'s New'**
  String get autoYoutubeWhatsNew;

  /// Android Auto browse subcategory: the user's saved YouTube playlists.
  ///
  /// In en, this message translates to:
  /// **'Your Playlists'**
  String get autoYoutubePlaylists;

  /// Android Auto browse subcategory: channels the user follows on YouTube.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions'**
  String get autoYoutubeSubscriptions;

  /// Home row title: the next episode to watch.
  ///
  /// In en, this message translates to:
  /// **'Next Up'**
  String get browseNextUp;

  /// Home / Discover row title: recently added media.
  ///
  /// In en, this message translates to:
  /// **'Recently Added'**
  String get browseRecentlyAdded;

  /// Home row title: the user's libraries.
  ///
  /// In en, this message translates to:
  /// **'My Media'**
  String get browseMyMedia;

  /// Home row title: latest additions in a named library.
  ///
  /// In en, this message translates to:
  /// **'Latest in {library}'**
  String browseLatestIn(String library);

  /// Home section error when a named row fails to load.
  ///
  /// In en, this message translates to:
  /// **'Could not load {title}'**
  String browseCouldNotLoad(String title);

  /// Empty home section placeholder.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet.'**
  String get browseNothingHereYet;

  /// Empty state: no libraries available.
  ///
  /// In en, this message translates to:
  /// **'No libraries'**
  String get browseNoLibraries;

  /// Empty state: no genres available.
  ///
  /// In en, this message translates to:
  /// **'No genres'**
  String get browseNoGenres;

  /// Empty state: no studios available.
  ///
  /// In en, this message translates to:
  /// **'No studios'**
  String get browseNoStudios;

  /// Empty state: no artists available.
  ///
  /// In en, this message translates to:
  /// **'No artists'**
  String get browseNoArtists;

  /// Empty state: an artist has no albums.
  ///
  /// In en, this message translates to:
  /// **'No albums'**
  String get browseNoAlbums;

  /// Empty state: the user has no favorites.
  ///
  /// In en, this message translates to:
  /// **'No favorites yet'**
  String get browseNoFavorites;

  /// Empty state: the user's Watchlist has nothing in it yet.
  ///
  /// In en, this message translates to:
  /// **'Your watchlist is empty'**
  String get browseNoWatchlist;

  /// Empty state: the library has no items.
  ///
  /// In en, this message translates to:
  /// **'This library is empty'**
  String get browseLibraryEmpty;

  /// Empty state: the collection has no items.
  ///
  /// In en, this message translates to:
  /// **'This collection is empty'**
  String get browseCollectionEmpty;

  /// Empty state: a search returned nothing.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get browseNoResults;

  /// Empty search results hint.
  ///
  /// In en, this message translates to:
  /// **'Try a different search.'**
  String get browseTryDifferentSearch;

  /// Idle search landing title.
  ///
  /// In en, this message translates to:
  /// **'Search Your Library'**
  String get browseSearchLibraryTitle;

  /// Idle search landing subtitle.
  ///
  /// In en, this message translates to:
  /// **'Movies, shows, episodes, music and more.'**
  String get browseSearchLibraryMessage;

  /// Search field placeholder on the library search screen.
  ///
  /// In en, this message translates to:
  /// **'Search movies, shows, music…'**
  String get browseSearchHint;

  /// Header for the recent search chips.
  ///
  /// In en, this message translates to:
  /// **'Recent Searches'**
  String get browseRecentSearches;

  /// Header for suggested items on the search landing.
  ///
  /// In en, this message translates to:
  /// **'Suggested'**
  String get browseSuggested;

  /// Filter option meaning all types / all items.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get browseAll;

  /// Media-type filter: movies.
  ///
  /// In en, this message translates to:
  /// **'Movies'**
  String get browseMovies;

  /// Search filter: TV shows.
  ///
  /// In en, this message translates to:
  /// **'Shows'**
  String get browseShows;

  /// Search filter: episodes.
  ///
  /// In en, this message translates to:
  /// **'Episodes'**
  String get browseEpisodes;

  /// Search filter: music.
  ///
  /// In en, this message translates to:
  /// **'Music'**
  String get browseMusic;

  /// Request media-type filter: TV shows.
  ///
  /// In en, this message translates to:
  /// **'TV Shows'**
  String get browseTvShows;

  /// Header of the library filter panel.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get browseFilter;

  /// Tooltip for the filters button.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get browseFilters;

  /// Library filter chip: unwatched only.
  ///
  /// In en, this message translates to:
  /// **'Unwatched'**
  String get browseUnwatched;

  /// Library filter section heading for genres.
  ///
  /// In en, this message translates to:
  /// **'Genre'**
  String get browseGenre;

  /// Sort-direction tooltip: ascending.
  ///
  /// In en, this message translates to:
  /// **'Ascending'**
  String get browseAscending;

  /// Sort-direction tooltip: descending.
  ///
  /// In en, this message translates to:
  /// **'Descending'**
  String get browseDescending;

  /// Tooltip to switch to list view.
  ///
  /// In en, this message translates to:
  /// **'List View'**
  String get browseListView;

  /// Tooltip to switch to grid view.
  ///
  /// In en, this message translates to:
  /// **'Grid View'**
  String get browseGridView;

  /// Tooltip for the sort menu button.
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get browseSortBy;

  /// Count of items in a library.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} item} other{{count} items}}'**
  String browseItemsCount(int count);

  /// Sort option: by name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get browseSortName;

  /// Sort option: by date added.
  ///
  /// In en, this message translates to:
  /// **'Date Added'**
  String get browseSortDateAdded;

  /// Sort option: by release date.
  ///
  /// In en, this message translates to:
  /// **'Release Date'**
  String get browseSortReleaseDate;

  /// Sort option: by rating.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get browseSortRating;

  /// Sort option: random order.
  ///
  /// In en, this message translates to:
  /// **'Random'**
  String get browseSortRandom;

  /// Empty state for a genre with no titles.
  ///
  /// In en, this message translates to:
  /// **'Nothing in {genre}'**
  String browseNothingInGenre(String genre);

  /// Empty state for a studio with no titles.
  ///
  /// In en, this message translates to:
  /// **'Nothing from {studio}'**
  String browseNothingFromStudio(String studio);

  /// Count of titles in a collection.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} title} other{{count} titles}}'**
  String browseTitlesCount(int count);

  /// Album action: shuffle play.
  ///
  /// In en, this message translates to:
  /// **'Shuffle'**
  String get browseShuffle;

  /// Tooltip for a track's more-actions menu.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get browseMore;

  /// Track menu: play next.
  ///
  /// In en, this message translates to:
  /// **'Play Next'**
  String get browsePlayNext;

  /// Track menu: add to the queue.
  ///
  /// In en, this message translates to:
  /// **'Add to Queue'**
  String get browseAddToQueue;

  /// Count of songs on an album.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} song} other{{count} songs}}'**
  String browseSongsCount(int count);

  /// Album total runtime in minutes (abbreviated).
  ///
  /// In en, this message translates to:
  /// **'{min} min'**
  String browseMinutesShort(int min);

  /// Hero button tooltip: open item details.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get browseDetails;

  /// Hero favorite toggle tooltip when already a favorite.
  ///
  /// In en, this message translates to:
  /// **'In My List'**
  String get browseInMyList;

  /// Hero favorite toggle tooltip when not a favorite.
  ///
  /// In en, this message translates to:
  /// **'Add to My List'**
  String get browseAddToMyList;

  /// Empty state title prompting Seerr setup.
  ///
  /// In en, this message translates to:
  /// **'Connect Seerr'**
  String get browseConnectSeerr;

  /// Empty state message prompting Seerr setup.
  ///
  /// In en, this message translates to:
  /// **'Add your Seerr URL and API key to discover and request.'**
  String get browseConnectSeerrMessage;

  /// Button to open Seerr settings.
  ///
  /// In en, this message translates to:
  /// **'Set Up'**
  String get browseSetUp;

  /// Tooltip / title for the Discover layout editor.
  ///
  /// In en, this message translates to:
  /// **'Customize Discover'**
  String get browseCustomizeDiscover;

  /// Tooltip to open Seerr settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get browseSettings;

  /// Discover row title: recent requests.
  ///
  /// In en, this message translates to:
  /// **'Recent Requests'**
  String get browseRecentRequests;

  /// Discover row title: trending.
  ///
  /// In en, this message translates to:
  /// **'Trending'**
  String get browseTrending;

  /// Discover row title: popular movies.
  ///
  /// In en, this message translates to:
  /// **'Popular Movies'**
  String get browsePopularMovies;

  /// Discover row title: movie genres.
  ///
  /// In en, this message translates to:
  /// **'Movie Genres'**
  String get browseMovieGenres;

  /// Discover row title: upcoming movies.
  ///
  /// In en, this message translates to:
  /// **'Upcoming Movies'**
  String get browseUpcomingMovies;

  /// Discover row title: popular series.
  ///
  /// In en, this message translates to:
  /// **'Popular Series'**
  String get browsePopularSeries;

  /// Discover row title: series genres.
  ///
  /// In en, this message translates to:
  /// **'Series Genres'**
  String get browseSeriesGenres;

  /// Discover row title: upcoming series.
  ///
  /// In en, this message translates to:
  /// **'Upcoming Series'**
  String get browseUpcomingSeries;

  /// Discover row title: TV networks.
  ///
  /// In en, this message translates to:
  /// **'Networks'**
  String get browseNetworks;

  /// Link to open a row's full grid.
  ///
  /// In en, this message translates to:
  /// **'See All'**
  String get browseSeeAll;

  /// Empty state for a Discover category/genre/company grid.
  ///
  /// In en, this message translates to:
  /// **'Nothing to show'**
  String get browseNothingToShow;

  /// TMDB sort option: by popularity.
  ///
  /// In en, this message translates to:
  /// **'Popularity'**
  String get browseSortPopularity;

  /// TMDB sort option: newest first.
  ///
  /// In en, this message translates to:
  /// **'Newest'**
  String get browseSortNewest;

  /// TMDB sort option: top rated.
  ///
  /// In en, this message translates to:
  /// **'Top Rated'**
  String get browseSortTopRated;

  /// Tooltip for the sort menu on filterable Discover grids.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get browseSort;

  /// Button to add a custom Discover slider.
  ///
  /// In en, this message translates to:
  /// **'Add Slider'**
  String get browseAddSlider;

  /// Instructions on the Discover layout editor.
  ///
  /// In en, this message translates to:
  /// **'Drag the handle or use the arrows to reorder. Toggle a row off to hide it from Discover.'**
  String get browseReorderHint;

  /// Subtitle marking a row as a user-created custom slider.
  ///
  /// In en, this message translates to:
  /// **'Custom Slider'**
  String get browseCustomSlider;

  /// Tooltip to move a Discover row up.
  ///
  /// In en, this message translates to:
  /// **'Move Up'**
  String get browseMoveUp;

  /// Tooltip to move a Discover row down.
  ///
  /// In en, this message translates to:
  /// **'Move Down'**
  String get browseMoveDown;

  /// Tooltip to delete a custom Discover slider.
  ///
  /// In en, this message translates to:
  /// **'Delete Slider'**
  String get browseDeleteSlider;

  /// Search field placeholder on the Seerr search tab.
  ///
  /// In en, this message translates to:
  /// **'Search movies & TV to request'**
  String get browseSeerrSearchHint;

  /// Empty state title on the Seerr search tab.
  ///
  /// In en, this message translates to:
  /// **'Search Seerr'**
  String get browseSearchSeerrTitle;

  /// Empty state message on the Seerr search tab.
  ///
  /// In en, this message translates to:
  /// **'Find any movie or show to request it.'**
  String get browseSearchSeerrMessage;

  /// Request status: declined.
  ///
  /// In en, this message translates to:
  /// **'Declined'**
  String get browseDeclined;

  /// Request status / filter: failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get browseFailed;

  /// Request status / filter: available.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get browseAvailable;

  /// Request status: partially available.
  ///
  /// In en, this message translates to:
  /// **'Partially Available'**
  String get browsePartiallyAvailable;

  /// Request status / filter: processing.
  ///
  /// In en, this message translates to:
  /// **'Processing'**
  String get browseProcessing;

  /// Request status / filter: pending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get browsePending;

  /// Request status / filter: approved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get browseApproved;

  /// Request filter: completed.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get browseCompleted;

  /// Request filter: unavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get browseUnavailable;

  /// Request filter: deleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get browseDeleted;

  /// Request sort: most recent.
  ///
  /// In en, this message translates to:
  /// **'Most Recent'**
  String get browseSortMostRecent;

  /// Request sort: last modified.
  ///
  /// In en, this message translates to:
  /// **'Last Modified'**
  String get browseSortLastModified;

  /// Tooltip to flip the request sort direction.
  ///
  /// In en, this message translates to:
  /// **'Toggle Sort Direction'**
  String get browseToggleSortDirection;

  /// Request action: approve.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get browseApprove;

  /// Request action: decline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get browseDecline;

  /// Request menu action: edit the request.
  ///
  /// In en, this message translates to:
  /// **'Edit Request'**
  String get browseEditRequest;

  /// Request action: delete the request.
  ///
  /// In en, this message translates to:
  /// **'Delete Request'**
  String get browseDeleteRequest;

  /// Request action: remove the media from Radarr/Sonarr.
  ///
  /// In en, this message translates to:
  /// **'Remove from {service}'**
  String browseRemoveFromService(String service);

  /// Fallback name for a series in a message.
  ///
  /// In en, this message translates to:
  /// **'this series'**
  String get browseThisSeries;

  /// Fallback name for a movie in a message.
  ///
  /// In en, this message translates to:
  /// **'this movie'**
  String get browseThisMovie;

  /// Label preceding the requested season numbers.
  ///
  /// In en, this message translates to:
  /// **'Season'**
  String get browseSeasonLabel;

  /// Request field label: status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get browseStatus;

  /// Request field label: requested by/when.
  ///
  /// In en, this message translates to:
  /// **'Requested'**
  String get browseRequested;

  /// Request field label: modified by/when.
  ///
  /// In en, this message translates to:
  /// **'Modified'**
  String get browseModified;

  /// Request field label: quality profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get browseProfile;

  /// Request field label: seasons.
  ///
  /// In en, this message translates to:
  /// **'Seasons'**
  String get browseSeasons;

  /// Fallback title for a series before its detail loads.
  ///
  /// In en, this message translates to:
  /// **'Series #{id}'**
  String browseSeriesNumber(int id);

  /// Fallback title for a movie before its detail loads.
  ///
  /// In en, this message translates to:
  /// **'Movie #{id}'**
  String browseMovieNumber(int id);

  /// Snackbar after approving a request.
  ///
  /// In en, this message translates to:
  /// **'Approved {title}'**
  String browseApprovedTitle(String title);

  /// Snackbar after declining a request.
  ///
  /// In en, this message translates to:
  /// **'Declined {title}'**
  String browseDeclinedTitle(String title);

  /// Snackbar after retrying a request.
  ///
  /// In en, this message translates to:
  /// **'Retrying {title}'**
  String browseRetryingTitle(String title);

  /// Snackbar after deleting a request.
  ///
  /// In en, this message translates to:
  /// **'Deleted request for {title}'**
  String browseDeletedRequestFor(String title);

  /// Snackbar after removing media from Radarr/Sonarr.
  ///
  /// In en, this message translates to:
  /// **'Removed {title} from {service}'**
  String browseRemovedFromService(String title, String service);

  /// Generic success snackbar.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get browseDone;

  /// Snackbar after editing a request.
  ///
  /// In en, this message translates to:
  /// **'Request updated'**
  String get browseRequestUpdated;

  /// Confirmation dialog body for a destructive request action.
  ///
  /// In en, this message translates to:
  /// **'{action}? This cannot be undone.'**
  String browseConfirmUndone(String action);

  /// Empty state title on the Requests tab.
  ///
  /// In en, this message translates to:
  /// **'No requests'**
  String get browseNoRequests;

  /// Empty state message on the Requests tab.
  ///
  /// In en, this message translates to:
  /// **'Requests you make will appear here to track.'**
  String get browseNoRequestsMessage;

  /// Relative time: days ago.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} day ago} other{{count} days ago}}'**
  String browseDaysAgo(int count);

  /// Relative time: hours ago.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} hour ago} other{{count} hours ago}}'**
  String browseHoursAgo(int count);

  /// Relative time: minutes ago.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} minute ago} other{{count} minutes ago}}'**
  String browseMinutesAgo(int count);

  /// Relative time: moments ago.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get browseJustNow;

  /// Connector before a requester's name, e.g. '3 days ago by'.
  ///
  /// In en, this message translates to:
  /// **'{ago} by'**
  String browseAgoBy(String ago);

  /// YouTube section tab label: the channels you follow.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions'**
  String get ytSubscriptions;

  /// Button on the YouTube watch page: drop the video and keep the audio playing in the background.
  ///
  /// In en, this message translates to:
  /// **'Listen'**
  String get ytListen;

  /// Video row menu action: play just this video's audio in the background.
  ///
  /// In en, this message translates to:
  /// **'Play audio'**
  String get ytPlayAudio;

  /// Button on the background-audio Now Playing: switch back to watching the video at the current position.
  ///
  /// In en, this message translates to:
  /// **'Watch video'**
  String get ytWatchVideo;

  /// Playlist action: play the whole playlist as background audio.
  ///
  /// In en, this message translates to:
  /// **'Listen to all'**
  String get ytListenAll;

  /// Quiet note on a playlist when fewer videos load than the count advertised, because YouTube won't return age-restricted or private videos to an anonymous client.
  ///
  /// In en, this message translates to:
  /// **'Some videos are unavailable (age-restricted or private).'**
  String get ytSomeUnavailable;

  /// Shown in the background-audio queue sheet when the up-next queue is empty.
  ///
  /// In en, this message translates to:
  /// **'Nothing up next. A related track plays automatically when this one ends.'**
  String get ytQueueEmpty;

  /// YouTube section tab label: newest uploads from subscribed channels.
  ///
  /// In en, this message translates to:
  /// **'What\'s New'**
  String get ytWhatsNew;

  /// YouTube tab / search filter label: playlists.
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get ytPlaylists;

  /// Floating pill label while a YouTube download is in progress. Distinct from the Jellyfin download pill's plain "Downloading" since both can show at once.
  ///
  /// In en, this message translates to:
  /// **'YouTube Download'**
  String get ytDownloadPill;

  /// Tab / screen title: downloaded items.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get ytDownloads;

  /// YouTube tab label: watch history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get ytHistory;

  /// YouTube search filter chip: search for videos.
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get ytVideos;

  /// YouTube search filter chip: search for channels.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get ytChannels;

  /// YouTube search: button that opens the video search filters sheet.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get ytFilters;

  /// Placeholder in the YouTube search field.
  ///
  /// In en, this message translates to:
  /// **'Search YouTube'**
  String get ytSearchYoutube;

  /// Empty-state title on the YouTube Search tab when the Videos filter is selected.
  ///
  /// In en, this message translates to:
  /// **'Search Videos'**
  String get ytSearchVideos;

  /// Empty-state message on the YouTube Search tab when the Videos filter is selected.
  ///
  /// In en, this message translates to:
  /// **'Videos play in-app, with no ads. Switch to Channels or Playlists above to search those instead.'**
  String get ytSearchVideosMessage;

  /// Empty-state title on the YouTube Search tab when the Channels filter is selected.
  ///
  /// In en, this message translates to:
  /// **'Search Channels'**
  String get ytSearchChannels;

  /// Empty-state message on the YouTube Search tab when the Channels filter is selected.
  ///
  /// In en, this message translates to:
  /// **'Find a channel by name and subscribe straight from the results.'**
  String get ytSearchChannelsMessage;

  /// Empty-state title on the YouTube Search tab when the Playlists filter is selected.
  ///
  /// In en, this message translates to:
  /// **'Search Playlists'**
  String get ytSearchPlaylists;

  /// Empty-state message on the YouTube Search tab when the Playlists filter is selected.
  ///
  /// In en, this message translates to:
  /// **'Open a playlist to see everything in it.'**
  String get ytSearchPlaylistsMessage;

  /// Heading over the list of recent YouTube search terms.
  ///
  /// In en, this message translates to:
  /// **'Recent Searches'**
  String get ytRecentSearches;

  /// Title of the YouTube video search filters bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'Search Filters'**
  String get ytSearchFilters;

  /// Group heading for sort options in the YouTube search filters sheet.
  ///
  /// In en, this message translates to:
  /// **'Sort By'**
  String get ytSortBy;

  /// YouTube search sort option: by relevance.
  ///
  /// In en, this message translates to:
  /// **'Relevance'**
  String get ytSortRelevance;

  /// YouTube search: sort-by option and filter group heading for upload date.
  ///
  /// In en, this message translates to:
  /// **'Upload Date'**
  String get ytUploadDate;

  /// YouTube search sort option: by view count.
  ///
  /// In en, this message translates to:
  /// **'View Count'**
  String get ytSortViewCount;

  /// YouTube search sort option: by rating.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get ytSortRating;

  /// YouTube search upload-date filter: any time.
  ///
  /// In en, this message translates to:
  /// **'Any Time'**
  String get ytUploadAnyTime;

  /// YouTube search upload-date filter: last hour.
  ///
  /// In en, this message translates to:
  /// **'Last Hour'**
  String get ytUploadLastHour;

  /// YouTube search upload-date filter: today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get ytUploadToday;

  /// YouTube search upload-date filter: this week.
  ///
  /// In en, this message translates to:
  /// **'This Week'**
  String get ytUploadThisWeek;

  /// YouTube search upload-date filter: this month.
  ///
  /// In en, this message translates to:
  /// **'This Month'**
  String get ytUploadThisMonth;

  /// YouTube search upload-date filter: this year.
  ///
  /// In en, this message translates to:
  /// **'This Year'**
  String get ytUploadThisYear;

  /// Group heading for video length filter in the YouTube search filters sheet.
  ///
  /// In en, this message translates to:
  /// **'Length'**
  String get ytLength;

  /// YouTube search length filter: any length.
  ///
  /// In en, this message translates to:
  /// **'Any Length'**
  String get ytLengthAny;

  /// YouTube search length filter: under 4 minutes.
  ///
  /// In en, this message translates to:
  /// **'Under 4 Minutes'**
  String get ytLengthUnder4;

  /// YouTube search length filter: 4 to 20 minutes.
  ///
  /// In en, this message translates to:
  /// **'4 to 20 Minutes'**
  String get ytLength4To20;

  /// YouTube search length filter: over 20 minutes.
  ///
  /// In en, this message translates to:
  /// **'Over 20 Minutes'**
  String get ytLengthOver20;

  /// Empty-state title when a YouTube search returns nothing.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get ytNoResults;

  /// Button that imports subscribed channels from a file.
  ///
  /// In en, this message translates to:
  /// **'Import Subscriptions'**
  String get ytImportSubscriptions;

  /// Short button label: import subscriptions.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get ytImport;

  /// Short button label: export subscriptions.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get ytExport;

  /// File-picker dialog title when exporting subscriptions.
  ///
  /// In en, this message translates to:
  /// **'Export Subscriptions'**
  String get ytExportSubscriptions;

  /// Empty-state title on the Subscriptions and What's New tabs.
  ///
  /// In en, this message translates to:
  /// **'No subscriptions yet'**
  String get ytNoSubscriptionsTitle;

  /// Empty-state message on the Subscriptions tab.
  ///
  /// In en, this message translates to:
  /// **'Search for a channel, or open one from any video, and hit Subscribe. Or import from Google Takeout or a NewPipe backup. Subscriptions are kept on this device, with no account needed.'**
  String get ytNoSubscriptionsMessage;

  /// Snackbar shown when a subscription import file has no channels.
  ///
  /// In en, this message translates to:
  /// **'No subscriptions found. Use YouTube\'s subscriptions.csv from Google Takeout, or a NewPipe backup.'**
  String get ytImportNotFound;

  /// Snackbar after an import where every channel was already subscribed.
  ///
  /// In en, this message translates to:
  /// **'Already subscribed to all {count}.'**
  String ytAlreadySubscribedAll(int count);

  /// Snackbar after importing subscriptions: how many of the total were newly added.
  ///
  /// In en, this message translates to:
  /// **'Added {added} of {total}.'**
  String ytAddedOfTotal(int added, int total);

  /// Snackbar after exporting subscriptions.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Exported {count} subscription.} other{Exported {count} subscriptions.}}'**
  String ytExportedSubscriptions(int count);

  /// Count of subscribed channels shown above the grid.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} channel} other{{count} channels}}'**
  String ytChannelCount(int count);

  /// Tooltip on an overflow / options menu button.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get ytOptions;

  /// Fallback label used when a channel's name is unknown.
  ///
  /// In en, this message translates to:
  /// **'Channel'**
  String get ytChannelFallback;

  /// Menu item / sheet title: manage feed groups for a channel.
  ///
  /// In en, this message translates to:
  /// **'Feed Groups'**
  String get ytFeedGroups;

  /// Menu item: unsubscribe from a channel.
  ///
  /// In en, this message translates to:
  /// **'Unsubscribe'**
  String get ytUnsubscribe;

  /// Empty-state message on the What's New tab.
  ///
  /// In en, this message translates to:
  /// **'Subscribe to a channel and its newest uploads land here.'**
  String get ytFeedEmptyMessage;

  /// Empty-state title when the What's New feed has no videos.
  ///
  /// In en, this message translates to:
  /// **'Nothing new'**
  String get ytNothingNew;

  /// Feed group filter chip that shows every subscription.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get ytAll;

  /// Dialog title when creating a feed group.
  ///
  /// In en, this message translates to:
  /// **'New Feed Group'**
  String get ytNewFeedGroup;

  /// Text field label for a name (playlist or feed group).
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get ytName;

  /// Hint text for the feed group name field, suggesting example names.
  ///
  /// In en, this message translates to:
  /// **'Music, News, Podcasts…'**
  String get ytFeedGroupHint;

  /// List item that creates a new feed group.
  ///
  /// In en, this message translates to:
  /// **'New Group'**
  String get ytNewGroup;

  /// Subtitle in the feed groups sheet: the channel name plus what groups do.
  ///
  /// In en, this message translates to:
  /// **'{channel}\nGroups filter What\'s New to the channels you pick.'**
  String ytFeedGroupsDescription(String channel);

  /// Button that confirms creating a playlist or feed group.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get ytCreate;

  /// Dialog title / button / list item for creating a new playlist.
  ///
  /// In en, this message translates to:
  /// **'New Playlist'**
  String get ytNewPlaylist;

  /// Empty-state title on the Playlists tab.
  ///
  /// In en, this message translates to:
  /// **'No playlists yet'**
  String get ytNoPlaylistsTitle;

  /// Empty-state message on the Playlists tab.
  ///
  /// In en, this message translates to:
  /// **'Make one here, or use the menu on any video and pick Add to Playlist. You can also save someone else\'s playlist from search. Everything is kept on this device.'**
  String get ytNoPlaylistsMessage;

  /// Section heading for the user's own local playlists.
  ///
  /// In en, this message translates to:
  /// **'Your Playlists'**
  String get ytYourPlaylists;

  /// Section heading / tooltip for playlists saved from other people.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get ytSaved;

  /// Dialog title when renaming a playlist.
  ///
  /// In en, this message translates to:
  /// **'Rename Playlist'**
  String get ytRenamePlaylist;

  /// Menu item: rename a playlist.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get ytRename;

  /// Empty-state title when there are no downloads.
  ///
  /// In en, this message translates to:
  /// **'No downloads'**
  String get ytNoDownloadsTitle;

  /// Empty-state message on the YouTube Downloads tab when ffmpeg is present.
  ///
  /// In en, this message translates to:
  /// **'Use the menu on any video and pick Download. Files are saved to {path}.'**
  String ytDownloadsEmptyFfmpeg(String path);

  /// Empty-state message on the YouTube Downloads tab when ffmpeg is missing.
  ///
  /// In en, this message translates to:
  /// **'Use the menu on any video and pick Download. ffmpeg is not installed, so video is limited to 360p — audio downloads are unaffected.'**
  String get ytDownloadsEmptyNoFfmpeg;

  /// Fallback save-location phrase used inline when the download folder path is unknown.
  ///
  /// In en, this message translates to:
  /// **'your Downloads folder'**
  String get ytDownloadsFolder;

  /// Download status: queued, waiting to start.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get ytDownloadWaiting;

  /// Download status: downloading the audio stream.
  ///
  /// In en, this message translates to:
  /// **'Downloading audio'**
  String get ytDownloadingAudio;

  /// Download status: downloading the video stream.
  ///
  /// In en, this message translates to:
  /// **'Downloading video'**
  String get ytDownloadingVideo;

  /// Download status: merging separate video and audio streams.
  ///
  /// In en, this message translates to:
  /// **'Merging video and audio'**
  String get ytDownloadMerging;

  /// Download status: file written to disk.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get ytDownloadSaved;

  /// Status label when a download failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get ytFailed;

  /// Download status: cancelled by the user.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get ytDownloadCancelled;

  /// Menu item: open the folder containing a downloaded file.
  ///
  /// In en, this message translates to:
  /// **'Show in Folder'**
  String get ytShowInFolder;

  /// Help text under the YouTube download folder settings: changing the folder only moves existing files if the user agrees.
  ///
  /// In en, this message translates to:
  /// **'New downloads go here. If you already have downloads, you\'ll be asked whether to move them too.'**
  String get prefsDownloadFolderNote;

  /// Dialog title after changing the download folder while downloads exist in the old one.
  ///
  /// In en, this message translates to:
  /// **'Move Existing Downloads?'**
  String get ytMoveDownloadsTitle;

  /// Dialog body: how many finished downloads would stay behind in the previous folder.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 download is in your old folder. Move it here too?} other{{count} downloads are in your old folder. Move them here too?}}'**
  String ytMoveDownloadsBody(int count);

  /// Dialog button: leave existing downloads in the old folder.
  ///
  /// In en, this message translates to:
  /// **'Keep Them Where They Are'**
  String get ytMoveDownloadsKeep;

  /// Dialog button: move existing downloads into the new folder.
  ///
  /// In en, this message translates to:
  /// **'Move Them'**
  String get ytMoveDownloadsMove;

  /// Confirmation after moving downloads to the new folder.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Moved 1 download.} other{Moved {count} downloads.}}'**
  String ytMoveDownloadsDone(int count);

  /// Some downloads could not be moved to the new folder.
  ///
  /// In en, this message translates to:
  /// **'Moved {moved} of {total} downloads. The rest couldn\'t be moved and stayed where they were.'**
  String ytMoveDownloadsPartial(int moved, int total);

  /// Android: the chosen download folder is outside the phone's main storage (an SD card, say). {folder} is the folder used instead, such as Movies/Fathom.
  ///
  /// In en, this message translates to:
  /// **'Fathom can\'t save here, so downloads go to {folder}.'**
  String prefsDownloadFolderUnavailable(String folder);

  /// Menu item (Android): open a downloaded file in another app, such as a video player.
  ///
  /// In en, this message translates to:
  /// **'Open With'**
  String get ytOpenWith;

  /// Menu item (Android): send a downloaded file to another app or person.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get ytShareFile;

  /// Error shown when no installed app can open or receive a downloaded file.
  ///
  /// In en, this message translates to:
  /// **'No app on this device can open that file.'**
  String get ytOpenFileFailed;

  /// Menu item: remove a download from the list but keep the file.
  ///
  /// In en, this message translates to:
  /// **'Remove from List'**
  String get ytRemoveFromList;

  /// Menu item: delete a downloaded file from disk.
  ///
  /// In en, this message translates to:
  /// **'Delete File'**
  String get ytDeleteFile;

  /// Empty-state title on the History tab.
  ///
  /// In en, this message translates to:
  /// **'Nothing watched yet'**
  String get ytNothingWatchedTitle;

  /// Empty-state message on the History tab.
  ///
  /// In en, this message translates to:
  /// **'Videos you watch show up here, and pick up where you left off. History is kept on this device.'**
  String get ytHistoryEmptyMessage;

  /// Button and dialog title to clear watch history.
  ///
  /// In en, this message translates to:
  /// **'Clear History'**
  String get ytClearHistory;

  /// Confirmation body when clearing watch history.
  ///
  /// In en, this message translates to:
  /// **'This removes every watched video and its saved position.'**
  String get ytClearHistoryConfirm;

  /// Button to enter multi-select mode on the Downloads tab.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get ytSelectDownloads;

  /// Button to select every finished download at once.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get ytSelectAll;

  /// App-bar-style label while some downloads are selected.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 selected} other{{count} selected}}'**
  String ytNSelected(int count);

  /// Confirmation dialog title for bulk-deleting selected downloads.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Delete download?} other{Delete {count} downloads?}}'**
  String ytDeleteSelectedTitle(int count);

  /// Confirmation dialog body for bulk-deleting selected downloads.
  ///
  /// In en, this message translates to:
  /// **'This removes the downloaded files from your device. They can be downloaded again later.'**
  String get ytDeleteSelectedConfirm;

  /// Tooltip to remove a single video from watch history.
  ///
  /// In en, this message translates to:
  /// **'Remove from History'**
  String get ytRemoveFromHistory;

  /// Heading over the related-videos rail on the watch page.
  ///
  /// In en, this message translates to:
  /// **'Up Next'**
  String get ytUpNext;

  /// Label for the autoplay toggle beside Up Next.
  ///
  /// In en, this message translates to:
  /// **'Autoplay'**
  String get ytAutoplay;

  /// Title of the play-queue bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'Up Next in Queue'**
  String get ytUpNextInQueue;

  /// Confirmation dialog title when clearing the play queue.
  ///
  /// In en, this message translates to:
  /// **'Clear Queue?'**
  String get ytClearQueueTitle;

  /// Confirmation body when clearing the play queue.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{This removes all {count} queued video.} other{This removes all {count} queued videos.}}'**
  String ytClearQueueConfirm(int count);

  /// Shown in the queue sheet when nothing is queued.
  ///
  /// In en, this message translates to:
  /// **'Nothing queued.'**
  String get ytNothingQueued;

  /// Menu item: remove a video from the play queue.
  ///
  /// In en, this message translates to:
  /// **'Remove from Queue'**
  String get ytRemoveFromQueue;

  /// Heading over the comments section on the watch page.
  ///
  /// In en, this message translates to:
  /// **'Comments'**
  String get ytComments;

  /// Shown in the Shorts comments sheet when a video has comments turned off or none could be loaded.
  ///
  /// In en, this message translates to:
  /// **'Comments are unavailable.'**
  String get ytCommentsUnavailable;

  /// Shown over a Short in the vertical viewer when its video stream could not be resolved.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this Short.'**
  String get ytShortUnavailable;

  /// Comments heading with a preformatted count string.
  ///
  /// In en, this message translates to:
  /// **'Comments  ·  {count}'**
  String ytCommentsCount(String count);

  /// Button to load more comments.
  ///
  /// In en, this message translates to:
  /// **'Show More Comments'**
  String get ytShowMoreComments;

  /// Toggle showing the number of replies to a comment.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} reply} other{{count} replies}}'**
  String ytReplies(int count);

  /// Shown when comment replies fail to load.
  ///
  /// In en, this message translates to:
  /// **'Could not load replies'**
  String get ytCouldNotLoadReplies;

  /// Button to expand a truncated video description.
  ///
  /// In en, this message translates to:
  /// **'Show More'**
  String get ytShowMore;

  /// Button to collapse an expanded video description.
  ///
  /// In en, this message translates to:
  /// **'Show Less'**
  String get ytShowLess;

  /// Empty-state title when a channel has no uploads.
  ///
  /// In en, this message translates to:
  /// **'No uploads'**
  String get ytNoUploads;

  /// Empty-state title when a channel tab (Shorts, Live, Playlists) has no content. {tab} is the tab name.
  ///
  /// In en, this message translates to:
  /// **'Nothing in {tab}'**
  String ytNothingInTab(String tab);

  /// Fallback title used when a playlist's name is unknown.
  ///
  /// In en, this message translates to:
  /// **'Playlist'**
  String get ytPlaylistFallback;

  /// Tooltip to save (bookmark) a playlist.
  ///
  /// In en, this message translates to:
  /// **'Save Playlist'**
  String get ytSavePlaylist;

  /// Empty-state title when a playlist has no videos.
  ///
  /// In en, this message translates to:
  /// **'Nothing in this playlist'**
  String get ytNothingInPlaylist;

  /// Empty-state title when a local playlist can't be found.
  ///
  /// In en, this message translates to:
  /// **'Playlist not found'**
  String get ytPlaylistNotFound;

  /// Empty-state title on an empty local playlist.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get ytMyPlaylistEmptyTitle;

  /// Empty-state message on an empty local playlist.
  ///
  /// In en, this message translates to:
  /// **'Use the menu on any video and pick Add to Playlist.'**
  String get ytMyPlaylistEmptyMessage;

  /// Menu item: remove a video from a playlist.
  ///
  /// In en, this message translates to:
  /// **'Remove from Playlist'**
  String get ytRemoveFromPlaylist;

  /// Snackbar after copying a video link.
  ///
  /// In en, this message translates to:
  /// **'Link copied to clipboard.'**
  String get ytLinkCopied;

  /// Snackbar when opening the system browser fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open a browser.'**
  String get ytCouldNotOpenBrowser;

  /// Video action: play this video next, before the rest of the queue.
  ///
  /// In en, this message translates to:
  /// **'Play Next'**
  String get ytPlayNext;

  /// Video action label once the video is in the queue.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get ytQueued;

  /// Video action: add this video to the play queue.
  ///
  /// In en, this message translates to:
  /// **'Add to Queue'**
  String get ytAddToQueue;

  /// Video action that opens the queue, showing how many are queued.
  ///
  /// In en, this message translates to:
  /// **'Queue ({count})'**
  String ytQueueCount(int count);

  /// Video action label once the video has been downloaded.
  ///
  /// In en, this message translates to:
  /// **'Downloaded'**
  String get ytDownloaded;

  /// Video action label while the video is downloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading'**
  String get ytDownloading;

  /// Video action / sheet title / button: download the video.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get ytDownload;

  /// Video action: copy the video link to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy Link'**
  String get ytCopyLink;

  /// Video action: open the video on YouTube in the system browser.
  ///
  /// In en, this message translates to:
  /// **'Open in Browser'**
  String get ytOpenInBrowser;

  /// Playlist action label when the video is already in a playlist.
  ///
  /// In en, this message translates to:
  /// **'Saved to Playlist'**
  String get ytSavedToPlaylist;

  /// Playlist action: add the video to a playlist.
  ///
  /// In en, this message translates to:
  /// **'Add to Playlist'**
  String get ytAddToPlaylist;

  /// Snackbar after starting a download.
  ///
  /// In en, this message translates to:
  /// **'Downloading. Progress is in the Downloads tab.'**
  String get ytDownloadInProgress;

  /// Download sheet group label: video or audio.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get ytType;

  /// Download type choice: video.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get ytVideo;

  /// Download type choice: audio only.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get ytAudio;

  /// Download sheet group label: the video container format.
  ///
  /// In en, this message translates to:
  /// **'Container'**
  String get ytContainer;

  /// Download sheet group label: the video resolution.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get ytQuality;

  /// Download sheet group label: the audio format.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get ytFormat;

  /// Download sheet group label: the audio bitrate.
  ///
  /// In en, this message translates to:
  /// **'Bitrate'**
  String get ytBitrate;

  /// Download summary for an MP3 audio download.
  ///
  /// In en, this message translates to:
  /// **'MP3 at {bitrate} kbps, converted with ffmpeg.'**
  String ytSummaryMp3(int bitrate);

  /// Download summary for an M4A audio download.
  ///
  /// In en, this message translates to:
  /// **'M4A, YouTube\'s original audio with no conversion.'**
  String get ytSummaryM4a;

  /// Download summary for a high-resolution video merged from separate streams. {box} is a container token like MP4 or MKV.
  ///
  /// In en, this message translates to:
  /// **'{height}p {box}, merged from separate video and audio.'**
  String ytSummaryMerged(int height, String box);

  /// Download summary for a low-resolution video remuxed into MKV.
  ///
  /// In en, this message translates to:
  /// **'{height}p, remuxed into MKV.'**
  String ytSummaryRemuxMkv(int height);

  /// Download summary for a low-resolution single-stream video. {box} is a container token like MP4.
  ///
  /// In en, this message translates to:
  /// **'{height}p {box}, a single stream.'**
  String ytSummarySingle(int height, String box);

  /// Note in the download sheet when ffmpeg is not installed.
  ///
  /// In en, this message translates to:
  /// **'ffmpeg not found, so only M4A audio can be downloaded, plus 360p MP4 for videos YouTube still offers as a single file. Install ffmpeg for MP3, MKV and higher resolutions.'**
  String get ytFfmpegNote;

  /// Subscribe button label once subscribed to a channel.
  ///
  /// In en, this message translates to:
  /// **'Subscribed'**
  String get ytSubscribed;

  /// Subscribe button label when not subscribed.
  ///
  /// In en, this message translates to:
  /// **'Subscribe'**
  String get ytSubscribe;

  /// Action-sheet row: open the video's channel page.
  ///
  /// In en, this message translates to:
  /// **'Go to Channel'**
  String get ytGoToChannel;

  /// Title of the add-to-playlist bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'Save to Playlist'**
  String get ytSaveToPlaylist;

  /// Instruction in the add-to-playlist sheet.
  ///
  /// In en, this message translates to:
  /// **'Tick a playlist to add this video. Untick to remove it.'**
  String get ytTickToAdd;

  /// Shown in the add-to-playlist sheet when there are no playlists.
  ///
  /// In en, this message translates to:
  /// **'No playlists yet. Playlists are kept on this device.'**
  String get ytNoPlaylistsDevice;

  /// Subtitle of a playlist row in the add-to-playlist sheet when the video is already in it. {count} is a preformatted count string.
  ///
  /// In en, this message translates to:
  /// **'{count}  ·  Saved — untick to remove'**
  String ytPlaylistSavedSubtitle(String count);

  /// Empty-state message on the offline Downloads screen.
  ///
  /// In en, this message translates to:
  /// **'Download a movie or episode to watch it offline.'**
  String get ytDownloadsScreenEmptyMessage;

  /// Subtitle on a completed offline download.
  ///
  /// In en, this message translates to:
  /// **'Available Offline'**
  String get ytAvailableOffline;

  /// Login validation error shown when the username field is empty.
  ///
  /// In en, this message translates to:
  /// **'Please enter your username.'**
  String get appEnterUsername;

  /// Generic fallback error shown on the login/connect screens when an unexpected exception occurs.
  ///
  /// In en, this message translates to:
  /// **'Unexpected error: {error}'**
  String appUnexpectedError(String error);

  /// Login error shown when Quick Connect is attempted but the server has it disabled.
  ///
  /// In en, this message translates to:
  /// **'Quick Connect is not enabled on this server.'**
  String get appQuickConnectNotEnabled;

  /// Login screen: username text field label.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get appUsername;

  /// Login screen: password text field label.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get appPassword;

  /// Login screen: divider label between the Sign In button and Quick Connect.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get appOr;

  /// Login screen: button that starts the Quick Connect sign-in flow.
  ///
  /// In en, this message translates to:
  /// **'Use Quick Connect'**
  String get appUseQuickConnect;

  /// Title of the Quick Connect dialog.
  ///
  /// In en, this message translates to:
  /// **'Quick Connect'**
  String get appQuickConnect;

  /// Quick Connect dialog: instructions telling the user to approve the shown code on another signed-in device.
  ///
  /// In en, this message translates to:
  /// **'Open Quick Connect on a device where you are already signed in to Jellyfin, then enter this code.'**
  String get appQuickConnectInstructions;

  /// Quick Connect dialog: status text while polling for the user to approve the code.
  ///
  /// In en, this message translates to:
  /// **'Waiting for approval…'**
  String get appWaitingForApproval;

  /// Server connect screen: subtitle under the Fathom logo.
  ///
  /// In en, this message translates to:
  /// **'Connect to your Jellyfin server'**
  String get appConnectToServer;

  /// Server connect screen: label for the server address text field.
  ///
  /// In en, this message translates to:
  /// **'Server Address'**
  String get appServerAddress;

  /// Server connect screen: button that validates and connects to the entered server.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get appConnect;

  /// Settings search: label for the Android video engine (ExoPlayer/media_kit) setting.
  ///
  /// In en, this message translates to:
  /// **'Video Player Engine'**
  String get searchPlayerBackend;

  /// Preferences: title for the Android video engine selector.
  ///
  /// In en, this message translates to:
  /// **'Video Player (Android)'**
  String get prefsPlayerBackend;

  /// Preferences: subtitle for the Android video engine selector.
  ///
  /// In en, this message translates to:
  /// **'ExoPlayer plays 4K/HDR smoothly on TV; media_kit is the classic engine.'**
  String get prefsPlayerBackendSub;

  /// Preferences: automatic video backend option.
  ///
  /// In en, this message translates to:
  /// **'Automatic (ExoPlayer on TV)'**
  String get prefsPlayerBackendAuto;

  /// Preferences: native ExoPlayer video backend option.
  ///
  /// In en, this message translates to:
  /// **'ExoPlayer (native, 4K/HDR)'**
  String get prefsPlayerBackendExo;

  /// Preferences: media_kit video backend option.
  ///
  /// In en, this message translates to:
  /// **'media_kit (libmpv)'**
  String get prefsPlayerBackendMediaKit;

  /// Server connect screen: button that scans the local network for Jellyfin servers.
  ///
  /// In en, this message translates to:
  /// **'Find Servers on My Network'**
  String get appFindServers;

  /// Server connect screen: label shown while scanning the local network for servers.
  ///
  /// In en, this message translates to:
  /// **'Searching your network…'**
  String get appScanningServers;

  /// Server connect screen: shown when a network scan finds no Jellyfin servers.
  ///
  /// In en, this message translates to:
  /// **'No servers found. Enter the address above instead.'**
  String get appNoServersFound;

  /// Splash screen tagline shown under the Fathom wordmark.
  ///
  /// In en, this message translates to:
  /// **'Dive into your media'**
  String get appTagline;

  /// Navigation rail label for the Home section.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get appNavHome;

  /// Navigation rail label for the Libraries section.
  ///
  /// In en, this message translates to:
  /// **'Libraries'**
  String get appNavLibraries;

  /// Navigation rail label for the Favorites section.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get appNavFavorites;

  /// Navigation rail label for the Watchlist section.
  ///
  /// In en, this message translates to:
  /// **'Watchlist'**
  String get appNavWatchlist;

  /// Navigation rail label for the Live TV section.
  ///
  /// In en, this message translates to:
  /// **'Live TV'**
  String get appNavLiveTv;

  /// Bottom navigation label opening a sheet of overflow destinations on phones.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get appNavMore;

  /// Navigation label for the internet radio section.
  ///
  /// In en, this message translates to:
  /// **'Radio'**
  String get appNavRadio;

  /// Radio screen title.
  ///
  /// In en, this message translates to:
  /// **'Radio'**
  String get radioTitle;

  /// Now Playing title while a station plays.
  ///
  /// In en, this message translates to:
  /// **'Radio'**
  String get radioNowPlaying;

  /// Shown under the station when there is no ICY track info.
  ///
  /// In en, this message translates to:
  /// **'Live Stream'**
  String get radioLiveStream;

  /// Toggles the station directory search.
  ///
  /// In en, this message translates to:
  /// **'Search Directory'**
  String get radioSearchDirectory;

  /// Radio tab: the user's saved stations.
  ///
  /// In en, this message translates to:
  /// **'My Stations'**
  String get radioTabMyStations;

  /// Radio tab: search and add stations from the directory.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get radioTabBrowse;

  /// Tooltip for the radio stop/dismiss button.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get radioStop;

  /// Tooltip for the radio rewind button.
  ///
  /// In en, this message translates to:
  /// **'Rewind 15 seconds'**
  String get radioRewind;

  /// Tooltip for the radio skip-forward button.
  ///
  /// In en, this message translates to:
  /// **'Skip 15 seconds'**
  String get radioSkip;

  /// Tooltip for the previous-station button on the radio Now Playing screen.
  ///
  /// In en, this message translates to:
  /// **'Previous Station'**
  String get radioPreviousStation;

  /// Tooltip for the next-station button on the radio Now Playing screen.
  ///
  /// In en, this message translates to:
  /// **'Next Station'**
  String get radioNextStation;

  /// Tooltip for the group header overflow menu.
  ///
  /// In en, this message translates to:
  /// **'Group Options'**
  String get radioGroupOptions;

  /// Menu action: rename a station group.
  ///
  /// In en, this message translates to:
  /// **'Rename Group'**
  String get radioRenameGroup;

  /// Menu action: delete a station group.
  ///
  /// In en, this message translates to:
  /// **'Delete Group'**
  String get radioDeleteGroup;

  /// Confirm body for deleting a group.
  ///
  /// In en, this message translates to:
  /// **'Stations in \"{group}\" move to Other. The stations themselves aren\'t removed.'**
  String radioDeleteGroupBody(String group);

  /// Placeholder in the radio directory search field.
  ///
  /// In en, this message translates to:
  /// **'Search stations…'**
  String get radioSearchHint;

  /// Empty state before a directory search is run.
  ///
  /// In en, this message translates to:
  /// **'Search for a station to add'**
  String get radioSearchPrompt;

  /// Empty state when a directory search returns nothing.
  ///
  /// In en, this message translates to:
  /// **'No stations found'**
  String get radioNoResults;

  /// Empty state when the station library is empty.
  ///
  /// In en, this message translates to:
  /// **'No saved stations yet'**
  String get radioNoStations;

  /// Empty-state hint for the station library.
  ///
  /// In en, this message translates to:
  /// **'Search the directory or add a station by URL'**
  String get radioNoStationsSub;

  /// Section header for favorite stations.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get radioFavorites;

  /// Section header for stations with no group.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get radioUngrouped;

  /// Adds a radio station by its stream URL.
  ///
  /// In en, this message translates to:
  /// **'Add by URL'**
  String get radioAddByUrl;

  /// Add a directory station to the library.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get radioAdd;

  /// Confirmation after saving a station.
  ///
  /// In en, this message translates to:
  /// **'Added {name}'**
  String radioAdded(String name);

  /// Mark a station as favorite.
  ///
  /// In en, this message translates to:
  /// **'Add to Favorites'**
  String get radioFavorite;

  /// Unmark a favorite station.
  ///
  /// In en, this message translates to:
  /// **'Remove from Favorites'**
  String get radioUnfavorite;

  /// Assign a station to a group/category.
  ///
  /// In en, this message translates to:
  /// **'Set Group'**
  String get radioSetGroup;

  /// Group/category field label.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get radioGroup;

  /// Station name field label.
  ///
  /// In en, this message translates to:
  /// **'Station Name'**
  String get radioStationName;

  /// Stream URL field label.
  ///
  /// In en, this message translates to:
  /// **'Stream URL'**
  String get radioStreamUrl;

  /// Edit-station field: the station logo image URL.
  ///
  /// In en, this message translates to:
  /// **'Logo URL (Optional)'**
  String get radioLogoUrl;

  /// Edit-station field: the station genre/tags.
  ///
  /// In en, this message translates to:
  /// **'Genre (Optional)'**
  String get radioGenre;

  /// Station homepage field label.
  ///
  /// In en, this message translates to:
  /// **'Homepage (Optional)'**
  String get radioHomepage;

  /// Banner shown across the top of the app when the active server cannot be reached.
  ///
  /// In en, this message translates to:
  /// **'Server unreachable. You are offline.'**
  String get appServerUnreachableOffline;

  /// Offline banner action button that opens the downloads screen.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get appDownloads;

  /// Notifications screen title.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get appNotifications;

  /// Notifications screen: action that removes all notifications.
  ///
  /// In en, this message translates to:
  /// **'Clear All'**
  String get appClearAll;

  /// Notifications screen empty state title.
  ///
  /// In en, this message translates to:
  /// **'No notifications'**
  String get appNoNotifications;

  /// Notifications screen: tooltip on the button that dismisses a single notification.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get appDismiss;

  /// Relative time label for a notification that arrived less than a minute ago.
  ///
  /// In en, this message translates to:
  /// **'now'**
  String get appTimeNow;

  /// Relative time label for a notification that arrived a number of minutes ago (abbreviated, e.g. 5m).
  ///
  /// In en, this message translates to:
  /// **'{count}m'**
  String appTimeMinutes(int count);

  /// Relative time label for a notification that arrived a number of hours ago (abbreviated, e.g. 3h).
  ///
  /// In en, this message translates to:
  /// **'{count}h'**
  String appTimeHours(int count);

  /// Relative time label for a notification that arrived a number of days ago (abbreviated, e.g. 2d).
  ///
  /// In en, this message translates to:
  /// **'{count}d'**
  String appTimeDays(int count);

  /// Watch Together: title of the create-group dialog and label of the create-group button.
  ///
  /// In en, this message translates to:
  /// **'Create Group'**
  String get appCreateGroup;

  /// Watch Together: hint for the group name text field.
  ///
  /// In en, this message translates to:
  /// **'Group Name'**
  String get appGroupName;

  /// Confirm button that creates a new group or playlist.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get appCreate;

  /// Watch Together: snackbar confirming a group was created.
  ///
  /// In en, this message translates to:
  /// **'Group created'**
  String get appGroupCreated;

  /// Watch Together: heading for other groups shown while you are already in a group.
  ///
  /// In en, this message translates to:
  /// **'Other Groups'**
  String get appOtherGroups;

  /// Watch Together: heading for joinable groups shown while you are not in a group.
  ///
  /// In en, this message translates to:
  /// **'Open Groups'**
  String get appOpenGroups;

  /// Watch Together: empty message when no other groups exist and you are already in one.
  ///
  /// In en, this message translates to:
  /// **'No other groups on this server.'**
  String get appNoOtherGroups;

  /// Watch Together: empty message when there are no groups to join.
  ///
  /// In en, this message translates to:
  /// **'No active groups yet. Create one above, or ask a friend to create one so it appears here.'**
  String get appNoActiveGroups;

  /// Watch Together (SyncPlay) screen title.
  ///
  /// In en, this message translates to:
  /// **'Watch Together'**
  String get appWatchTogether;

  /// Watch Together: inline error when the group list fails to load, followed by the raw error detail.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load groups. {message}'**
  String appCouldntLoadGroups(String message);

  /// Watch Together: explanatory intro shown when you are not in a group.
  ///
  /// In en, this message translates to:
  /// **'Watch in sync with others on this server. Create a group or join one below, then everyone opens the same title to keep playback aligned.'**
  String get appSyncPlayIntro;

  /// Watch Together: fallback display name for the current group when the server does not provide one.
  ///
  /// In en, this message translates to:
  /// **'Watch Together Group'**
  String get appWatchTogetherGroup;

  /// Watch Together: status line inside the current-group card.
  ///
  /// In en, this message translates to:
  /// **'Connected. Playback will sync while you watch together.'**
  String get appGroupConnected;

  /// Watch Together: heading for the list of group members, with the member count.
  ///
  /// In en, this message translates to:
  /// **'Members ({count})'**
  String appMembers(int count);

  /// Watch Together: button that leaves the current group.
  ///
  /// In en, this message translates to:
  /// **'Leave Group'**
  String get appLeaveGroup;

  /// Watch Together: hint text under the Leave Group button.
  ///
  /// In en, this message translates to:
  /// **'Leaving turns off Watch Together for you; others stay in the group.'**
  String get appLeaveGroupHint;

  /// Watch Together: group row subtitle when the group has no participants.
  ///
  /// In en, this message translates to:
  /// **'No one watching yet'**
  String get appNoOneWatching;

  /// Watch Together: group row subtitle showing how many people are watching and their names.
  ///
  /// In en, this message translates to:
  /// **'{count} watching · {names}'**
  String appWatchingList(int count, String names);

  /// Watch Together: fallback name for a joinable group when the server does not provide one.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get appGroup;

  /// Watch Together: action to join a group.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get appJoin;

  /// Watch Together: label on a group row when you are already in another group and cannot join.
  ///
  /// In en, this message translates to:
  /// **'In a group'**
  String get appInAGroup;

  /// Watch Together: badge on the current-group card indicating the group is active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get appActive;

  /// Title of the create-playlist dialog and label of the new-playlist action.
  ///
  /// In en, this message translates to:
  /// **'New Playlist'**
  String get appNewPlaylist;

  /// Label for the playlist name text field in the create-playlist dialog.
  ///
  /// In en, this message translates to:
  /// **'Playlist Name'**
  String get appPlaylistName;

  /// Snackbar confirming a named playlist was created.
  ///
  /// In en, this message translates to:
  /// **'Created \"{name}\"'**
  String appCreatedNamed(String name);

  /// Playlists screen title.
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get appPlaylists;

  /// Playlists screen empty state title.
  ///
  /// In en, this message translates to:
  /// **'No playlists'**
  String get appNoPlaylists;

  /// Playlists screen empty state message.
  ///
  /// In en, this message translates to:
  /// **'Create a playlist, then add movies, shows, or songs.'**
  String get appNoPlaylistsMessage;

  /// Snackbar confirming a named item was removed from a playlist.
  ///
  /// In en, this message translates to:
  /// **'Removed \"{name}\"'**
  String appRemovedNamed(String name);

  /// Playlist detail: title of the delete-playlist dialog and its menu action.
  ///
  /// In en, this message translates to:
  /// **'Delete Playlist'**
  String get appDeletePlaylist;

  /// Playlist detail: confirmation body when deleting a named playlist.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"? The items stay in your library.'**
  String appDeletePlaylistConfirm(String name);

  /// Snackbar confirming a named playlist was deleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted \"{name}\"'**
  String appDeletedNamed(String name);

  /// Playlist detail empty state title.
  ///
  /// In en, this message translates to:
  /// **'Empty playlist'**
  String get appEmptyPlaylist;

  /// Playlist detail empty state message.
  ///
  /// In en, this message translates to:
  /// **'Add items from any movie, show, or song page.'**
  String get appEmptyPlaylistMessage;

  /// Count of items in a playlist (e.g. 1 item, 5 items).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} item} other{{count} items}}'**
  String appItemsCount(int count);

  /// Snackbar confirming items were added to a named playlist.
  ///
  /// In en, this message translates to:
  /// **'Added to \"{playlist}\"'**
  String appAddedToNamed(String playlist);

  /// Title of the add-to-playlist bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'Add to Playlist'**
  String get appAddToPlaylist;

  /// Add-to-playlist sheet: message when the user has no playlists to add to.
  ///
  /// In en, this message translates to:
  /// **'No playlists yet.'**
  String get appNoPlaylistsYet;

  /// AppBar title for the server administration hub.
  ///
  /// In en, this message translates to:
  /// **'Server Admin'**
  String get adminTitle;

  /// Placeholder text in the admin search box.
  ///
  /// In en, this message translates to:
  /// **'Search server settings'**
  String get adminSearchHint;

  /// Empty state shown when an admin search returns no results.
  ///
  /// In en, this message translates to:
  /// **'No settings match “{query}”'**
  String adminNoMatch(String query);

  /// Admin hub group header: server configuration sections.
  ///
  /// In en, this message translates to:
  /// **'Server Configuration'**
  String get adminSectionServerConfig;

  /// Admin hub group header: content and access sections.
  ///
  /// In en, this message translates to:
  /// **'Content & Access'**
  String get adminSectionContentAccess;

  /// Admin hub group header (and section label): Live TV.
  ///
  /// In en, this message translates to:
  /// **'Live TV'**
  String get adminSectionLiveTv;

  /// Admin hub group header: maintenance sections.
  ///
  /// In en, this message translates to:
  /// **'Maintenance'**
  String get adminSectionMaintenance;

  /// Admin hub group header: extensions (plugins).
  ///
  /// In en, this message translates to:
  /// **'Extensions'**
  String get adminSectionExtensions;

  /// Admin section title: general server settings.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get adminGeneralTitle;

  /// Admin hub tile subtitle for General settings.
  ///
  /// In en, this message translates to:
  /// **'Name, language, display, resume'**
  String get adminGeneralSubtitle;

  /// Admin section title: playback / transcoding settings.
  ///
  /// In en, this message translates to:
  /// **'Playback'**
  String get adminPlaybackTitle;

  /// Admin hub tile subtitle for Playback settings.
  ///
  /// In en, this message translates to:
  /// **'Transcoding & hardware acceleration'**
  String get adminPlaybackSubtitle;

  /// Admin section title: branding (splash, login message, custom CSS).
  ///
  /// In en, this message translates to:
  /// **'Branding'**
  String get adminBrandingTitle;

  /// Admin hub tile subtitle for Branding settings.
  ///
  /// In en, this message translates to:
  /// **'Splash, login message & custom CSS'**
  String get adminBrandingSubtitle;

  /// Admin section title: networking settings.
  ///
  /// In en, this message translates to:
  /// **'Networking'**
  String get adminNetworkingTitle;

  /// Admin hub tile subtitle for Networking settings.
  ///
  /// In en, this message translates to:
  /// **'Remote access, published URL, ports'**
  String get adminNetworkingSubtitle;

  /// Admin screen title: server backups.
  ///
  /// In en, this message translates to:
  /// **'Backups'**
  String get adminBackupsTitle;

  /// Admin hub subtitle for the Backups screen.
  ///
  /// In en, this message translates to:
  /// **'Create and restore snapshots of the server'**
  String get adminBackupsSubtitle;

  /// Intro text at the top of the Backups screen.
  ///
  /// In en, this message translates to:
  /// **'Create and restore snapshots of your server. A backup can include the database, metadata, subtitles, and trickplay images, and is stored on the server.'**
  String get adminBackupsHelp;

  /// Empty state on the Backups screen.
  ///
  /// In en, this message translates to:
  /// **'No backups yet'**
  String get adminBackupsNone;

  /// Shown when the server has no backup API.
  ///
  /// In en, this message translates to:
  /// **'This server does not offer backups. They need a newer version of Jellyfin.'**
  String get adminBackupsUnsupported;

  /// Button and dialog title: make a new server backup.
  ///
  /// In en, this message translates to:
  /// **'Create Backup'**
  String get adminBackupCreate;

  /// Note in the Create Backup dialog.
  ///
  /// In en, this message translates to:
  /// **'Depending on the size of your library, a backup can take a while.'**
  String get adminBackupDisclaimer;

  /// Backup content option: the server database. Always included.
  ///
  /// In en, this message translates to:
  /// **'Database'**
  String get adminBackupDatabase;

  /// Backup content option: metadata such as artwork and NFO data.
  ///
  /// In en, this message translates to:
  /// **'Metadata'**
  String get adminBackupMetadata;

  /// Backup content option: subtitles stored by the server.
  ///
  /// In en, this message translates to:
  /// **'Subtitles'**
  String get adminBackupSubtitles;

  /// Backup content option: trickplay scrubbing images.
  ///
  /// In en, this message translates to:
  /// **'Trickplay'**
  String get adminBackupTrickplay;

  /// Title of the dialog shown while a backup is being written.
  ///
  /// In en, this message translates to:
  /// **'Backup in progress'**
  String get adminBackupInProgress;

  /// Confirmation after a backup finishes.
  ///
  /// In en, this message translates to:
  /// **'Backup created'**
  String get adminBackupCreated;

  /// Title of the warning shown when creating a backup while tasks run.
  ///
  /// In en, this message translates to:
  /// **'Scheduled tasks are running'**
  String get adminBackupTasksRunning;

  /// Warning body listing running scheduled tasks.
  ///
  /// In en, this message translates to:
  /// **'It is best to wait for these to finish, or stop them, before backing up:\n\n{tasks}'**
  String adminBackupTasksRunningBody(String tasks);

  /// Title of the sheet showing one backup's details.
  ///
  /// In en, this message translates to:
  /// **'Backup Details'**
  String get adminBackupDetails;

  /// Label for where a backup is stored on the server.
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get adminBackupPath;

  /// Label for the Jellyfin version a backup was made on.
  ///
  /// In en, this message translates to:
  /// **'Server Version'**
  String get adminBackupServerVersion;

  /// Label for what a backup contains.
  ///
  /// In en, this message translates to:
  /// **'Includes'**
  String get adminBackupIncludes;

  /// Confirmation after copying a backup's path.
  ///
  /// In en, this message translates to:
  /// **'Path copied'**
  String get adminBackupPathCopied;

  /// Action: restore the server from a backup.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get adminBackupRestore;

  /// Confirmation title before restoring a backup.
  ///
  /// In en, this message translates to:
  /// **'Restore This Backup?'**
  String get adminBackupRestoreTitle;

  /// Warning before restoring a backup.
  ///
  /// In en, this message translates to:
  /// **'The server restarts and is unusable until the restore finishes, and anything added or changed since this backup was made is lost.\n\nOnly restore a backup onto the same Jellyfin version it was made on ({version}). Restoring onto a different version is unsupported and can leave the server unusable.'**
  String adminBackupRestoreBody(String version);

  /// Title of the dialog shown while the server restores.
  ///
  /// In en, this message translates to:
  /// **'Restore in progress'**
  String get adminBackupRestoring;

  /// Body of the restore progress dialog.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the server to come back. This can take several minutes.'**
  String get adminBackupRestoringBody;

  /// Confirmation when the server is back after a restore.
  ///
  /// In en, this message translates to:
  /// **'Restore complete'**
  String get adminBackupRestored;

  /// Admin section title: API keys (app access tokens).
  ///
  /// In en, this message translates to:
  /// **'API Keys'**
  String get adminApiKeysTitle;

  /// Admin hub tile subtitle for API Keys.
  ///
  /// In en, this message translates to:
  /// **'App access tokens'**
  String get adminApiKeysSubtitle;

  /// Admin section title (and section label): media libraries.
  ///
  /// In en, this message translates to:
  /// **'Libraries'**
  String get adminLibrariesTitle;

  /// Admin hub tile subtitle for Libraries.
  ///
  /// In en, this message translates to:
  /// **'Media folders and scans'**
  String get adminLibrariesSubtitle;

  /// Admin section title: user accounts.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get adminUsersTitle;

  /// Admin hub tile subtitle for Users.
  ///
  /// In en, this message translates to:
  /// **'Accounts and permissions'**
  String get adminUsersSubtitle;

  /// Admin section title (and section label): client devices.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get adminDevicesTitle;

  /// Admin hub tile subtitle for Devices.
  ///
  /// In en, this message translates to:
  /// **'Registered client devices'**
  String get adminDevicesSubtitle;

  /// Admin section title: active client sessions.
  ///
  /// In en, this message translates to:
  /// **'Active Sessions'**
  String get adminSessionsTitle;

  /// Admin hub tile subtitle for Active Sessions.
  ///
  /// In en, this message translates to:
  /// **'Who is connected now'**
  String get adminSessionsSubtitle;

  /// Admin section title: Live TV (tuners and guide).
  ///
  /// In en, this message translates to:
  /// **'Live TV'**
  String get adminLiveTvTitle;

  /// Admin hub tile subtitle for Live TV.
  ///
  /// In en, this message translates to:
  /// **'Tuners and TV guide'**
  String get adminLiveTvSubtitle;

  /// Admin section title: DVR (recordings).
  ///
  /// In en, this message translates to:
  /// **'DVR'**
  String get adminDvrTitle;

  /// Admin hub tile subtitle for DVR.
  ///
  /// In en, this message translates to:
  /// **'Scheduled, series & recordings'**
  String get adminDvrSubtitle;

  /// Admin section title: scheduled background tasks.
  ///
  /// In en, this message translates to:
  /// **'Scheduled Tasks'**
  String get adminTasksTitle;

  /// Admin hub tile subtitle for Scheduled Tasks.
  ///
  /// In en, this message translates to:
  /// **'Run and review background jobs'**
  String get adminTasksSubtitle;

  /// Admin section title: server activity log.
  ///
  /// In en, this message translates to:
  /// **'Activity Log'**
  String get adminActivityTitle;

  /// Admin hub tile subtitle for Activity Log.
  ///
  /// In en, this message translates to:
  /// **'Recent server events'**
  String get adminActivitySubtitle;

  /// Admin section title: server log files.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get adminLogsTitle;

  /// Admin hub tile subtitle for Logs.
  ///
  /// In en, this message translates to:
  /// **'Server log files'**
  String get adminLogsSubtitle;

  /// Admin section title: system info, restart and shutdown.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get adminSystemTitle;

  /// Admin hub tile subtitle for System.
  ///
  /// In en, this message translates to:
  /// **'Server info, restart & shutdown'**
  String get adminSystemSubtitle;

  /// Admin section title: plugins.
  ///
  /// In en, this message translates to:
  /// **'Plugins'**
  String get adminPluginsTitle;

  /// Admin hub tile subtitle for Plugins.
  ///
  /// In en, this message translates to:
  /// **'Installed, catalog & repositories'**
  String get adminPluginsSubtitle;

  /// Generic empty state for an admin list with no items.
  ///
  /// In en, this message translates to:
  /// **'Nothing here.'**
  String get adminNothingHere;

  /// Confirmation dialog title for restarting the server.
  ///
  /// In en, this message translates to:
  /// **'Restart Server?'**
  String get adminRestartServerConfirmTitle;

  /// Confirmation dialog title for shutting down the server.
  ///
  /// In en, this message translates to:
  /// **'Shut Down Server?'**
  String get adminShutDownServerConfirmTitle;

  /// Confirmation dialog body for restarting the server.
  ///
  /// In en, this message translates to:
  /// **'The Jellyfin server will restart.'**
  String get adminRestartServerConfirmBody;

  /// Confirmation dialog body for shutting down the server.
  ///
  /// In en, this message translates to:
  /// **'The Jellyfin server will shut down and become unreachable.'**
  String get adminShutDownServerConfirmBody;

  /// Button label: restart the server.
  ///
  /// In en, this message translates to:
  /// **'Restart'**
  String get adminRestart;

  /// Button label: shut down the server.
  ///
  /// In en, this message translates to:
  /// **'Shut Down'**
  String get adminShutDown;

  /// Snackbar confirming a server restart was requested.
  ///
  /// In en, this message translates to:
  /// **'Restart requested'**
  String get adminRestartRequested;

  /// Snackbar confirming a server shutdown was requested.
  ///
  /// In en, this message translates to:
  /// **'Shutdown requested'**
  String get adminShutdownRequested;

  /// System info list label: server name.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get adminServerLabel;

  /// System info list label: server version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get adminVersionLabel;

  /// System info list label: operating system.
  ///
  /// In en, this message translates to:
  /// **'Operating System'**
  String get adminOperatingSystemLabel;

  /// System info list label: CPU architecture.
  ///
  /// In en, this message translates to:
  /// **'Architecture'**
  String get adminArchitectureLabel;

  /// Dialog title and list action: create a new user.
  ///
  /// In en, this message translates to:
  /// **'Create User'**
  String get adminCreateUser;

  /// Text field label: account username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get adminUsername;

  /// Text field label: account password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get adminPassword;

  /// Text field label: optional password when creating a user.
  ///
  /// In en, this message translates to:
  /// **'Password (optional)'**
  String get adminPasswordOptional;

  /// Button label: create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get adminCreate;

  /// Snackbar after creating a user.
  ///
  /// In en, this message translates to:
  /// **'Created \"{name}\"'**
  String adminCreatedUser(String name);

  /// Fallback user screen title, and the non-administrator role label.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get adminUser;

  /// User role label: administrator.
  ///
  /// In en, this message translates to:
  /// **'Administrator'**
  String get adminUserAdministrator;

  /// User status label: the account is disabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get adminUserDisabled;

  /// Button label: trigger a scan of all libraries.
  ///
  /// In en, this message translates to:
  /// **'Scan All Libraries'**
  String get adminScanAllLibraries;

  /// Tooltip: scan just this one library.
  ///
  /// In en, this message translates to:
  /// **'Scan This Library'**
  String get adminScanThisLibrary;

  /// Snackbar confirming a full library scan started.
  ///
  /// In en, this message translates to:
  /// **'Library scan started'**
  String get adminLibraryScanStarted;

  /// Snackbar confirming a scan of a specific library started.
  ///
  /// In en, this message translates to:
  /// **'Scanning {name}'**
  String adminScanningLibrary(String name);

  /// Fallback word used in place of a missing library name in a scan message.
  ///
  /// In en, this message translates to:
  /// **'library'**
  String get adminLibraryFallback;

  /// Fallback collection type shown when a library has no declared type.
  ///
  /// In en, this message translates to:
  /// **'mixed'**
  String get adminCollectionTypeMixed;

  /// Library list subtitle: collection type and folder count.
  ///
  /// In en, this message translates to:
  /// **'{type} · {count, plural, =1{1 folder} other{{count} folders}}'**
  String adminLibrarySubtitle(String type, int count);

  /// Tooltip: run a scheduled task now.
  ///
  /// In en, this message translates to:
  /// **'Run Now'**
  String get adminRunNow;

  /// Snackbar after starting a scheduled task.
  ///
  /// In en, this message translates to:
  /// **'Started: {name}'**
  String adminTaskStarted(String name);

  /// Dialog title and tooltip: send a message to a session.
  ///
  /// In en, this message translates to:
  /// **'Send Message'**
  String get adminSendMessage;

  /// Text field placeholder for a message to send to a session.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get adminMessageHint;

  /// Button label: send the message.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get adminSend;

  /// Header of a message pushed to a client session.
  ///
  /// In en, this message translates to:
  /// **'Message from {name}'**
  String adminMessageFrom(String name);

  /// Snackbar confirming a session message was sent.
  ///
  /// In en, this message translates to:
  /// **'Message sent'**
  String get adminMessageSent;

  /// Fallback shown when a session has no known user name.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get adminUnknownUser;

  /// Field label: the server's display name.
  ///
  /// In en, this message translates to:
  /// **'Server Name'**
  String get adminServerName;

  /// Section label: server settings group.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get adminSectionServer;

  /// Section label: metadata settings group.
  ///
  /// In en, this message translates to:
  /// **'Metadata'**
  String get adminSectionMetadata;

  /// Field label: preferred metadata language.
  ///
  /// In en, this message translates to:
  /// **'Preferred Metadata Language'**
  String get adminPreferredMetadataLanguage;

  /// Example hint for a language code field.
  ///
  /// In en, this message translates to:
  /// **'e.g. en'**
  String get adminMetadataLanguageHint;

  /// Field label: metadata country.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get adminCountry;

  /// Example hint for a country code field.
  ///
  /// In en, this message translates to:
  /// **'e.g. US'**
  String get adminCountryHint;

  /// Section label: library display settings group.
  ///
  /// In en, this message translates to:
  /// **'Library Display'**
  String get adminSectionLibraryDisplay;

  /// Toggle label: show a plain folder browse view.
  ///
  /// In en, this message translates to:
  /// **'Show Folder View'**
  String get adminShowFolderView;

  /// Subtitle for the Show Folder View toggle.
  ///
  /// In en, this message translates to:
  /// **'Add a plain folder browse view'**
  String get adminShowFolderViewSubtitle;

  /// Toggle label: save metadata files as hidden.
  ///
  /// In en, this message translates to:
  /// **'Save Metadata as Hidden Files'**
  String get adminSaveMetadataHidden;

  /// Toggle label: include external content in suggestions.
  ///
  /// In en, this message translates to:
  /// **'External Content in Suggestions'**
  String get adminExternalContentSuggestions;

  /// Section label: playback resume settings group.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get adminSectionResume;

  /// Field label: minimum resume percentage.
  ///
  /// In en, this message translates to:
  /// **'Minimum Resume %'**
  String get adminMinResumePct;

  /// Field label: maximum resume percentage.
  ///
  /// In en, this message translates to:
  /// **'Maximum Resume %'**
  String get adminMaxResumePct;

  /// Field label: minimum resume duration in seconds.
  ///
  /// In en, this message translates to:
  /// **'Minimum Resume Duration (s)'**
  String get adminMinResumeDuration;

  /// Section label: access settings group.
  ///
  /// In en, this message translates to:
  /// **'Access'**
  String get adminSectionAccess;

  /// Toggle label: enable Quick Connect sign-in.
  ///
  /// In en, this message translates to:
  /// **'Quick Connect'**
  String get adminQuickConnect;

  /// Subtitle for the Quick Connect toggle.
  ///
  /// In en, this message translates to:
  /// **'Let users sign in with a code from an already-authorized device'**
  String get adminQuickConnectSubtitle;

  /// Branding section heading: splash screen.
  ///
  /// In en, this message translates to:
  /// **'Splash Screen'**
  String get adminSplashScreen;

  /// Hint about recommended splash screen image dimensions.
  ///
  /// In en, this message translates to:
  /// **'Custom images should be 16:9, at least 1920x1080.'**
  String get adminSplashHint;

  /// Button label: upload an image.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get adminUpload;

  /// Toggle label: enable the custom splash screen image.
  ///
  /// In en, this message translates to:
  /// **'Enable Splash Screen Image'**
  String get adminEnableSplashImage;

  /// Field label: login page disclaimer text.
  ///
  /// In en, this message translates to:
  /// **'Login Disclaimer'**
  String get adminLoginDisclaimer;

  /// Helper text under the login disclaimer field.
  ///
  /// In en, this message translates to:
  /// **'Shown at the bottom of the sign-in page'**
  String get adminLoginDisclaimerHelper;

  /// Field label: custom CSS (CSS is a technical token).
  ///
  /// In en, this message translates to:
  /// **'Custom CSS'**
  String get adminCustomCss;

  /// Section label: hardware acceleration settings group.
  ///
  /// In en, this message translates to:
  /// **'Hardware Acceleration'**
  String get adminSectionHardwareAccel;

  /// Dropdown label: hardware acceleration type.
  ///
  /// In en, this message translates to:
  /// **'Acceleration'**
  String get adminAcceleration;

  /// Hardware acceleration option: none.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get adminAccelNone;

  /// Toggle label: enable hardware encoding.
  ///
  /// In en, this message translates to:
  /// **'Enable Hardware Encoding'**
  String get adminEnableHwEncoding;

  /// Toggle label: enable tone mapping.
  ///
  /// In en, this message translates to:
  /// **'Enable Tone Mapping'**
  String get adminEnableToneMapping;

  /// Toggle label: enable VPP tone mapping (VPP is a technical token).
  ///
  /// In en, this message translates to:
  /// **'Enable VPP Tone Mapping'**
  String get adminEnableVppToneMapping;

  /// Toggle label: allow HEVC encoding (HEVC is a codec token).
  ///
  /// In en, this message translates to:
  /// **'Allow HEVC Encoding'**
  String get adminAllowHevcEncoding;

  /// Toggle label: allow AV1 encoding (AV1 is a codec token).
  ///
  /// In en, this message translates to:
  /// **'Allow AV1 Encoding'**
  String get adminAllowAv1Encoding;

  /// Section label: encoding settings group.
  ///
  /// In en, this message translates to:
  /// **'Encoding'**
  String get adminSectionEncoding;

  /// Dropdown label: FFmpeg encoder preset.
  ///
  /// In en, this message translates to:
  /// **'Encoder Preset'**
  String get adminEncoderPreset;

  /// Encoder preset option: automatic.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get adminPresetAuto;

  /// Field label: H.264 CRF quality value (technical tokens).
  ///
  /// In en, this message translates to:
  /// **'H.264 CRF'**
  String get adminH264Crf;

  /// Field label: H.265 CRF quality value (technical tokens).
  ///
  /// In en, this message translates to:
  /// **'H.265 CRF'**
  String get adminH265Crf;

  /// Field label: transcoding thread count, 0 means auto.
  ///
  /// In en, this message translates to:
  /// **'Transcode Thread Count (0 = auto)'**
  String get adminTranscodeThreadCount;

  /// Toggle label: enable subtitle extraction.
  ///
  /// In en, this message translates to:
  /// **'Enable Subtitle Extraction'**
  String get adminEnableSubtitleExtraction;

  /// Section label: transcode throttling settings group.
  ///
  /// In en, this message translates to:
  /// **'Throttling'**
  String get adminSectionThrottling;

  /// Toggle label: throttle transcodes.
  ///
  /// In en, this message translates to:
  /// **'Throttle Transcodes'**
  String get adminThrottleTranscodes;

  /// Subtitle for the Throttle Transcodes toggle.
  ///
  /// In en, this message translates to:
  /// **'Pause transcoding when far enough ahead'**
  String get adminThrottleTranscodesSubtitle;

  /// Field label: throttle delay in seconds.
  ///
  /// In en, this message translates to:
  /// **'Throttle Delay (s)'**
  String get adminThrottleDelay;

  /// Section label: trickplay (scrub preview) settings group.
  ///
  /// In en, this message translates to:
  /// **'Trickplay'**
  String get adminSectionTrickplay;

  /// Toggle label: hardware-accelerated trickplay generation.
  ///
  /// In en, this message translates to:
  /// **'Hardware Accelerated Generation'**
  String get adminTrickplayHwGeneration;

  /// Toggle label: hardware-accelerated trickplay encoding.
  ///
  /// In en, this message translates to:
  /// **'Hardware Accelerated Encoding'**
  String get adminTrickplayHwEncoding;

  /// Toggle label: extract only keyframes for trickplay.
  ///
  /// In en, this message translates to:
  /// **'Keyframe-Only Extraction'**
  String get adminKeyframeOnlyExtraction;

  /// Subtitle for the Keyframe-Only Extraction toggle.
  ///
  /// In en, this message translates to:
  /// **'Faster, less precise scrubbing'**
  String get adminKeyframeOnlyExtractionSubtitle;

  /// Dropdown label: trickplay scan behavior.
  ///
  /// In en, this message translates to:
  /// **'Scan Behavior'**
  String get adminScanBehavior;

  /// Scan behavior option: non-blocking, during the scan.
  ///
  /// In en, this message translates to:
  /// **'Non-Blocking (during scan)'**
  String get adminScanBehaviorNonBlocking;

  /// Scan behavior option: blocking, before the scan finishes.
  ///
  /// In en, this message translates to:
  /// **'Blocking (before scan finishes)'**
  String get adminScanBehaviorBlocking;

  /// Dropdown label: trickplay process priority.
  ///
  /// In en, this message translates to:
  /// **'Process Priority'**
  String get adminProcessPriority;

  /// Process priority option: high.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get adminPriorityHigh;

  /// Process priority option: above normal.
  ///
  /// In en, this message translates to:
  /// **'Above Normal'**
  String get adminPriorityAboveNormal;

  /// Process priority option: normal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get adminPriorityNormal;

  /// Process priority option: below normal.
  ///
  /// In en, this message translates to:
  /// **'Below Normal'**
  String get adminPriorityBelowNormal;

  /// Process priority option: idle.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get adminPriorityIdle;

  /// Field label: trickplay interval in milliseconds.
  ///
  /// In en, this message translates to:
  /// **'Interval (ms)'**
  String get adminInterval;

  /// Field label: trickplay width resolutions list.
  ///
  /// In en, this message translates to:
  /// **'Width Resolutions'**
  String get adminWidthResolutions;

  /// Hint: enter comma-separated widths.
  ///
  /// In en, this message translates to:
  /// **'comma-separated, e.g. 320'**
  String get adminWidthResolutionsHint;

  /// Field label: trickplay tile width in thumbnails.
  ///
  /// In en, this message translates to:
  /// **'Tile Width (thumbnails)'**
  String get adminTileWidth;

  /// Field label: trickplay tile height in thumbnails.
  ///
  /// In en, this message translates to:
  /// **'Tile Height (thumbnails)'**
  String get adminTileHeight;

  /// Field label: trickplay JPEG quality (JPEG is a token).
  ///
  /// In en, this message translates to:
  /// **'JPEG Quality (0-100)'**
  String get adminJpegQuality;

  /// Field label: trickplay process threads, 0 means auto.
  ///
  /// In en, this message translates to:
  /// **'Process Threads (0 = auto)'**
  String get adminProcessThreads;

  /// Button label: start trickplay image generation now.
  ///
  /// In en, this message translates to:
  /// **'Generate Trickplay Images Now'**
  String get adminGenerateTrickplayNow;

  /// Hint below the Generate Trickplay button.
  ///
  /// In en, this message translates to:
  /// **'Save first, then generate. This runs in the background and can take a while on large libraries.'**
  String get adminTrickplayGenerateHint;

  /// Snackbar: the server has no trickplay generation task.
  ///
  /// In en, this message translates to:
  /// **'No trickplay task found on the server'**
  String get adminNoTrickplayTask;

  /// Snackbar confirming trickplay generation started.
  ///
  /// In en, this message translates to:
  /// **'Generating trickplay images (runs in the background)'**
  String get adminGeneratingTrickplay;

  /// Section label: file paths settings group.
  ///
  /// In en, this message translates to:
  /// **'Paths'**
  String get adminSectionPaths;

  /// Field label: transcoding temporary files path.
  ///
  /// In en, this message translates to:
  /// **'Transcoding Temp Path'**
  String get adminTranscodingTempPath;

  /// Field hint: leave blank to use the default.
  ///
  /// In en, this message translates to:
  /// **'Leave blank for default'**
  String get adminHintLeaveBlankDefault;

  /// Section label: remote access settings group.
  ///
  /// In en, this message translates to:
  /// **'Remote Access'**
  String get adminSectionRemoteAccess;

  /// Toggle label: allow remote connections.
  ///
  /// In en, this message translates to:
  /// **'Allow Remote Connections'**
  String get adminAllowRemoteConnections;

  /// Field label: server base URL path.
  ///
  /// In en, this message translates to:
  /// **'Base URL'**
  String get adminBaseUrl;

  /// Section label: HTTPS settings group (HTTPS is a token).
  ///
  /// In en, this message translates to:
  /// **'HTTPS'**
  String get adminSectionHttps;

  /// Toggle label: enable HTTPS.
  ///
  /// In en, this message translates to:
  /// **'Enable HTTPS'**
  String get adminEnableHttps;

  /// Toggle label: require HTTPS.
  ///
  /// In en, this message translates to:
  /// **'Require HTTPS'**
  String get adminRequireHttps;

  /// Field label: TLS certificate file path.
  ///
  /// In en, this message translates to:
  /// **'Certificate Path'**
  String get adminCertificatePath;

  /// Hint for the certificate path field (PFX is a token).
  ///
  /// In en, this message translates to:
  /// **'PFX file on the server'**
  String get adminCertificatePathHint;

  /// Field label: certificate password.
  ///
  /// In en, this message translates to:
  /// **'Certificate Password'**
  String get adminCertificatePassword;

  /// Section label: network ports settings group.
  ///
  /// In en, this message translates to:
  /// **'Ports'**
  String get adminSectionPorts;

  /// Field label: internal HTTP port.
  ///
  /// In en, this message translates to:
  /// **'HTTP Port'**
  String get adminHttpPort;

  /// Field label: internal HTTPS port.
  ///
  /// In en, this message translates to:
  /// **'HTTPS Port'**
  String get adminHttpsPort;

  /// Field label: public HTTP port.
  ///
  /// In en, this message translates to:
  /// **'Public HTTP Port'**
  String get adminPublicHttpPort;

  /// Field label: public HTTPS port.
  ///
  /// In en, this message translates to:
  /// **'Public HTTPS Port'**
  String get adminPublicHttpsPort;

  /// Section label: network discovery settings group.
  ///
  /// In en, this message translates to:
  /// **'Discovery'**
  String get adminSectionDiscovery;

  /// Toggle label: enable UPnP (UPnP is a token).
  ///
  /// In en, this message translates to:
  /// **'Enable UPnP'**
  String get adminEnableUpnp;

  /// Toggle label: enable autodiscovery.
  ///
  /// In en, this message translates to:
  /// **'Enable Autodiscovery'**
  String get adminEnableAutodiscovery;

  /// Section label: advanced settings group.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get adminSectionAdvanced;

  /// Toggle label: enable IPv6 (IPv6 is a token).
  ///
  /// In en, this message translates to:
  /// **'Enable IPv6'**
  String get adminEnableIpv6;

  /// Field label: known reverse-proxy addresses.
  ///
  /// In en, this message translates to:
  /// **'Known Proxies'**
  String get adminKnownProxies;

  /// Hint for the known proxies field.
  ///
  /// In en, this message translates to:
  /// **'comma-separated, for reverse proxies'**
  String get adminKnownProxiesHint;

  /// Field label: local network subnets.
  ///
  /// In en, this message translates to:
  /// **'LAN Networks'**
  String get adminLanNetworks;

  /// Hint for the LAN networks field (CIDR example is technical).
  ///
  /// In en, this message translates to:
  /// **'comma-separated CIDR, e.g. 192.168.1.0/24'**
  String get adminLanNetworksHint;

  /// Dialog title: create a new API key.
  ///
  /// In en, this message translates to:
  /// **'New API Key'**
  String get adminNewApiKey;

  /// Field label: name of the app the API key is for.
  ///
  /// In en, this message translates to:
  /// **'App Name'**
  String get adminAppName;

  /// Confirmation dialog title: revoke an API key.
  ///
  /// In en, this message translates to:
  /// **'Revoke API Key?'**
  String get adminRevokeApiKeyConfirm;

  /// Confirmation dialog body: revoking an API key.
  ///
  /// In en, this message translates to:
  /// **'Apps using this key will lose access.'**
  String get adminRevokeApiKeyBody;

  /// Button and tooltip: revoke an API key.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get adminRevoke;

  /// Floating action button label: create a new API key.
  ///
  /// In en, this message translates to:
  /// **'New Key'**
  String get adminNewKey;

  /// Empty state: no API keys exist.
  ///
  /// In en, this message translates to:
  /// **'No API keys.'**
  String get adminNoApiKeys;

  /// Empty state: no server log files.
  ///
  /// In en, this message translates to:
  /// **'No log files.'**
  String get adminNoLogFiles;

  /// Plugins tab: installed plugins.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get adminTabInstalled;

  /// Plugins tab: plugin catalog.
  ///
  /// In en, this message translates to:
  /// **'Catalog'**
  String get adminTabCatalog;

  /// Plugins tab: plugin repositories.
  ///
  /// In en, this message translates to:
  /// **'Repositories'**
  String get adminTabRepositories;

  /// Button and tooltip: uninstall a plugin.
  ///
  /// In en, this message translates to:
  /// **'Uninstall'**
  String get adminUninstall;

  /// Confirmation dialog title: uninstall a named plugin.
  ///
  /// In en, this message translates to:
  /// **'Uninstall {name}?'**
  String adminUninstallConfirm(String name);

  /// Confirmation dialog body: uninstalling a plugin.
  ///
  /// In en, this message translates to:
  /// **'The plugin will be removed. A server restart may be required.'**
  String get adminUninstallBody;

  /// Snackbar after uninstalling a plugin.
  ///
  /// In en, this message translates to:
  /// **'Uninstalled {name}'**
  String adminUninstalledPlugin(String name);

  /// Empty state: no plugins installed.
  ///
  /// In en, this message translates to:
  /// **'No plugins installed.'**
  String get adminNoPlugins;

  /// Button label: install a plugin.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get adminInstall;

  /// Button label: install the latest version of a plugin.
  ///
  /// In en, this message translates to:
  /// **'Install Latest'**
  String get adminInstallLatest;

  /// Snackbar after starting a plugin install.
  ///
  /// In en, this message translates to:
  /// **'Installing {name}. A restart may be required.'**
  String adminInstallingPlugin(String name);

  /// Empty state: no plugin packages available.
  ///
  /// In en, this message translates to:
  /// **'No packages available. Add a repository to browse plugins.'**
  String get adminNoPackages;

  /// Dialog title and button: add a plugin repository.
  ///
  /// In en, this message translates to:
  /// **'Add Repository'**
  String get adminAddRepository;

  /// Generic field label: name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get adminName;

  /// Field label: plugin repository manifest URL.
  ///
  /// In en, this message translates to:
  /// **'Manifest URL'**
  String get adminManifestUrl;

  /// Empty state: no plugin repositories configured.
  ///
  /// In en, this message translates to:
  /// **'No repositories configured.'**
  String get adminNoRepositories;

  /// Plugin detail: installed version.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String adminPluginVersion(String version);

  /// Heading: raw plugin configuration in JSON.
  ///
  /// In en, this message translates to:
  /// **'Configuration (JSON)'**
  String get adminConfigJson;

  /// Hint under the raw plugin configuration editor.
  ///
  /// In en, this message translates to:
  /// **'Advanced: edit this plugin’s raw configuration.'**
  String get adminConfigJsonHint;

  /// Heading above the generated plugin settings form.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get adminPluginSettings;

  /// Subtitle under the plugin settings heading.
  ///
  /// In en, this message translates to:
  /// **'Edit this plugin’s configuration.'**
  String get adminPluginSettingsHint;

  /// Toggle: switch the plugin config editor to raw JSON.
  ///
  /// In en, this message translates to:
  /// **'Edit as JSON'**
  String get adminEditAsJson;

  /// Shown for an empty list field in the plugin settings form.
  ///
  /// In en, this message translates to:
  /// **'No entries'**
  String get adminNoEntries;

  /// Label for a complex plugin setting edited as raw JSON.
  ///
  /// In en, this message translates to:
  /// **'Advanced (JSON)'**
  String get adminAdvancedJson;

  /// Button label: save the plugin configuration.
  ///
  /// In en, this message translates to:
  /// **'Save Configuration'**
  String get adminSaveConfiguration;

  /// Shown when a plugin exposes no editable configuration.
  ///
  /// In en, this message translates to:
  /// **'This plugin has no editable configuration.'**
  String get adminNoEditableConfig;

  /// Snackbar: the edited plugin configuration is not valid JSON.
  ///
  /// In en, this message translates to:
  /// **'Configuration is not valid JSON.'**
  String get adminInvalidJson;

  /// Plugin package detail: authored by owner.
  ///
  /// In en, this message translates to:
  /// **'by {owner}'**
  String adminPackageBy(String owner);

  /// Heading: available plugin versions.
  ///
  /// In en, this message translates to:
  /// **'Versions'**
  String get adminVersions;

  /// Dropdown label: tuner type.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get adminType;

  /// Dialog title and button: add a Live TV tuner.
  ///
  /// In en, this message translates to:
  /// **'Add Tuner'**
  String get adminAddTuner;

  /// Dialog title: edit a Live TV tuner.
  ///
  /// In en, this message translates to:
  /// **'Edit Tuner'**
  String get adminEditTuner;

  /// Tuner type: M3U (M3U is a token).
  ///
  /// In en, this message translates to:
  /// **'M3U Tuner'**
  String get adminM3uTuner;

  /// Field label: M3U playlist URL.
  ///
  /// In en, this message translates to:
  /// **'M3U URL'**
  String get adminM3uUrl;

  /// Field label: tuner device URL.
  ///
  /// In en, this message translates to:
  /// **'Device URL'**
  String get adminDeviceUrl;

  /// Field label: optional friendly name for a tuner.
  ///
  /// In en, this message translates to:
  /// **'Friendly Name'**
  String get adminFriendlyName;

  /// Field hint: this field is optional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get adminHintOptional;

  /// Dialog title and button: add a TV guide provider.
  ///
  /// In en, this message translates to:
  /// **'Add Guide Provider'**
  String get adminAddGuideProvider;

  /// Subtitle for the XMLTV guide provider option.
  ///
  /// In en, this message translates to:
  /// **'A guide file or URL'**
  String get adminXmltvSubtitle;

  /// Subtitle for the Schedules Direct guide provider option.
  ///
  /// In en, this message translates to:
  /// **'Sign in and pick your lineup'**
  String get adminScdSubtitle;

  /// Dialog title: edit an XMLTV guide.
  ///
  /// In en, this message translates to:
  /// **'Edit XMLTV Guide'**
  String get adminEditXmltvGuide;

  /// Dialog title: add an XMLTV guide.
  ///
  /// In en, this message translates to:
  /// **'Add XMLTV Guide'**
  String get adminAddXmltvGuide;

  /// Field label: XMLTV guide file path or URL.
  ///
  /// In en, this message translates to:
  /// **'XMLTV File Path or URL'**
  String get adminXmltvPathLabel;

  /// Confirmation dialog title: remove the named thing.
  ///
  /// In en, this message translates to:
  /// **'Remove {what}?'**
  String adminRemoveConfirm(String what);

  /// Phrase inserted into the remove-confirmation for a tuner.
  ///
  /// In en, this message translates to:
  /// **'this tuner'**
  String get adminWhatTuner;

  /// Phrase inserted into the remove-confirmation for a guide provider.
  ///
  /// In en, this message translates to:
  /// **'this guide provider'**
  String get adminWhatGuideProvider;

  /// Confirmation body: removal affects the server, not just this client.
  ///
  /// In en, this message translates to:
  /// **'This removes it from the server, not just from this client.'**
  String get adminRemoveFromServerBody;

  /// Empty state: no Live TV tuners configured.
  ///
  /// In en, this message translates to:
  /// **'No tuners configured.'**
  String get adminNoTuners;

  /// Empty state: no TV guide providers configured.
  ///
  /// In en, this message translates to:
  /// **'No guide providers configured.'**
  String get adminNoGuideProviders;

  /// Live TV tab: tuners.
  ///
  /// In en, this message translates to:
  /// **'Tuners'**
  String get adminTabTuners;

  /// Live TV tab: TV guide.
  ///
  /// In en, this message translates to:
  /// **'TV Guide'**
  String get adminTabTvGuide;

  /// Live TV tab: recording options.
  ///
  /// In en, this message translates to:
  /// **'Recording'**
  String get adminTabRecording;

  /// Section label: TV guide options.
  ///
  /// In en, this message translates to:
  /// **'Guide'**
  String get adminSectionGuide;

  /// Field label: number of guide days to keep.
  ///
  /// In en, this message translates to:
  /// **'Guide Days'**
  String get adminGuideDays;

  /// Helper text for the guide days field.
  ///
  /// In en, this message translates to:
  /// **'How many days of guide data to keep. Blank means auto.'**
  String get adminGuideDaysHelper;

  /// Section label: recording paths.
  ///
  /// In en, this message translates to:
  /// **'Recording Paths'**
  String get adminSectionRecordingPaths;

  /// Field label: default recording path.
  ///
  /// In en, this message translates to:
  /// **'Recording Path'**
  String get adminRecordingPath;

  /// Field label: movie recording path.
  ///
  /// In en, this message translates to:
  /// **'Movie Recording Path'**
  String get adminMovieRecordingPath;

  /// Field label: series recording path.
  ///
  /// In en, this message translates to:
  /// **'Series Recording Path'**
  String get adminSeriesRecordingPath;

  /// Section label: recording padding.
  ///
  /// In en, this message translates to:
  /// **'Padding'**
  String get adminSectionPadding;

  /// Field label: recording pre-padding in seconds.
  ///
  /// In en, this message translates to:
  /// **'Pre-padding (seconds)'**
  String get adminPrePadding;

  /// Field label: recording post-padding in seconds.
  ///
  /// In en, this message translates to:
  /// **'Post-padding (seconds)'**
  String get adminPostPadding;

  /// Section label: recording options.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get adminSectionOptions;

  /// Toggle label: organize recordings into subfolders.
  ///
  /// In en, this message translates to:
  /// **'Recording Subfolders'**
  String get adminRecordingSubfolders;

  /// Toggle label: save recording NFO metadata (NFO is a token).
  ///
  /// In en, this message translates to:
  /// **'Save Recording NFO'**
  String get adminSaveRecordingNfo;

  /// Toggle label: save recording images.
  ///
  /// In en, this message translates to:
  /// **'Save Recording Images'**
  String get adminSaveRecordingImages;

  /// Field label: minutes to start recording before scheduled time.
  ///
  /// In en, this message translates to:
  /// **'Start Before'**
  String get adminStartBefore;

  /// Field label: minutes to stop recording after scheduled time.
  ///
  /// In en, this message translates to:
  /// **'Stop After'**
  String get adminStopAfter;

  /// Fallback title for a series recording rule with no name.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get adminSeriesFallback;

  /// DVR tab: scheduled recordings.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get adminTabScheduled;

  /// DVR tab: series recording rules.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get adminTabSeries;

  /// DVR tab: completed recordings.
  ///
  /// In en, this message translates to:
  /// **'Recorded'**
  String get adminTabRecorded;

  /// Empty state: no scheduled recordings.
  ///
  /// In en, this message translates to:
  /// **'No scheduled recordings.'**
  String get adminNoScheduledRecordings;

  /// Empty state: no series recording rules.
  ///
  /// In en, this message translates to:
  /// **'No series rules.'**
  String get adminNoSeriesRules;

  /// Series rule subtitle: pre/post padding in minutes.
  ///
  /// In en, this message translates to:
  /// **'Pad {pre}m / {post}m'**
  String adminSeriesPad(int pre, int post);

  /// Empty state: no completed recordings.
  ///
  /// In en, this message translates to:
  /// **'No recordings.'**
  String get adminNoRecordings;

  /// Empty state: no client devices.
  ///
  /// In en, this message translates to:
  /// **'No devices.'**
  String get adminNoDevices;

  /// Field label: postal code for Schedules Direct lineup lookup.
  ///
  /// In en, this message translates to:
  /// **'Postal Code'**
  String get adminPostalCode;

  /// Button label: search for Schedules Direct lineups.
  ///
  /// In en, this message translates to:
  /// **'Find Lineups'**
  String get adminFindLineups;

  /// Dropdown label: Schedules Direct lineup.
  ///
  /// In en, this message translates to:
  /// **'Lineup'**
  String get adminLineup;

  /// Toggle label: apply this guide provider to all tuners.
  ///
  /// In en, this message translates to:
  /// **'Enable All Tuners'**
  String get adminEnableAllTuners;

  /// Error shown when no Schedules Direct lineups match the postal code.
  ///
  /// In en, this message translates to:
  /// **'No lineups found for that postal code.'**
  String get adminNoLineups;

  /// User permission: full administrator access.
  ///
  /// In en, this message translates to:
  /// **'Allow Server Management'**
  String get adminAllowServerManagement;

  /// Subtitle for the Allow Server Management permission.
  ///
  /// In en, this message translates to:
  /// **'Full administrator access'**
  String get adminAllowServerManagementSub;

  /// User permission: disable the account.
  ///
  /// In en, this message translates to:
  /// **'Disable This User'**
  String get adminDisableUser;

  /// Subtitle for the Disable This User permission.
  ///
  /// In en, this message translates to:
  /// **'Blocks sign-in'**
  String get adminDisableUserSub;

  /// User permission: hide the user from the login screen.
  ///
  /// In en, this message translates to:
  /// **'Hide From Login Screen'**
  String get adminHideFromLogin;

  /// User permission: manage collections.
  ///
  /// In en, this message translates to:
  /// **'Allow Collection Management'**
  String get adminAllowCollectionMgmt;

  /// User permission: manage subtitles.
  ///
  /// In en, this message translates to:
  /// **'Allow Subtitle Management'**
  String get adminAllowSubtitleMgmt;

  /// User permission: play media.
  ///
  /// In en, this message translates to:
  /// **'Allow Media Playback'**
  String get adminAllowMediaPlayback;

  /// User permission: audio transcoding.
  ///
  /// In en, this message translates to:
  /// **'Allow Audio Transcoding'**
  String get adminAllowAudioTranscoding;

  /// User permission: video transcoding.
  ///
  /// In en, this message translates to:
  /// **'Allow Video Transcoding'**
  String get adminAllowVideoTranscoding;

  /// User permission: playback requiring remuxing/conversion.
  ///
  /// In en, this message translates to:
  /// **'Allow Playback Requiring Conversion'**
  String get adminAllowRemuxing;

  /// User permission: download content.
  ///
  /// In en, this message translates to:
  /// **'Allow Downloads'**
  String get adminAllowDownloads;

  /// User permission: delete content.
  ///
  /// In en, this message translates to:
  /// **'Allow Deleting Content'**
  String get adminAllowDeleting;

  /// User permission: access Live TV.
  ///
  /// In en, this message translates to:
  /// **'Allow Live TV Access'**
  String get adminAllowLiveTvAccess;

  /// User permission: manage Live TV and DVR.
  ///
  /// In en, this message translates to:
  /// **'Allow Live TV / DVR Management'**
  String get adminAllowLiveTvMgmt;

  /// User permission: remote-control other users.
  ///
  /// In en, this message translates to:
  /// **'Allow Remote Control of Others'**
  String get adminAllowRemoteControlOthers;

  /// User permission: be remote-controlled by others.
  ///
  /// In en, this message translates to:
  /// **'Allow Being Remote Controlled'**
  String get adminAllowBeingControlled;

  /// User editor tab: profile / permissions.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get adminTabProfile;

  /// User editor tab: library/device/channel access.
  ///
  /// In en, this message translates to:
  /// **'Access'**
  String get adminTabAccess;

  /// User editor tab: parental controls.
  ///
  /// In en, this message translates to:
  /// **'Parental'**
  String get adminTabParental;

  /// User editor tab: password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get adminTabPassword;

  /// User editor section: management permissions.
  ///
  /// In en, this message translates to:
  /// **'Management'**
  String get adminSectionManagement;

  /// User editor section: playback permissions.
  ///
  /// In en, this message translates to:
  /// **'Playback'**
  String get adminSectionPlayback;

  /// User editor section: remote control permissions.
  ///
  /// In en, this message translates to:
  /// **'Remote'**
  String get adminSectionRemote;

  /// User editor section: streaming limits.
  ///
  /// In en, this message translates to:
  /// **'Limits'**
  String get adminSectionLimits;

  /// Field label: maximum simultaneous streams for the user.
  ///
  /// In en, this message translates to:
  /// **'Max Simultaneous Streams'**
  String get adminMaxSimultaneousStreams;

  /// Field hint: zero means unlimited.
  ///
  /// In en, this message translates to:
  /// **'0 = unlimited'**
  String get adminHintZeroUnlimited;

  /// Field label: failed logins before the account locks out.
  ///
  /// In en, this message translates to:
  /// **'Failed Logins Before Lockout'**
  String get adminFailedLoginsBeforeLockout;

  /// Field hint: 0 uses the default, -1 never locks out.
  ///
  /// In en, this message translates to:
  /// **'0 = default, -1 = never'**
  String get adminFailedLoginsHint;

  /// Field label: remote streaming bitrate limit.
  ///
  /// In en, this message translates to:
  /// **'Remote Streaming Limit'**
  String get adminRemoteStreamingLimit;

  /// User editor section: channel access.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get adminSectionChannels;

  /// Toggle label: grant access to all libraries.
  ///
  /// In en, this message translates to:
  /// **'Access All Libraries'**
  String get adminAccessAllLibraries;

  /// Toggle label: grant access to all devices.
  ///
  /// In en, this message translates to:
  /// **'Access All Devices'**
  String get adminAccessAllDevices;

  /// Toggle: always transcode remote media sources such as Live TV for this user.
  ///
  /// In en, this message translates to:
  /// **'Force Transcoding of Remote Sources'**
  String get adminForceRemoteTranscoding;

  /// Subtitle under the force remote transcoding toggle.
  ///
  /// In en, this message translates to:
  /// **'Such as Live TV'**
  String get adminForceRemoteTranscodingSub;

  /// Section header: which libraries a user may delete media from.
  ///
  /// In en, this message translates to:
  /// **'Allow Media Deletion From'**
  String get adminSectionDeletion;

  /// Toggle: the user may delete media from every library.
  ///
  /// In en, this message translates to:
  /// **'All Libraries'**
  String get adminDeleteFromAll;

  /// Section header for a user's watch-together permissions.
  ///
  /// In en, this message translates to:
  /// **'SyncPlay'**
  String get adminSectionSyncPlay;

  /// Dropdown label: what a user may do with SyncPlay groups.
  ///
  /// In en, this message translates to:
  /// **'SyncPlay Access'**
  String get adminSyncPlayAccess;

  /// SyncPlay access option.
  ///
  /// In en, this message translates to:
  /// **'Create and Join Groups'**
  String get adminSyncPlayCreateAndJoin;

  /// SyncPlay access option.
  ///
  /// In en, this message translates to:
  /// **'Join Groups Only'**
  String get adminSyncPlayJoin;

  /// SyncPlay access option.
  ///
  /// In en, this message translates to:
  /// **'Disabled for This User'**
  String get adminSyncPlayNone;

  /// Section header for a user's authentication and password reset providers.
  ///
  /// In en, this message translates to:
  /// **'Sign-In'**
  String get adminSectionSignIn;

  /// Dropdown label: how this user signs in.
  ///
  /// In en, this message translates to:
  /// **'Authentication Provider'**
  String get adminAuthProvider;

  /// Dropdown label: how this user resets a forgotten password.
  ///
  /// In en, this message translates to:
  /// **'Password Reset Provider'**
  String get adminPasswordResetProvider;

  /// Help under the device access list.
  ///
  /// In en, this message translates to:
  /// **'This only applies to devices that can be uniquely identified, and does not block browser access. Limiting devices stops this user signing in on a new device until it is approved here.'**
  String get adminDeviceAccessHelp;

  /// Help under the channel access list.
  ///
  /// In en, this message translates to:
  /// **'Choose the channels this user can see.'**
  String get adminChannelAccessHelp;

  /// Help under the maximum parental rating dropdown.
  ///
  /// In en, this message translates to:
  /// **'Content rated higher than this is hidden from this user.'**
  String get adminRatingHelp;

  /// Help above the block unrated item types.
  ///
  /// In en, this message translates to:
  /// **'Hide items of these kinds that have no rating, or a rating the server does not recognise.'**
  String get adminBlockUnratedHelp;

  /// Unrated item type.
  ///
  /// In en, this message translates to:
  /// **'Books'**
  String get adminUnratedBooks;

  /// Unrated item type: plugin channel content.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get adminUnratedChannels;

  /// Unrated item type.
  ///
  /// In en, this message translates to:
  /// **'Live TV'**
  String get adminUnratedLiveTv;

  /// Unrated item type.
  ///
  /// In en, this message translates to:
  /// **'Movies'**
  String get adminUnratedMovies;

  /// Unrated item type.
  ///
  /// In en, this message translates to:
  /// **'Music'**
  String get adminUnratedMusic;

  /// Unrated item type.
  ///
  /// In en, this message translates to:
  /// **'Trailers'**
  String get adminUnratedTrailers;

  /// Unrated item type.
  ///
  /// In en, this message translates to:
  /// **'Shows'**
  String get adminUnratedShows;

  /// Unrated item type: anything not covered by the other types. Only shown when a user already blocks it, so it can be cleared.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get adminUnratedOther;

  /// Section header: tags a user's content must carry.
  ///
  /// In en, this message translates to:
  /// **'Allow Items With Tags'**
  String get adminAllowedTags;

  /// Help for allowed tags.
  ///
  /// In en, this message translates to:
  /// **'Only show media with at least one of these tags.'**
  String get adminAllowedTagsHelp;

  /// Section header: tags that hide content from a user.
  ///
  /// In en, this message translates to:
  /// **'Block Items With Tags'**
  String get adminBlockedTags;

  /// Help for blocked tags.
  ///
  /// In en, this message translates to:
  /// **'Hide media with at least one of these tags.'**
  String get adminBlockedTagsHelp;

  /// Button and dialog title: add a tag.
  ///
  /// In en, this message translates to:
  /// **'Add Tag'**
  String get adminAddTag;

  /// Text field label for a tag.
  ///
  /// In en, this message translates to:
  /// **'Tag'**
  String get adminTag;

  /// Section header: hours a user may use the server.
  ///
  /// In en, this message translates to:
  /// **'Access Schedule'**
  String get adminAccessSchedule;

  /// Help for access schedules.
  ///
  /// In en, this message translates to:
  /// **'Limit this user to certain days and hours. With no schedule, access is not limited.'**
  String get adminAccessScheduleHelp;

  /// Button and dialog title: add an access schedule.
  ///
  /// In en, this message translates to:
  /// **'Add Schedule'**
  String get adminAddSchedule;

  /// Dropdown label: day or days a schedule applies to.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get adminScheduleDay;

  /// Dropdown label: when a schedule's access begins.
  ///
  /// In en, this message translates to:
  /// **'Start Time'**
  String get adminScheduleStart;

  /// Dropdown label: when a schedule's access ends.
  ///
  /// In en, this message translates to:
  /// **'End Time'**
  String get adminScheduleEnd;

  /// Access schedule day option.
  ///
  /// In en, this message translates to:
  /// **'Every Day'**
  String get adminEveryDay;

  /// Access schedule day option.
  ///
  /// In en, this message translates to:
  /// **'Weekdays'**
  String get adminWeekdays;

  /// Access schedule day option.
  ///
  /// In en, this message translates to:
  /// **'Weekends'**
  String get adminWeekends;

  /// Toggle label: grant access to all channels.
  ///
  /// In en, this message translates to:
  /// **'Access All Channels'**
  String get adminAccessAllChannels;

  /// User editor section: maximum allowed parental rating.
  ///
  /// In en, this message translates to:
  /// **'Maximum Allowed Rating'**
  String get adminSectionMaxRating;

  /// Dropdown label: maximum parental rating.
  ///
  /// In en, this message translates to:
  /// **'Max Parental Rating'**
  String get adminMaxParentalRating;

  /// Parental rating option: no restriction.
  ///
  /// In en, this message translates to:
  /// **'None (unrestricted)'**
  String get adminRatingNone;

  /// Toggle label: block items that have no parental rating.
  ///
  /// In en, this message translates to:
  /// **'Block Items With No Rating'**
  String get adminBlockUnrated;

  /// List action: set or reset the user's password.
  ///
  /// In en, this message translates to:
  /// **'Set / Reset Password'**
  String get adminSetResetPassword;

  /// Dialog title and action: delete the user.
  ///
  /// In en, this message translates to:
  /// **'Delete User'**
  String get adminDeleteUser;

  /// Dialog title: set the user's password.
  ///
  /// In en, this message translates to:
  /// **'Set Password'**
  String get adminSetPassword;

  /// Password field hint: leaving it blank clears the password.
  ///
  /// In en, this message translates to:
  /// **'New password (blank = clear)'**
  String get adminNewPasswordHint;

  /// Button label: set the password.
  ///
  /// In en, this message translates to:
  /// **'Set'**
  String get adminSet;

  /// Snackbar confirming the password was updated.
  ///
  /// In en, this message translates to:
  /// **'Password updated'**
  String get adminPasswordUpdated;

  /// Confirmation body: permanently delete a named user.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete \"{name}\"?'**
  String adminDeleteUserConfirm(String name);

  /// Snackbar after deleting a user.
  ///
  /// In en, this message translates to:
  /// **'Deleted \"{name}\"'**
  String adminDeletedUser(String name);

  /// Snackbar confirming a settings change was saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get adminSaved;

  /// Tooltip on the sidebar button that collapses the navigation rail.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get miscCollapseSidebar;

  /// Tooltip on the sidebar button that expands the navigation rail.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get miscExpandSidebar;

  /// Notification bell label/tooltip in the navigation rail; opens the notification centre.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get miscNotifications;

  /// Sidebar navigation group that expands to Playlists, Genres, Studios, Artists and Downloads.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get miscBrowse;

  /// Sidebar Browse sub-item: the user's playlists.
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get miscNavPlaylists;

  /// Sidebar Browse sub-item: browse by genre.
  ///
  /// In en, this message translates to:
  /// **'Genres'**
  String get miscNavGenres;

  /// Sidebar Browse sub-item: browse by studio.
  ///
  /// In en, this message translates to:
  /// **'Studios'**
  String get miscNavStudios;

  /// Sidebar Browse sub-item: browse by artist.
  ///
  /// In en, this message translates to:
  /// **'Artists'**
  String get miscNavArtists;

  /// Fallback label for the profile menu when the signed-in user's name is unavailable.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get miscAccount;

  /// Profile menu item that opens the SyncPlay (watch together) screen.
  ///
  /// In en, this message translates to:
  /// **'Watch Together'**
  String get miscWatchTogether;

  /// Subtitle under Watch Together in the profile menu when the user is currently in a SyncPlay group.
  ///
  /// In en, this message translates to:
  /// **'In a group'**
  String get miscInAGroup;

  /// Profile menu item and dialog title for approving a Quick Connect sign-in code.
  ///
  /// In en, this message translates to:
  /// **'Quick Connect'**
  String get miscQuickConnect;

  /// Profile menu item that opens the app settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get miscSettings;

  /// Profile menu item (admins only) that opens the server administration screen.
  ///
  /// In en, this message translates to:
  /// **'Administration'**
  String get miscAdministration;

  /// Snackbar shown after approving a Quick Connect code.
  ///
  /// In en, this message translates to:
  /// **'Device approved'**
  String get miscDeviceApproved;

  /// Error shown when a Quick Connect code could not be approved.
  ///
  /// In en, this message translates to:
  /// **'That code could not be approved.'**
  String get miscCodeNotApproved;

  /// Instruction in the Quick Connect authorize dialog.
  ///
  /// In en, this message translates to:
  /// **'Enter the code shown on the device you are signing in on.'**
  String get miscEnterCodePrompt;

  /// Hint text for the Quick Connect code input field.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get miscCode;

  /// Button that approves a Quick Connect code.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get miscApprove;

  /// Inline error shown when a single content row fails to load.
  ///
  /// In en, this message translates to:
  /// **'Could not load this row.'**
  String get miscCouldntLoad;

  /// Relative upload time for a video, in years.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 year ago} other{{count} years ago}}'**
  String miscYearsAgo(int count);

  /// Relative upload time for a video, in months.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 month ago} other{{count} months ago}}'**
  String miscMonthsAgo(int count);

  /// Relative upload time for a video, in days.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day ago} other{{count} days ago}}'**
  String miscDaysAgo(int count);

  /// Relative upload time for a video, in hours.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hour ago} other{{count} hours ago}}'**
  String miscHoursAgo(int count);

  /// Relative upload time for a video uploaded within the last hour.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get miscJustNow;

  /// Number of videos in a local YouTube playlist.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 video} other{{count} videos}}'**
  String miscVideoCount(int count);

  /// Player seek-bar marker label for an intro media segment.
  ///
  /// In en, this message translates to:
  /// **'Intro'**
  String get miscSegmentIntro;

  /// Player seek-bar marker label for a recap media segment.
  ///
  /// In en, this message translates to:
  /// **'Recap'**
  String get miscSegmentRecap;

  /// Player seek-bar marker label for an outro/credits media segment.
  ///
  /// In en, this message translates to:
  /// **'Outro'**
  String get miscSegmentOutro;

  /// Player seek-bar marker label for a preview media segment.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get miscSegmentPreview;

  /// Player seek-bar marker label for a commercial media segment.
  ///
  /// In en, this message translates to:
  /// **'Commercial'**
  String get miscSegmentCommercial;

  /// Player seek-bar marker label for an unrecognised media segment type.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get miscSegmentUnknown;

  /// TMDB production status for a TV series that is still airing.
  ///
  /// In en, this message translates to:
  /// **'Returning Series'**
  String get miscSeerrStatusReturningSeries;

  /// TMDB production status for a TV series that has concluded.
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get miscSeerrStatusEnded;

  /// TMDB production status for a released movie.
  ///
  /// In en, this message translates to:
  /// **'Released'**
  String get miscSeerrStatusReleased;

  /// TMDB production status for a title currently in production.
  ///
  /// In en, this message translates to:
  /// **'In Production'**
  String get miscSeerrStatusInProduction;

  /// TMDB production status for a title in post-production.
  ///
  /// In en, this message translates to:
  /// **'Post Production'**
  String get miscSeerrStatusPostProduction;

  /// TMDB production status for a planned title.
  ///
  /// In en, this message translates to:
  /// **'Planned'**
  String get miscSeerrStatusPlanned;

  /// TMDB production status for a rumored title.
  ///
  /// In en, this message translates to:
  /// **'Rumored'**
  String get miscSeerrStatusRumored;

  /// TMDB production status for a cancelled title.
  ///
  /// In en, this message translates to:
  /// **'Canceled'**
  String get miscSeerrStatusCanceled;

  /// TMDB production status for a TV pilot.
  ///
  /// In en, this message translates to:
  /// **'Pilot'**
  String get miscSeerrStatusPilot;

  /// App bar title for the Live TV screen.
  ///
  /// In en, this message translates to:
  /// **'Live TV'**
  String get extraLiveTvTitle;

  /// Live TV tab label: the EPG program guide.
  ///
  /// In en, this message translates to:
  /// **'Guide'**
  String get extraTabGuide;

  /// Live TV tab label: the channel list.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get extraTabChannels;

  /// Live TV tab label: DVR recordings.
  ///
  /// In en, this message translates to:
  /// **'Recordings'**
  String get extraTabRecordings;

  /// Empty-state title on the Live TV Recordings tab.
  ///
  /// In en, this message translates to:
  /// **'No recordings yet'**
  String get extraNoRecordings;

  /// Empty-state message on the Live TV Recordings tab, telling the user how to make a recording.
  ///
  /// In en, this message translates to:
  /// **'Schedule one from the Guide.'**
  String get extraNoRecordingsHint;

  /// Empty-state title shown when there are no Live TV channels.
  ///
  /// In en, this message translates to:
  /// **'No channels found'**
  String get extraNoChannelsFound;

  /// Badge on a guide program that is recording right now (recording indicator).
  ///
  /// In en, this message translates to:
  /// **'REC'**
  String get extraBadgeRec;

  /// Badge on a guide program that is currently airing live.
  ///
  /// In en, this message translates to:
  /// **'LIVE'**
  String get extraBadgeLive;

  /// Button in a media row header that opens the full list of that section's items.
  ///
  /// In en, this message translates to:
  /// **'See All'**
  String get extraSeeAll;

  /// Tooltip for a YouTube video row overflow (three-dot) menu button.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get extraMore;

  /// Duration badge on a YouTube Shorts thumbnail.
  ///
  /// In en, this message translates to:
  /// **'Short'**
  String get miscVideoShort;

  /// View-count label on a video, e.g. '1.2M views'.
  ///
  /// In en, this message translates to:
  /// **'{count} views'**
  String miscViews(String count);

  /// Settings search result title: which screen the app opens on when launched.
  ///
  /// In en, this message translates to:
  /// **'Open on Startup'**
  String get searchOpenOnStartup;

  /// Settings search result title: OS-level system notifications toggle (desktop and mobile).
  ///
  /// In en, this message translates to:
  /// **'System Notifications'**
  String get searchDesktopNotifications;

  /// Settings search result title: notification for a new Seerr request.
  ///
  /// In en, this message translates to:
  /// **'New Request'**
  String get searchNewRequest;

  /// Settings search result title: notification when a request is approved.
  ///
  /// In en, this message translates to:
  /// **'Request Approved'**
  String get searchRequestApproved;

  /// Settings search result title: notification when a request is declined.
  ///
  /// In en, this message translates to:
  /// **'Request Declined'**
  String get searchRequestDeclined;

  /// Settings search result title: notification when requested media is now available.
  ///
  /// In en, this message translates to:
  /// **'Now Available'**
  String get searchNowAvailable;

  /// Settings search result title: polling interval for Seerr request status updates.
  ///
  /// In en, this message translates to:
  /// **'Check for Request Updates'**
  String get searchCheckForRequestUpdates;

  /// Settings search result title: notification when a download finishes.
  ///
  /// In en, this message translates to:
  /// **'Download Complete'**
  String get searchDownloadComplete;

  /// Settings search result title: image cache storage / clear cache.
  ///
  /// In en, this message translates to:
  /// **'Image Cache'**
  String get searchImageCache;

  /// Settings search result title: where downloaded Jellyfin media is saved.
  ///
  /// In en, this message translates to:
  /// **'Download Location'**
  String get searchDownloadLocation;

  /// Settings search result title: app theme (dark/light/system).
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get searchTheme;

  /// Settings search result title: pure black AMOLED dark theme toggle.
  ///
  /// In en, this message translates to:
  /// **'AMOLED Black'**
  String get searchAmoledBlack;

  /// Settings search result title: the interface size (zoom) setting.
  ///
  /// In en, this message translates to:
  /// **'Interface Size'**
  String get searchInterfaceSize;

  /// Settings search result title: show a rating badge on poster cards.
  ///
  /// In en, this message translates to:
  /// **'Rating on Cards'**
  String get searchRatingOnCards;

  /// Settings search result title: custom accent / highlight color.
  ///
  /// In en, this message translates to:
  /// **'Accent Color'**
  String get searchAccentColor;

  /// Settings search result title: featured hero banner on the home screen.
  ///
  /// In en, this message translates to:
  /// **'Home Banner'**
  String get searchHomeBanner;

  /// Settings search result title: reorder / customize home screen rows.
  ///
  /// In en, this message translates to:
  /// **'Home Layout'**
  String get searchHomeLayout;

  /// Settings search result title: video scaling mode (contain/cover/fill).
  ///
  /// In en, this message translates to:
  /// **'Video Fit'**
  String get searchVideoFit;

  /// Settings search result title: player control bar appearance (glass/blur).
  ///
  /// In en, this message translates to:
  /// **'Control Bar'**
  String get searchControlBar;

  /// Settings search result title: maximum streaming quality / bitrate cap.
  ///
  /// In en, this message translates to:
  /// **'Max Quality'**
  String get searchMaxQuality;

  /// Settings search result title: playback quality for trailers.
  ///
  /// In en, this message translates to:
  /// **'Trailer Quality'**
  String get searchTrailerQuality;

  /// Settings search result title: default playback speed.
  ///
  /// In en, this message translates to:
  /// **'Default Speed'**
  String get searchDefaultSpeed;

  /// Settings search result title: automatically play the next episode.
  ///
  /// In en, this message translates to:
  /// **'Autoplay Next Episode'**
  String get searchAutoplayNextEpisode;

  /// Settings search result title: remember audio/subtitle track choices.
  ///
  /// In en, this message translates to:
  /// **'Remember Track Selections'**
  String get searchRememberTrackSelections;

  /// Settings search result title: trickplay preview thumbnails when scrubbing.
  ///
  /// In en, this message translates to:
  /// **'Preview Thumbnails While Seeking'**
  String get searchPreviewThumbnailsWhileSeeking;

  /// Settings search result title: automatically skip intro segments.
  ///
  /// In en, this message translates to:
  /// **'Auto-Skip Intros'**
  String get searchAutoSkipIntros;

  /// Settings search result title: automatically skip credits/outro segments.
  ///
  /// In en, this message translates to:
  /// **'Auto-Skip Credits'**
  String get searchAutoSkipCredits;

  /// Settings search result title: when the Up Next card appears during credits.
  ///
  /// In en, this message translates to:
  /// **'Up Next Timing'**
  String get searchUpNextTiming;

  /// Settings search result title: how the Up Next prompt is presented (card or pill).
  ///
  /// In en, this message translates to:
  /// **'Up Next Style'**
  String get searchUpNextStyle;

  /// Settings search result title: GPU hardware video decoding toggle.
  ///
  /// In en, this message translates to:
  /// **'Hardware Decoding'**
  String get searchHardwareDecoding;

  /// Settings search result title: preferred/default audio language.
  ///
  /// In en, this message translates to:
  /// **'Audio Language'**
  String get searchAudioLanguage;

  /// Settings search result title: preferred/default subtitle language.
  ///
  /// In en, this message translates to:
  /// **'Subtitle Language'**
  String get searchSubtitleLanguage;

  /// Settings search result title: subtitle text size / scale.
  ///
  /// In en, this message translates to:
  /// **'Subtitle Size'**
  String get searchSubtitleSize;

  /// Settings search result title: subtitle text color.
  ///
  /// In en, this message translates to:
  /// **'Subtitle Color'**
  String get searchSubtitleColor;

  /// Settings search result title: subtitle background box / shadow.
  ///
  /// In en, this message translates to:
  /// **'Subtitle Background'**
  String get searchSubtitleBackground;

  /// Settings search result title: vertical placement of subtitles.
  ///
  /// In en, this message translates to:
  /// **'Subtitle Position'**
  String get searchSubtitlePosition;

  /// Settings search result title: auto-display synced music lyrics.
  ///
  /// In en, this message translates to:
  /// **'Show Lyrics Automatically'**
  String get searchShowLyricsAutomatically;

  /// Settings search result title: fetch missing lyrics from an online source.
  ///
  /// In en, this message translates to:
  /// **'Look Up Missing Lyrics Online'**
  String get searchLookUpMissingLyricsOnline;

  /// Settings search result title: show Rotten Tomatoes critic (Tomatometer) rating. 'Rotten Tomatoes' is a brand name.
  ///
  /// In en, this message translates to:
  /// **'Rotten Tomatoes Critics'**
  String get searchRottenTomatoesCritics;

  /// Settings search result title: show Rotten Tomatoes audience (popcorn) rating. 'Rotten Tomatoes' is a brand name.
  ///
  /// In en, this message translates to:
  /// **'Rotten Tomatoes Audience'**
  String get searchRottenTomatoesAudience;

  /// Settings search result title: show IMDb rating. 'IMDb' is a brand name.
  ///
  /// In en, this message translates to:
  /// **'IMDb Rating'**
  String get searchImdbRating;

  /// Settings search result title: show the community (Jellyfin/TMDB) vote average.
  ///
  /// In en, this message translates to:
  /// **'Community Score'**
  String get searchCommunityScore;

  /// Settings search result title: additional rating sources via MDBList. 'MDBList' is a brand name.
  ///
  /// In en, this message translates to:
  /// **'More Ratings (MDBList)'**
  String get searchMoreRatingsMdblist;

  /// Settings search result title: enable the YouTube feature. 'YouTube' is a brand name.
  ///
  /// In en, this message translates to:
  /// **'Enable YouTube'**
  String get searchEnableYouTube;

  /// Settings search result title: YouTube autoplay of the next/recommended video.
  ///
  /// In en, this message translates to:
  /// **'Autoplay'**
  String get searchAutoplay;

  /// Settings search result title: show YouTube dislike counts (Return YouTube Dislike).
  ///
  /// In en, this message translates to:
  /// **'Show Dislike Counts'**
  String get searchShowDislikeCounts;

  /// Settings search result title: replace clickbait YouTube titles/thumbnails (DeArrow).
  ///
  /// In en, this message translates to:
  /// **'De-Clickbait Titles'**
  String get searchDeClickbaitTitles;

  /// Settings search result title: default YouTube playback quality/resolution.
  ///
  /// In en, this message translates to:
  /// **'Default Quality'**
  String get searchDefaultQuality;

  /// Settings search result title: seek-backward step size in seconds.
  ///
  /// In en, this message translates to:
  /// **'Skip Back'**
  String get searchSkipBack;

  /// Settings search result title: seek-forward step size in seconds.
  ///
  /// In en, this message translates to:
  /// **'Skip Forward'**
  String get searchSkipForward;

  /// Settings search result title: YouTube list vs grid layout.
  ///
  /// In en, this message translates to:
  /// **'List View Mode'**
  String get searchListViewMode;

  /// Settings search result title: YouTube thumbnail image quality.
  ///
  /// In en, this message translates to:
  /// **'Thumbnail Quality'**
  String get searchThumbnailQuality;

  /// Settings search result title: YouTube download quality / audio format.
  ///
  /// In en, this message translates to:
  /// **'Download Quality'**
  String get searchDownloadQuality;

  /// Settings search result title: YouTube download video container (MP4/MKV).
  ///
  /// In en, this message translates to:
  /// **'Video Container'**
  String get searchVideoContainer;

  /// Settings search result title: YouTube content/results language.
  ///
  /// In en, this message translates to:
  /// **'Content Language'**
  String get searchContentLanguage;

  /// Settings search result title: YouTube content region/country.
  ///
  /// In en, this message translates to:
  /// **'Content Country'**
  String get searchContentCountry;

  /// Settings search result title: YouTube restricted / safe mode filter.
  ///
  /// In en, this message translates to:
  /// **'Restricted Mode'**
  String get searchRestrictedMode;

  /// Settings search result title: show YouTube comments.
  ///
  /// In en, this message translates to:
  /// **'Show Comments'**
  String get searchShowComments;

  /// Settings search result title: show YouTube up-next / related videos.
  ///
  /// In en, this message translates to:
  /// **'Show Up Next'**
  String get searchShowUpNext;

  /// Settings search result title: show the YouTube video description.
  ///
  /// In en, this message translates to:
  /// **'Show Description'**
  String get searchShowDescription;

  /// Settings search result title: retain YouTube watch history.
  ///
  /// In en, this message translates to:
  /// **'Keep Watch History'**
  String get searchKeepWatchHistory;

  /// Settings search result title: resume YouTube playback at last position.
  ///
  /// In en, this message translates to:
  /// **'Resume Playback'**
  String get searchResumePlayback;

  /// Settings search result title: retain YouTube search history.
  ///
  /// In en, this message translates to:
  /// **'Keep Search History'**
  String get searchKeepSearchHistory;

  /// Settings search result title: skip sponsor segments (SponsorBlock).
  ///
  /// In en, this message translates to:
  /// **'Skip Sponsor Segments'**
  String get searchSkipSponsorSegments;

  /// Settings search result title: delete YouTube watch history.
  ///
  /// In en, this message translates to:
  /// **'Clear Watch History'**
  String get searchClearWatchHistory;

  /// Settings search result title: delete YouTube search history.
  ///
  /// In en, this message translates to:
  /// **'Clear Search History'**
  String get searchClearSearchHistory;

  /// Settings search result title: prompt before clearing the YouTube queue.
  ///
  /// In en, this message translates to:
  /// **'Confirm Before Clearing Queue'**
  String get searchConfirmBeforeClearingQueue;

  /// Settings search result title: number of retry attempts for failed downloads.
  ///
  /// In en, this message translates to:
  /// **'Download Retries'**
  String get searchDownloadRetries;

  /// Settings search result title: number of concurrent/parallel downloads.
  ///
  /// In en, this message translates to:
  /// **'Simultaneous Downloads'**
  String get searchSimultaneousDownloads;

  /// Settings search result title: destination folders for downloads.
  ///
  /// In en, this message translates to:
  /// **'Download Folders'**
  String get searchDownloadFolders;

  /// Settings search result title: show a toast/notice when a SponsorBlock segment is skipped.
  ///
  /// In en, this message translates to:
  /// **'Say When Something Is Skipped'**
  String get searchSayWhenSomethingIsSkipped;

  /// Settings search result title: SyncPlay watch-together / watch party feature.
  ///
  /// In en, this message translates to:
  /// **'Watch Together'**
  String get searchWatchTogether;

  /// Settings search section/title: General settings.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get searchGeneral;

  /// Settings search section: Appearance settings.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get searchAppearance;

  /// Settings search section: Home screen settings.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get searchHome;

  /// Settings search section: video Player settings.
  ///
  /// In en, this message translates to:
  /// **'Player'**
  String get searchPlayer;

  /// Settings search section: Audio and Subtitles settings.
  ///
  /// In en, this message translates to:
  /// **'Audio & Subtitles'**
  String get searchAudioSubtitles;

  /// Settings search section: Ratings settings.
  ///
  /// In en, this message translates to:
  /// **'Ratings'**
  String get searchRatings;

  /// Settings search result title: the Seerr connection / sign-in screen (API key, Jellyfin, or local account).
  ///
  /// In en, this message translates to:
  /// **'Seerr Sign-in'**
  String get searchSeerrConnection;

  /// Settings search section: YouTube settings. 'YouTube' is a brand name.
  ///
  /// In en, this message translates to:
  /// **'YouTube'**
  String get searchYouTube;

  /// Settings search section: Integrations settings.
  ///
  /// In en, this message translates to:
  /// **'Integrations'**
  String get searchIntegrations;

  /// Admin settings search result title: the server's display name.
  ///
  /// In en, this message translates to:
  /// **'Server Name'**
  String get searchServerName;

  /// Admin settings search result title: preferred language for fetched metadata.
  ///
  /// In en, this message translates to:
  /// **'Preferred Metadata Language'**
  String get searchPreferredMetadataLanguage;

  /// Admin settings search result title: metadata country/region.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get searchCountry;

  /// Admin settings search result title: Quick Connect code-based login/pairing.
  ///
  /// In en, this message translates to:
  /// **'Quick Connect'**
  String get searchQuickConnect;

  /// Admin settings search result title: show the raw folder library view.
  ///
  /// In en, this message translates to:
  /// **'Show Folder View'**
  String get searchShowFolderView;

  /// Admin settings search result title: min/max played percentages that count as resumed/watched.
  ///
  /// In en, this message translates to:
  /// **'Resume Thresholds'**
  String get searchResumeThresholds;

  /// Admin settings search section/title: server Playback and transcoding settings.
  ///
  /// In en, this message translates to:
  /// **'Playback'**
  String get searchPlayback;

  /// Admin settings search result title: transcoding hardware acceleration (VAAPI/NVENC/QSV).
  ///
  /// In en, this message translates to:
  /// **'Hardware Acceleration'**
  String get searchHardwareAcceleration;

  /// Admin settings search result title: enable GPU hardware encoding.
  ///
  /// In en, this message translates to:
  /// **'Enable Hardware Encoding'**
  String get searchEnableHardwareEncoding;

  /// Admin settings search result title: allow HEVC (H.265) and AV1 output encoding. Codec names are technical tokens.
  ///
  /// In en, this message translates to:
  /// **'Allow HEVC / AV1 Encoding'**
  String get searchAllowHevcAv1Encoding;

  /// Admin settings search result title: transcoder speed/quality preset.
  ///
  /// In en, this message translates to:
  /// **'Encoder Preset'**
  String get searchEncoderPreset;

  /// Admin settings search result title: number of CPU threads used for encoding.
  ///
  /// In en, this message translates to:
  /// **'Encoding Thread Count'**
  String get searchEncodingThreadCount;

  /// Admin settings search result title: HDR tone mapping settings.
  ///
  /// In en, this message translates to:
  /// **'Tone Mapping'**
  String get searchToneMapping;

  /// Admin settings search result title: subtitle extraction / burn-in settings.
  ///
  /// In en, this message translates to:
  /// **'Subtitle Extraction'**
  String get searchSubtitleExtraction;

  /// Admin settings search result title: trickplay scrub-preview thumbnail generation.
  ///
  /// In en, this message translates to:
  /// **'Trickplay'**
  String get searchTrickplay;

  /// Admin settings search result title: throttle transcoding when the buffer is full.
  ///
  /// In en, this message translates to:
  /// **'Transcode Throttling'**
  String get searchTranscodeThrottling;

  /// Admin settings search section/title: server Branding (login message, custom CSS, splash).
  ///
  /// In en, this message translates to:
  /// **'Branding'**
  String get searchBranding;

  /// Admin settings search result title: custom message shown on the login screen.
  ///
  /// In en, this message translates to:
  /// **'Login Message'**
  String get searchLoginMessage;

  /// Admin settings search result title: custom CSS styling. 'CSS' is a technical token.
  ///
  /// In en, this message translates to:
  /// **'Custom CSS'**
  String get searchCustomCss;

  /// Admin settings search result title: splash screen image.
  ///
  /// In en, this message translates to:
  /// **'Splash Screen Image'**
  String get searchSplashScreenImage;

  /// Admin settings search section/title: server Networking settings.
  ///
  /// In en, this message translates to:
  /// **'Networking'**
  String get searchNetworking;

  /// Admin settings search result title: allow external/remote (WAN) connections.
  ///
  /// In en, this message translates to:
  /// **'Allow Remote Connections'**
  String get searchAllowRemoteConnections;

  /// Admin settings search result title: the externally published server URL/domain.
  ///
  /// In en, this message translates to:
  /// **'Published Server URL'**
  String get searchPublishedServerUrl;

  /// Admin settings search result title: HTTP and HTTPS port numbers. 'HTTP'/'HTTPS' are technical tokens.
  ///
  /// In en, this message translates to:
  /// **'HTTP / HTTPS Ports'**
  String get searchHttpHttpsPorts;

  /// Admin settings search result title: enable HTTPS/SSL. 'HTTPS' is a technical token.
  ///
  /// In en, this message translates to:
  /// **'Enable HTTPS'**
  String get searchEnableHttps;

  /// Admin settings search result title: SSL/TLS certificate file path and password.
  ///
  /// In en, this message translates to:
  /// **'Certificate Path & Password'**
  String get searchCertificatePathPassword;

  /// Admin settings search result title: enable UPnP port forwarding. 'UPnP' is a technical token.
  ///
  /// In en, this message translates to:
  /// **'Enable UPnP'**
  String get searchEnableUpnp;

  /// Admin settings search result title: enable IPv6. 'IPv6' is a technical token.
  ///
  /// In en, this message translates to:
  /// **'Enable IPv6'**
  String get searchEnableIpv6;

  /// Admin settings search result title: trusted reverse proxy addresses.
  ///
  /// In en, this message translates to:
  /// **'Known Proxies'**
  String get searchKnownProxies;

  /// Admin settings search result title: local (LAN) network subnets. 'LAN' is a technical token.
  ///
  /// In en, this message translates to:
  /// **'LAN Networks'**
  String get searchLanNetworks;

  /// Admin settings search result title: local network autodiscovery (DLNA).
  ///
  /// In en, this message translates to:
  /// **'Autodiscovery'**
  String get searchAutodiscovery;

  /// Admin settings search result title: API keys / access tokens. 'API' is a technical token.
  ///
  /// In en, this message translates to:
  /// **'API Keys'**
  String get searchApiKeys;

  /// Admin settings search result title: media libraries management.
  ///
  /// In en, this message translates to:
  /// **'Libraries'**
  String get searchLibraries;

  /// Admin settings search result title: user accounts management.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get searchUsers;

  /// Admin settings search result title: registered client devices.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get searchDevices;

  /// Admin settings search result title: currently connected sessions / now playing.
  ///
  /// In en, this message translates to:
  /// **'Active Sessions'**
  String get searchActiveSessions;

  /// Admin settings search section/title: Live TV configuration (tuners, guide).
  ///
  /// In en, this message translates to:
  /// **'Live TV'**
  String get searchLiveTv;

  /// Admin settings search result title: DVR recording configuration. 'DVR' is a term/abbreviation.
  ///
  /// In en, this message translates to:
  /// **'DVR'**
  String get searchDvr;

  /// Admin settings search result title: scheduled background tasks/jobs.
  ///
  /// In en, this message translates to:
  /// **'Scheduled Tasks'**
  String get searchScheduledTasks;

  /// Admin settings search result title: server activity/event log.
  ///
  /// In en, this message translates to:
  /// **'Activity Log'**
  String get searchActivityLog;

  /// Admin settings search result title: server log files.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get searchLogs;

  /// Admin settings search result title: system info, restart/shutdown, version.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get searchSystem;

  /// Admin settings search section/title: plugins catalog and repositories.
  ///
  /// In en, this message translates to:
  /// **'Plugins'**
  String get searchPlugins;

  /// Admin settings search section: Server Configuration group.
  ///
  /// In en, this message translates to:
  /// **'Server Configuration'**
  String get searchServerConfiguration;

  /// Admin settings search section: Content & Access group (libraries, users, devices, sessions).
  ///
  /// In en, this message translates to:
  /// **'Content & Access'**
  String get searchContentAccess;

  /// Admin settings search section: Maintenance group (tasks, logs, system).
  ///
  /// In en, this message translates to:
  /// **'Maintenance'**
  String get searchMaintenance;

  /// Admin settings search section: Extensions group (plugins).
  ///
  /// In en, this message translates to:
  /// **'Extensions'**
  String get searchExtensions;

  /// OS notification title when a download finishes.
  ///
  /// In en, this message translates to:
  /// **'Download complete'**
  String get notifDownloadComplete;

  /// Title of the Chromecast device-picker sheet.
  ///
  /// In en, this message translates to:
  /// **'Cast to'**
  String get castTo;

  /// Label on the Cast button/pill that opens the device picker.
  ///
  /// In en, this message translates to:
  /// **'Cast'**
  String get castAction;

  /// Shown while scanning for Chromecast devices.
  ///
  /// In en, this message translates to:
  /// **'Searching for devices…'**
  String get castSearching;

  /// Snackbar when resolving/starting a cast fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start casting'**
  String get castFailed;

  /// Ends the current Chromecast session.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get castDisconnect;

  /// Button to end casting and return to local playback.
  ///
  /// In en, this message translates to:
  /// **'Stop Casting'**
  String get castStop;

  /// Header showing the connected Chromecast.
  ///
  /// In en, this message translates to:
  /// **'Casting to {device}'**
  String castConnectedTo(String device);

  /// Header shown while a cast session is starting.
  ///
  /// In en, this message translates to:
  /// **'Connecting to {device}…'**
  String castConnecting(String device);

  /// OS notification title while a download is in progress.
  ///
  /// In en, this message translates to:
  /// **'Downloading'**
  String get notifDownloading;

  /// OS notification title when a download fails.
  ///
  /// In en, this message translates to:
  /// **'Download failed'**
  String get notifDownloadFailed;

  /// OS notification title when a new Seerr request is made.
  ///
  /// In en, this message translates to:
  /// **'New request'**
  String get notifNewRequest;

  /// OS notification body for a new pending Seerr request.
  ///
  /// In en, this message translates to:
  /// **'{title} · pending approval'**
  String notifPendingApproval(String title);

  /// OS notification title when a requested title becomes available.
  ///
  /// In en, this message translates to:
  /// **'{title} is now available'**
  String notifNowAvailable(String title);

  /// OS notification body when a requested title becomes available.
  ///
  /// In en, this message translates to:
  /// **'Downloaded and ready to watch'**
  String get notifNowAvailableBody;

  /// OS notification title when a Seerr request is approved.
  ///
  /// In en, this message translates to:
  /// **'Request approved'**
  String get notifRequestApproved;

  /// OS notification title when a Seerr request is declined.
  ///
  /// In en, this message translates to:
  /// **'Request declined'**
  String get notifRequestDeclined;

  /// OS notification title for a generic Seerr request status change.
  ///
  /// In en, this message translates to:
  /// **'Request update'**
  String get notifRequestUpdate;

  /// Fallback title in a notification when a requested movie's name can't be fetched.
  ///
  /// In en, this message translates to:
  /// **'A movie'**
  String get notifAMovie;

  /// Fallback title in a notification when a requested show's name can't be fetched.
  ///
  /// In en, this message translates to:
  /// **'A TV show'**
  String get notifAShow;

  /// Settings hub entry to export/import app settings.
  ///
  /// In en, this message translates to:
  /// **'Backup & Restore'**
  String get settingsBackup;

  /// Subtitle for the Backup & Restore settings entry.
  ///
  /// In en, this message translates to:
  /// **'Export or import your app settings'**
  String get settingsBackupSubtitle;

  /// Title of the Backup & Restore screen.
  ///
  /// In en, this message translates to:
  /// **'Backup & Restore'**
  String get backupTitle;

  /// Explains what a settings backup contains and excludes.
  ///
  /// In en, this message translates to:
  /// **'Move your app settings and server addresses between devices. Passwords and API keys are never exported, so you\'ll sign in again after importing.'**
  String get backupIntro;

  /// Action to export settings to a file.
  ///
  /// In en, this message translates to:
  /// **'Export Settings'**
  String get backupExportTitle;

  /// Export subtitle on desktop (save to a file).
  ///
  /// In en, this message translates to:
  /// **'Save your settings to a file.'**
  String get backupExportSub;

  /// Export subtitle on mobile (share the file).
  ///
  /// In en, this message translates to:
  /// **'Share your settings as a file.'**
  String get backupExportSubShare;

  /// Subject line when sharing the settings file.
  ///
  /// In en, this message translates to:
  /// **'Fathom settings'**
  String get backupExportSubject;

  /// Confirmation after saving the export.
  ///
  /// In en, this message translates to:
  /// **'Saved to {path}'**
  String backupSavedTo(Object path);

  /// Action to import settings from a file.
  ///
  /// In en, this message translates to:
  /// **'Import Settings'**
  String get backupImportTitle;

  /// Import subtitle.
  ///
  /// In en, this message translates to:
  /// **'Restore from a file, replacing your current settings.'**
  String get backupImportSub;

  /// Title of the import confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Import settings?'**
  String get backupImportConfirmTitle;

  /// Body of the import confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Your current settings will be replaced, and you\'ll sign in to your server again.'**
  String get backupImportConfirmBody;

  /// Confirm button on the import dialog.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get backupImportAction;

  /// Confirmation after a successful import.
  ///
  /// In en, this message translates to:
  /// **'Settings imported.'**
  String get backupImported;

  /// Import confirmation listing servers to sign back into.
  ///
  /// In en, this message translates to:
  /// **'Settings imported. Sign in to reconnect: {servers}'**
  String backupImportedWithServers(Object servers);

  /// Error when the chosen file is not a Fathom backup.
  ///
  /// In en, this message translates to:
  /// **'That file is not a valid Fathom settings backup.'**
  String get backupInvalid;

  /// Generic backup or import failure.
  ///
  /// In en, this message translates to:
  /// **'Backup failed: {error}'**
  String backupFailed(Object error);

  /// Title of the import group-selection dialog.
  ///
  /// In en, this message translates to:
  /// **'Choose what to import'**
  String get backupImportChoose;

  /// Backup group: theme, accent, Home layout.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get backupGroupAppearance;

  /// Backup group: player and playback settings.
  ///
  /// In en, this message translates to:
  /// **'Player'**
  String get backupGroupPlayer;

  /// Backup group: YouTube client settings.
  ///
  /// In en, this message translates to:
  /// **'YouTube'**
  String get backupGroupYoutube;

  /// Backup group: everything else (notifications, updates, language).
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get backupGroupGeneral;

  /// Backup group: saved radio stations, groups, favorites.
  ///
  /// In en, this message translates to:
  /// **'Internet Radio'**
  String get backupGroupRadio;

  /// Backup group: server addresses and username.
  ///
  /// In en, this message translates to:
  /// **'Servers'**
  String get backupGroupServers;

  /// Snackbar shown when the TV has no speech recognizer for the on-screen keyboard's mic button.
  ///
  /// In en, this message translates to:
  /// **'Voice input isn\'t available on this device'**
  String get tvVoiceUnavailable;

  /// Title of the elimination-wheel decider screen.
  ///
  /// In en, this message translates to:
  /// **'Movie Night Wheel'**
  String get wheelTitle;

  /// Shown on the wheel setup screen when there are no titles to pick from yet.
  ///
  /// In en, this message translates to:
  /// **'Search your library above to add titles, or put a few on your Watchlist.'**
  String get wheelNeedsWatchlist;

  /// Instructions on the wheel's setup screen, above the checklist.
  ///
  /// In en, this message translates to:
  /// **'Pick at least two titles, then spin.'**
  String get wheelSetupHint;

  /// Start button label, showing how many titles are selected.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Start with 1 Title} other{Start with {count} Titles}}'**
  String wheelStartWith(int count);

  /// Disabled Start button label when fewer than 2 titles are selected.
  ///
  /// In en, this message translates to:
  /// **'Pick at Least 2 Titles'**
  String get wheelNeedTwo;

  /// Header above the wheel showing how many titles remain in this round.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 Left} other{{count} Left}}'**
  String wheelRemaining(int count);

  /// Hint text below the wheel.
  ///
  /// In en, this message translates to:
  /// **'Tap or flick the wheel to spin'**
  String get wheelTapToSpin;

  /// Shown over a dimmed poster right after a spin eliminates a title.
  ///
  /// In en, this message translates to:
  /// **'{name} is out!'**
  String wheelEliminated(String name);

  /// Small eyebrow label above the winning title's poster.
  ///
  /// In en, this message translates to:
  /// **'TONIGHT\'S PICK'**
  String get wheelWinnerLabel;

  /// Button to restart the wheel from the setup screen.
  ///
  /// In en, this message translates to:
  /// **'Spin Again'**
  String get wheelSpinAgain;

  /// Hint below the wheel on TV, where the remote's OK/Select button spins it.
  ///
  /// In en, this message translates to:
  /// **'Press OK to spin'**
  String get wheelPressToSpin;

  /// Wheel game mode: each spin eliminates a title until one remains.
  ///
  /// In en, this message translates to:
  /// **'Last One Standing'**
  String get wheelModeLast;

  /// Wheel game mode: one spin picks the winner.
  ///
  /// In en, this message translates to:
  /// **'Single Spin'**
  String get wheelModeSingle;

  /// Wheel game mode: the first title landed on twice wins.
  ///
  /// In en, this message translates to:
  /// **'Best of 3'**
  String get wheelModeBest3;

  /// Explains the Last One Standing mode on the setup screen.
  ///
  /// In en, this message translates to:
  /// **'Each spin knocks one title out until one is left.'**
  String get wheelModeLastHint;

  /// Explains the Single Spin mode on the setup screen.
  ///
  /// In en, this message translates to:
  /// **'One spin. Wherever it lands is tonight\'s pick.'**
  String get wheelModeSingleHint;

  /// Explains the Best of 3 mode on the setup screen.
  ///
  /// In en, this message translates to:
  /// **'The first title the wheel lands on twice wins.'**
  String get wheelModeBest3Hint;

  /// Label of the search field for adding library titles to the wheel.
  ///
  /// In en, this message translates to:
  /// **'Add from Your Library'**
  String get wheelSearchLabel;

  /// Placeholder in the wheel's library search field.
  ///
  /// In en, this message translates to:
  /// **'Search movies and shows'**
  String get wheelSearchHint;

  /// Shown under the wheel's library search when nothing matches.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get wheelNoResults;

  /// Tag on a wheel candidate that was added from the library rather than the Watchlist.
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get wheelAdded;

  /// Tag on a wheel candidate the user has already watched.
  ///
  /// In en, this message translates to:
  /// **'Watched'**
  String get wheelWatched;

  /// Filter chip: only include titles not yet watched.
  ///
  /// In en, this message translates to:
  /// **'Unwatched'**
  String get wheelFilterUnwatched;

  /// Filter chip: only include titles with a runtime of 2 hours or less.
  ///
  /// In en, this message translates to:
  /// **'Under 2 Hours'**
  String get wheelFilterUnder2h;

  /// Genre filter chip label when no genre is chosen.
  ///
  /// In en, this message translates to:
  /// **'Genre'**
  String get wheelFilterGenre;

  /// Genre filter menu option that clears the genre filter.
  ///
  /// In en, this message translates to:
  /// **'All Genres'**
  String get wheelFilterAllGenres;

  /// Button that checks every title currently shown on the wheel setup list.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get wheelSelectAll;

  /// Button that unchecks every title currently shown on the wheel setup list.
  ///
  /// In en, this message translates to:
  /// **'Select None'**
  String get wheelSelectNone;

  /// Shown on the wheel setup list when the filters exclude every title.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches these filters.'**
  String get wheelNothingMatches;

  /// Button under the wheel that reverses the last result.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get wheelUndo;

  /// Header above the wheel in Best of 3 mode.
  ///
  /// In en, this message translates to:
  /// **'Spin {current} of {total}'**
  String wheelSpinOf(int current, int total);

  /// Header above the wheel when three spins landed on three different titles.
  ///
  /// In en, this message translates to:
  /// **'Tiebreaker: This Spin Decides It'**
  String get wheelTiebreak;

  /// Header above the wheel in Single Spin mode.
  ///
  /// In en, this message translates to:
  /// **'One Spin Decides It'**
  String get wheelSingleHeader;

  /// Shown over a poster in Best of 3 mode when the wheel lands on it.
  ///
  /// In en, this message translates to:
  /// **'{name} scores!'**
  String wheelScored(String name);

  /// Tooltip for the wheel's sound toggle while sound is on.
  ///
  /// In en, this message translates to:
  /// **'Mute Sounds'**
  String get wheelMute;

  /// Tooltip for the wheel's sound toggle while sound is off.
  ///
  /// In en, this message translates to:
  /// **'Unmute Sounds'**
  String get wheelUnmute;

  /// Play button on the wheel's result screen while in a Watch Together group.
  ///
  /// In en, this message translates to:
  /// **'Play for Group'**
  String get wheelPlayForGroup;

  /// Note under the result screen's buttons while in a Watch Together group.
  ///
  /// In en, this message translates to:
  /// **'Everyone in your Watch Together group will start watching.'**
  String get wheelGroupHint;

  /// Sleep timer button tooltip, player menu entry, and sheet title.
  ///
  /// In en, this message translates to:
  /// **'Sleep Timer'**
  String get sleepTimer;

  /// Sleep timer option: stop playback after this many minutes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 Minute} other{{count} Minutes}}'**
  String sleepTimerMinutes(int count);

  /// Sleep timer option: stop when the current song finishes instead of playing the next.
  ///
  /// In en, this message translates to:
  /// **'End of Track'**
  String get sleepTimerEndOfTrack;

  /// Sleep timer option: stop when the current episode finishes instead of playing the next.
  ///
  /// In en, this message translates to:
  /// **'End of Episode'**
  String get sleepTimerEndOfEpisode;

  /// Sleep timer option: stop when the current movie or video finishes.
  ///
  /// In en, this message translates to:
  /// **'End of Video'**
  String get sleepTimerEndOfVideo;

  /// Sleep timer countdown, e.g. 'Stops in 23m'.
  ///
  /// In en, this message translates to:
  /// **'Stops in {time}'**
  String sleepTimerStopsIn(String time);

  /// Sleep timer status when set to stop at the end of the current track or episode.
  ///
  /// In en, this message translates to:
  /// **'Stops at the end of this one'**
  String get sleepTimerAfterThis;

  /// Button that cancels a running sleep timer.
  ///
  /// In en, this message translates to:
  /// **'Turn Off'**
  String get sleepTimerTurnOff;

  /// Tooltip / screen-reader label for the repeat (off / all / one) button.
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get commonRepeat;

  /// Tooltip / screen-reader label for a three-dot overflow menu button.
  ///
  /// In en, this message translates to:
  /// **'More Options'**
  String get commonMoreOptions;

  /// Tooltip / screen-reader label for the button that reveals the typed password.
  ///
  /// In en, this message translates to:
  /// **'Show Password'**
  String get loginShowPassword;

  /// Tooltip / screen-reader label for the button that hides the typed password again.
  ///
  /// In en, this message translates to:
  /// **'Hide Password'**
  String get loginHidePassword;

  /// Screen-reader label for the spinning wheel.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Movie Night Wheel with 1 title} other{Movie Night Wheel with {count} titles}}'**
  String a11yWheel(int count);

  /// Screen-reader name of the action that spins the wheel.
  ///
  /// In en, this message translates to:
  /// **'Spin'**
  String get a11ySpin;

  /// Screen-reader announcement of the wheel's final pick.
  ///
  /// In en, this message translates to:
  /// **'Tonight\'s pick: {name}'**
  String a11yWinner(String name);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
