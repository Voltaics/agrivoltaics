import 'package:flutter/material.dart';

import '../../../../../app_colors.dart';
import '../../../../../models/frost_rule_config.dart';
import 'frost_engine_config_field_specs.dart';

/// Generates a grouped, collapsible form from [frostConfigFieldSpecs] —
/// one `TextFormField`/`DropdownButtonFormField` per spec, instead of a
/// hand-built controller per field (this config surface has ~35 threshold
/// fields, too many for `create_alert_rule_dialog.dart`'s pattern).
///
/// Owns its own `TextEditingController`s, seeded from [initialValues] once.
/// To reset the form for a different zone, give this widget a new `key`
/// (e.g. `ValueKey(zoneId)`) rather than relying on `didUpdateWidget` —
/// Flutter will tear down and recreate the state, which re-seeds cleanly.
class FrostEngineConfigFormBuilder extends StatefulWidget {
  const FrostEngineConfigFormBuilder({
    super.key,
    required this.initialValues,
    required this.onFieldChanged,
    this.enabled = true,
  });

  /// Current values keyed by `frostRuleConfig` field name — see
  /// `FrostRuleConfig.toFieldMap()`.
  final Map<String, dynamic> initialValues;

  /// Called with the parsed value whenever a field changes and passes its
  /// own validation. The caller (the config dialog) is the source of truth
  /// for the draft being saved.
  final void Function(String key, dynamic value) onFieldChanged;

  final bool enabled;

  @override
  State<FrostEngineConfigFormBuilder> createState() =>
      _FrostEngineConfigFormBuilderState();
}

class _FrostEngineConfigFormBuilderState extends State<FrostEngineConfigFormBuilder> {
  final Map<String, TextEditingController> _controllers = {};
  late Map<String, String> _dropdownValues;

  @override
  void initState() {
    super.initState();

    _dropdownValues = {};

    for (final spec in frostConfigFieldSpecs) {
      final value = widget.initialValues[spec.key];

      switch (spec.type) {
        case FrostConfigFieldType.growthStageDropdown:
          _dropdownValues[spec.key] =
              value is String && kFrostGrowthStages.contains(value)
                  ? value
                  : kFrostGrowthStages.first;
          break;
        case FrostConfigFieldType.decimal:
        case FrostConfigFieldType.integer:
        case FrostConfigFieldType.text:
          _controllers[spec.key] = TextEditingController(text: value?.toString() ?? '');
          break;
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String? Function(String?) _validatorFor(FrostConfigFieldSpec spec) {
    return (value) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isEmpty) return 'Required';

      if (spec.type == FrostConfigFieldType.text) return null;

      final parsed = spec.type == FrostConfigFieldType.integer
          ? int.tryParse(trimmed)
          : double.tryParse(trimmed);

      if (parsed == null) return 'Invalid number';
      if (spec.min != null && parsed < spec.min!) return 'Must be ≥ ${spec.min}';
      if (spec.max != null && parsed > spec.max!) return 'Must be ≤ ${spec.max}';
      return null;
    };
  }

  void _emitField(FrostConfigFieldSpec spec, String rawText) {
    final trimmed = rawText.trim();

    switch (spec.type) {
      case FrostConfigFieldType.integer:
        final parsed = int.tryParse(trimmed);
        if (parsed != null) widget.onFieldChanged(spec.key, parsed);
        break;
      case FrostConfigFieldType.decimal:
        final parsed = double.tryParse(trimmed);
        if (parsed != null) widget.onFieldChanged(spec.key, parsed);
        break;
      case FrostConfigFieldType.text:
        widget.onFieldChanged(spec.key, trimmed);
        break;
      case FrostConfigFieldType.growthStageDropdown:
        break; // handled by _buildDropdown's onChanged directly.
    }
  }

  @override
  Widget build(BuildContext context) {
    final fieldsByGroup = frostConfigFieldsByGroup();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in frostConfigGroupOrder)
          if ((fieldsByGroup[group] ?? const []).isNotEmpty)
            _buildGroup(group, fieldsByGroup[group]!),
      ],
    );
  }

  Widget _buildGroup(String group, List<FrostConfigFieldSpec> specs) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: group == frostConfigGroupGeneral,
        tilePadding: EdgeInsets.zero,
        title: Text(
          group,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: AppColors.textOnLight,
          ),
        ),
        childrenPadding: const EdgeInsets.only(bottom: 12),
        children: [
          for (final spec in specs) ...[
            _buildField(spec),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildField(FrostConfigFieldSpec spec) {
    if (spec.type == FrostConfigFieldType.growthStageDropdown) {
      return _buildDropdown(spec);
    }

    final controller = _controllers[spec.key]!;

    return TextFormField(
      controller: controller,
      autofillHints: const [],
      enabled: widget.enabled,
      keyboardType: spec.type == FrostConfigFieldType.text
          ? TextInputType.text
          : TextInputType.numberWithOptions(
              decimal: spec.type == FrostConfigFieldType.decimal,
              signed: true,
            ),
      decoration: InputDecoration(
        labelText: spec.unit == null ? spec.label : '${spec.label} (${spec.unit})',
        helperText: spec.helperText,
        helperMaxLines: 3,
        border: const OutlineInputBorder(),
      ),
      validator: _validatorFor(spec),
      onChanged: (value) => _emitField(spec, value),
    );
  }

  Widget _buildDropdown(FrostConfigFieldSpec spec) {
    final value = _dropdownValues[spec.key] ?? kFrostGrowthStages.first;

    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: spec.label,
        helperText: spec.helperText,
        helperMaxLines: 3,
        border: const OutlineInputBorder(),
      ),
      items: kFrostGrowthStages
          .map(
            (stage) => DropdownMenuItem(
              value: stage,
              child: Text(frostGrowthStageLabel(stage)),
            ),
          )
          .toList(),
      onChanged: !widget.enabled
          ? null
          : (newValue) {
              if (newValue == null) return;
              setState(() => _dropdownValues[spec.key] = newValue);
              widget.onFieldChanged(spec.key, newValue);
            },
    );
  }
}
