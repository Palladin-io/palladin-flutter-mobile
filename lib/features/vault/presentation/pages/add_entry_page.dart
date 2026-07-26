import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/icon_color_browser_sheet.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../data/datasources/entry_remote_datasource.dart';
import '../../data/services/entry_icon_upload_service.dart';
import '../../data/services/vault_icon_upload_service.dart'
    show VaultIconUploadErrorKind, VaultIconUploadException;
import '../../domain/entities/custom_field.dart';
import '../../domain/entities/entry_entity.dart';
import '../../domain/repositories/entry_repository.dart';
import '../cubit/create_entry_cubit.dart';
import '../widgets/custom_fields_editor.dart';
import '../widgets/entry_form_utils.dart';
import '../widgets/entry_form_widgets.dart';
import '../widgets/entry_icon_tile.dart';
import '../widgets/entry_notes_section.dart';
import '../widgets/script_editor_field.dart';
import '../widgets/script_refs_editor.dart';
import '../widgets/totp_section.dart';
import '../widgets/vault_visuals.dart';

/// Full-screen Add Entry form.
///
/// Field order: Label → Description → URL → Icon → Type → Type-specific
/// fields → Notes → Encryption notice → Save button. The color picker
/// was dropped — `EntryEntity` has no color field on the backend, so the
/// control silently discarded user input.
///
/// Custom icon upload follows the two-step pattern: the entry is created
/// first (with a preset icon name so the server gets a valid entry ID),
/// then the image is uploaded to S3 and the entry is patched.
class AddEntryPage extends StatelessWidget {
  const AddEntryPage({super.key, required this.vaultId, this.wrappedVK});

  final String vaultId;

  /// Base64 sealed VK from the parent vault detail screen — when
  /// supplied, the create-entry pipeline avoids a redundant
  /// `GET /api/vaults/{id}` call. `null` is safe (the repository will
  /// fetch on demand).
  final String? wrappedVK;

