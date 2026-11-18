# soliplex_folder_picker

Picks a folder through the platform's own document picker and reads its files
by the reference that picker grants. The app's folder upload uses it where a
picked folder's path cannot be read with `dart:io`, and `file_picker`
elsewhere.

| Platform | Status |
| -------- | ------ |
| Android  | Implemented: `ACTION_OPEN_DOCUMENT_TREE`, walked with `DocumentsContract`. Scoped storage hides other apps' files under the tree's path. |
| iOS      | Not yet. See below. |

## Quick start

```bash
cd packages/soliplex_folder_picker
flutter test
flutter analyze --fatal-infos
```

## The contract

`SoliplexFolderPicker` (`lib/soliplex_folder_picker.dart`) documents the four
methods a platform answers on the `ai.soliplex/folder_picker` channel: `pick`,
`open`, `read` and `close`. The Dart side and its tests are platform-agnostic.
A platform passes them by answering those methods as documented.

The caller (`pickFolderImpl` in the app) skips dot-segments and flattens
names; the platform lists every file and nothing else.

## Adding iOS

1. In `pubspec.yaml`, add beside `android`:

   ```yaml
   ios:
     pluginClass: SoliplexFolderPickerPlugin
   ```

2. Add `ios/soliplex_folder_picker.podspec` and
   `ios/Classes/SoliplexFolderPickerPlugin.swift` (`flutter create
   --template=plugin --platforms=ios` scaffolds both). Pick with
   `UIDocumentPickerViewController(forOpeningContentTypes: [.folder])`; call
   `startAccessingSecurityScopedResource()` on the picked URL, enumerate it
   with `FileManager`, and read with `FileHandle`. Stop accessing once the last
   handle is closed.
3. Add `TargetPlatform.iOS` to `SoliplexFolderPicker.supportedPlatforms`. The
   app then routes iOS folder picks here with no change of its own.
4. Check on a device: pick a folder from Files (iCloud Drive and On My
   iPhone), with a subfolder and a dotfile, from a thread's "Upload to
   thread → Folder…" and from room info's "Upload folder to room".
