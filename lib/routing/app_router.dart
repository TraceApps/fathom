import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'route_observer.dart';

import '../models/base_item.dart';
import '../models/server_connection.dart';
import '../screens/accounts_screen.dart';
import '../screens/admin_config_screens.dart';
import '../screens/admin_screen.dart';
import '../screens/detail_screen.dart';
import '../screens/backup_screen.dart';
import '../screens/diagnostics_screen.dart';
import '../screens/discover_screen.dart';
import '../screens/downloads_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/favorites_screen.dart';
import '../screens/artists_screen.dart';
import '../screens/genres_screen.dart';
import '../screens/home_layout_screen.dart';
import '../screens/navigation_layout_screen.dart';
import '../screens/keyboard_shortcuts_screen.dart';
import '../screens/home_screen.dart';
import '../screens/libraries_screen.dart';
import '../screens/library_screen.dart';
import '../screens/live_tv_screen.dart';
import '../screens/login_screen.dart';
import '../screens/movie_wheel_screen.dart';
import '../screens/person_screen.dart';
import '../screens/now_playing_screen.dart';
import '../screens/exo_player_screen.dart';
import '../screens/player_screen.dart';
import '../services/tv_mode.dart';
import '../screens/youtube_channel_screen.dart';
import '../screens/youtube_player_screen.dart';
import '../screens/radio_screen.dart';
import '../screens/watchlist_screen.dart';
import '../screens/youtube_screen.dart';
import '../screens/youtube_watch_screen.dart';
import '../screens/youtube_shorts_screen.dart';
import '../models/youtube_video.dart';
import '../screens/playlist_detail_screen.dart';
import '../screens/playlists_screen.dart';
import '../screens/preferences_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/program_detail_screen.dart';
import '../screens/search_screen.dart';
import '../models/seerr_detail.dart';
import '../screens/seerr_collection_screen.dart';
import '../screens/seerr_credits_screen.dart';
import '../screens/seerr_detail_screen.dart';
import '../screens/seerr_person_screen.dart';
import '../screens/seerr_season_screen.dart';
import '../screens/seerr_settings_screen.dart';
import '../models/arr.dart';
import '../screens/arr_activity_screens.dart';
import '../screens/arr_add_screen.dart';
import '../screens/arr_detail_screens.dart';
import '../screens/arr_files_screen.dart';
import '../screens/arr_import_screen.dart';
import '../screens/arr_collections_screen.dart';
import '../screens/arr_releases_screen.dart';
import '../screens/arr_screen.dart';
import '../screens/arr_settings_screen.dart';
import '../screens/updates_screen.dart';
import '../models/seerr_result.dart';
import '../screens/server_connect_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/support_screen.dart';
import '../screens/studios_screen.dart';
import '../screens/syncplay_screen.dart';
import '../screens/user_edit_screen.dart';
import '../screens/splash_screen.dart';
import '../screens/youtube_playlist_screen.dart';
import '../screens/youtube_my_playlist_screen.dart';
import '../state/preferences.dart';
import '../state/session_controller.dart';
import 'app_shell.dart';

CustomTransitionPage<void> _fadePage(Widget child, {LocalKey? key}) {
  return CustomTransitionPage<void>(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    transitionsBuilder: (context, animation, secondary, child) {
      final inCurve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      // The outgoing page eases back slightly for a soft cross-fade of depth.
      final outCurve = CurvedAnimation(
        parent: secondary,
        curve: Curves.easeInCubic,
        reverseCurve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: inCurve,
        child: SlideTransition(
          position: Tween<Offset>(
                  begin: const Offset(0, 0.018), end: Offset.zero)
              .animate(inCurve),
          child: FadeTransition(
            opacity: Tween<double>(begin: 1, end: 0).animate(outCurve),
            child: ScaleTransition(
              scale: Tween<double>(begin: 1, end: 0.985).animate(outCurve),
              child: child,
            ),
          ),
        ),
      );
    },
  );
}

/// Holds the splash for a minimum beat so startup reads as a branded moment
/// rather than a flash, even when the persisted session restores instantly.
/// Starts counting the first time it's read (app launch). Shorten or drop the
/// duration here to change how long the splash lingers.
final splashReadyProvider = FutureProvider<void>(
    (ref) => Future<void>.delayed(const Duration(milliseconds: 3200)));

