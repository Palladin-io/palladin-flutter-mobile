import 'dart:convert';
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
import '../../../../core/widgets/app_toggle.dart';
import '../../../../core/widgets/warning_zone.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../public_asset_catalog/domain/services/website_icon_service.dart';
import '../../../public_asset_catalog/presentation/website_icon_auto_resolver.dart';
import '../../../public_asset_catalog/presentation/widgets/public_asset_picker_sheet.dart';
import '../../data/services/canonical_entry_detail_service.dart';
import '../../data/services/encrypted_presentation_asset_service.dart';
import '../../data/services/script_access_impact_service.dart';
import '../../domain/entities/custom_field.dart';
import '../../domain/entities/agent_visibility_policy.dart';
import '../../domain/entities/entry_entity.dart';
import '../../domain/entities/totp_config.dart';
import '../../domain/repositories/entry_repository.dart';
import '../cubit/edit_entry_cubit.dart';
import '../widgets/custom_fields_editor.dart';
import '../widgets/entry_field_row.dart';
import '../widgets/entry_form_utils.dart';
import '../widgets/entry_form_widgets.dart';
import '../widgets/entry_icon_tile.dart';
import '../widgets/entry_notes_section.dart';
import '../widgets/script_editor_field.dart';
import '../widgets/script_parameters_editor.dart';
import '../widgets/script_refs_editor.dart';
import '../widgets/totp_display.dart';
import '../widgets/totp_section.dart';
import '../widgets/vault_visuals.dart';

/// The Details tab of the entry detail screen.
///
/// Authenticates and decrypts MemberSecret on entry, then renders a read-only
/// quick-access view. Editing is an explicit mode; secrets stay masked until
/// the user reveals an individual field.
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

