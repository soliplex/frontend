import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_frontend/src/modules/room/workdir_files_status.dart';

void main() {
  group('workdirErrorMessage', () {
    test('asks for a new sign-in on AuthException', () {
      expect(
        workdirErrorMessage(const AuthException(message: 'token abc')),
        'Sign in again to see these files.',
      );
    });

    test('says the server is unreachable on NetworkException', () {
      expect(
        workdirErrorMessage(const NetworkException(message: 'http://x/y')),
        "Couldn't reach the server.",
      );
    });

    test('says the server is unavailable on a 5xx ApiException', () {
      expect(
        workdirErrorMessage(
            const ApiException(message: 'boom', statusCode: 503)),
        'Server is temporarily unavailable.',
      );
    });

    test('is generic on an ApiException below 500', () {
      expect(
        workdirErrorMessage(
            const ApiException(message: 'bad', statusCode: 400)),
        'Something went wrong.',
      );
    });

    test('is generic on a non-Soliplex error', () {
      expect(workdirErrorMessage(TypeError()), 'Something went wrong.');
    });
  });
}
