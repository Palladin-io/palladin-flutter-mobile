import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/utils/secure_clipboard.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/icon_color_browser_sheet.dart';
import '../../../../core/widgets/icon_picker_grid.dart' show IconMoreTile;
import '../../../../core/widgets/warning_zone.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../../onboarding/presentation/widgets/primary_button.dart';
import '../../data/datasources/entry_remote_datasource.dart';
import '../../data/services/entry_icon_upload_service.dart';
import '../../data/services/vault_icon_upload_service.dart'
    show VaultIconUploadErrorKind, VaultIconUploadException;
import '../../domain/entities/custom_field.dart';
import '../../domain/entities/entry_entity.dart';
import '../../domain/entities/totp_config.dart';
import '../../domain/repositories/entry_repository.dart';
import '../cubit/edit_entry_cubit.dart';
import '../widgets/custom_fields_editor.dart';
import '../widgets/entry_field_row.dart';
import '../widgets/entry_form_utils.dart';
import '../widgets/entry_form_widgets.dart';
import '../widgets/entry_icon_picker.dart';
import '../widgets/script_refs_editor.dart';
import '../widgets/totp_display.dart';
import '../widgets/vault_visuals.dart';

/// The Details tab of the entry detail screen.
///
/// Defaults to a **read-only, quick-access** presentation: each field is a
/// non-editable row with per-value copy (and, for secrets, a masked value +
/// reveal toggle) — mirroring the web entry-row quick actions. The payload
/// is decrypted once on open (the parent wires the reveal into the shared
/// [EditEntryCubit]); secrets stay masked until the user taps reveal.
///
/// Tapping **Edit** swaps in the existing edit form (same cubit-driven flow
/// that used to be the tab's default). Saving or cancelling returns to the
/// read-only view with refreshed values. Delete lives in the edit-mode
/// danger zone, unchanged.
class EntryDetailsTab extends StatefulWidget {
  const EntryDetailsTab({
    super.key,
    required this.entry,
    required this.onUpdated,
    required this.onDeleted,
    this.wrappedVK,
    this.editController,
  });

  final EntryEntity entry;

  /// Bubbles the freshly-saved entity up to the host page so it can update
  /// the app-bar title and return an [EntryDetailUpdated] result on back.
  final ValueChanged<EntryEntity> onUpdated;

  /// Fires after a successful delete so the host page can pop with an
  /// [EntryDetailDeleted] result.
  final ValueChanged<String> onDeleted;

  final String? wrappedVK;

  /// Bridges edit mode to the host AppBar so a Cancel action can sit beside the
  /// entry name (very top) instead of inside the tab body.
  final EntryEditController? editController;

  @override
  State<EntryDetailsTab> createState() => _EntryDetailsTabState();
}

class _EntryDetailsTabState extends State<EntryDetailsTab> {
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
  String _icon = EntryVisuals.defaultIconName;
  String _colorHex = EntryVisuals.defaultColorHex;
  String? _urlError;
  bool _pickingIcon = false;
  bool _uploadingIcon = false;
  bool _valueObscured = true;
  bool _passwordObscured = true;
  bool _populated = false;

  List<CustomField> _customFields = const [];
  bool _customFieldsValid = true;
  List<ScriptRef> _refs = const [];

  /// Legacy flat `otpauth://` TOTP string on an imported credential — kept
  /// so an edit does not drop it (v2 moves TOTP into a custom field).
  String? _credentialTotp;

  /// Candidate reference targets for a Script entry, loaded lazily on edit.
  List<EntryEntity>? _vaultEntries;
  bool _loadingEntries = false;

  /// Edit mode toggle — false renders the read-only quick-access view.
  bool _editMode = false;

  /// Whether the single secret field (password / key value) is unmasked in
  /// the read-only view. Reset every time we return to read-only.
  bool _secretRevealed = false;

  /// Per-custom-field reveal flags (keyed by field id) in the read-only
  /// view. Reset when returning to read-only.
  final Set<String> _revealedCustom = <String>{};

  /// The last persisted plaintext payload + metadata, used to render the
  /// read-only view. Populated on reveal and refreshed after a save so the
  /// read-only view never re-decrypts.
  Map<String, dynamic>? _payload;
  EntryEntity? _revealedEntry;