final routerProvider = Provider<GoRouter>((ref) {
  // Rebuild the router's redirect whenever the session changes.
  final refresh = ValueNotifier<int>(0);
  ref.onDispose(refresh.dispose);
  // Only refresh the router when the redirect-relevant state changes: whether
  // the session is loading, and whether it's signed in. In-place session edits
  // (an internal/external address swap) must NOT churn the router — doing so
  // while on a deep route trips a framework teardown assertion.
  ref.listen(sessionControllerProvider, (prev, next) {
    if ((prev?.isLoading ?? true) != next.isLoading ||
        (prev?.value != null) != (next.value != null)) {
      refresh.value++;
    }
  });
  ref.listen(splashReadyProvider, (_, _) => refresh.value++);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    // navWatcher first so its didPush records the route kind before
    // routeObserver dispatches didPushNext to the player.
    observers: [navWatcher, routeObserver],
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionControllerProvider);
      final loc = state.matchedLocation;

      // Stay on the splash while the session restores or the minimum splash
      // beat hasn't elapsed, whichever is longer.
      final splashReady = ref.read(splashReadyProvider).hasValue;
      if (session.isLoading || !splashReady) {
        return loc == '/' ? null : '/';
      }

      final loggedIn = session.asData?.value != null;
      final onAuthFlow = loc == '/connect' || loc == '/login';

      if (!loggedIn) {
        return onAuthFlow ? null : '/connect';
      }
      // Signed in: only bounce the splash. /connect + /login stay reachable so
      // you can add another account; LoginScreen navigates home on success.
      if (loc == '/') {
        final start = ref.read(preferencesProvider).asData?.value.startupScreen;
        return switch (start) {
          'libraries' => '/libraries',
          'livetv' => '/livetv',
          _ => '/home',
        };
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SplashScreen()),
      GoRoute(
          path: '/connect', builder: (_, _) => const ServerConnectScreen()),
      GoRoute(
        path: '/login',
        builder: (context, state) =>
            LoginScreen(connection: state.extra as ServerConnection),
      ),
      // Full-screen routes sit outside the shell (no mini-player bar).
      GoRoute(
        path: '/player',
        pageBuilder: (context, state) {
          final e = state.extra;
          final backend =
              ref.read(preferencesProvider).asData?.value.playerBackend ??
                  'auto';
          // Key the page by item id so replacing the player with a DIFFERENT
          // item (a SyncPlay group switching content) builds a fresh
          // PlayerScreen that actually loads the new media, instead of reusing
          // the old screen (same route path) and keeping the old video playing.
          final BaseItemDto item;
          final bool resume;
          if (e is BaseItemDto) {
            item = e;
            resume = true;
          } else if (e is ({BaseItemDto item, bool resume})) {
            item = e.item;
            resume = e.resume;
          } else {
            // The route's `extra` was lost (e.g. an app-level remount rebuilt
            // this page from scratch — go_router doesn't retain `extra` across
            // that). Never hard-cast null here; that crashes the whole app to a
            // blank screen. Send the user home instead.
            return _fadePage(const _LostPlayerRoute(),
                key: const ValueKey('player-lost'));
          }
          // The native ExoPlayer backend handles VOD when selected (tunneled
          // 4K/HDR). Live TV also uses ExoPlayer on Android TV: it's the only
          // path that renders the broadcast's embedded CEA-608 captions there
          // (ExoPlayer decodes them in its own text renderer; media_kit/mpv on
          // the TV box doesn't surface them). Live stays on media_kit elsewhere.
          final useExo = item.isLiveChannel
              ? isTvDevice
              : exoBackendActive(backend);
          final Widget screen = useExo
              ? ExoPlayerScreen(item: item, resume: resume)
              : PlayerScreen(item: item, resume: resume);
          return _fadePage(screen, key: ValueKey('player-${item.id}'));
        },
      ),
      GoRoute(
        path: '/trailer',
        pageBuilder: (context, state) {
          final e = state.extra;
          if (e is String) {
            return _fadePage(YoutubePlayerScreen(url: e, isTrailer: true));
          }
          final r = e as ({String url, String? title});
          return _fadePage(YoutubePlayerScreen(
              url: r.url, title: r.title, isTrailer: true));
        },
      ),
      GoRoute(
        path: '/youtube/watch',
        pageBuilder: (context, state) {
          final r = state.extra as ({String videoId, String? title});
          return _fadePage(
              YoutubeWatchScreen(videoId: r.videoId, title: r.title));
        },
      ),
      GoRoute(
        path: '/youtube/shorts',
        pageBuilder: (context, state) {
          final r = state.extra as ({
            List<YoutubeVideo> shorts,
            int startIndex,
            String? continuation,
          });
          return _fadePage(YoutubeShortsScreen(
            shorts: r.shorts,
            startIndex: r.startIndex,
            continuation: r.continuation,
          ));
        },
      ),
      // On the root navigator, not in the shell, and deliberately so. The
      // watch page is a root route, so a shell route pushed from it lands in
      // the shell's navigator — underneath the video that's still on screen.
      // The channel page opened behind the watch page and looked like a dead
      // click. It carries its own Scaffold and back button, so it stands alone
      // here, and the sidebar behaviour now matches the watch page it's
      // reached from.
      GoRoute(
        path: '/youtube/channel',
        pageBuilder: (context, state) {
          final r = state.extra as ({String channelId, String? title});
          return _fadePage(
              YoutubeChannelScreen(channelId: r.channelId, title: r.title));
        },
      ),
      // Root navigator too, for the same reason as the channel page: it's
      // opened from search inside the shell AND from pages that aren't.
      GoRoute(
        path: '/youtube/playlist',
        pageBuilder: (context, state) {
          final r =
              state.extra as ({String playlistId, String? title, int? count});
          return _fadePage(YoutubePlaylistScreen(
              playlistId: r.playlistId,
              title: r.title,
              expectedCount: r.count));
        },
      ),
      // Your own playlists, as opposed to /youtube/playlist which shows
      // someone else's fetched from YouTube.
      // A downloaded file. The player opens anything that isn't a YouTube URL
      // straight from disk, so this needs no special plumbing beyond the
      // route; YoutubeDownloadPlayerScreen adds resume + channel/art parity
      // with the online watch page, scoped to the download's own local state.
      GoRoute(
        path: '/youtube/file',
        pageBuilder: (context, state) {
          final r = state.extra as ({
            String path,
            String videoId,
            String? title,
            String? author,
            String? thumbnailUrl,
          });
          return _fadePage(YoutubeDownloadPlayerScreen(
            path: r.path,
            videoId: r.videoId,
            title: r.title,
            author: r.author,
            thumbnailUrl: r.thumbnailUrl,
          ));
        },
      ),
      GoRoute(
        path: '/youtube/my-playlist',
        pageBuilder: (context, state) => _fadePage(
            YoutubeMyPlaylistScreen(playlistId: state.extra as String)),
      ),
      GoRoute(
        path: '/nowplaying',
        pageBuilder: (_, _) => _fadePage(const NowPlayingScreen()),
      ),
      // Signed-in content routes share the shell + docked mini now-playing bar.
      ShellRoute(
        navigatorKey: shellNavigatorKey,
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
              path: '/home',
              pageBuilder: (_, _) => _fadePage(const HomeScreen())),
          GoRoute(
            path: '/item',
            pageBuilder: (context, state) =>
                _fadePage(DetailScreen(item: state.extra as BaseItemDto)),
          ),
          GoRoute(
            path: '/library',
            pageBuilder: (context, state) =>
                _fadePage(LibraryScreen(library: state.extra as BaseItemDto)),
          ),
          GoRoute(
              path: '/search',
              pageBuilder: (_, _) => _fadePage(const SearchScreen())),
          GoRoute(
              path: '/libraries',
              pageBuilder: (_, _) => _fadePage(const LibrariesScreen())),
          GoRoute(
              path: '/livetv',
              pageBuilder: (_, _) => _fadePage(const LiveTvScreen())),
          GoRoute(
              path: '/youtube',
              pageBuilder: (_, state) =>
                  _fadePage(YoutubeScreen(initialTab: state.extra as int?))),
          GoRoute(
              path: '/radio',
              pageBuilder: (_, _) => _fadePage(const RadioScreen())),
          GoRoute(
            path: '/program',
            pageBuilder: (context, state) =>
                _fadePage(ProgramDetailScreen(args: state.extra as ProgramArgs)),
          ),
          GoRoute(
              path: '/settings',
              pageBuilder: (_, _) => _fadePage(const SettingsScreen())),
          GoRoute(
            path: '/preferences',
            pageBuilder: (context, state) => _fadePage(
                PreferencesScreen(section: state.extra as String? ?? 'appearance')),
          ),
          GoRoute(
              path: '/favorites',
              pageBuilder: (_, _) => _fadePage(const FavoritesScreen())),
          GoRoute(
              path: '/watchlist',
              pageBuilder: (_, _) => _fadePage(const WatchlistScreen())),
          GoRoute(
              path: '/watchlist/wheel',
              pageBuilder: (_, _) => _fadePage(const MovieWheelScreen())),
          GoRoute(
              path: '/home-layout',
              pageBuilder: (_, _) => _fadePage(const HomeLayoutScreen())),
          GoRoute(
              path: '/navigation-layout',
              pageBuilder: (_, _) =>
                  _fadePage(const NavigationLayoutScreen())),
          GoRoute(
              path: '/shortcuts',
              pageBuilder: (_, _) =>
                  _fadePage(const KeyboardShortcutsScreen())),
          GoRoute(
              path: '/support',
              pageBuilder: (_, _) => _fadePage(const SupportScreen())),
          GoRoute(
              path: '/genres',
              pageBuilder: (_, _) => _fadePage(const GenresScreen())),
          GoRoute(
            path: '/genre',
            pageBuilder: (context, state) =>
                _fadePage(GenreItemsScreen(genre: state.extra as String)),
          ),
          GoRoute(
              path: '/studios',
              pageBuilder: (_, _) => _fadePage(const StudiosScreen())),
          GoRoute(
              path: '/artists',
              pageBuilder: (_, _) => _fadePage(const ArtistsScreen())),
          GoRoute(
            path: '/artist',
            pageBuilder: (context, state) {
              final a = state.extra as BaseItemDto;
              return _fadePage(
                  ArtistAlbumsScreen(artistId: a.id, artistName: a.name));
            },
          ),
          GoRoute(
            path: '/studio',
            pageBuilder: (context, state) =>
                _fadePage(StudioItemsScreen(studio: state.extra as String)),
          ),
          GoRoute(
              path: '/playlists',
              pageBuilder: (_, _) => _fadePage(const PlaylistsScreen())),
          GoRoute(
            path: '/playlist',
            pageBuilder: (context, state) => _fadePage(
                PlaylistDetailScreen(playlist: state.extra as BaseItemDto)),
          ),
          GoRoute(
            path: '/person',
            pageBuilder: (context, state) =>
                _fadePage(PersonScreen(person: state.extra as Person)),
          ),
          GoRoute(
              path: '/admin',
              pageBuilder: (_, _) => _fadePage(const AdminScreen())),
          GoRoute(
            path: '/admin/user',
            pageBuilder: (context, state) =>
                _fadePage(UserEditScreen(userId: state.extra as String)),
          ),
          GoRoute(
              path: '/admin/general',
              pageBuilder: (_, _) => _fadePage(const AdminGeneralScreen())),
          GoRoute(
              path: '/admin/playback',
              pageBuilder: (_, _) => _fadePage(const AdminPlaybackScreen())),
          GoRoute(
              path: '/admin/branding',
              pageBuilder: (_, _) => _fadePage(const AdminBrandingScreen())),
          GoRoute(
              path: '/admin/network',
              pageBuilder: (_, _) => _fadePage(const AdminNetworkScreen())),
          GoRoute(
              path: '/admin/apikeys',
              pageBuilder: (_, _) => _fadePage(const AdminApiKeysScreen())),
          GoRoute(
              path: '/admin/backups',
              pageBuilder: (_, _) => _fadePage(const AdminBackupsScreen())),
          GoRoute(
              path: '/admin/logs',
              pageBuilder: (_, _) => _fadePage(const AdminLogsScreen())),
          GoRoute(
            path: '/admin/logs/view',
            pageBuilder: (context, state) =>
                _fadePage(AdminLogViewScreen(name: state.extra as String)),
          ),
          GoRoute(
              path: '/admin/system',
              pageBuilder: (_, _) => _fadePage(const AdminSystemScreen())),
          GoRoute(
              path: '/admin/users',
              pageBuilder: (_, _) => _fadePage(const AdminUsersScreen())),
          GoRoute(
              path: '/admin/libraries',
              pageBuilder: (_, _) => _fadePage(const AdminLibrariesScreen())),
          GoRoute(
              path: '/admin/tasks',
              pageBuilder: (_, _) => _fadePage(const AdminTasksScreen())),
          GoRoute(
              path: '/admin/sessions',
              pageBuilder: (_, _) => _fadePage(const AdminSessionsScreen())),
          GoRoute(
              path: '/admin/activity',
              pageBuilder: (_, _) => _fadePage(const AdminActivityScreen())),
          GoRoute(
              path: '/admin/plugins',
              pageBuilder: (_, _) => _fadePage(const AdminPluginsScreen())),
          GoRoute(
            path: '/admin/plugins/installed',
            pageBuilder: (context, state) => _fadePage(AdminInstalledPluginScreen(
                plugin: state.extra as Map<String, dynamic>)),
          ),
          GoRoute(
            path: '/admin/plugins/package',
            pageBuilder: (context, state) => _fadePage(
                AdminPackageScreen(package: state.extra as Map<String, dynamic>)),
          ),
          GoRoute(
              path: '/admin/devices',
              pageBuilder: (_, _) => _fadePage(const AdminDevicesScreen())),
          GoRoute(
              path: '/admin/livetv',
              pageBuilder: (_, _) => _fadePage(const AdminLiveTvScreen())),
          GoRoute(
              path: '/admin/dvr',
              pageBuilder: (_, _) => _fadePage(const AdminDvrScreen())),
          GoRoute(
              path: '/accounts',
              pageBuilder: (_, _) => _fadePage(const AccountsScreen())),
          GoRoute(
              path: '/profile',
              pageBuilder: (_, _) => _fadePage(const ProfileScreen())),
          GoRoute(
              path: '/downloads',
              pageBuilder: (_, _) => _fadePage(const DownloadsScreen())),
          GoRoute(
              path: '/downloads/detail',
              pageBuilder: (context, state) => _fadePage(
                  DownloadDetailScreen(itemKey: state.extra as String))),
          GoRoute(
              path: '/notifications',
              pageBuilder: (_, _) => _fadePage(const NotificationsScreen())),
          GoRoute(
              path: '/discover',
              pageBuilder: (_, _) => _fadePage(const DiscoverScreen())),
          GoRoute(
              path: '/seerr-settings',
              pageBuilder: (_, _) => _fadePage(const SeerrSettingsScreen())),
          GoRoute(
              path: '/arr',
              pageBuilder: (_, _) => _fadePage(const ArrScreen())),
          GoRoute(
              path: '/arr-settings',
              pageBuilder: (_, _) => _fadePage(const ArrSettingsScreen())),
          GoRoute(
              path: '/arr/movie/:id',
              pageBuilder: (_, state) => _fadePage(ArrMovieScreen(
                  id: int.tryParse(state.pathParameters['id'] ?? '') ?? 0))),
          GoRoute(
              path: '/arr/add',
              pageBuilder: (_, state) => _fadePage(ArrAddScreen(
                  term: state.uri.queryParameters['term']))),
          GoRoute(
              path: '/arr/add/:kind',
              pageBuilder: (_, state) => _fadePage(ArrAddScreen(
                  kind: state.pathParameters['kind'] == 'series'
                      ? ArrKind.sonarr
                      : ArrKind.radarr,
                  term: state.uri.queryParameters['term'],
                  folder: state.uri.queryParameters['folder']))),
          GoRoute(
              path: '/arr/collections',
              pageBuilder: (_, _) => _fadePage(const ArrCollectionsScreen())),
          GoRoute(
              path: '/arr/blocklist',
              pageBuilder: (_, _) => _fadePage(const ArrBlocklistScreen())),
          GoRoute(
              path: '/arr/health',
              pageBuilder: (_, _) => _fadePage(const ArrHealthScreen())),
          GoRoute(
              path: '/arr/releases',
              pageBuilder: (_, state) => _fadePage(ArrReleasesScreen(
                  target: ArrReleaseTarget.fromQuery(
                      state.uri.queryParameters)))),
          GoRoute(
              path: '/arr/import',
              pageBuilder: (_, state) => _fadePage(ArrImportScreen(
                  target: ArrImportTarget.fromQuery(
                      state.uri.queryParameters)))),
          GoRoute(
              path: '/arr/series/:id/files',
              pageBuilder: (_, state) => _fadePage(ArrSeriesFilesScreen(
                  id: int.tryParse(state.pathParameters['id'] ?? '') ?? 0))),
          GoRoute(
              path: '/arr/series/:id',
              pageBuilder: (_, state) => _fadePage(ArrSeriesScreen(
                  id: int.tryParse(state.pathParameters['id'] ?? '') ?? 0))),
          GoRoute(
              path: '/updates',
              pageBuilder: (_, _) => _fadePage(const UpdatesScreen())),
          GoRoute(
              path: '/diagnostics',
              pageBuilder: (_, _) => _fadePage(const DiagnosticsScreen())),
          GoRoute(
              path: '/backup',
              pageBuilder: (_, _) => _fadePage(const BackupScreen())),
          GoRoute(
            path: '/seerr-detail',
            pageBuilder: (context, state) =>
                _fadePage(SeerrDetailScreen(result: state.extra as SeerrResult)),
          ),
          // Deep link to a title by id, used by notifications (which can't carry
          // a SeerrResult object). The detail screen fills in the real data.
          GoRoute(
            path: '/seerr/:type/:id',
            pageBuilder: (context, state) {
              final type = state.pathParameters['type'] == 'tv' ? 'tv' : 'movie';
              final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
              return _fadePage(SeerrDetailScreen(
                  result: SeerrResult(tmdbId: id, mediaType: type, title: '')));
            },
          ),
          GoRoute(
            path: '/seerr-category',
            pageBuilder: (context, state) {
              final e = state.extra as ({String key, String title});
              return _fadePage(
                  SeerrCategoryScreen(categoryKey: e.key, title: e.title));
            },
          ),
          GoRoute(
            path: '/seerr-person',
            pageBuilder: (context, state) => _fadePage(
                SeerrPersonScreen(personId: state.extra as int)),
          ),
          GoRoute(
            path: '/seerr-credits',
            pageBuilder: (context, state) {
              final e = state.extra as ({
                String title,
                List<SeerrCast> cast,
                List<SeerrCrew> crew
              });
              return _fadePage(SeerrCreditsScreen(
                  title: e.title, cast: e.cast, crew: e.crew));
            },
          ),
          GoRoute(
            path: '/seerr-collection',
            pageBuilder: (context, state) => _fadePage(
                SeerrCollectionScreen(collectionId: state.extra as int)),
          ),
          GoRoute(
            path: '/seerr-season',
            pageBuilder: (context, state) {
              final e = state.extra
                  as ({int tvId, int seasonNumber, String seasonName});
              return _fadePage(SeerrSeasonScreen(
                  tvId: e.tvId,
                  seasonNumber: e.seasonNumber,
                  seasonName: e.seasonName));
            },
          ),
          GoRoute(
            path: '/seerr-genre',
            pageBuilder: (context, state) {
              final e = state.extra
                  as ({String mediaType, int genreId, String title});
              return _fadePage(SeerrGenreScreen(
                  mediaType: e.mediaType,
                  genreId: e.genreId,
                  title: e.title));
            },
          ),
          GoRoute(
            path: '/seerr-company',
            pageBuilder: (context, state) {
              final e =
                  state.extra as ({String kind, int id, String title});
              return _fadePage(SeerrCompanyScreen(
                  kind: e.kind, id: e.id, title: e.title));
            },
          ),
          GoRoute(
              path: '/seerr-layout',
              pageBuilder: (_, _) =>
                  _fadePage(const SeerrDiscoverLayoutScreen())),
          GoRoute(
              path: '/syncplay',
              pageBuilder: (_, _) => _fadePage(const SyncPlayScreen())),
        ],
      ),
    ],
  );
});

/// Fallback shown if a `/player` route is ever built without its `extra` (the
/// item). Rather than crash on a null cast, it bounces straight back home.
class _LostPlayerRoute extends StatefulWidget {
  const _LostPlayerRoute();

  @override
  State<_LostPlayerRoute> createState() => _LostPlayerRouteState();
}

class _LostPlayerRouteState extends State<_LostPlayerRoute> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go('/');
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(backgroundColor: Colors.black);
}
