import 'package:flutter/material.dart';

import '../../features/onboarding/presentation/widgets/onboarding_text_field.dart';
import '../theme/app_colors.dart';

/// Shared type-to-search field — a labelled [OnboardingTextField] that suggests
/// from a (potentially large) option list, with a themed dropdown of matches.
///
/// Used wherever a select would have too many entries to scroll (agent type,
/// vault / entry pickers…). The field looks identical to the app's text inputs
/// (44px, label above). Selection emits [onSelected]; raw text edits emit
/// [onTextChanged] so callers can either map free text to a value or clear an
/// invalid selection.
class AppAutocompleteField<T extends Object> extends StatelessWidget {
  const AppAutocompleteField({
    super.key,
    this.label,
    required this.initialText,
    required this.options,
    required this.displayString,
    required this.onSelected,
    this.onTextChanged,
    this.hintText,
    this.enabled = true,
  });

  /// Caption rendered above the field (like [OnboardingTextField.label]).
  final String? label;

  /// Text shown when the field is first built — typically the display string
  /// of the already-selected value, or empty.
  final String initialText;

  final List<T> options;

  /// Renders an option (and the selected value) as its display label.
  final String Function(T) displayString;

  /// Fired when the user picks an option from the suggestions.
  final ValueChanged<T> onSelected;

  /// Fired on every raw text edit. Use it to map free text to a value (combo
  /// box) or to clear the selection when the text no longer matches an option.
  final ValueChanged<String>? onTextChanged;

  final String? hintText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<T>(
      // Applied once when the field is created (key the parent by its subject
      // to re-seed). Safe vs. mutating the controller during build.
      initialValue: TextEditingValue(text: initialText),
      displayStringForOption: displayString,
      optionsBuilder: (TextEditingValue value) {
        final q = value.text.trim().toLowerCase();
        if (q.isEmpty) return options;
        return options.where((o) => displayString(o).toLowerCase().contains(q));
      },
      onSelected: onSelected,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        final brightness = Theme.of(context).brightness;
        return OnboardingTextField(
          controller: controller,
          focusNode: focusNode,
          label: label,
          hintText: hintText,
          enabled: enabled,
          onChanged: onTextChanged,
          onSubmitted: (_) => onFieldSubmitted(),
          suffixIcon: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Icon(
              Icons.expand_more,
              size: 18,
              color: AppColors.onSurfaceSubtle(brightness),
            ),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, opts) => _OptionsList<T>(
        options: opts.toList(),
        displayString: displayString,
        onSelected: onSelected,
      ),
    );
  }
}

/// Themed suggestion list — matches the app's modal surface instead of the
/// default white Material popup.
class _OptionsList<T extends Object> extends StatelessWidget {
  const _OptionsList({
    required this.options,
    required this.displayString,
    required this.onSelected,
  });

  final List<T> options;
  final String Function(T) displayString;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.only(top: 4),
          constraints: const BoxConstraints(maxHeight: 240),
          decoration: BoxDecoration(
            color: AppColors.modalBackground(brightness),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.cardBorder(brightness)),
          ),
          child: ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            itemCount: options.length,
            itemBuilder: (context, i) {
              final o = options[i];
              return InkWell(
                onTap: () => onSelected(o),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: Text(
                    displayString(o),
                    style: TextStyle(
                      color: AppColors.onSurface(brightness),
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
