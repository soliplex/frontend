final _brTag = RegExp(r'<br\s*/?>');

/// Replaces HTML `<br>` line breaks with newlines so the markdown parser
/// renders them as breaks rather than dropping the unknown tag.
String sanitizeMarkdown(String markdown) => markdown.replaceAll(_brTag, '\n');
