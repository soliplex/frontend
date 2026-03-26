import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/vs2015.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:markdown/markdown.dart' as md;

class CodeBlockBuilder extends MarkdownElementBuilder {
  CodeBlockBuilder({required this.preferredStyle});

  final TextStyle preferredStyle;

  @override
  Widget? visitElementAfter(
    md.Element element,
    TextStyle? preferredStyle,
  ) {
    final code = element.textContent;
    final language = _languageFrom(element);

    if (language == 'svg') {
      return Semantics(
        label: 'SVG image',
        child: _SvgCodeBlock(code: code, codeStyle: this.preferredStyle),
      );
    }

    final semanticLabel =
        language == 'plaintext' ? 'Code block' : 'Code block in $language';
    return Semantics(
      label: semanticLabel,
      child: _CodeBlock(
        code: code,
        language: language,
        codeStyle: this.preferredStyle,
      ),
    );
  }

  static String _languageFrom(md.Element pre) {
    final children = pre.children;
    if (children != null) {
      for (final child in children) {
        if (child is md.Element && child.tag == 'code') {
          final className = child.attributes['class'];
          if (className != null && className.startsWith('language-')) {
            return className.replaceFirst('language-', '');
          }
        }
      }
    }
    return 'plaintext';
  }
}

Future<void> _copyToClipboard(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    const SnackBar(content: Text('Copied to clipboard')),
  );
}

class _ToolbarIconButton extends StatelessWidget {
  const _ToolbarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: iconColor),
        ),
      ),
    );
  }
}

class _SvgCodeBlock extends StatefulWidget {
  const _SvgCodeBlock({required this.code, required this.codeStyle});

  final String code;
  final TextStyle codeStyle;

  @override
  State<_SvgCodeBlock> createState() => _SvgCodeBlockState();
}

class _SvgCodeBlockState extends State<_SvgCodeBlock> {
  bool _showSource = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(theme),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: _showSource ? _sourceView() : _previewView(),
        ),
      ],
    );
  }

  Widget _previewView() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 400),
      child: SvgPicture.string(
        widget.code,
        placeholderBuilder: (_) => const SizedBox.shrink(),
        errorBuilder: (_, __, ___) => const Icon(
          Icons.broken_image,
          size: 48,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _sourceView() {
    return HighlightView(
      widget.code,
      language: 'xml',
      theme: githubTheme,
      padding: EdgeInsets.zero,
      textStyle: widget.codeStyle,
    );
  }

  Widget _toolbar(ThemeData theme) {
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, top: 4),
          child: Text('svg', style: labelStyle),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: _ToolbarIconButton(
            icon: _showSource ? Icons.image : Icons.code,
            tooltip: _showSource ? 'Show preview' : 'Show source',
            onTap: () => setState(() => _showSource = !_showSource),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 4, top: 4),
          child: _ToolbarIconButton(
            icon: Icons.copy,
            tooltip: 'Copy SVG',
            onTap: () => _copyToClipboard(context, widget.code),
          ),
        ),
      ],
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({
    required this.code,
    required this.language,
    required this.codeStyle,
  });

  final String code;
  final String language;
  final TextStyle codeStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (language != 'plaintext')
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 4),
                child: Text(
                  language,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(right: 4, top: 4),
              child: _ToolbarIconButton(
                icon: Icons.copy,
                tooltip: 'Copy code',
                onTap: () => _copyToClipboard(context, code),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: HighlightView(
            code,
            language: language,
            theme:
                theme.brightness == Brightness.dark ? vs2015Theme : githubTheme,
            padding: EdgeInsets.zero,
            textStyle: codeStyle,
          ),
        ),
      ],
    );
  }
}
