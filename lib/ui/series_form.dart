import 'package:flutter/material.dart';

import '../models/series.dart';

class SeriesFormResult {
  const SeriesFormResult({
    required this.url,
    required this.title,
    required this.chapter,
    required this.status,
    required this.openAfter,
  });

  final String url;
  final String title;
  final String chapter;
  final ReadStatus status;
  final bool openAfter;
}

/// Bottom sheet used both to add (optionally pre-filled from a share) and to
/// edit a series.
class SeriesForm extends StatefulWidget {
  const SeriesForm({
    super.key,
    this.existing,
    this.initialUrl,
    this.initialTitle,
  });

  final Series? existing;
  final String? initialUrl;
  final String? initialTitle;

  @override
  State<SeriesForm> createState() => _SeriesFormState();
}

class _SeriesFormState extends State<SeriesForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _url;
  late final TextEditingController _title;
  late final TextEditingController _chapter;
  late ReadStatus _status;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _url = TextEditingController(text: e?.url ?? widget.initialUrl ?? '');
    _title = TextEditingController(text: e?.title ?? widget.initialTitle ?? '');
    _chapter = TextEditingController(text: e?.chapter ?? '');
    _status = e?.status ?? ReadStatus.reading;
  }

  @override
  void dispose() {
    _url.dispose();
    _title.dispose();
    _chapter.dispose();
    super.dispose();
  }

  static String _normalizeUrl(String raw) {
    final t = raw.trim();
    return t.contains('://') ? t : 'https://$t';
  }

  String? _validateUrl(String? v) {
    final u = Uri.tryParse(_normalizeUrl(v ?? ''));
    final ok =
        u != null &&
        (u.scheme == 'http' || u.scheme == 'https') &&
        u.host.contains('.');
    return ok ? null : 'Enter a valid link';
  }

  void _submit(bool open) {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      SeriesFormResult(
        url: _normalizeUrl(_url.text),
        title: _title.text.trim(),
        chapter: _chapter.text.trim(),
        status: _status,
        openAfter: open,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _editing ? 'Edit series' : 'Add to shelf',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Link to the chapter or series page',
                  border: OutlineInputBorder(),
                ),
                validator: _validateUrl,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _title,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Title',
                  helperText: _editing
                      ? null
                      : 'Leave empty to detect from the page',
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_editing) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _chapter,
                  decoration: const InputDecoration(
                    labelText: 'Current chapter',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final s in ReadStatus.values)
                    ChoiceChip(
                      label: Text(s.label),
                      selected: _status == s,
                      onSelected: (_) => setState(() => _status = s),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _submit(false),
                      child: const Text('Save'),
                    ),
                  ),
                  if (!_editing) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => _submit(true),
                        child: const Text('Save & read'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
