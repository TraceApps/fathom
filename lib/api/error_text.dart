import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../l10n/l10n.dart';
import '../services/diagnostics.dart';
import 'arr_client.dart';
import 'jellyfin_client.dart';
import 'mdblist_client.dart';
import 'seerr_client.dart';

/// What to tell a person about a failure, whatever was thrown.
///
/// The clients throw their own exceptions with a message written to be read
/// (a rejected key, a server that isn't there). Those are shown as they are.
/// Anything else used to reach the screen as Dart printed it ("DioException
/// [connection error]: ...", "type 'Null' is not a subtype of ..."); it is
/// said plainly here, and what was thrown goes to the diagnostics log.
String errorText(Object error) {
  var e = error;
  // A client's own exception, carried inside the one the network layer threw.
  if (e is DioException && _written(e.error) != null) e = e.error!;
  final written = _written(e);
  if (written != null) return written;
  if (e is String) return e;
  if (e is DioException) return dioErrorText(e);
  if (e is SocketException) return tr.errLostConnection;
  if (e is TimeoutException) return tr.errTimeout;
  if (e is TlsException) return tr.errCertificate;
  // `throw Exception('...')`: words of ours, behind Dart's own prefix.
  final said = e.toString();
  if (e is Exception && said.startsWith('Exception: ') && said.length > 11) {
    return said.substring(11);
  }
  Diagnostics.instance.add('error', '${e.runtimeType}: $e');
  return tr.errUnexpected;
}

String? _written(Object? e) => switch (e) {
  JellyfinException() => e.message,
  ArrException() => e.message,
  SeerrException() => e.message,
  MdbListException() => e.message,
  _ => null,
};

/// A failed request in plain words. [connecting] is for the first contact
/// with an address someone typed, where "not found" means "no server here".
String dioErrorText(DioException e, {bool connecting = false}) {
  final l = tr;
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return l.errTimeout;
    case DioExceptionType.connectionError:
      return connecting ? l.errUnreachable : l.errLostConnection;
    case DioExceptionType.badCertificate:
      return l.errCertificate;
    case DioExceptionType.badResponse:
      final code = e.response?.statusCode;
      if (code == 404) return connecting ? l.errNoServerHere : l.errNotFound;
      if (code == 401 && !connecting) return l.errSignInEnded;
      return code == null ? l.errTalking : l.errServer(code);
    default:
      return l.errTalking;
  }
}
