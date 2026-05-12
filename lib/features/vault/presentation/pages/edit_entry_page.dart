import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../data/datasources/entry_remote_datasource.dart';
import '../../data/services/entry_icon_upload_service.dart';
import '../../domain/entities/entry_entity.dart';
import '../../domain/exceptions/entry_exceptions.dart';
import '../cubit/edit_entry_cubit.dart';
import '../widgets/entry_icon_picker.dart';
import '../widgets/vault_color_picker.dart';
import '../widgets/vault_visuals.dart';

/// Full-screen Edit Entry form.
///
/// Field order and controls mirror the Add Entry form. When [cachedPayload]
/// is provided (entry was already revealed on the entries tab), the form
/// pre-populates immediately. Otherwise the page decrypts the entry first
/// (shows a brief loading indicator).
///
/// On save the payload is re-encrypted and PUT to the server. A two-step
/// icon upload (presign → S3 → PATCH) runs after the metadata update if
/// the user chose a new custom image.
class EditEntryPage extends StatelessWidget {
  const EditEntryPage({
    super.key,
    required this.entry,
    this.cachedPayload,
    this.wrappedVK,
  });

  final EntryEntity entry;

  /// Plaintext payload already held by the entries tab — skips re-decrypt.
  final Map<String, dynamic>? cachedPayload;

  /// Base64 sealed VK passed down from the vault detail screen.
  final String? wrappedVK;

