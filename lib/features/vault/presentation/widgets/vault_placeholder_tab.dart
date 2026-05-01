import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Generic empty-state used by the Logs and Members tabs while their
/// real implementation is parked in later tickets.
class VaultPlaceholderTab extends StatelessWidget {
  const VaultPlaceholderTab({
    super.key,
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: AppColors.textTertiaryMobile),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textTertiaryMobile,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
