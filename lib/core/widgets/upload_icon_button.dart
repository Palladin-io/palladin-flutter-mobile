import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../../l10n/generated/app_localizations.dart';

/// Full-width "Upload Custom Icon" button shared across all icon pickers
/// (form pages and browser sheet). Styled to match [OnboardingTextField].
/// While [isLoading] is true the label shimmers left-to-right in brandRed.
///
/// The button intentionally shows NO image preview — the uploaded icon
/// appears in the picker grid (via [ImagePresetTile]) instead.
class UploadIconButton extends StatefulWidget {
  const UploadIconButton({
    super.key,
    required this.accentColor,
    required this.onTap,
    this.isLoading = false,
  });

  final Color accentColor;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  State<UploadIconButton> createState() => _UploadIconButtonState();
}

class _UploadIconButtonState extends State<UploadIconButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    if (widget.isLoading) _shimmer.repeat();
  }

  @override
  void didUpdateWidget(UploadIconButton old) {
    super.didUpdateWidget(old);
    if (widget.isLoading == old.isLoading) return;
    if (widget.isLoading) {
      _shimmer.repeat();
    } else {
      _shimmer.stop();
      _shimmer.reset();
    }
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  Widget _buildLabel(String text, Brightness brightness) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.file_upload_outlined,
          size: 15,
          color: widget.isLoading
              ? Colors.white
              : AppColors.onSurfaceMuted(brightness),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: widget.isLoading
                ? Colors.white
                : AppColors.onSurface(brightness),
          ),
        ),
      ],
    );
    if (!widget.isLoading) return row;
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (_, child) => ShaderMask(
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment(_shimmer.value * 4 - 2, 0),
          end: Alignment(_shimmer.value * 4, 0),
          colors: [
            AppColors.brandRed.withValues(alpha: 0.3),
            AppColors.brandRed,
            AppColors.brandRed.withValues(alpha: 0.3),
          ],
        ).createShader(bounds),
        blendMode: BlendMode.srcIn,
        child: child!,
      ),
      child: row,
    );
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final l10n = AppLocalizations.of(context)!;

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.inputFill(brightness),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.inputBorder(brightness)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [_buildLabel(l10n.vaultIconUpload, brightness)],
        ),
      ),
    );
  }
}
