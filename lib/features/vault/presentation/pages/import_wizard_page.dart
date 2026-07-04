import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_bar_title.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../onboarding/presentation/widgets/primary_button.dart';
import '../cubit/import_wizard_cubit.dart';
import '../widgets/import_column_mapper.dart';
import '../widgets/import_preview_list.dart';
import '../widgets/import_wizard_widgets.dart';

/// Full-screen import wizard for one vault. Reacts to [ImportWizardCubit]
/// state to render each step (pick → preview / map columns → progress →
/// summary) inside a single route so the cubit stays alive across steps.
class ImportWizardPage extends StatelessWidget {
  const ImportWizardPage({
    super.key,
    required this.vaultId,
    required this.vaultName,
    this.wrappedVK,
  });

  final String vaultId;
  final String vaultName;
  final String? wrappedVK;

  /// Pushes the wizard for a known vault. Resolves to `true` when at least
  /// one entry was imported so the caller can refresh its entry list.
  static Future<bool?> push(
    BuildContext context, {
    required String vaultId,
    required String vaultName,
    String? wrappedVK,
  }) {
    return Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        builder: (_) => ImportWizardPage(
          vaultId: vaultId,
          vaultName: vaultName,
          wrappedVK: wrappedVK,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ImportWizardCubit>(
      create: (_) => getIt<ImportWizardCubit>(param1: vaultId),
      child: _ImportWizardView(
        vaultId: vaultId,
        vaultName: vaultName,
        wrappedVK: wrappedVK,
      ),
    );
  }
}

class _ImportWizardView extends StatefulWidget {
  const _ImportWizardView({
    required this.vaultId,
    required this.vaultName,
    this.wrappedVK,
  });

  final String vaultId;
  final String vaultName;
  final String? wrappedVK;

  @override
  State<_ImportWizardView> createState() => _ImportWizardViewState();
}

class _ImportWizardViewState extends State<_ImportWizardView> {
  bool _picking = false;

  Future<void> _pickFile() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'json', 'xml', 'zip', '1pux', 'txt'],
        withData: true,
      );
      if (!mounted) return;
      final file = result?.files.singleOrNull;
      final bytes = file?.bytes;
      if (bytes == null) return;
      await context
          .read<ImportWizardCubit>()
          .parseBytes(bytes, fileName: file?.name);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _runImport() async {
    final auth = context.read<AuthBloc>().state;
    final l10n = AppLocalizations.of(context)!;
    if (auth is! AuthAuthenticated || auth.privateKey == null) {
      _snack(l10n.importErrorCrypto);
      return;
    }
    final keyCopy = Uint8List.fromList(auth.privateKey!);
    try {
      await context.read<ImportWizardCubit>().import(
            privateKey: keyCopy,
            untitledLabel: l10n.importUntitledFallback,
            wrappedVK: widget.wrappedVK,
          );
    } finally {
      keyCopy.fillRange(0, keyCopy.length, 0);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return BlocBuilder<ImportWizardCubit, ImportWizardState>(
      builder: (context, state) {
        final busy = state is ImportWizardImporting || state is ImportWizardParsing;
        return AppScreen.appBar(
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            iconTheme: IconThemeData(color: AppColors.onSurface(brightness)),
            leading: IconButton(
              icon: const Icon(Icons.close, size: 22),
              tooltip: l10n.vaultCancel,
              onPressed: busy
                  ? null
                  : () => Navigator.of(context)
                      .pop(state is ImportWizardSuccess),
            ),
            title: AppBarTitle(title: l10n.importTitle, subtitle: widget.vaultName),
          ),
          body: _buildBody(context, state, l10n),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    ImportWizardState state,
    AppLocalizations l10n,
  ) {
    return switch (state) {
      ImportWizardInitial() => _IntroStep(
          picking: _picking,
          onPickFile: _pickFile,
        ),
      ImportWizardParsing() => const _CenteredSpinner(),
      ImportWizardNeedsMapping(:final table) => ImportColumnMapper(
          table: table,
          onSubmit: (mapping) =>
              context.read<ImportWizardCubit>().applyMapping(mapping),
        ),
      ImportWizardPreview() => ImportPreviewList(
          state: state,
          onToggle: (i) => context.read<ImportWizardCubit>().toggleItem(i),
          onStrategy: (s) =>
              context.read<ImportWizardCubit>().setConflictStrategy(s),
          onImport: _runImport,
        ),
      ImportWizardImporting() => _ProgressStep(state: state),
      ImportWizardSuccess() => _SuccessStep(
          state: state,
          onDone: () => Navigator.of(context).pop(true),
        ),
      ImportWizardFailure(:final reason) => _FailureStep(
          reason: reason,
          picking: _picking,
          onRetry: _pickFile,
          onClose: () => Navigator.of(context).pop(false),
        ),
    };
  }
}

/// Step 1 — intro + file picker.
class _IntroStep extends StatelessWidget {
  const _IntroStep({required this.picking, required this.onPickFile});

  final bool picking;
  final VoidCallback onPickFile;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        0,
        AppSpacing.screenH,
        AppSpacing.screenBottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.file_upload_outlined,
            size: 48,
            color: AppColors.brandRed,
          ),
          const SizedBox(height: AppSpacing.section),
          Text(
            l10n.importIntroTitle,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.innerGap),
          Text(
            l10n.importIntroBody,
            style: TextStyle(
              color: AppColors.onSurfaceMuted(brightness),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.importSupportedFormats,
            style: const TextStyle(
              color: AppColors.textTertiaryMobile,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const Spacer(),
          PrimaryButton(
            label: l10n.importChooseFile,
            isLoading: picking,
            onPressed: onPickFile,
          ),
        ],
      ),
    );
  }
}

