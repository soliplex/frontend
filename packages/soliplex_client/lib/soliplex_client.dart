/// Pure Dart client for Soliplex backend HTTP and AG-UI APIs.
library soliplex_client;

// AG-UI protocol from ag_ui package.
// TextPart and ImagePart name the domain's message parts; AG-UI's wire parts
// of the same names are exported as AguiTextPart and AguiImagePart.
// FileSource names the room module's file origin; nothing outside this package
// needs AG-UI's provider-file part source.
export 'package:ag_ui/ag_ui.dart'
    hide CancelToken, FileSource, ImagePart, TextPart;

export 'src/api/api.dart';
export 'src/application/application.dart';
export 'src/auth/auth.dart';
export 'src/domain/domain.dart';
export 'src/errors/errors.dart';
export 'src/http/http.dart';
export 'src/utils/utils.dart';
