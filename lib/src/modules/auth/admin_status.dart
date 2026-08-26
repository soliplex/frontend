import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final Logger _logger = LogManager.instance.getLogger('soliplex.admin_status');

/// Whether the signed-in user administers one server.
///
/// The question takes no room, so one answer serves every room on that server.
/// Answering it writes an `admin_access_allowed` or `admin_access_denied`
/// audit record server-side, which is why an answer is kept rather than asked
/// per screen.
///
/// A verdict the installation delivered is kept until [clear]. A request that
/// could not be answered at all is not kept, so a blip does not pin "unknown"
/// for the rest of the session; neither is a refusal, which answers but cannot
/// be attributed to the installation — [_fetch] says why at that arm.
///
/// Two things clear it, and neither covers the other: signing out, and the
/// signed-in identity changing. `ServerManager` and `UserSwitchTeardown` each
/// say why at their call site.
final class AdminStatus {
  /// Reads through [api], which must be the api for [serverId].
  AdminStatus({required SoliplexApi api, required String serverId})
      : _api = api,
        _serverId = serverId;

  final SoliplexApi _api;
  final String _serverId;

  Future<bool?>? _pending;

  /// Which signed-in identity the answers belong to. A request carries the
  /// epoch it was issued under, so one that outlives a [clear] can tell it has
  /// been retired.
  ///
  /// Bumped by [clear] rather than by [read], so nothing depends on `??=`
  /// leaving its right-hand side unevaluated on a cache hit: a bump there
  /// would retire the in-flight request that a concurrent reader is waiting
  /// on, and pin the `null` it returns for the rest of the session.
  ///
  /// At most one live request matches this at a time, which is what makes the
  /// comparison mean "still installed". That rests on a failing request
  /// clearing [_pending] and returning with nothing suspending in between: an
  /// `await` anywhere in that tail would leave it live while the slot is free,
  /// so the next [read] would install a sibling on the same epoch and both
  /// would pass the test.
  int _generation = 0;

  /// Whether the signed-in user is an administrator, or `null` when the
  /// question could not be answered.
  ///
  /// Never completes with an error, so callers need no guard: the final `catch`
  /// in [_fetch] is bare rather than `on Exception`, so an `Error` is reported
  /// as unanswered rather than thrown, and logging cannot throw past it because
  /// `LogManager` guards every sink write. `null` is not "no" — callers decide
  /// what to do without an answer. A refusal is a "no" and arrives as `false`,
  /// so no caller has to read a denial out of an absence.
  Future<bool?> read() => _pending ??= _fetch(_generation);

  Future<bool?> _fetch(int generation) async {
    try {
      final isAdmin = await _api.getIsAdminUser();
      // A [clear] while this was in flight retired it: the answer describes
      // whoever was signed in when it was asked, so it is dropped rather than
      // handed to a caller who by now means someone else.
      return generation == _generation ? isAdmin : null;
    } on PermissionDeniedException catch (e) {
      // A refusal is the server answering, not failing to answer. Folding it
      // into `null` would hand the caller a grant, so the gate would loosen
      // exactly as the installation tightened.
      //
      // Answered, but not kept, unlike a `false` that arrives over 200. That
      // one is attributable — the installation said it. A refusal is not: this
      // endpoint is contracted to answer, so a 403 is either a policy this
      // client does not model or a gateway refusing on the installation's
      // behalf, and the second locks out an administrator who is one. Releasing
      // the slot costs an ask per screen that opens the card and buys the
      // recourse of leaving and coming back.
      //
      // At `warning` because the release log floor drops anything lower, and
      // because both readings above are worth a record. The message is the
      // backend's own text, so only the status is kept.
      _logger.warning(
        'The administrator check was refused; treating the caller as not one',
        attributes: {'serverId': _serverId, 'statusCode': e.statusCode},
      );
      if (generation == _generation) _pending = null;
      return generation == _generation ? false : null;
    } catch (e, st) {
      // Releasing the slot lets the next read ask again; the generation test
      // keeps a request already retired by [clear] from dropping the newer one
      // that replaced it.
      if (generation == _generation) _pending = null;
      // This request carries no user input — a fixed path, no body — so
      // nothing it could put in a [NetworkException]'s message is a value the
      // user or the backend supplied, and the host and OS error left there are
      // the whole diagnosis, so it is forwarded whole. The reasoning is about
      // this request, not about the type: `DartHttpClient` interpolates the
      // underlying exception into that message, so a request carrying a body
      // would need the same treatment as below. Anything else can carry
      // the response it failed on, so only its shape is kept. That shape is a
      // bare type name for an [ApiException], which would leave a proxy's 502
      // and the installation's own 500 indistinguishable, so the status code
      // rides alongside — it is a protocol constant, not a value the server
      // chose to put in the response.
      _logger.warning(
        'Could not check whether the user is an administrator',
        error: e is NetworkException ? e : null,
        attributes: {
          'serverId': _serverId,
          if (e is ApiException) 'statusCode': e.statusCode,
          if (e is! NetworkException) 'failure': describeFailure(e),
        },
        stackTrace: st,
      );
      return null;
    }
  }

  /// Forgets the answer and retires any request in flight, so the next [read]
  /// asks again.
  void clear() {
    // Retiring is what the bump does: [_fetch] compares against this, so a
    // request still in flight can neither deliver its answer nor clear a slot
    // a later [read] installs.
    _generation++;
    _pending = null;
  }
}
