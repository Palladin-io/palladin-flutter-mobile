import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../domain/entities/entry_entity.dart';
import '../../domain/exceptions/entry_exceptions.dart';
import '../cubit/create_entry_cubit.dart';

/// Full-screen Add Entry form.
///
/// Houses both the **Key** and **Credential** variants — the entry type
/// is selected via a dropdown at the top of the form, which swaps the
/// secret-input cluster between a single value field (Key) and a
/// username/password/url trio (Credential). Notes are always shown.
///
/// On submit the form trims every input, builds the payload map,
/// forwards it to [CreateEntryCubit] (which encrypts it on-device and
/// POSTs the ciphertext + nonce), and pops the page returning the new
/// [EntryEntity] so the caller can insert it into the entries list.
class AddEntryPage extends StatelessWidget {
  const AddEntryPage({super.key, required this.vaultId});

  final String vaultId;

  /// Pushes the page on the root navigator and returns the created
  /// entry, or `null` when the user cancels.
  static Future<EntryEntity?> push(
    BuildContext context, {
    required String vaultId,
  }) {
    return Navigator.of(context, rootNavigator: true).push<EntryEntity>(
      MaterialPageRoute(builder: (_) => AddEntryPage(vaultId: vaultId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<CreateEntryCubit>(
      create: (_) => getIt<CreateEntryCubit>(),
      child: _AddEntryView(vaultId: vaultId),
    );
  }
}

class _AddEntryView extends StatefulWidget {
  const _AddEntryView({required this.vaultId});

  final String vaultId;

  @override
  State<_AddEntryView> createState() => _AddEntryViewState();
}

class _AddEntryViewState extends State<_AddEntryView> {
  final _labelController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _valueController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _urlController = TextEditingController();
  final _notesController = TextEditingController();

  EntryType _type = EntryType.credential;
  bool _valueObscured = true;
  bool _passwordObscured = true;

  @override
  void dispose() {
    _labelController.dispose();
    _descriptionController.dispose();
    _valueController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _urlController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    if (_labelController.text.trim().isEmpty) return false;
    return switch (_type) {
      EntryType.key => _valueController.text.trim().isNotEmpty,
      EntryType.credential => _usernameController.text.trim().isNotEmpty &&
          _passwordController.text.trim().isNotEmpty,
    };
  }

  /// Extracts a host (`stripe.com`) from a free-form URL field. Falls
  /// back to the trimmed input if it isn't a parseable absolute URL —
  /// the backend stores `urlDomain` purely as a meta hint, not for
  /// authentication, so a best-effort extraction is fine.
  String? _extractDomain(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      final uri = Uri.parse(trimmed);
      if (uri.hasAuthority && uri.host.isNotEmpty) return uri.host;
    } on FormatException {
      // Fall through to the heuristic below.
    }
    // Strip protocol and path manually for inputs like "stripe.com/api".
    final withoutScheme =
        trimmed.replaceFirst(RegExp(r'^[a-zA-Z][a-zA-Z0-9+\-.]*://'), '');
    final firstSegment = withoutScheme.split('/').first;
    return firstSegment.isEmpty ? null : firstSegment;
  }

  Map<String, dynamic> _buildPayload() {
    final notes = _notesController.text.trim();
    return switch (_type) {
      EntryType.key => KeyPayload(
          value: _valueController.text.trim(),
          notes: notes.isEmpty ? null : notes,
        ).toJson(),
      EntryType.credential => CredentialPayload(
          username: _usernameController.text.trim(),
          password: _passwordController.text.trim(),
          url: _urlController.text.trim().isEmpty
              ? null
              : _urlController.text.trim(),
          notes: notes.isEmpty ? null : notes,
        ).toJson(),
    };
  }

  Future<void> _submit() async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated || auth.privateKey == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)!.entryErrorCrypto),
        ));
      return;
    }

    // Defensive copy of the unlocked private key so the cubit can mutate
    // it without touching the auth bloc's state. We zero `keyCopy` in
    // `finally` — the crypto service already disposes its `SecureKey`,
    // but the raw `Uint8List` we hand it would otherwise linger on the
    // heap with the secret key material.
    final keyCopy = Uint8List.fromList(auth.privateKey!);
    final urlDomain = _type == EntryType.credential
        ? _extractDomain(_urlController.text)
        : null;
    try {
      await context.read<CreateEntryCubit>().createEntry(
            vaultId: widget.vaultId,
            label: _labelController.text,
            description: _descriptionController.text,
            type: _type,
            payload: _buildPayload(),
            urlDomain: urlDomain,
            privateKey: keyCopy,
          );
    } finally {
      keyCopy.fillRange(0, keyCopy.length, 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return BlocConsumer<CreateEntryCubit, CreateEntryState>(
      listenWhen: (previous, current) => current is CreateEntrySuccess,
      listener: (context, state) {
        if (state is CreateEntrySuccess) {
          Navigator.of(context).pop(state.entry);
        }
      },
      builder: (context, state) {
        final isLoading = state is CreateEntryLoading;
        final canSubmit = !isLoading && _canSubmit;

        return Container(
          decoration: BoxDecoration(
            gradient: AppColors.backgroundGradient(brightness),
          ),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              iconTheme:
                  IconThemeData(color: AppColors.onSurface(brightness)),
              leading: IconButton(
                icon: const Icon(Icons.close, size: 22),
                onPressed: isLoading
                    ? null
                    : () => Navigator.of(context).pop(),
                tooltip: l10n.vaultCancel,
              ),
              title: Text(
                l10n.entryAddTitle,
                style: TextStyle(
                  color: AppColors.onSurface(brightness),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: canSubmit ? _submit : null,
                  child: Text(
                    isLoading ? l10n.entrySaving : l10n.entrySaveAction,
                    style: TextStyle(
                      color: canSubmit
                          ? AppColors.brandRed
                          : AppColors.onSurfaceMuted(brightness),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
            body: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OnboardingTextField(
                      label: l10n.entryLabelLabel,
                      hintText: l10n.entryLabelHint,
                      controller: _labelController,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    OnboardingTextField(
                      label: l10n.entryDescriptionLabel,
                      controller: _descriptionController,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    _EntryTypeDropdown(
                      value: _type,
                      onChanged: (next) {
                        if (next == null || next == _type) return;
                        setState(() => _type = next);
                      },
                      l10n: l10n,
                    ),
                    const SizedBox(height: 16),
                    if (_type == EntryType.key)
                      OnboardingTextField(
                        label: l10n.entryValueLabel,
                        controller: _valueController,
                        obscureText: _valueObscured,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => setState(() {}),
                        suffixIcon: _ObscureToggle(
                          obscured: _valueObscured,
                          onPressed: () => setState(
                            () => _valueObscured = !_valueObscured,
                          ),
                        ),
                      )
                    else ...[
                      OnboardingTextField(
                        label: l10n.entryUsernameLabel,
                        controller: _usernameController,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 16),
                      OnboardingTextField(
                        label: l10n.entryPasswordLabel,
                        controller: _passwordController,
                        obscureText: _passwordObscured,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => setState(() {}),
                        suffixIcon: _ObscureToggle(
                          obscured: _passwordObscured,
                          onPressed: () => setState(
                            () => _passwordObscured = !_passwordObscured,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      OnboardingTextField(
                        label: l10n.entryUrlLabel,
                        controller: _urlController,
                        textInputAction: TextInputAction.next,
                      ),
                    ],
                    const SizedBox(height: 16),
                    _NotesField(
                      controller: _notesController,
                      label: l10n.entryNotesLabel,
                      brightness: brightness,
                    ),
                    const SizedBox(height: 20),
                    _EncryptionNotice(message: l10n.entryEncryptionNotice),
                    if (state is CreateEntryError) ...[
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage(l10n, state.kind),
                        style: const TextStyle(
                          color: AppColors.brandRed,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: canSubmit ? _submit : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandRed,
                          disabledBackgroundColor:
                              AppColors.brandRed.withValues(alpha: 0.35),
                          foregroundColor: AppColors.onBrandRed,
                          disabledForegroundColor:
                              AppColors.onBrandRed.withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          isLoading ? l10n.entrySaving : l10n.entrySaveAction,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _errorMessage(AppLocalizations l10n, EntryErrorKind kind) {
    return switch (kind) {
      EntryErrorKind.notFound => l10n.entryErrorNotFound,
      EntryErrorKind.forbidden => l10n.entryErrorForbidden,
      EntryErrorKind.validation => l10n.entryErrorValidation,
      EntryErrorKind.cryptoFailure => l10n.entryErrorCrypto,
      EntryErrorKind.networkError => l10n.errorCannotConnectToServer,
      EntryErrorKind.unknown => l10n.entryErrorUnknown,
    };
  }
}

class _EntryTypeDropdown extends StatelessWidget {
  const _EntryTypeDropdown({
    required this.value,
    required this.onChanged,
    required this.l10n,
  });

  final EntryType value;
  final ValueChanged<EntryType?> onChanged;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.entryTypeLabel,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurfaceMuted(brightness),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.inputFill(brightness),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.inputBorder(brightness),
              width: 1,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<EntryType>(
              value: value,
              isExpanded: true,
              dropdownColor: AppColors.modalBackground(brightness),
              iconEnabledColor: AppColors.onSurfaceMuted(brightness),
              style: TextStyle(
                color: AppColors.inputText(brightness),
                fontSize: 14,
              ),
              items: [
                DropdownMenuItem(
                  value: EntryType.credential,
                  child: Text(l10n.entryTypeCredential),
                ),
                DropdownMenuItem(
                  value: EntryType.key,
                  child: Text(l10n.entryTypeKey),
                ),
              ],
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _ObscureToggle extends StatelessWidget {
  const _ObscureToggle({required this.obscured, required this.onPressed});

  final bool obscured;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        obscured ? Icons.visibility : Icons.visibility_off,
        size: 18,
        color: AppColors.textTertiaryMobile,
      ),
      onPressed: onPressed,
      splashRadius: 18,
      tooltip: AppLocalizations.of(context)!.vaultRevealValue,
    );
  }
}

class _NotesField extends StatelessWidget {
  const _NotesField({
    required this.controller,
    required this.label,
    required this.brightness,
  });

  final TextEditingController controller;
  final String label;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurfaceMuted(brightness),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          cursorColor: AppColors.onSurface(brightness),
          style: TextStyle(
            color: AppColors.inputText(brightness),
            fontSize: 14,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.inputFill(brightness),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: AppColors.inputBorder(brightness),
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: AppColors.onSurface(brightness),
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EncryptionNotice extends StatelessWidget {
  const _EncryptionNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.tealAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.tealAccent.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.lock_outline,
            size: 16,
            color: AppColors.tealAccent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.tealAccent,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
