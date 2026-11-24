import 'package:flutter_test/flutter_test.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_frontend/src/modules/room/pdf/pdf_quote.dart';
import 'package:soliplex_frontend/src/modules/room/pdf/pending_quotes.dart';

void main() {
  const a = PdfQuote(text: 'a', documentTitle: 'x.pdf', pageNumber: 1);
  const b = PdfQuote(text: 'b', documentTitle: 'x.pdf', pageNumber: 2);

  late RoomQuotes quotes;
  setUp(() => quotes = RoomQuotes());
  tearDown(() => quotes.dispose());

  test('keeps quotes per thread', () {
    quotes
      ..add('t1', a)
      ..add('t2', b);
    expect(quotes.peek('t1'), [a]);
    expect(quotes.peek('t2'), [b]);
    expect(quotes.peek(null), isEmpty);
  });

  test('does not add the same passage twice', () {
    quotes
      ..add('t', a)
      ..add('t',
          const PdfQuote(text: 'a', documentTitle: 'x.pdf', pageNumber: 1));
    expect(quotes.peek('t'), [a]);
  });

  test('take empties the thread', () {
    quotes
      ..add('t', a)
      ..add('t', b);
    expect(quotes.take('t'), [a, b]);
    expect(quotes.peek('t'), isEmpty);
    expect(quotes.take('t'), isEmpty);
  });

  test('restore puts a failed send back in front', () {
    quotes.add('t', b);
    quotes.restore('t', [a, b]);
    expect(quotes.peek('t'), [a, b]);
  });

  test('remove and clearThread drop quotes', () {
    quotes
      ..add('t', a)
      ..add('t', b)
      ..remove('t', a);
    expect(quotes.peek('t'), [b]);
    quotes.clearThread('t');
    expect(quotes.peek('t'), isEmpty);
  });

  test('migrateToThread moves the welcome screen quotes', () {
    quotes
      ..add(null, a)
      ..migrateToThread('new');
    expect(quotes.peek(null), isEmpty);
    expect(quotes.peek('new'), [a]);
  });

  test('migrateToThread with nothing waiting changes nothing', () {
    quotes
      ..add('existing', b)
      ..migrateToThread('existing');
    expect(quotes.peek('existing'), [b]);
  });

  test('watch subscribes the reader to changes', () {
    final seen = <List<PdfQuote>>[];
    final stop = effect(() => seen.add(quotes.watch('t')));
    quotes.add('t', a);
    quotes.add('other', b);
    stop();
    expect(seen, [
      isEmpty,
      [a],
      [a]
    ]);
  });
}
