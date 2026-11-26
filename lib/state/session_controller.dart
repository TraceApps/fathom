import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/accounts_store.dart';
import '../models/session.dart';
import 'providers.dart';

final accountsStoreProvider = Provider<AccountsStore>((ref) {
  return AccountsStore(ref.watch(secureStorageProvider));
});

/// Holds the active [Session] (or null when signed out) and manages the full
/// set of signed-in accounts (multi-server / multi-user).
class SessionController extends AsyncNotifier<Session?> {
  AccountsStore get _store => ref.read(accountsStoreProvider);
  Accounts _accounts = const Accounts();

  @override
  Future<Session?> build() async {
    _accounts = await _store.load();
    return _accounts.active;
  }

  List<Session> get accounts => _accounts.sessions;
  String? get activeKey => _accounts.activeKey;

  Future<void> signIn(Session session) async {
    final key = accountKey(session);
    final others =
        _accounts.sessions.where((s) => accountKey(s) != key).toList();
    _accounts = Accounts(sessions: [...others, session], activeKey: key);
    await _store.save(_accounts);
    state = AsyncData(session);
  }

  Future<void> switchTo(Session session) async {
    _accounts =
        Accounts(sessions: _accounts.sessions, activeKey: accountKey(session));
    await _store.save(_accounts);
    state = AsyncData(_accounts.active);
  }

  Future<void> removeAccount(Session session) async {
    final key = accountKey(session);
    final remaining =
        _accounts.sessions.where((s) => accountKey(s) != key).toList();
    final wasActive = _accounts.activeKey == key;
    _accounts = Accounts(
      sessions: remaining,
      activeKey: wasActive
          ? (remaining.isNotEmpty ? accountKey(remaining.first) : null)
          : _accounts.activeKey,
    );
    await _store.save(_accounts);
    state = AsyncData(_accounts.active);
  }

  /// Replace the active session in the account list, preserving its identity
  /// key (serverId+userId), so callers can mutate address fields safely.
  void _replaceActive(Session updated) {
    final key = accountKey(updated);
    _accounts = Accounts(
      sessions: [
        for (final s in _accounts.sessions)
          accountKey(s) == key ? updated : s,
      ],
      activeKey: _accounts.activeKey,
    );
  }

  /// Swap the address the app uses right now (driven by the address resolver as
  /// the home network comes and goes). Identity keys on serverId+userId, so this
  /// never re-keys or forks the account.
  Future<void> setActiveBaseUrl(String url) async {
    final active = _accounts.active;
    if (active == null || active.baseUrl == url) return;
    final updated = active.copyWith(baseUrl: url);
    _replaceActive(updated);
    await _store.save(_accounts);
    state = AsyncData(updated);
  }

  /// Configure the active account's internal (home) and external (remote)
  /// addresses. Pass null for either to clear it. Setting both enables the
  /// seamless reachability-based switching.
  Future<void> setServerAddresses({
    required String? internal,
    required String? external,
  }) async {
    final active = _accounts.active;
    if (active == null) return;
    final updated =
        active.copyWith(internalUrl: internal, externalUrl: external);
    _replaceActive(updated);
    await _store.save(_accounts);
    state = AsyncData(updated);
  }

  /// Sets the home and remote addresses of the signed-in account [key]
  /// (see [accountKey]), active or not. A restore uses this for every
  /// account the backup has addresses for.
  Future<void> setAddressesFor(
    String key, {
    required String? internal,
    required String? external,
  }) async {
    if (key == _accounts.activeKey) {
      return setServerAddresses(internal: internal, external: external);
    }
    final sessions = [
      for (final s in _accounts.sessions)
        accountKey(s) == key
            ? s.copyWith(internalUrl: internal, externalUrl: external)
            : s,
    ];
    _accounts = Accounts(sessions: sessions, activeKey: _accounts.activeKey);
    await _store.save(_accounts);
  }

  /// Signs out the active account (switching to another if one remains).
  Future<void> signOut() async {
    final active = _accounts.active;
    if (active != null) {
      await removeAccount(active);
    } else {
      state = const AsyncData(null);
    }
  }
}

final sessionControllerProvider =
    AsyncNotifierProvider<SessionController, Session?>(SessionController.new);
