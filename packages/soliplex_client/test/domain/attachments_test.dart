import 'package:soliplex_client/soliplex_client.dart';
import 'package:test/test.dart';

void main() {
  test('sandboxSkillName matches the backend wire key', () {
    expect(sandboxSkillName, 'bubble-sandbox');
  });
}