  static Future<EntryEntity?> push(
    BuildContext context, {
    required EntryEntity entry,
    Map<String, dynamic>? cachedPayload,
    String? wrappedVK,
  }) {
    return Navigator.of(context, rootNavigator: true).push<EntryEntity>(
      MaterialPageRoute(
        builder: (_) => EditEntryPage(
          entry: entry,
          cachedPayload: cachedPayload,
          wrappedVK: wrappedVK,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<EditEntryCubit>(
      create: (_) {
        final cubit = getIt<EditEntryCubit>();
        if (cachedPayload != null) {
          cubit.setReady(entry, cachedPayload!);
        } else {
          final auth = context.read<AuthBloc>().state;
          if (auth is AuthAuthenticated && auth.privateKey != null) {
            final keyCopy = Uint8List.fromList(auth.privateKey!);
            cubit
                .revealForEdit(
                  entry: entry,
                  privateKey: keyCopy,
                  wrappedVK: wrappedVK,
                )
                .whenComplete(() => keyCopy.fillRange(0, keyCopy.length, 0));
          }
        }
        return cubit;
      },
      child: _EditEntryView(entry: entry, wrappedVK: wrappedVK),
    );
  }
}

class _EditEntryView extends StatefulWidget {
  const _EditEntryView({required this.entry, this.wrappedVK});

  final EntryEntity entry;
  final String? wrappedVK;

  @override
  State<_EditEntryView> createState() => _EditEntryViewState();
}

class _EditEntryViewState extends State<_EditEntryView> {
  final _labelController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _valueController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _urlController = TextEditingController();
  final _notesController = TextEditingController();

  EntryType _type = EntryType.credential;
  String _icon = EntryVisuals.defaultIconName;
  String _color = EntryVisuals.defaultColorHex;
  XFile? _pendingIconFile;
  bool _pickingIcon = false;
  bool _uploadingIcon = false;

  bool _valueObscured = true;
  bool _passwordObscured = true;

  bool _populated = false;

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

  void _populateFrom(EntryEntity entry, Map<String, dynamic> payload) {
    if (_populated) return;
    _populated = true;
    _labelController.text = entry.label;
    _descriptionController.text = entry.description ?? '';
    _type = entry.type;
    _icon = entry.icon ?? EntryVisuals.defaultIconName;

    if (entry.type == EntryType.key) {
      _valueController.text = (payload['value'] as String?) ?? '';
      _urlController.text = (payload['url'] as String?) ?? '';
    } else {
      _usernameController.text = (payload['username'] as String?) ?? '';
      _passwordController.text = (payload['password'] as String?) ?? '';
      _urlController.text = (payload['url'] as String?) ?? '';
    }
    _notesController.text = (payload['notes'] as String?) ?? '';
  }

  bool get _canSubmit {
    if (_labelController.text.trim().isEmpty) return false;
    return switch (_type) {
      EntryType.key => _valueController.text.trim().isNotEmpty,
      EntryType.credential => _usernameController.text.trim().isNotEmpty &&
          _passwordController.text.trim().isNotEmpty,
    };
  }

  String? _extractDomain(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      final uri = Uri.parse(trimmed);
      if (uri.hasAuthority && uri.host.isNotEmpty) return uri.host;
    } on FormatException {
      // fall through
    }
    final withoutScheme =
        trimmed.replaceFirst(RegExp(r'^[a-zA-Z][a-zA-Z0-9+\-.]*://'), '');
    final firstSegment = withoutScheme.split('/').first;
    return firstSegment.isEmpty ? null : firstSegment;
  }

  Map<String, dynamic> _buildPayload() {
    final notes = _notesController.text.trim();
    final url = _urlController.text.trim().isEmpty
        ? null
        : _urlController.text.trim();
    return switch (_type) {
      EntryType.key => KeyPayload(
          value: _valueController.text.trim(),
          url: url,
          notes: notes.isEmpty ? null : notes,
        ).toJson(),
      EntryType.credential => CredentialPayload(
          username: _usernameController.text.trim(),
          password: _passwordController.text.trim(),
          url: url,
          notes: notes.isEmpty ? null : notes,
        ).toJson(),
    };
  }

  Future<void> _pickCustomIcon() async {
    if (_pickingIcon || _uploadingIcon) return;
    setState(() => _pickingIcon = true);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (file == null || !mounted) return;
      setState(() {
        _pendingIconFile = file;
        _icon = 'file://${file.path}';
      });
    } finally {
      if (mounted) setState(() => _pickingIcon = false);
    }
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

    final keyCopy = Uint8List.fromList(auth.privateKey!);
    final urlDomain = _extractDomain(_urlController.text);
    final iconForApi = _pendingIconFile != null ? null : _icon;
    try {
      await context.read<EditEntryCubit>().updateEntry(
            vaultId: widget.entry.vaultId,
            entryId: widget.entry.id,
            label: _labelController.text,
            description: _descriptionController.text,
            icon: iconForApi,
            type: _type,
            payload: _buildPayload(),
            urlDomain: urlDomain,
            privateKey: keyCopy,
            wrappedVK: widget.wrappedVK,
          );
    } finally {
      keyCopy.fillRange(0, keyCopy.length, 0);
    }

    if (!mounted) return;
    final cubitState = context.read<EditEntryCubit>().state;
    if (cubitState is! EditEntrySuccess) return;

    var entry = cubitState.entry;
    if (_pendingIconFile != null) {
      setState(() => _uploadingIcon = true);
      try {
        final service = EntryIconUploadService(getIt<EntryRemoteDatasource>());
        final url = await service.uploadIcon(
          widget.entry.vaultId,
          entry.id,
          File(_pendingIconFile!.path),
        );
        entry = entry.copyWith(icon: url);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content:
                  Text(AppLocalizations.of(context)!.vaultIconUploadError),
            ));
        }
      } finally {
        if (mounted) setState(() => _uploadingIcon = false);
      }
    }

    if (mounted) Navigator.of(context).pop(entry);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return BlocConsumer<EditEntryCubit, EditEntryState>(
      listenWhen: (_, s) => s is EditEntryReady,
      listener: (_, state) {
        if (state is EditEntryReady) {
          setState(() => _populateFrom(state.entry, state.payload));
        }
      },
      builder: (context, state) {
        if (state is EditEntryInitial || state is EditEntryRevealing) {
          return _buildRevealingScaffold(l10n, brightness);
        }
        if (state is EditEntryError && !_populated) {
          return _buildErrorScaffold(l10n, brightness, state.kind);
        }
        return _buildFormScaffold(l10n, brightness, state);
      },
    );
  }

  Widget _buildRevealingScaffold(AppLocalizations l10n, Brightness brightness) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.backgroundGradient(brightness),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: _buildAppBar(l10n, brightness, isBusy: true),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.tealAccent,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                l10n.entryRevealingForEdit,
                style: const TextStyle(
                  color: AppColors.textTertiaryMobile,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorScaffold(
    AppLocalizations l10n,
    Brightness brightness,
    EntryErrorKind kind,
  ) {
    return Container(
      decoration:
          BoxDecoration(gradient: AppColors.backgroundGradient(brightness)),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: _buildAppBar(l10n, brightness, isBusy: false),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _errorMessage(l10n, kind),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.brandRed,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormScaffold(
    AppLocalizations l10n,
    Brightness brightness,
    EditEntryState state,
  ) {
    final accentColor = VaultVisuals.colorFor(_color);
    final isLoading = state is EditEntryLoading || _uploadingIcon;
    final isBusy = isLoading || _pickingIcon;
    final canSubmit = !isBusy && _canSubmit;

    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.backgroundGradient(brightness),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: _buildAppBar(l10n, brightness, isBusy: isBusy),
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
                Text(
                  l10n.vaultIconLabel,
                  style: TextStyle(
                    color: AppColors.onSurfaceSubtle(brightness),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                EntryIconPicker(
                  selected: _icon,
                  accentColor: accentColor,
                  onSelected: (name) => setState(() {
                    _icon = name;
                    _pendingIconFile = null;
                  }),
                  onPickCustom: (_pickingIcon || _uploadingIcon)
                      ? null
                      : _pickCustomIcon,
                  isLoadingCustom: _pickingIcon || _uploadingIcon,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.vaultColorLabel,
                  style: TextStyle(
                    color: AppColors.onSurfaceSubtle(brightness),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                VaultColorPicker(
                  selected: _color,
                  onSelected: (hex) => setState(() => _color = hex),
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
                if (_type == EntryType.key) ...[
                  OnboardingTextField(
                    label: l10n.entryValueLabel,
                    controller: _valueController,
                    obscureText: _valueObscured,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => setState(() {}),
                    suffixIcon: _ObscureToggle(
                      obscured: _valueObscured,
                      onPressed: () =>
                          setState(() => _valueObscured = !_valueObscured),
                    ),
                  ),
                  const SizedBox(height: 16),
                  OnboardingTextField(
                    label: l10n.entryUrlLabel,
                    controller: _urlController,
                    textInputAction: TextInputAction.next,
                  ),
                ] else ...[
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
                          () => _passwordObscured = !_passwordObscured),
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
                if (state is EditEntryError) ...[
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
  }

  AppBar _buildAppBar(
    AppLocalizations l10n,
    Brightness brightness, {
    required bool isBusy,
  }) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(color: AppColors.onSurface(brightness)),
      leading: IconButton(
        icon: const Icon(Icons.close, size: 22),
        onPressed: isBusy ? null : () => Navigator.of(context).pop(),
        tooltip: l10n.vaultCancel,
      ),
      title: Text(
        l10n.entryEditTitle,
        style: TextStyle(
          color: AppColors.onSurface(brightness),
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
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

// ── Shared sub-widgets (mirrors add_entry_page.dart) ─────────────────

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
