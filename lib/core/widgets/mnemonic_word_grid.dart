import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Two-column, numbered grid of recovery-mnemonic words.
///
/// The canonical way to render a BIP-39 recovery phrase. Shared so the
/// registration wizard, the onboarding backup step, and the recovery
/// flow all display the phrase identically. Read-only display; the words
/// are never editable here.
class MnemonicWordGrid extends StatelessWidget {
  const MnemonicWordGrid({super.key, required this.words});

  final List<String> words;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: words.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: AppSpacing.innerGap,
        mainAxisSpacing: AppSpacing.innerGap,
        childAspectRatio: 4.8,
      ),
      itemBuilder: (_, index) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.innerGap),
          decoration: BoxDecoration(
            color: AppColors.cardFill(brightness),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.cardBorder(brightness)),
          ),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.onSurfaceSubtle(brightness),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  words[index],
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.onSurface(brightness),
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