class _CenteredSpinner extends StatelessWidget {
  const _CenteredSpinner();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColors.brandRed),
          const SizedBox(height: AppSpacing.section),
          Text(
            l10n.importParsing,
            style: TextStyle(
              color: AppColors.onSurfaceMuted(brightness),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// Step 3 — commit progress.
class _ProgressStep extends StatelessWidget {
  const _ProgressStep({required this.state});

  final ImportWizardImporting state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.importImporting(state.done, state.total),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.section),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: state.progress,
              minHeight: 6,
              backgroundColor: AppColors.cardFill(brightness),
              color: AppColors.brandRed,
            ),
          ),
        ],
      ),
    );
  }
}

/// Final — success summary.
class _SuccessStep extends StatelessWidget {
  const _SuccessStep({required this.state, required this.onDone});

  final ImportWizardSuccess state;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        0,
        AppSpacing.screenH,
        AppSpacing.screenBottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Icon(Icons.check_circle_outline,
              size: 56, color: AppColors.positiveAccent),
          const SizedBox(height: AppSpacing.section),
          Text(
            l10n.importSuccessTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.innerGap),
          Text(
            l10n.importSuccessBody(state.createdCount, state.updatedCount),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.onSurfaceMuted(brightness),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          if (state.skippedCount > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.importSuccessSkipped(state.skippedCount),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textTertiaryMobile,
                fontSize: 12,
              ),
            ),
          ],
          const Spacer(),
          PrimaryButton(label: l10n.importDone, onPressed: onDone),
        ],
      ),
    );
  }
}

/// Terminal error — offers to pick another file or close.
class _FailureStep extends StatelessWidget {
  const _FailureStep({
    required this.reason,
    required this.picking,
    required this.onRetry,
    required this.onClose,
  });

  final ImportFailureReason reason;
  final bool picking;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        0,
        AppSpacing.screenH,
        AppSpacing.screenBottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Icon(Icons.error_outline, size: 56, color: AppColors.brandRed),
          const SizedBox(height: AppSpacing.section),
          Text(
            l10n.importFailedTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.innerGap),
          Text(
            ImportWizardCopy.failureMessage(l10n, reason),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.onSurfaceMuted(brightness),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const Spacer(),
          PrimaryButton(
            label: l10n.importTryAnother,
            isLoading: picking,
            onPressed: onRetry,
          ),
          const SizedBox(height: AppSpacing.fieldGap),
          TextButton(
            onPressed: onClose,
            child: Text(
              l10n.vaultCancel,
              style: TextStyle(color: AppColors.onSurfaceMuted(brightness)),
            ),
          ),
        ],
      ),
    );
  }
}
