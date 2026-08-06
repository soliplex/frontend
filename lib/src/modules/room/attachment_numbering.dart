import 'package:soliplex_agent/soliplex_agent.dart';

/// How many attachment slots sit before each message in [messages].
///
/// A thread's images are numbered in one sequence rather than restarting per
/// message, so that one number names one image for as long as the thread lasts;
/// a message needs to know how many came before it to number its own.
///
/// Counts slots, so an attachment that could not be rebuilt still spends its
/// number and the images after it keep the ones they were given. This is the
/// same rule the AG-UI mapper numbers by on the way out, which is what lets the
/// number the user reads match the one the model was told.
List<int> attachmentOffsets(List<ChatMessage> messages) {
  final offsets = List<int>.filled(messages.length, 0);
  var before = 0;
  for (var i = 0; i < messages.length; i++) {
    offsets[i] = before;
    final message = messages[i];
    if (message is TextMessage) {
      before += message.parts?.attachmentCount ?? 0;
    }
  }
  return offsets;
}
