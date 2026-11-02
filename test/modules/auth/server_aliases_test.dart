import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/auth/server_aliases.dart';
import 'package:soliplex_frontend/src/modules/auth/server_entry.dart';

void main() {
  final url = Uri.parse('https://api.example.com');
  final base = aliasFromUrl(url);

  test('derives the alias from the URL', () {
    expect(ServerAliases().claim(url), base);
  });

  test('suffixes a derived alias that is taken', () {
    final aliases = ServerAliases();

    expect(
      [aliases.claim(url), aliases.claim(url), aliases.claim(url)],
      [base, '$base-2', '$base-3'],
    );
  });

  test('keeps a free preferred alias', () {
    expect(ServerAliases().claim(url, preferred: 'mine'), 'mine');
  });

  test('derives one when the preferred alias is taken', () {
    final aliases = ServerAliases()..claim(url, preferred: 'mine');

    expect(aliases.claim(url, preferred: 'mine'), base);
  });

  test('a released alias can be claimed again', () {
    final aliases = ServerAliases();
    final first = aliases.claim(url);

    aliases.release(first);

    expect(aliases.claim(url), first);
  });

  test('clear frees every alias', () {
    final aliases = ServerAliases()
      ..claim(url)
      ..claim(url, preferred: 'mine');

    aliases.clear();

    expect(aliases.claim(url), base);
    expect(aliases.claim(url, preferred: 'mine'), 'mine');
  });
}
