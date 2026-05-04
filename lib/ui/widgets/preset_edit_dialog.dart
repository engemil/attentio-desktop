import 'package:flutter/material.dart';

import 'package:attentio_desktop/providers/presets_provider.dart';

/// Dialog for creating or editing a [DevicePreset].
///
/// Returns the edited [DevicePreset] on save, or `null` if cancelled.
/// Pass [existing] and [index] to enable delete functionality.
class PresetEditDialog extends StatefulWidget {
  const PresetEditDialog({
    super.key,
    this.existing,
    this.index,
    this.initialR = 255,
    this.initialG = 255,
    this.initialB = 255,
    this.initialBrightness = 100,
  });

  /// If non-null, we are editing an existing preset.
  final DevicePreset? existing;

  /// Index of the preset being edited (used for context only).
  final int? index;

  /// Default colour/brightness when creating a new preset (typically the
  /// current Controls card state).
  final int initialR;
  final int initialG;
  final int initialB;
  final int initialBrightness;

  @override
  State<PresetEditDialog> createState() => _PresetEditDialogState();
}

/// Sentinel value returned to signal that the preset should be deleted.
class PresetDeleteSentinel {
  const PresetDeleteSentinel();
}

class _PresetEditDialogState extends State<PresetEditDialog> {
  late final TextEditingController _nameCtrl;
  late double _r;
  late double _g;
  late double _b;
  late double _brightness;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _r = (e?.r ?? widget.initialR).toDouble();
    _g = (e?.g ?? widget.initialG).toDouble();
    _b = (e?.b ?? widget.initialB).toDouble();
    _brightness = (e?.brightness ?? widget.initialBrightness).toDouble();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(DevicePreset(
      name: name,
      r: _r.round(),
      g: _g.round(),
      b: _b.round(),
      brightness: _brightness.round(),
    ));
  }

  void _delete() {
    Navigator.of(context).pop(const PresetDeleteSentinel());
  }

  @override
  Widget build(BuildContext context) {
    final previewColor = Color.fromARGB(255, _r.round(), _g.round(), _b.round());
    return AlertDialog(
      actionsAlignment: _isEditing ? MainAxisAlignment.spaceBetween : MainAxisAlignment.end,
      title: Text(_isEditing ? 'Edit Preset' : 'Save as Preset'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: previewColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    // ignore: deprecated_member_use
                    '#${previewColor.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildSlider('R', _r, Colors.red, (v) => setState(() => _r = v)),
              _buildSlider('G', _g, Colors.green, (v) => setState(() => _g = v)),
              _buildSlider('B', _b, Colors.blue, (v) => setState(() => _b = v)),
              const SizedBox(height: 8),
              Text('Brightness: ${_brightness.round()}%'),
              Slider(
                value: _brightness,
                min: 0,
                max: 100,
                divisions: 100,
                label: '${_brightness.round()}%',
                onChanged: (v) => setState(() => _brightness = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (_isEditing)
          TextButton(
            onPressed: _delete,
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _buildSlider(
    String label,
    double value,
    Color activeColor,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(width: 16, child: Text(label)),
        Expanded(
          child: Slider(
            value: value,
            min: 0,
            max: 255,
            divisions: 255,
            activeColor: activeColor,
            label: value.round().toString(),
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 32, child: Text(value.round().toString())),
      ],
    );
  }
}