  @override
  void initState() {
    super.initState();
    widget.editController?.bindCancel(_cancelEdit);
    // Resolve reference target names for a Script entry's read-only view.
    if (widget.entry.type == EntryType.script) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _ensureVaultEntriesLoaded(),
      );
    }
  }

  /// Resolves a reference target entry id to its label, falling back to a
  /// shortened id when the entry list hasn't loaded or the entry is gone.
  String _refEntryLabel(String entryId) {
    final entries = _vaultEntries;
    if (entries != null) {
      for (final e in entries) {
        if (e.id == entryId) return e.label;
      }
    }
    if (entryId.length <= 14) return entryId;
    return '${entryId.substring(0, 8)}…${entryId.substring(entryId.length - 6)}';
  }

  Future<void> _copyTotp(String code) async {
    await SecureClipboard.copy(code);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(l10n.totpCodeCopied),
        duration: const Duration(seconds: 1),
      ));
  }

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

  // ── Population / snapshot ──────────────────────────────────────────

  void _adoptRevealed(EntryEntity entry, Map<String, dynamic> payload) {
    _populated = true;
    _revealedEntry = entry;
    _payload = payload;
    _syncControllersFromSnapshot();
  }

  /// Loads the edit-form controllers from the current saved snapshot so a
  /// fresh Edit session always starts from persisted values (never leftover
  /// dirty text from a cancelled edit).
  void _syncControllersFromSnapshot() {
    final entry = _revealedEntry;
    final payload = _payload;
    if (entry == null || payload == null) return;
    _labelController.text = entry.label;
    _descriptionController.text = entry.description ?? '';
    _type = entry.type;
    _icon = entry.icon ?? EntryVisuals.defaultIconName;
    _urlController.text = (payload['url'] as String?) ?? '';
    _notesController.text = (payload['notes'] as String?) ?? '';
    _customFields = CustomField.listFromPayload(payload);
    _customFieldsValid = true;
    switch (entry.type) {
      case EntryType.key:
        _valueController.text = (payload['value'] as String?) ?? '';
      case EntryType.credential:
        _usernameController.text = (payload['username'] as String?) ?? '';
        _passwordController.text = (payload['password'] as String?) ?? '';
        _credentialTotp = payload['totp'] as String?;
      case EntryType.script:
        _scriptController.text = (payload['script'] as String?) ?? '';
        _interpreter =
            ScriptInterpreter.fromName(payload['interpreter'] as String?);
        _refs = ScriptRef.listFromPayload(payload);
    }
  }

  /// Loads the vault's key/credential entries for a Script entry's
  /// reference picker. Best-effort; excludes this entry and other scripts.
  Future<void> _ensureVaultEntriesLoaded() async {
    if (_vaultEntries != null || _loadingEntries) return;
    setState(() => _loadingEntries = true);
    try {
      final entries =
          await getIt<EntryRepository>().listEntries(widget.entry.vaultId);
      if (!mounted) return;
      setState(() {
        _vaultEntries = entries
            .where((e) =>
                e.type != EntryType.script && e.id != widget.entry.id)
            .toList(growable: false);
      });
    } catch (_) {
      if (mounted) setState(() => _vaultEntries = const []);
    } finally {
      if (mounted) setState(() => _loadingEntries = false);
    }
  }

  // ── Mode transitions ───────────────────────────────────────────────

  void _enterEditMode() {
    setState(() {
      _syncControllersFromSnapshot();
      _urlError = null;
      _valueObscured = true;
      _passwordObscured = true;
      _editMode = true;
    });
    if (_type == EntryType.script) _ensureVaultEntriesLoaded();
    widget.editController?.publishEditing(true);
  }

  void _cancelEdit() {
    setState(() {
      _editMode = false;
      _secretRevealed = false;
      _urlError = null;
    });
    widget.editController?.publishEditing(false);
  }

  // ── Copy / clipboard ───────────────────────────────────────────────

  Future<void> _copy(String value, String field) async {
    await SecureClipboard.copy(value);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(l10n.entryCopiedField(field)),
        duration: const Duration(seconds: 1),
      ));
  }

  // ── Edit-form helpers (unchanged behaviour) ────────────────────────

  bool _validateUrl() {
    final valid = EntryFormUtils.isValidUrl(_urlController.text);
    setState(
      () => _urlError =
          valid ? null : AppLocalizations.of(context)!.entryUrlInvalid,
    );
    return valid;
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

  Map<String, dynamic> _buildPayload() => EntryFormUtils.buildPayload(
        type: _type,
        value: _valueController.text,
        username: _usernameController.text,
        password: _passwordController.text,
        url: _urlController.text,
        notes: _notesController.text,
        fields: _customFields,
        script: _scriptController.text,
        interpreter: _interpreter,
        refs: _refs,
        credentialTotp: _credentialTotp,
      );

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

  Future<void> _openEntryBrowser() async {
    final l10n = AppLocalizations.of(context)!;
    final result = await IconColorBrowserSheet.show(
      context,
      icons: EntryVisuals.iconChoices
          .map((c) => (name: c.name, icon: c.icon, paletteColor: c.paletteColor))
          .toList(),
      colorOptions:
          VaultVisuals.colorChoices.map(VaultVisuals.colorFor).toList(),
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

  /// The entry's real creation timestamp, read from the revealed entity so
  /// it survives an edit.
  DateTime _originalCreatedAt(EditEntryState state) => switch (state) {
        EditEntryReady(:final entry) => entry.createdAt,
        EditEntrySuccess(:final entry) => entry.createdAt,
        _ => _revealedEntry?.createdAt ?? widget.entry.createdAt,
      };

  Future<void> _submit() async {
    if (!_validateUrl()) return;
    final payload = _buildPayload();
    if (!EntryFormUtils.isPayloadWithinLimit(payload)) {
      _showSnackBar(AppLocalizations.of(context)!.entryTooLarge);
      return;
    }
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated || auth.privateKey == null) {
      _showSnackBar(AppLocalizations.of(context)!.entryErrorCrypto);
      return;
    }

    final keyCopy = Uint8List.fromList(auth.privateKey!);
    final urlDomain = EntryFormUtils.extractDomain(_urlController.text);
    final hasCustomFile = _icon.startsWith('file://');
    final iconForApi = hasCustomFile ? null : _icon;
    final cubit = context.read<EditEntryCubit>();
    try {
      await cubit.updateEntry(
        vaultId: widget.entry.vaultId,
        entryId: widget.entry.id,
        label: _labelController.text,
        description: _descriptionController.text,
        icon: iconForApi,
        type: _type,
        payload: payload,
        urlDomain: urlDomain,
        privateKey: keyCopy,
        wrappedVK: widget.wrappedVK,
        createdAt: _originalCreatedAt(cubit.state),
      );
    } finally {
      keyCopy.fillRange(0, keyCopy.length, 0);
    }

    if (!mounted) return;
    final cubitState = context.read<EditEntryCubit>().state;
    if (cubitState is! EditEntrySuccess) return;

    var entry = cubitState.entry;
    if (hasCustomFile) {
      setState(() => _uploadingIcon = true);
      try {
        final service = EntryIconUploadService(getIt<EntryRemoteDatasource>());
        final url = await service.uploadIcon(
          widget.entry.vaultId,
          entry.id,
          File(_icon.substring(7)),
        );
        entry = entry.copyWith(icon: url);
      } on VaultIconUploadException catch (e) {
        entry = entry.copyWith(icon: widget.entry.icon);
        if (mounted) {
          final l = AppLocalizations.of(context)!;
          final msg = switch (e.kind) {
            VaultIconUploadErrorKind.unsupportedFormat =>
              l.vaultIconUploadFormatError,
            VaultIconUploadErrorKind.fileTooLarge => l.vaultIconUploadSizeError,
            _ => l.vaultIconUploadError,
          };
          _showSnackBar(msg);
        }
      } catch (_) {
        entry = entry.copyWith(icon: widget.entry.icon);
        if (mounted) {
          _showSnackBar(AppLocalizations.of(context)!.vaultIconUploadError);
        }
      } finally {
        if (mounted) setState(() => _uploadingIcon = false);
      }
    }

    if (!mounted) return;
    // Refresh the snapshot from the just-saved values and drop back to the
    // read-only view — the page keeps this as the pending "updated" result.
    setState(() {
      _revealedEntry = entry;
      _payload = _buildPayload();
      _secretRevealed = false;
      _revealedCustom.clear();
      _editMode = false;
    });
    widget.editController?.publishEditing(false);
    widget.onUpdated(entry);
  }

  Future<void> _confirmDelete() async {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.modalBackground(brightness),
        title: Text(
          l10n.entryDeleteTitle,
          style: TextStyle(color: AppColors.onSurface(brightness)),
        ),
        content: Text(
          l10n.entryDeleteConfirm,
          style: TextStyle(
            color: AppColors.onSurfaceMuted(brightness),
            fontSize: 13,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              l10n.vaultCancel,
              style: TextStyle(color: AppColors.onSurfaceMuted(brightness)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              l10n.entryDeleteAction,
              style: const TextStyle(color: AppColors.brandRed),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    // ignore: use_build_context_synchronously
    await context.read<EditEntryCubit>().deleteEntry(
          vaultId: widget.entry.vaultId,
          entryId: widget.entry.id,
        );
    if (!mounted) return;
    final state = context.read<EditEntryCubit>().state;
    if (state is EditEntryDeleted) {
      widget.onDeleted(widget.entry.id);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return BlocBuilder<EditEntryCubit, EditEntryState>(
      builder: (context, state) {
        // Adopt the decrypted payload the first time it is available. Done in
        // the builder (not a listener) so it also covers the case where the
        // cubit is already `EditEntryReady` on first build — the cachedPayload
        // / setReady path — where a BlocListener would never fire. Mutating
        // `_populated`/controllers here is a safe memoisation: the same build
        // then renders the populated view, so no extra rebuild is scheduled.
        if (state is EditEntryReady && !_populated) {
          _adoptRevealed(state.entry, state.payload);
        }
        if (!_populated &&
            (state is EditEntryInitial || state is EditEntryRevealing)) {
          return _RevealLoading(message: l10n.entryRevealingForEdit);
        }
        if (!_populated && state is EditEntryError) {
          return _RevealError(
            message: EntryFormUtils.errorMessage(l10n, state.kind),
          );
        }
        return _editMode
            ? _buildEditForm(l10n, brightness, state)
            : _buildReadOnly(l10n, brightness);
      },
    );
  }

  // ── Read-only quick-access view ────────────────────────────────────

  Widget _buildReadOnly(AppLocalizations l10n, Brightness brightness) {
    final entry = _revealedEntry ?? widget.entry;
    final payload = _payload ?? const <String, dynamic>{};

    final url = (payload['url'] as String?)?.trim() ?? '';
    final username = (payload['username'] as String?) ?? '';
    final password = (payload['password'] as String?) ?? '';
    final value = (payload['value'] as String?) ?? '';
    final notes = (payload['notes'] as String?) ?? '';
    final description = entry.description ?? '';

    final fields = <Widget>[];

    void addField(Widget child) {
      if (fields.isNotEmpty) {
        fields.add(_FieldDivider(brightness: brightness));
      }
      fields.add(child);
    }

    if (description.isNotEmpty) {
      addField(_ReadOnlyField(
        label: l10n.entryDescriptionLabel,
        row: EntryFieldRow(
          icon: Icons.notes,
          value: description,
          isMasked: false,
          revealed: true,
          onToggleReveal: null,
          onCopy: () => _copy(description, l10n.entryDescriptionLabel),
        ),
      ));
    }

    if (url.isNotEmpty) {
      addField(_ReadOnlyField(
        label: l10n.entryUrlLabel,
        row: EntryFieldRow(
          icon: Icons.link,
          value: url,
          isMasked: false,
          revealed: true,
          onToggleReveal: null,
          onCopy: () => _copy(url, l10n.entryUrlLabel),
          extraTrailing: EntrySmallIconButton(
            icon: Icons.open_in_new,
            tooltip: l10n.vaultOpenLink,
            // url_launcher is not a dependency — degrade "open" to copy.
            onPressed: () => _copy(url, l10n.entryUrlLabel),
          ),
        ),
      ));
    }

    switch (entry.type) {
      case EntryType.key:
        if (value.isNotEmpty) {
          addField(_ReadOnlyField(
            label: l10n.entryValueLabel,
            row: EntryFieldRow(
              icon: Icons.vpn_key,
              value: value,
              isMasked: true,
              revealed: _secretRevealed,
              onToggleReveal: () =>
                  setState(() => _secretRevealed = !_secretRevealed),
              onCopy: () => _copy(value, l10n.entryValueLabel),
            ),
          ));
        }
      case EntryType.credential:
        if (username.isNotEmpty) {
          addField(_ReadOnlyField(
            label: l10n.entryUsernameLabel,
            row: EntryFieldRow(
              icon: Icons.person,
              value: username,
              isMasked: false,
              revealed: true,
              onToggleReveal: null,
              onCopy: () => _copy(username, l10n.entryUsernameLabel),
            ),
          ));
        }
        if (password.isNotEmpty) {
          addField(_ReadOnlyField(
            label: l10n.entryPasswordLabel,
            row: EntryFieldRow(
              icon: Icons.lock,
              value: password,
              isMasked: true,
              revealed: _secretRevealed,
              onToggleReveal: () =>
                  setState(() => _secretRevealed = !_secretRevealed),
              onCopy: () => _copy(password, l10n.entryPasswordLabel),
            ),
          ));
        }
      case EntryType.script:
        _addScriptFields(addField, payload, l10n, brightness);
    }

    _addCustomFields(addField, payload, l10n, brightness);

    if (notes.isNotEmpty) {
      addField(_ReadOnlyField(
        label: l10n.entryNotesLabel,
        row: EntryFieldRow(
          icon: Icons.sticky_note_2_outlined,
          value: notes,
          isMasked: false,
          revealed: true,
          onToggleReveal: null,
          onCopy: () => _copy(notes, l10n.entryNotesLabel),
        ),
      ));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.fieldGap,
        AppSpacing.screenH,
        AppSpacing.screenBottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (fields.isEmpty)
            _EmptyReadOnly(message: l10n.entryEmpty, brightness: brightness)
          else
            Container(
              decoration: BoxDecoration(
                color: AppColors.cardFill(brightness),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.cardBorder(brightness),
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.cardPadding,
                vertical: AppSpacing.innerGap,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: fields,
              ),
            ),
          if (entry.type == EntryType.script) ...[
            const SizedBox(height: AppSpacing.section),
            WarningZone(
              title: l10n.entryScriptExecOnlyTitle,
              message: l10n.entryScriptExecOnlyNotice,
            ),
          ],
          const SizedBox(height: AppSpacing.section),
          EntryEncryptionNotice(message: l10n.entryEncryptionNotice),
          const SizedBox(height: AppSpacing.section),
          // Edit as a full-width button below the encrypted fields.
          PrimaryButton(
            label: l10n.entryEditAction,
            onPressed: _enterEditMode,
          ),
          const SizedBox(height: AppSpacing.section),
          _DangerZone(
            label: l10n.entryDangerZone,
            deleteLabel: l10n.entryDeleteAction,
            onDelete: _confirmDelete,
            brightness: brightness,
          ),
        ],
      ),
    );
  }

  void _toggleCustomReveal(String id) {
    setState(() {
      if (!_revealedCustom.remove(id)) _revealedCustom.add(id);
    });
  }

  /// Read-only rendering of a Script entry's body, interpreter and refs.
  void _addScriptFields(
    void Function(Widget) addField,
    Map<String, dynamic> payload,
    AppLocalizations l10n,
    Brightness brightness,
  ) {
    final script = (payload['script'] as String?) ?? '';
    final interpreter =
        ScriptInterpreter.fromName(payload['interpreter'] as String?);
    final refs = ScriptRef.listFromPayload(payload);

    if (script.isNotEmpty) {
      addField(_ReadOnlyField(
        label: l10n.entryScriptLabel,
        row: _ScriptBodyView(
          script: script,
          revealed: _secretRevealed,
          brightness: brightness,
          onToggle: () =>
              setState(() => _secretRevealed = !_secretRevealed),
          onCopy: () => _copy(script, l10n.entryScriptLabel),
        ),
      ));
    }

    addField(_ReadOnlyField(
      label: l10n.entryInterpreterLabel,
      row: EntryFieldRow(
        icon: Icons.code,
        value: interpreter.wireName,
        isMasked: false,
        revealed: true,
        onToggleReveal: null,
        onCopy: () => _copy(interpreter.wireName, l10n.entryInterpreterLabel),
      ),
    ));

    for (final ref in refs) {
      if (ref.env.isEmpty) continue;
      addField(_ReadOnlyField(
        label: ref.env,
        row: EntryFieldRow(
          icon: Icons.data_object,
          value: '${_refEntryLabel(ref.entryId)} · ${ref.field}',
          isMasked: false,
          revealed: true,
          onToggleReveal: null,
          onCopy: () => _copy(ref.env, l10n.entryRefEnvLabel),
        ),
      ));
    }
  }

  /// Read-only rendering of custom fields (text / concealed / totp).
  /// Unknown types are ignored (spec §1 forward-compat).
  void _addCustomFields(
    void Function(Widget) addField,
    Map<String, dynamic> payload,
    AppLocalizations l10n,
    Brightness brightness,
  ) {
    final customFields = CustomField.listFromPayload(payload);
    for (final field in customFields) {
      switch (field.type) {
        case CustomFieldType.text:
          addField(_ReadOnlyField(
            label: field.label,
            row: EntryFieldRow(
              icon: Icons.short_text,
              value: field.textValue,
              isMasked: false,
              revealed: true,
              onToggleReveal: null,
              onCopy: () => _copy(field.textValue, field.label),
            ),
          ));
        case CustomFieldType.concealed:
          addField(_ReadOnlyField(
            label: field.label,
            row: EntryFieldRow(
              icon: Icons.lock_outline,
              value: field.textValue,
              isMasked: true,
              revealed: _revealedCustom.contains(field.id),
              onToggleReveal: () => _toggleCustomReveal(field.id),
              onCopy: () => _copy(field.textValue, field.label),
            ),
          ));
        case CustomFieldType.totp:
          final config = field.totp;
          if (config == null) break;
          addField(_ReadOnlyField(
            label: field.label,
            row: _TotpFieldRow(
              config: config,
              revealed: _revealedCustom.contains(field.id),
              onToggle: () => _toggleCustomReveal(field.id),
              onCopy: _copyTotp,
            ),
          ));
        case CustomFieldType.unknown:
          break;
      }
    }
  }

  // ── Edit form (previous default presentation) ──────────────────────

  /// Type-specific edit fields for the currently-selected [_type].
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
              onPressed: () =>
                  setState(() => _valueObscured = !_valueObscured),
            ),
          ),
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
        ],
      EntryType.script => [
          WarningZone(
            title: l10n.entryScriptExecOnlyTitle,
            message: l10n.entryScriptExecOnlyNotice,
          ),
          const SizedBox(height: AppSpacing.fieldGap),
          OnboardingTextField(
            label: l10n.entryScriptLabel,
            hintText: l10n.entryScriptHint,
            controller: _scriptController,
            maxLines: 8,
            monospace: true,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.fieldGap),
          EntryInterpreterDropdown(
            value: _interpreter,
            onChanged: (next) {
              if (next == null) return;
              setState(() => _interpreter = next);
            },
          ),
          const SizedBox(height: AppSpacing.fieldGap),
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
              vaultId: widget.entry.vaultId,
              entries: _vaultEntries ?? const [],
              initial: _refs,
              onChanged: (refs) => setState(() => _refs = refs),
            ),
        ],
    };
  }

  Widget _buildEditForm(
    AppLocalizations l10n,
    Brightness brightness,
    EditEntryState state,
  ) {
    final accentColor = VaultVisuals.colorFor(_colorHex);
    final isLoading = state is EditEntryLoading || _uploadingIcon;
    final isBusy = isLoading || _pickingIcon;
    final canSubmit = !isBusy && _canSubmit;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.fieldGap,
        AppSpacing.screenH,
        AppSpacing.screenBottom,
      ),
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
          const SizedBox(height: AppSpacing.fieldGap),
          OnboardingTextField(
            label: l10n.entryDescriptionLabel,
            controller: _descriptionController,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.fieldGap),
          if (_type != EntryType.script) ...[
            OnboardingTextField(
              label: l10n.entryUrlLabel,
              controller: _urlController,
              textInputAction: TextInputAction.next,
              borderColor: _urlError != null ? AppColors.brandRed : null,
              focusBorderColor: _urlError != null ? AppColors.brandRed : null,
              onChanged: (_) => _validateUrl(),
              feedbackChild: Text(
                _urlError ?? '',
                style:
                    const TextStyle(color: AppColors.brandRed, fontSize: 11),
              ),
              feedbackVisible: _urlError != null,
              feedbackReserveSpace: false,
            ),
            const SizedBox(height: AppSpacing.fieldGap),
          ],
          Text(
            l10n.vaultIconLabel,
            style: TextStyle(
              color: AppColors.onSurfaceSubtle(brightness),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.innerGap),
          EntryIconPicker(
            selected: _icon,
            accentColor: accentColor,
            onSelected: (name) => setState(() => _icon = name),
            moreTile: IconMoreTile(onTap: _openEntryBrowser),
          ),
          const SizedBox(height: AppSpacing.fieldGap),
          EntryTypeDropdown(
            value: _type,
            onChanged: (next) {
              if (next == null || next == _type) return;
              setState(() => _type = next);
              if (next == EntryType.script) _ensureVaultEntriesLoaded();
            },
          ),
          const SizedBox(height: AppSpacing.fieldGap),
          ..._typeFields(l10n),
          const SizedBox(height: AppSpacing.fieldGap),
          CustomFieldsEditor(
            initial: _customFields,
            onChanged: (fields, valid) => setState(() {
              _customFields = fields;
              _customFieldsValid = valid;
            }),
          ),
          const SizedBox(height: AppSpacing.fieldGap),
          EntryNotesField(
            controller: _notesController,
            label: l10n.entryNotesLabel,
          ),
          const SizedBox(height: AppSpacing.section),
          EntryEncryptionNotice(message: l10n.entryEncryptionNotice),
          if (state is EditEntryError) ...[
            const SizedBox(height: AppSpacing.fieldGap),
            Text(
              EntryFormUtils.errorMessage(l10n, state.kind),
              style: const TextStyle(color: AppColors.brandRed, fontSize: 12),
            ),
          ],
          const SizedBox(height: AppSpacing.section),
          EntrySaveButton(
            isLoading: isLoading,
            onPressed: canSubmit ? _submit : null,
          ),
          const SizedBox(height: AppSpacing.section),
          _DangerZone(
            label: l10n.entryDangerZone,
            deleteLabel:
                isLoading ? l10n.entryDeleting : l10n.entryDeleteAction,
            onDelete: isBusy ? null : _confirmDelete,
            brightness: brightness,
          ),
        ],
      ),
    );
  }
}

