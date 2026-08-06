import 'package:soliplex_agent/soliplex_agent.dart';

/// Stands for one image in a persisted draft.
///
/// The same marker serves every image, unlike the per-image code units the
/// live composer uses: a draft carries no bytes, so at restore time every
/// image is unavailable and there is no identity for two markers to confuse.
///
/// It is a non-whitespace character, which is what lets a draft of images and
/// no caption reach storage at all: `persistComposerDraft` returns early on a
/// whitespace-only draft, leaving an older draft in the slot to be restored
/// later in its place.
const composerDraftImageMarker = '￼';

/// Serializes [parts] to the single string a composer draft is stored as:
/// text runs verbatim, one [composerDraftImageMarker] per image, in order.
///
/// **A draft carries each image's position and none of its bytes.** Drafts
/// live in `SharedPreferences`, which on Android is an XML file read whole
/// into memory at first access, and base64 inflates by 4/3 — so persisted
/// images would be paid for at every launch. The source images are still on
/// the device, where re-picking one is a few taps; retyping a paragraph is
/// not.
///
/// The inverse is `InlineImageComposerController.restoreDraft`, which turns
/// each marker back into a placeholder the user must remove before sending, so
/// nothing is dropped from the message without them seeing it go.
String encodeComposerDraft(List<MessagePart> parts) {
  final draft = StringBuffer();
  for (final part in parts) {
    switch (part) {
      case TextPart(:final text):
        // The marker has to mean one thing. A copy out of a PDF can carry the
        // same character, and restoring that as an image would tell the user
        // an image they never attached went missing; it stands for an object
        // that is not there, so dropping it costs nothing visible.
        draft.write(text.replaceAll(composerDraftImageMarker, ''));
      case ImagePart():
      case MissingAttachmentPart():
        draft.write(composerDraftImageMarker);
    }
  }
  return draft.toString();
}
