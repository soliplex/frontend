import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/room/response_segmenter.dart';

const _result = ServerToolCallCompleted(toolCallId: 'c1', result: 'ok');

void main() {
  test('the first message to speak in a response takes its work', () {
    // A producer that emits two texts in one response has not done two
    // things, so the second must not split the response's work.
    final segmenter = ResponseSegmenter()
      ..speaks('m1')
      ..speaks('m2')
      ..arrives(_result);

    expect(segmenter.arrives(const ThinkingStarted()), equals('m1'));
  });

  test('a result ends its response only when the next one starts', () {
    // State the tool wrote and a parallel call's result still belong to the
    // response that made the call.
    final segmenter = ResponseSegmenter()
      ..speaks('m1')
      ..arrives(_result);

    expect(segmenter.arrives(const StateUpdated(aguiState: {})), isNull);
    expect(segmenter.speaks('m2'), equals('m1'));
  });

  test('a response that said nothing leaves its work for the next speaker', () {
    final segmenter = ResponseSegmenter()..arrives(_result);

    expect(segmenter.arrives(const ThinkingStarted()), isNull);
    expect(segmenter.ends(), isNull);
  });

  test('the run ending hands the open response to whoever spoke in it', () {
    final segmenter = ResponseSegmenter()..speaks('m1');

    expect(segmenter.ends(), equals('m1'));
  });
}