class _EntryDetailsTabState extends State<EntryDetailsTab>
    with WidgetsBindingObserver {
  final _labelController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _valueController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _urlController = TextEditingController();
  final _notesController = TextEditingController();
  final _scriptController = TextEditingController();
  final _cardholderController = TextEditingController();
  final _cardNumberController = TextEditingController();
  final _expiryMonthController = TextEditingController();
  final _expiryYearController = TextEditingController();
  final _billingAddressController = TextEditingController();

  EntryType _type = EntryType.credential;
  ScriptInterpreter _interpreter = ScriptInterpreter.bash;
  String _icon = EntryVisuals.defaultIconName;
  String? _resolvedWebsiteIcon;
  late final WebsiteIconAutoResolver _websiteIconResolver;
  String _colorHex = EntryVisuals.defaultColorHex;
  String? _urlError;
  bool _pickingIcon = false;
  bool _uploadingIcon = false;
  bool _reservingIcon = false;
  bool _submitInFlight = false;
  bool _valueObscured = true;
  bool _passwordObscured = true;
  bool _populated = false;
  int _plaintextEpoch = 0;
  AgentVisibilityPolicy? _agentPolicy;
  String? _agentLabel;

  List<CustomField> _customFields = const [];
  bool _customFieldsValid = true;
  List<CustomField> _totpFields = const [];
  List<ScriptRef> _refs = const [];
  List<ScriptParameterDefinition> _scriptParameters = const [];
  bool _returnResultToAgent = false;

  /// Every custom field in display order — 2FA first, then the rest.
  List<CustomField> get _allCustomFields => [..._totpFields, ..._customFields];

  /// Legacy flat `otpauth://` TOTP string on an imported credential — kept
  /// so an edit does not drop it (v2 moves TOTP into a custom field).
  Object? _credentialTotp;

  /// Candidate reference targets for a Script entry, loaded lazily on edit.
  List<EntryEntity>? _vaultEntries;
  bool _loadingEntries = false;

  /// Details opens as a quick-access view. The mutable form is entered only
  /// through the pinned Edit action.
  bool _editMode = false;

  /// Whether the single secret field (password / key value) is unmasked in
  /// the read-only view. Reset every time we return to read-only.
  bool _secretRevealed = false;
  final Set<String> _revealedCardFields = <String>{};

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
    _websiteIconResolver = WebsiteIconAutoResolver(
      service: getIt.isRegistered<WebsiteIconService>()
          ? getIt<WebsiteIconService>()
          : null,
      onReference: (reference) {
        if (mounted && _editMode) {
          setState(() {
            _resolvedWebsiteIcon = null;
            _icon = reference;
          });
        }
      },
      onResolved: (reference) {
        if (mounted && _editMode) {
          setState(() => _resolvedWebsiteIcon = reference);
        }
      },
      onAutomaticCleared: () {
        if (mounted && _editMode) {
          setState(() {
            _resolvedWebsiteIcon = null;
            _icon = EntryVisuals.defaultIconForType(_type);
          });
        }
      },
    );
    _urlController.addListener(_resolveWebsiteIcon);
    WidgetsBinding.instance.addObserver(this);
    widget.editController?.bindCancel(_cancelEdit);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.editController?.publishEditing(false);
      if (context.read<EditEntryCubit>().state is EditEntryInitial) {
        _requestReveal();
      }
    });
    // Resolve reference target names for a Script entry's read-only view.
    if (widget.entry.type == EntryType.script) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _ensureVaultEntriesLoaded(),
      );
    }
  }

  void _resolveWebsiteIcon() {
    if (_editMode && _type != EntryType.script) {
      _websiteIconResolver.resolve(_urlController.text);
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
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.totpCodeCopied),
          duration: const Duration(seconds: 1),
        ),
      );
  }

  @override
  void dispose() {
    _websiteIconResolver.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _clearPlaintextState();
    _labelController.dispose();
    _descriptionController.dispose();
    _valueController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _urlController.dispose();
    _notesController.dispose();
    _scriptController.dispose();
    _cardholderController.dispose();
    _cardNumberController.dispose();
    _expiryMonthController.dispose();
    _expiryYearController.dispose();
    _billingAddressController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      context.read<EditEntryCubit>().clearSensitiveState();
      if (mounted) {
        setState(() {
          _editMode = false;
          _reservingIcon = false;
          _clearPlaintextState();
        });
        widget.editController?.publishEditing(false);
      }
    } else if (mounted) {
      _requestReveal();
    }
  }

  void _clearPlaintextState() {
    _plaintextEpoch++;
    _payload = null;
    _revealedEntry = null;
    _populated = false;
    _secretRevealed = false;
    _revealedCardFields.clear();
    _revealedCustom.clear();
    _valueController.clear();
    _usernameController.clear();
    _passwordController.clear();
    _urlController.clear();
    _descriptionController.clear();
    _notesController.clear();
    _scriptController.clear();
    _cardholderController.clear();
    _cardNumberController.clear();
    _expiryMonthController.clear();
    _expiryYearController.clear();
    _billingAddressController.clear();
    _customFields = const [];
    _totpFields = const [];
    _refs = const [];
    _scriptParameters = const [];
    _returnResultToAgent = false;
    _credentialTotp = null;
    _agentPolicy = null;
    _agentLabel = null;
  }

  // ── Population / snapshot ──────────────────────────────────────────

  void _adoptRevealed(EntryEntity entry, Map<String, dynamic> payload) {
    _populated = true;
    _revealedEntry = entry;
    _payload = payload;
    final cubit = context.read<EditEntryCubit>();
    _agentPolicy = cubit.agentVisibilityPolicy(entry.type);
    _agentLabel = cubit.agentLabel;
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
    // A persisted glyph, upload, or catalog choice is authoritative. Its
    // provenance is intentionally not leaked in plaintext, so Edit must never
    // guess that it was automatic and replace it during an unrelated save.
    if (entry.icon != null) _websiteIconResolver.markManualSelection();
    _resolvedWebsiteIcon = null;
    _urlController.text = (payload['url'] as String?) ?? '';
    _notesController.text = (payload['notes'] as String?) ?? '';
    final allFields = CustomField.listFromPayload(payload);
    _totpFields = allFields
        .where((f) => f.type == CustomFieldType.totp)
        .toList();
    _customFields = allFields
        .where((f) => f.type != CustomFieldType.totp)
        .toList();
    _customFieldsValid = true;
    switch (entry.type) {
      case EntryType.key:
        _valueController.text = (payload['value'] as String?) ?? '';
      case EntryType.credential:
        _usernameController.text = (payload['username'] as String?) ?? '';
        _passwordController.text = (payload['password'] as String?) ?? '';
        _credentialTotp = payload['totp'];
      case EntryType.script:
        _scriptController.text = (payload['script'] as String?) ?? '';
        _interpreter = ScriptInterpreter.fromName(
          payload['interpreter'] as String?,
        );
        _refs = ScriptRef.listFromPayload(payload);
        final execution = payload['execution'];
        if (execution is Map) {
          final metadata = ScriptExecutionMetadata.fromJson(
            Map<String, dynamic>.from(execution),
          );
          _scriptParameters = metadata.parameters;
          _returnResultToAgent = metadata.returnResultToAgent;
        } else {
          // Legacy Scripts predate explicit result delivery and fail closed.
          _scriptParameters = const [];
          _returnResultToAgent = false;
        }
      case EntryType.creditCard:
        _cardholderController.text =
            (payload['cardholderName'] as String?) ?? '';
        _cardNumberController.text = (payload['cardNumber'] as String?) ?? '';
        _expiryMonthController.text = (payload['expiryMonth'] as String?) ?? '';
        _expiryYearController.text = (payload['expiryYear'] as String?) ?? '';
        _billingAddressController.text =
            (payload['billingAddress'] as String?) ?? '';
    }
  }

  /// Loads the vault's key/credential entries for a Script entry's
  /// reference picker. Best-effort; excludes this entry and other scripts.
  Future<void> _ensureVaultEntriesLoaded() async {
    if (_vaultEntries != null || _loadingEntries) return;
    setState(() => _loadingEntries = true);
    try {
      final entries = await getIt<EntryRepository>().listEntries(
        widget.entry.vaultId,
      );
      if (!mounted) return;
      setState(() {
        _vaultEntries = entries
            .where((e) => e.type != EntryType.script && e.id != widget.entry.id)
            .toList(growable: false);
      });
    } catch (_) {
      if (mounted) setState(() => _vaultEntries = const []);
    } finally {
      if (mounted) setState(() => _loadingEntries = false);
    }
  }

  // ── Mode transitions ───────────────────────────────────────────────

  Future<void> _requestReveal({
    bool editAfter = false,
    EntryEntity? expected,
    bool forceRemote = false,
  }) async {
    if (context.read<EditEntryCubit>().state is EditEntryRevealing) return;
    final recoveringFromConflict =
        context.read<EditEntryCubit>().state is EditEntryConflict;
    if (recoveringFromConflict) {
      setState(_clearPlaintextState);
    }
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated || auth.privateKey == null) {
      context.read<EditEntryCubit>().markRevealUnavailable();
      return;
    }
    final keyCopy = Uint8List.fromList(auth.privateKey!);
    try {
      await context.read<EditEntryCubit>().revealForEdit(
        entry: expected ?? widget.entry,
        privateKey: keyCopy,
        wrappedVK: widget.wrappedVK,
        forceRemote: forceRemote || recoveringFromConflict,
      );
    } finally {
      keyCopy.fillRange(0, keyCopy.length, 0);
    }
    if (!mounted || context.read<EditEntryCubit>().state is! EditEntryReady) {
      return;
    }
    if (editAfter) _enterEditMode();
  }

  void _enterEditMode() {
    if (!_populated || !context.read<EditEntryCubit>().hasCanonicalSnapshot) {
      setState(_clearPlaintextState);
      _requestReveal(editAfter: true);
      return;
    }
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
      _syncControllersFromSnapshot();
      _editMode = false;
      _secretRevealed = false;
      _revealedCardFields.clear();
      _revealedCustom.clear();
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
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.entryCopiedField(field)),
          duration: const Duration(seconds: 1),
        ),
      );
  }

  // ── Edit-form helpers (unchanged behaviour) ────────────────────────

  bool _validateUrl() {
    final valid = EntryFormUtils.isValidUrl(_urlController.text);
    setState(
      () => _urlError = valid
          ? null
          : AppLocalizations.of(context)!.entryUrlInvalid,
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
        description: _descriptionController.text,
        refs: _refs,
        scriptParameters: _scriptParameters,
        cardholderName: _cardholderController.text,
        cardNumber: _cardNumberController.text,
        expiryMonth: _expiryMonthController.text,
        expiryYear: _expiryYearController.text,
      );

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
    scriptDescription: _descriptionController.text,
    scriptParameters: _scriptParameters,
    returnResultToAgent: _returnResultToAgent,
    credentialTotp: _credentialTotp,
    cardholderName: _cardholderController.text,
    cardNumber: _cardNumberController.text,
    expiryMonth: _expiryMonthController.text,
    expiryYear: _expiryYearController.text,
    billingAddress: _billingAddressController.text,
  );

  bool _isDiscoverable(String fieldId) =>
      _agentPolicy?.fields[fieldId] == AgentFieldAccess.discovery;

  void _toggleDiscovery(String fieldId) {
    final policy = _agentPolicy;
    if (policy == null) return;
    final enabled = !_isDiscoverable(fieldId);
    final fields = Map<String, AgentFieldAccess>.from(policy.fields)
      ..[fieldId] = enabled
          ? AgentFieldAccess.discovery
          : AgentFieldAccess.never;
    if (fieldId == 'agentLabel') {
      setState(() {
        _agentPolicy = AgentVisibilityPolicy(
          discoverable: enabled,
          fields: fields,
        );
        _agentLabel ??= _labelController.text.trim();
      });
      return;
    }
    setState(() {
      _agentPolicy = AgentVisibilityPolicy(
        discoverable: policy.discoverable,
        fields: fields,
      );
    });
  }

  Widget _discoveryButton(String fieldId, AppLocalizations l10n) {
    final selected = _isDiscoverable(fieldId);
    return IconButton(
      key: ValueKey('entry-discovery-$fieldId'),
      onPressed: _agentPolicy == null ? null : () => _toggleDiscovery(fieldId),
      tooltip: selected
          ? l10n.entryFieldAgentVisibleDisableTip
          : l10n.entryFieldAgentVisibleEnableTip,
      icon: Icon(
        Icons.smart_toy_outlined,
        size: 17,
        color: selected ? AppColors.vaultBlue : AppColors.textTertiaryMobile,
      ),
    );
  }

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
      onPickPublicAsset: () => PublicAssetPickerSheet.show(context),
    );
    if (!mounted || result == null) return;
    final pickedColor = result.color;
    final matchedHex = VaultVisuals.colorChoices.firstWhere(
      (hex) => VaultVisuals.colorFor(hex).toARGB32() == pickedColor.toARGB32(),
      orElse: () => EntryVisuals.defaultColorHex,
    );
    setState(() {
      if (result.iconKey != null) {
        _websiteIconResolver.markManualSelection();
        _resolvedWebsiteIcon = null;
        _icon = result.iconKey!;
      }
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
    if (!_canSubmit) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.totpEntryIncomplete),
        ),
      );
      return;
    }
    if (_submitInFlight) return;
    _submitInFlight = true;
    try {
      await _submitOnce();
    } finally {
      _submitInFlight = false;
    }
  }

  Future<void> _submitOnce() async {
    if (_reservingIcon) return;
    if (!_validateUrl()) return;
    final initialAuth = context.read<AuthBloc>().state;
    if (initialAuth is! AuthAuthenticated || initialAuth.privateKey == null) {
      _showSnackBar(AppLocalizations.of(context)!.entryErrorCrypto);
      return;
    }

    final submissionEpoch = _plaintextEpoch;
    setState(() => _reservingIcon = true);
    final reservationType = _type;
    final reservationUrl = _urlController.text;
    final reservedReference = reservationType == EntryType.script
        ? null
        : await _websiteIconResolver.ensureNow(reservationUrl);
    if (!mounted) return;
    final cubit = context.read<EditEntryCubit>();
    final auth = context.read<AuthBloc>().state;
    if (submissionEpoch != _plaintextEpoch ||
        !_editMode ||
        !_populated ||
        !cubit.hasCanonicalSnapshot ||
        auth is! AuthAuthenticated ||
        auth.privateKey == null) {
      setState(() => _reservingIcon = false);
      return;
    }
    setState(() {
      if (reservedReference != null &&
          _type == reservationType &&
          _urlController.text == reservationUrl) {
        _icon = reservedReference;
      }
      _reservingIcon = false;
    });

    // Build the complete write snapshot after the asynchronous reservation
    // boundary so secret fields and presentation metadata always belong to
    // the same visible form state. Stale URL responses are ignored above.
    final payload = _buildPayload();
    if (!EntryFormUtils.isPayloadWithinLimit(payload)) {
      _showSnackBar(AppLocalizations.of(context)!.entryTooLarge);
      return;
    }
    if ((widget.entry.type == EntryType.script || _type == EntryType.script) &&
        jsonEncode(payload) != jsonEncode(_payload) &&
        !await _confirmScriptImpact()) {
      return;
    }
    if (!mounted) return;

    final keyCopy = Uint8List.fromList(auth.privateKey!);
    final hasCustomFile = _icon.startsWith('file://');
    final iconForApi = hasCustomFile ? null : _icon;
    try {
      await cubit.updateEntry(
        vaultId: widget.entry.vaultId,
        entryId: widget.entry.id,
        label: _labelController.text,
        description: _descriptionController.text,
        icon: iconForApi,
        type: _type,
        payload: payload,
        privateKey: keyCopy,
        wrappedVK: widget.wrappedVK,
        createdAt: _originalCreatedAt(cubit.state),
        agentFields: CustomField.agentFieldsFrom(_allCustomFields),
        agentVisibilityPolicy: _agentPolicy,
        agentLabel: _agentLabel,
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
      final assetKey = Uint8List.fromList(auth.privateKey!);
      try {
        final reference = await getIt<EncryptedPresentationAssetService>()
            .uploadFile(
              target: PresentationAssetTarget.entry,
              vaultId: widget.entry.vaultId,
              entryId: entry.id,
              file: File(_icon.substring(7)),
              memberPrivateKey: assetKey,
            );
        final canonical = getIt<CanonicalEntryDetailService>();
        final snapshot = await canonical.reveal(
          expected: entry,
          memberPrivateKey: assetKey,
        );
        entry = await canonical.update(
          snapshot: snapshot,
          expected: entry,
          label: entry.label,
          description: _descriptionController.text,
          icon: reference,
          type: _type,
          content: payload,
          memberPrivateKey: assetKey,
        );
      } catch (_) {
        entry = entry.copyWith(icon: widget.entry.icon);
        if (mounted) {
          _showSnackBar(AppLocalizations.of(context)!.vaultIconUploadError);
        }
      } finally {
        assetKey.fillRange(0, assetKey.length, 0);
        if (mounted) setState(() => _uploadingIcon = false);
      }
    }

    if (!mounted) return;
    // Keep the canonical form visible and refresh its optimistic base so a
    // second save cannot reuse the revision that was just committed.
    setState(() {
      _revealedEntry = entry;
      _payload = _buildPayload();
      _secretRevealed = false;
      _revealedCardFields.clear();
      _revealedCustom.clear();
      _editMode = false;
    });
    widget.editController?.publishEditing(false);
    widget.onUpdated(entry);
    _showSnackBar(AppLocalizations.of(context)!.entryChangesSaved);
    // The local Member cache is repaired asynchronously after a mutation and
    // may still expose N while this successful response already returned N+1.
    // Refresh the form from the authoritative encrypted head so the UI never
    // misreports that short cache-lag window as a decryption failure.
    await _requestReveal(expected: entry, forceRemote: true);
  }

  Future<bool> _confirmScriptImpact() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final impact = await getIt<ScriptAccessImpactService>().get(
        vaultId: widget.entry.vaultId,
        scriptEntryId: widget.entry.id,
      );
      if (!mounted || impact.effectiveAgentCount == 0) return mounted;
      return await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              title: Text(l10n.entryScriptImpactTitle),
              content: Text(
                l10n.entryScriptImpactMessage(
                  impact.effectiveAgentCount,
                  impact.directAgentCount,
                  impact.fullAgentCount,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(l10n.approvalCancel),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(l10n.entryScriptImpactConfirm),
                ),
              ],
            ),
          ) ??
          false;
    } catch (_) {
      if (mounted) _showSnackBar(l10n.entryScriptImpactCheckFailed);
      return false;
    }
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

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthAuthenticated && state.privateKey != null) {
          _requestReveal();
          return;
        }
        if (mounted) setState(_clearPlaintextState);
      },
      child: BlocBuilder<EditEntryCubit, EditEntryState>(
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
          if (!_populated && state is EditEntryRevealing) {
            return _RevealLoading(message: l10n.entryRevealingForEdit);
          }
          if (!_populated && state is EditEntryError) {
            return _RevealError(
              message: EntryFormUtils.errorMessage(l10n, state.kind),
              onRetry: () => _requestReveal(forceRemote: true),
            );
          }
          if (state is EditEntryConflict) {
            return _RevealError(
              message: l10n.entryErrorConflict,
              onRetry: () => _requestReveal(editAfter: true, forceRemote: true),
            );
          }
          if (!_populated) {
            return _RevealLoading(message: l10n.entryRevealingForEdit);
          }
          return _editMode
              ? _buildEditForm(l10n, brightness, state)
              : _buildReadOnly(l10n, brightness);
        },
      ),
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
      addField(
        _ReadOnlyField(
          label: l10n.entryDescriptionLabel,
          row: EntryFieldRow(
            icon: Icons.notes,
            value: description,
            isMasked: false,
            revealed: true,
            onToggleReveal: null,
            onCopy: () => _copy(description, l10n.entryDescriptionLabel),
          ),
        ),
      );
    }

    if (url.isNotEmpty) {
      addField(
        _ReadOnlyField(
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
              // This surface intentionally keeps its existing copy behavior.
              onPressed: () => _copy(url, l10n.entryUrlLabel),
            ),
          ),
        ),
      );
    }

    switch (entry.type) {
      case EntryType.key:
        if (value.isNotEmpty) {
          addField(
            _ReadOnlyField(
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
            ),
          );
        }
      case EntryType.credential:
        if (username.isNotEmpty) {
          addField(
            _ReadOnlyField(
              label: l10n.entryUsernameLabel,
              row: EntryFieldRow(
                icon: Icons.person,
                value: username,
                isMasked: false,
                revealed: true,
                onToggleReveal: null,
                onCopy: () => _copy(username, l10n.entryUsernameLabel),
              ),
            ),
          );
        }
        if (password.isNotEmpty) {
          addField(
            _ReadOnlyField(
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
            ),
          );
        }
      case EntryType.script:
        _addScriptFields(addField, payload, l10n, brightness);
      case EntryType.creditCard:
        for (final item in <(String, String, IconData, bool)>[
          (
            'cardholderName',
            l10n.entryCardholderNameLabel,
            Icons.person,
            false,
          ),
          ('cardNumber', l10n.entryCardNumberLabel, Icons.credit_card, true),
          (
            'expiryMonth',
            l10n.entryExpiryMonthLabel,
            Icons.calendar_month,
            false,
          ),
          (
            'expiryYear',
            l10n.entryExpiryYearLabel,
            Icons.calendar_month,
            false,
          ),
          ('billingAddress', l10n.entryBillingAddressLabel, Icons.home, false),
        ]) {
          final text = payload[item.$1] as String? ?? '';
          if (text.isEmpty) continue;
          addField(
            _ReadOnlyField(
              label: item.$2,
              row: EntryFieldRow(
                icon: item.$3,
                value: text,
                isMasked: item.$4,
                revealed: !item.$4 || _revealedCardFields.contains(item.$1),
                onToggleReveal: item.$4
                    ? () => setState(() {
                        if (!_revealedCardFields.add(item.$1)) {
                          _revealedCardFields.remove(item.$1);
                        }
                      })
                    : null,
                onCopy: () => _copy(text, item.$2),
              ),
            ),
          );
        }
    }

    _addCustomFields(addField, payload, l10n, brightness);

    if (notes.isNotEmpty) {
      addField(
        _ReadOnlyField(
          label: l10n.entryNotesLabel,
          row: EntryFieldRow(
            icon: Icons.sticky_note_2_outlined,
            value: notes,
            isMasked: false,
            revealed: true,
            onToggleReveal: null,
            onCopy: () => _copy(notes, l10n.entryNotesLabel),
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenH,
              AppSpacing.fieldGap,
              AppSpacing.screenH,
              AppSpacing.section,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (fields.isEmpty)
                  _EmptyReadOnly(
                    message: l10n.entryEmpty,
                    brightness: brightness,
                  )
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
                  _ExecOnlyNote(message: l10n.entryScriptExecOnlyNotice),
                ],
                const SizedBox(height: AppSpacing.section),
                _DangerZone(
                  label: l10n.entryDangerZone,
                  deleteLabel: l10n.entryDeleteAction,
                  onDelete: _confirmDelete,
                  brightness: brightness,
                ),
              ],
            ),
          ),
        ),
        Container(
          key: const ValueKey('entry-edit-footer'),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            AppSpacing.md,
            AppSpacing.screenH,
            AppSpacing.screenBottom,
          ),
          decoration: BoxDecoration(
            color: AppColors.cardFill(brightness),
            border: Border(
              top: BorderSide(color: AppColors.navBorder(brightness)),
            ),
          ),
          child: PrimaryButton(
            label: l10n.entryEditAction,
            onPressed: _enterEditMode,
          ),
        ),
      ],
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
    final interpreter = ScriptInterpreter.fromName(
      payload['interpreter'] as String?,
    );
    final refs = ScriptRef.listFromPayload(payload);

    if (script.isNotEmpty) {
      addField(
        _ReadOnlyField(
          label: l10n.entryScriptLabel,
          row: _ScriptBodyView(
            script: script,
            revealed: _secretRevealed,
            brightness: brightness,
            onToggle: () => setState(() => _secretRevealed = !_secretRevealed),
            onCopy: () => _copy(script, l10n.entryScriptLabel),
          ),
        ),
      );
    }

    addField(
      _ReadOnlyField(
        label: l10n.entryInterpreterLabel,
        row: EntryFieldRow(
          icon: Icons.code,
          value: interpreter.wireName,
          isMasked: false,
          revealed: true,
          onToggleReveal: null,
          onCopy: () => _copy(interpreter.wireName, l10n.entryInterpreterLabel),
        ),
      ),
    );

    for (final ref in refs) {
      if (ref.env.isEmpty) continue;
      addField(
        _ReadOnlyField(
          label: ref.env,
          row: EntryFieldRow(
            icon: Icons.data_object,
            value: '${_refEntryLabel(ref.entryId)} · ${ref.field}',
            isMasked: false,
            revealed: true,
            onToggleReveal: null,
            onCopy: () => _copy(ref.env, l10n.entryRefEnvLabel),
          ),
        ),
      );
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
        case CustomFieldType.multiline:
          addField(
            _ReadOnlyField(
              label: field.label,
              row: EntryFieldRow(
                icon: field.type == CustomFieldType.multiline
                    ? Icons.notes
                    : Icons.short_text,
                value: field.textValue,
                isMasked: false,
                revealed: true,
                onToggleReveal: null,
                onCopy: () => _copy(field.textValue, field.label),
                multiline: field.type == CustomFieldType.multiline,
              ),
            ),
          );
        case CustomFieldType.concealed:
          addField(
            _ReadOnlyField(
              label: field.label,
              row: EntryFieldRow(
                icon: Icons.lock_outline,
                value: field.textValue,
                isMasked: true,
                revealed: _revealedCustom.contains(field.id),
                onToggleReveal: () => _toggleCustomReveal(field.id),
                onCopy: () => _copy(field.textValue, field.label),
              ),
            ),
          );
        case CustomFieldType.totp:
          final config = field.totp;
          if (config == null) break;
          addField(
            _ReadOnlyField(
              label: field.label,
              row: _TotpFieldRow(
                config: config,
                revealed: _revealedCustom.contains(field.id),
                onToggle: () => _toggleCustomReveal(field.id),
                onCopy: _copyTotp,
              ),
            ),
          );
        case CustomFieldType.unknown:
          break;
      }
    }
  }

  // ── Edit form (previous default presentation) ──────────────────────

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
    suffixIcon: _discoveryButton('urlDomain', l10n),
  );

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
            onPressed: () => setState(() => _valueObscured = !_valueObscured),
          ),
        ),
      ],
      EntryType.credential => [
        OnboardingTextField(
          label: l10n.entryUsernameLabel,
          controller: _usernameController,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
          suffixIcon: _discoveryButton('username', l10n),
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
        EntrySectionHeader(label: l10n.entryScriptParametersLabel),
        const SizedBox(height: AppSpacing.innerGap),
        ScriptParametersEditor(
          initial: _scriptParameters,
          onChanged: (parameters) =>
              setState(() => _scriptParameters = parameters),
        ),
        const SizedBox(height: AppSpacing.section),
        Row(
          children: [
            Expanded(child: Text(l10n.entryScriptReturnResultLabel)),
            AppToggle(
              value: _returnResultToAgent,
              onChanged: (value) =>
                  setState(() => _returnResultToAgent = value),
            ),
          ],
        ),
        if (_returnResultToAgent) ...[
          const SizedBox(height: AppSpacing.innerGap),
          WarningZone(
            title: l10n.entryScriptReturnResultLabel.toUpperCase(),
            message: l10n.entryScriptReturnResultHint,
          ),
        ],
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
            vaultId: widget.entry.vaultId,
            entries: _vaultEntries ?? const [],
            initial: _refs,
            onChanged: (refs) => setState(() => _refs = refs),
          ),
      ],
      EntryType.creditCard => [
        OnboardingTextField(
          label: l10n.entryCardholderNameLabel,
          controller: _cardholderController,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.fieldGap),
        OnboardingTextField(
          label: l10n.entryCardNumberLabel,
          controller: _cardNumberController,
          obscureText: _valueObscured,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
          suffixIcon: EntryObscureToggle(
            obscured: _valueObscured,
            onPressed: () => setState(() => _valueObscured = !_valueObscured),
          ),
        ),
        const SizedBox(height: AppSpacing.fieldGap),
        OnboardingTextField(
          label: l10n.entryExpiryMonthLabel,
          controller: _expiryMonthController,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.fieldGap),
        OnboardingTextField(
          label: l10n.entryExpiryYearLabel,
          controller: _expiryYearController,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.fieldGap),
        OnboardingTextField(
          label: l10n.entryBillingAddressLabel,
          controller: _billingAddressController,
          textInputAction: TextInputAction.next,
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
    final isLoading =
        state is EditEntryLoading || _uploadingIcon || _reservingIcon;
    final isBusy = isLoading || _pickingIcon;
    final canSubmit = !isBusy && _canSubmit;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenH,
              AppSpacing.fieldGap,
              AppSpacing.screenH,
              AppSpacing.section,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EntryTypeDropdown(
                  value: _type,
                  enabled: _type != EntryType.creditCard,
                  allowCreditCard: false,
                  onChanged: (next) {
                    if (next == null || next == _type) return;
                    setState(() {
                      _type = next;
                      if (!EntryVisuals.isCustomUrl(_icon)) {
                        _resolvedWebsiteIcon = null;
                        _icon = EntryVisuals.defaultIconForType(next);
                      }
                    });
                    if (next == EntryType.script) _ensureVaultEntriesLoaded();
                  },
                ),
                const SizedBox(height: AppSpacing.fieldGap),
                EntryFieldCaption(label: l10n.entryLabelLabel),
                const SizedBox(height: AppSpacing.innerGap),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EntryIconTile(
                      icon: _resolvedWebsiteIcon ?? _icon,
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
                        suffixIcon: _discoveryButton('agentLabel', l10n),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.fieldGap),
                EntryFieldCaption(label: l10n.entryDescriptionLabel),
                const SizedBox(height: AppSpacing.innerGap),
                OnboardingTextField(
                  controller: _descriptionController,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  suffixIcon: _discoveryButton('description', l10n),
                ),
                const SizedBox(height: AppSpacing.fieldGap),
                ..._typeFields(l10n),
                const SizedBox(height: AppSpacing.section),
                if (_type != EntryType.script) ...[
                  TotpSection(
                    onApplied: _submit,
                    disabled: isBusy,
                    initial: _totpFields,
                    onChanged: (fields) => setState(() => _totpFields = fields),
                  ),
                  const SizedBox(height: AppSpacing.section),
                ],
                CustomFieldsEditor(
                  initial: _customFields,
                  onChanged: (fields, valid) => setState(() {
                    _customFields = fields;
                    _customFieldsValid = valid;
                  }),
                ),
                const SizedBox(height: AppSpacing.section),
                EntryNotesSection(
                  controller: _notesController,
                  initiallyVisible: _notesController.text.trim().isNotEmpty,
                ),
                if (state is EditEntryError) ...[
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
                _DangerZone(
                  label: l10n.entryDangerZone,
                  deleteLabel: isLoading
                      ? l10n.entryDeleting
                      : l10n.entryDeleteAction,
                  onDelete: isBusy ? null : _confirmDelete,
                  brightness: brightness,
                ),
              ],
            ),
          ),
        ),
        Container(
          key: const ValueKey('entry-save-footer'),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            AppSpacing.md,
            AppSpacing.screenH,
            AppSpacing.screenBottom,
          ),
          decoration: BoxDecoration(
            color: AppColors.cardFill(brightness),
            border: Border(
              top: BorderSide(color: AppColors.navBorder(brightness)),
            ),
          ),
          child: EntrySaveButton(
            isLoading: isLoading,
            onPressed: canSubmit ? _submit : null,
          ),
        ),
      ],
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

/// Calm exec-only annotation (script accent) shown below a Script entry —
/// replaces the louder WarningZone per the redesign.
class _ExecOnlyNote extends StatelessWidget {
  const _ExecOnlyNote({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: AppSpacing.xxs),
          child: Icon(Icons.terminal, size: 12, color: AppColors.vaultViolet),
        ),
        const SizedBox(width: AppSpacing.innerGap),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              color: AppColors.onSurfaceSubtle(brightness),
              fontSize: 11.5,
              height: 1.35,
            ),
          ),
        ),
      ],
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
          Expanded(
            child: TotpDisplay(config: config, onCopy: onCopy),
          ),
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
  const _RevealError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.brandRed,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.section),
            IconButton(
              onPressed: onRetry,
              color: AppColors.brandRed,
              icon: const Icon(Icons.refresh),
            ),
          ],
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
                disabledForegroundColor: AppColors.brandRed.withValues(
                  alpha: 0.4,
                ),
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
