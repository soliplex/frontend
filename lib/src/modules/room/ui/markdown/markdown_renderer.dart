import 'package:flutter/widgets.dart';

typedef MarkdownLinkHandler = void Function(String href, String? title);
typedef MarkdownImageHandler = void Function(String src, String? alt);

abstract class MarkdownRenderer extends StatelessWidget {
  const MarkdownRenderer({
    required this.data,
    this.onLinkTap,
    this.onImageTap,
    super.key,
  });

  final String data;

  /// Overrides the default link-tap behavior. When null, taps open the link
  /// in the platform's default handler (browser, mail client, etc.).
  final MarkdownLinkHandler? onLinkTap;
  final MarkdownImageHandler? onImageTap;
}