// ── Read-only sub-widgets ────────────────────────────────────────────

/// A labelled read-only field: a small caption above an [EntryFieldRow].
class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.label, required this.row});

  final String label;
  final Widget row;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.innerGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.onSurfaceSubtle(brightness),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          row,
        ],
      ),
    );
  }
}

class _FieldDivider extends StatelessWidget {
  const _FieldDivider({required this.brightness});

  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: AppColors.onSurface(brightness).withValues(alpha: 0.06),
    );
  }
}

/// Small right-aligned Edit / Cancel affordance shown above the fields.

class _EmptyReadOnly extends StatelessWidget {
  const _EmptyReadOnly({required this.message, required this.brightness});

  final String message;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
      child: Center(
        child: Text(
          message,
          style: TextStyle(
            color: AppColors.onSurfaceSubtle(brightness),
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

/// Read-only script body — masked behind bullets with a reveal toggle and
/// copy; when revealed shows the full body in a scrollable monospace box.
class _ScriptBodyView extends StatelessWidget {
  const _ScriptBodyView({
    required this.script,
    required this.revealed,
    required this.brightness,
    required this.onToggle,
    required this.onCopy,
  });

  final String script;
  final bool revealed;
  final Brightness brightness;
  final VoidCallback onToggle;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.terminal,
              size: 12,
              color: AppColors.onSurfaceSubtle(brightness),
            ),
            const SizedBox(width: AppSpacing.innerGap),
            Expanded(
              child: revealed
                  ? const SizedBox.shrink()
                  : Text(
                      '••••••••••••',
                      style: TextStyle(
                        color: AppColors.onSurface(brightness),
                        fontSize: 12,
                        fontFamily: 'monospace',
                        letterSpacing: 0.5,
                      ),
                    ),
            ),
            EntrySmallIconButton(
              icon: revealed ? Icons.visibility_off : Icons.visibility,
              tooltip: l10n.vaultRevealValue,
              onPressed: onToggle,
            ),
            const SizedBox(width: AppSpacing.xs),
            EntrySmallIconButton(
              icon: Icons.content_copy,
              tooltip: l10n.vaultCopyValue,
              onPressed: onCopy,
            ),
          ],
        ),
        if (revealed) ...[
          const SizedBox(height: AppSpacing.innerGap),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 220),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.inputFill(brightness),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.cardBorder(brightness)),
            ),
            child: SingleChildScrollView(
              child: Text(
                script,
                style: TextStyle(
                  color: AppColors.onSurface(brightness),
                  fontSize: 12,
                  height: 1.4,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Read-only TOTP custom field — masked until revealed, then a live code
/// with a countdown ring (via [TotpDisplay]).
class _TotpFieldRow extends StatelessWidget {
  const _TotpFieldRow({
    required this.config,
    required this.revealed,
    required this.onToggle,
    required this.onCopy,
  });

  final TotpConfig config;
  final bool revealed;
  final VoidCallback onToggle;
  final ValueChanged<String> onCopy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    if (revealed) {
      return Row(
        children: [
          Expanded(child: TotpDisplay(config: config, onCopy: onCopy)),
          const SizedBox(width: AppSpacing.xs),
          EntrySmallIconButton(
            icon: Icons.visibility_off,
            tooltip: l10n.vaultRevealValue,
            onPressed: onToggle,
          ),
        ],
      );
    }
    return Row(
      children: [
        Icon(
          Icons.timer_outlined,
          size: 12,
          color: AppColors.onSurfaceSubtle(brightness),
        ),
        const SizedBox(width: AppSpacing.innerGap),
        Expanded(
          child: Text(
            '••• •••',
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 12,
              fontFamily: 'monospace',
              letterSpacing: 2,
            ),
          ),
        ),
        EntrySmallIconButton(
          icon: Icons.visibility,
          tooltip: l10n.vaultRevealValue,
          onPressed: onToggle,
        ),
      ],
    );
  }
}

class _RevealLoading extends StatelessWidget {
  const _RevealLoading({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.brandRed,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            style: const TextStyle(
              color: AppColors.textTertiaryMobile,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _RevealError extends StatelessWidget {
  const _RevealError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.brandRed,
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

// ── Danger zone ──────────────────────────────────────────────────────

/// Bridges the Details tab's edit mode to the host AppBar: the tab publishes
/// whether it is editing and binds its cancel action, so the AppBar can show a
/// Cancel button beside the entry name (at the very top) only while editing.
class EntryEditController extends ChangeNotifier {
  bool _editing = false;
  bool get editing => _editing;

  VoidCallback? _onCancel;

  void publishEditing(bool value) {
    if (_editing == value) return;
    _editing = value;
    notifyListeners();
  }

  void bindCancel(VoidCallback onCancel) => _onCancel = onCancel;

  void requestCancel() => _onCancel?.call();
}

class _DangerZone extends StatelessWidget {
  const _DangerZone({
    required this.label,
    required this.deleteLabel,
    required this.onDelete,
    required this.brightness,
  });

  final String label;
  final String deleteLabel;
  final VoidCallback? onDelete;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.brandRed.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.brandRed.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.brandRed,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 44,
            child: OutlinedButton(
              onPressed: onDelete,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.brandRed,
                disabledForegroundColor:
                    AppColors.brandRed.withValues(alpha: 0.4),
                side: BorderSide(
                  color: onDelete != null
                      ? AppColors.brandRed.withValues(alpha: 0.5)
                      : AppColors.brandRed.withValues(alpha: 0.2),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                deleteLabel,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
