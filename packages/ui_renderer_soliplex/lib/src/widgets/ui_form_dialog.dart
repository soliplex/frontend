import 'package:flutter/material.dart';

/// Renders a simple form from a JSON schema map.
///
/// Schema shape (PR 2 — string fields only):
/// ```json
/// {
///   "title": "Optional dialog title override",
///   "fields": [
///     { "name": "email", "label": "Email", "required": true },
///     { "name": "notes", "label": "Notes", "required": false }
///   ]
/// }
/// ```
/// Richer schema shapes (selects, dates, nested objects) are deferred to
/// the layout refactor when inline system-message forms land.
class UiFormDialog extends StatefulWidget {
  const UiFormDialog({super.key, required this.schema, required this.title});

  final Map<String, Object?> schema;
  final String title;

  static Future<Map<String, Object?>?> show({
    required BuildContext context,
    required String title,
    required Map<String, Object?> schema,
  }) {
    return showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => UiFormDialog(title: title, schema: schema),
    );
  }

  @override
  State<UiFormDialog> createState() => _UiFormDialogState();
}

class _UiFormDialogState extends State<UiFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};

  List<Map<String, Object?>> get _fields {
    final raw = widget.schema['fields'];
    if (raw is! List) return const [];
    return raw.cast<Map<String, Object?>>();
  }

  @override
  void initState() {
    super.initState();
    for (final field in _fields) {
      final name = field['name'] as String? ?? '';
      _controllers[name] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      final values = {
        for (final entry in _controllers.entries) entry.key: entry.value.text,
      };
      Navigator.of(context).pop(values);
    }
  }

  @override
  Widget build(BuildContext context) {
    final schemaTitle = widget.schema['title'] as String?;
    return AlertDialog(
      title: Text(schemaTitle ?? widget.title),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _fields.map((field) {
              final name = field['name'] as String? ?? '';
              final label = field['label'] as String? ?? name;
              final required = field['required'] as bool? ?? true;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  controller: _controllers[name],
                  decoration: InputDecoration(labelText: label),
                  validator: required
                      ? (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null
                      : null,
                ),
              );
            }).toList(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Submit')),
      ],
    );
  }
}