  static Future<EntryEntity?> push(
    BuildContext context, {
    required String vaultId,
    String? wrappedVK,
  }) {
    return Navigator.of(context, rootNavigator: true).push<EntryEntity>(
      MaterialPageRoute(
        builder: (_) => AddEntryPage(vaultId: vaultId, wrappedVK: wrappedVK),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<CreateEntryCubit>(
      create: (_) => getIt<CreateEntryCubit>(),
      child: _AddEntryView(vaultId: vaultId, wrappedVK: wrappedVK),
    );
  }
}

class _AddEntryView extends StatefulWidget {
  const _AddEntryView({required this.vaultId, this.wrappedVK});

  final String vaultId;
  final String? wrappedVK;

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
  final _scriptController = TextEditingController();

  EntryType _type = EntryType.credential;
  ScriptInterpreter _interpreter = ScriptInterpreter.bash;
  String _icon = EntryVisuals.defaultIconForType(EntryType.credential);
  String _colorHex = EntryVisuals.defaultColorHex;
  bool _pickingIcon = false;
  bool _uploadingIcon = false;

  bool _valueObscured = true;
  bool _passwordObscured = true;
  String? _urlError;

  /// Non-TOTP custom fields (managed by [CustomFieldsEditor]).
  List<CustomField> _customFields = const [];
  bool _customFieldsValid = true;

  /// TOTP fields (managed by the dedicated 2FA section).
  List<CustomField> _totpFields = const [];

  List<ScriptRef> _refs = const [];

  /// Every custom field in display order — 2FA first, then the rest.
  List<CustomField> get _allCustomFields => [..._totpFields, ..._customFields];

  /// Candidate reference targets for a Script entry, loaded lazily the
  /// first time the user selects the Script type. `null` = not loaded yet.
  List<EntryEntity>? _vaultEntries;
  bool _loadingEntries = false;

  @override
  void dispose() {
    _labelController.dispose();
    _descriptionController.dispose();
    _valueController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _urlController.dispose();
    _notesController.dispose();
    _scriptController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _customFieldsValid &&
      EntryFormUtils.canSubmit(
        type: _type,
        label: _labelController.text,
        value: _valueController.text,
        username: _usernameController.text,
        password: _passwordController.text,
        script: _scriptController.text,
      );

  /// Loads the vault's key/credential entries so a Script entry can point
  /// its references at them. Best-effort — a failure just leaves the
  /// picker empty.
  Future<void> _ensureVaultEntriesLoaded() async {
    if (_vaultEntries != null || _loadingEntries) return;
    setState(() => _loadingEntries = true);
    try {
      final entries = await getIt<EntryRepository>().listEntries(
        widget.vaultId,
      );
      if (!mounted) return;
      setState(() {
        _vaultEntries = entries
            .where((e) => e.type != EntryType.script)
            .toList(growable: false);
      });
    } catch (_) {
      if (mounted) setState(() => _vaultEntries = const []);
    } finally {
      if (mounted) setState(() => _loadingEntries = false);
    }
  }

  bool _validateUrl() {
    final valid = EntryFormUtils.isValidUrl(_urlController.text);
    setState(
      () => _urlError = valid
          ? null
          : AppLocalizations.of(context)!.entryUrlInvalid,
    );
    return valid;
  }

  Map<String, dynamic> _buildPayload() => EntryFormUtils.buildPayload(
    type: _type,
    value: _valueController.text,
    username: _usernameController.text,
    password: _passwordController.text,
    url: _urlController.text,
    notes: _notesController.text,
    fields: _allCustomFields,
    script: _scriptController.text,
    interpreter: _interpreter,
    refs: _refs,
  );

  Widget _urlField(AppLocalizations l10n) => OnboardingTextField(
    label: l10n.entryUrlLabel,
    controller: _urlController,
    textInputAction: TextInputAction.next,
    borderColor: _urlError != null ? AppColors.brandRed : null,
    focusBorderColor: _urlError != null ? AppColors.brandRed : null,
    onChanged: (_) => _validateUrl(),
    feedbackChild: Text(
      _urlError ?? '',
      style: const TextStyle(color: AppColors.brandRed, fontSize: 11),
    ),
    feedbackVisible: _urlError != null,
    feedbackReserveSpace: false,
  );

  /// Type-specific form fields for the currently-selected [_type]. Ends
  /// with the type's own trailing controls (URL / injected data).
  List<Widget> _typeFields(AppLocalizations l10n) {
    return switch (_type) {
      EntryType.key => [
        OnboardingTextField(
          label: l10n.entryValueLabel,
          controller: _valueController,
          obscureText: _valueObscured,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
          suffixIcon: EntryObscureToggle(
            obscured: _valueObscured,
            onPressed: () => setState(() => _valueObscured = !_valueObscured),
          ),
        ),
        const SizedBox(height: AppSpacing.fieldGap),
        _urlField(l10n),
      ],
      EntryType.credential => [
        OnboardingTextField(
          label: l10n.entryUsernameLabel,
          controller: _usernameController,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.fieldGap),
        OnboardingTextField(
          label: l10n.entryPasswordLabel,
          controller: _passwordController,
          obscureText: _passwordObscured,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
          suffixIcon: EntryObscureToggle(
            obscured: _passwordObscured,
            onPressed: () =>
                setState(() => _passwordObscured = !_passwordObscured),
          ),
        ),
        const SizedBox(height: AppSpacing.fieldGap),
        _urlField(l10n),
      ],
      EntryType.script => [
        ScriptEditorField(
          controller: _scriptController,
          interpreter: _interpreter,
          onInterpreterChanged: (next) => setState(() => _interpreter = next),
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.section),
        EntrySectionHeader(label: l10n.entryInjectedDataLabel),
        const SizedBox(height: AppSpacing.innerGap),
        if (_loadingEntries && _vaultEntries == null)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.brandRed,
                ),
              ),
            ),
          )
        else
          ScriptRefsEditor(
            vaultId: widget.vaultId,
            entries: _vaultEntries ?? const [],
            initial: _refs,
            onChanged: (refs) => setState(() => _refs = refs),
          ),
      ],
    };
  }

  /// Called by the browser upload circle — returns the file:// path
  /// without updating [_icon] (the browser handles selection state).
  Future<String?> _pickIconFile() async {
    if (_pickingIcon || _uploadingIcon) return null;
    setState(() => _pickingIcon = true);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (file == null || !mounted) return null;
      return 'file://${file.path}';
    } finally {
      if (mounted) setState(() => _pickingIcon = false);
    }
  }

  /// Opens the full icon + color browser sheet. Mirrors the agents
  /// approve sheet flow — the user picks a glyph and a swatch in one
  /// modal instead of having a separate color picker row below the icon
  /// grid.
  Future<void> _openEntryBrowser() async {
    final l10n = AppLocalizations.of(context)!;
    final result = await IconColorBrowserSheet.show(
      context,
      icons: EntryVisuals.iconChoices
          .map(
            (c) => (name: c.name, icon: c.icon, paletteColor: c.paletteColor),
          )
          .toList(),
      colorOptions: VaultVisuals.colorChoices
          .map(VaultVisuals.colorFor)
          .toList(),
      initialIconKey: _icon,
      initialColor: VaultVisuals.colorFor(_colorHex),
      title: l10n.agentIconBrowserTitle,
      confirmLabel: l10n.agentIconChoose,
      onPickCustom: _pickIconFile,
    );
    if (!mounted || result == null) return;
    final pickedColor = result.color;
    final matchedHex = VaultVisuals.colorChoices.firstWhere(
      (hex) => VaultVisuals.colorFor(hex).toARGB32() == pickedColor.toARGB32(),
      orElse: () => EntryVisuals.defaultColorHex,
    );
    setState(() {
      if (result.iconKey != null) _icon = result.iconKey!;
      _colorHex = matchedHex;
    });
  }

  Future<void> _submit() async {
    if (!_validateUrl()) return;
    final payload = _buildPayload();
    if (!EntryFormUtils.isPayloadWithinLimit(payload)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.entryTooLarge)),
        );
      return;
    }
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated || auth.privateKey == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.entryErrorCrypto),
          ),
        );
      return;
    }

    final keyCopy = Uint8List.fromList(auth.privateKey!);
    final urlDomain = EntryFormUtils.extractDomain(_urlController.text);
    final hasCustomFile = _icon.startsWith('file://');
    // Send null icon when a custom file is pending — the preset icon will
    // be replaced by the S3 URL after the two-step upload.
    final iconForApi = hasCustomFile ? null : _icon;
    try {
      await context.read<CreateEntryCubit>().createEntry(
        vaultId: widget.vaultId,
        label: _labelController.text,
        description: _descriptionController.text,
        icon: iconForApi,
        type: _type,
        payload: payload,
        urlDomain: urlDomain,
        privateKey: keyCopy,
        wrappedVK: widget.wrappedVK,
        agentFields: CustomField.agentFieldsFrom(_allCustomFields),
      );
    } finally {
      keyCopy.fillRange(0, keyCopy.length, 0);
    }

    if (!mounted) return;
    final cubitState = context.read<CreateEntryCubit>().state;
    if (cubitState is! CreateEntrySuccess) return;

    var entry = cubitState.entry;
    if (hasCustomFile) {
      setState(() => _uploadingIcon = true);
      try {
        final service = EntryIconUploadService(getIt<EntryRemoteDatasource>());
        final url = await service.uploadIcon(
          widget.vaultId,
          entry.id,
          File(_icon.substring(7)),
        );
        entry = entry.copyWith(icon: url);
      } on VaultIconUploadException catch (e) {
        if (mounted) {
          final l = AppLocalizations.of(context)!;
          final msg = switch (e.kind) {
            VaultIconUploadErrorKind.unsupportedFormat =>
              l.vaultIconUploadFormatError,
            VaultIconUploadErrorKind.fileTooLarge => l.vaultIconUploadSizeError,
            _ => l.vaultIconUploadError,
          };
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(msg),
                duration: const Duration(seconds: 6),
              ),
            );
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  AppLocalizations.of(context)!.vaultIconUploadError,
                ),
                duration: const Duration(seconds: 6),
              ),
            );
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
    // The icon tint follows the user-picked color from the icon-browser
    // sheet. The color is UI-only — there is no per-entry color field on
    // the backend, so we do not forward it to the API.
    final accentColor = VaultVisuals.colorFor(_colorHex);

    return BlocBuilder<CreateEntryCubit, CreateEntryState>(
      builder: (context, state) {
        final isLoading = state is CreateEntryLoading || _uploadingIcon;
        final isBusy = isLoading || _pickingIcon;
        final canSubmit = !isBusy && _canSubmit;

        return AppScreen.appBar(
          appBar: AppBar(
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
              l10n.entryAddTitle,
              style: TextStyle(
                color: AppColors.onSurface(brightness),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          body: SingleChildScrollView(
            // Title→content gap (headerGap) is owned by AppScreen.appBar.
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenH,
              0,
              AppSpacing.screenH,
              AppSpacing.screenBottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Type — a select-input, consistent with the other fields.
                EntryTypeDropdown(
                  value: _type,
                  onChanged: (next) {
                    if (next == null || next == _type) return;
                    setState(() {
                      _type = next;
                      if (EntryVisuals.isCustomUrl(_icon)) return;
                      _icon = EntryVisuals.defaultIconForType(next);
                    });
                    if (next == EntryType.script) _ensureVaultEntriesLoaded();
                  },
                ),
                const SizedBox(height: AppSpacing.fieldGap),
                // 2. Label — with inline entry icon + agent-visible hint.
                EntryFieldCaption(
                  label: l10n.entryLabelLabel,
                  agentVisibleHint: true,
                ),
                const SizedBox(height: AppSpacing.innerGap),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EntryIconTile(
                      icon: _icon,
                      accentColor: accentColor,
                      onTap: _openEntryBrowser,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: OnboardingTextField(
                        hintText: l10n.entryLabelHint,
                        controller: _labelController,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.fieldGap),
                // 3. Description — agent-visible.
                EntryFieldCaption(
                  label: l10n.entryDescriptionLabel,
                  agentVisibleHint: true,
                ),
                const SizedBox(height: AppSpacing.innerGap),
                OnboardingTextField(
                  controller: _descriptionController,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: AppSpacing.fieldGap),
                // 4. Type-specific fields (+ URL / injected data).
                ..._typeFields(l10n),
                const SizedBox(height: AppSpacing.section),
                // 5. Two-factor authentication (not for Script).
                if (_type != EntryType.script) ...[
                  TotpSection(
                    initial: _totpFields,
                    onChanged: (fields) => setState(() => _totpFields = fields),
                  ),
                  const SizedBox(height: AppSpacing.section),
                ],
                // 6. Additional fields (all types).
                CustomFieldsEditor(
                  initial: _customFields,
                  onChanged: (fields, valid) => setState(() {
                    _customFields = fields;
                    _customFieldsValid = valid;
                  }),
                ),
                const SizedBox(height: AppSpacing.section),
                // 7. Notes — add-on-demand (hidden until the user taps).
                EntryNotesSection(
                  controller: _notesController,
                  initiallyVisible: _notesController.text.trim().isNotEmpty,
                ),
                const SizedBox(height: AppSpacing.section),
                EntryEncryptionNotice(
                  message: _type == EntryType.key
                      ? l10n.entryKeyVisibilityPolicy
                      : l10n.entryEncryptionNotice,
                ),
                if (state is CreateEntryError) ...[
                  const SizedBox(height: AppSpacing.fieldGap),
                  Text(
                    EntryFormUtils.errorMessage(l10n, state.kind),
                    style: const TextStyle(
                      color: AppColors.brandRed,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.section),
                // 8. Save button
                EntrySaveButton(
                  isLoading: isLoading,
                  onPressed: canSubmit ? _submit : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
