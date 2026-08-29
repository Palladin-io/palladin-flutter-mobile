import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_screen.dart';
import '../../../../core/widgets/app_toggle.dart';
import '../../../../core/widgets/icon_color_browser_sheet.dart';
import '../../../../core/widgets/warning_zone.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../../public_asset_catalog/domain/services/website_icon_service.dart';
import '../../../public_asset_catalog/presentation/website_icon_auto_resolver.dart';
import '../../../public_asset_catalog/presentation/widgets/public_asset_picker_sheet.dart';
import '../../data/services/canonical_entry_detail_service.dart';
import '../../data/services/encrypted_presentation_asset_service.dart';
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
import '../widgets/script_parameters_editor.dart';
import '../widgets/script_refs_editor.dart';
import '../widgets/totp_section.dart';
import '../widgets/vault_visuals.dart';

/// Full-screen Add Entry form.
///
/// Field order: Label → Description → URL → Icon → Type → Type-specific
/// fields → Notes → Save button. The color picker
/// was dropped — `EntryEntity` has no color field on the backend, so the
/// control silently discarded user input.
///
/// Custom icon upload follows the two-step pattern: the entry is created
/// first so the encrypted asset can be bound to its server-issued ID, then
/// opaque authenticated ciphertext is uploaded and the entry is patched with
/// the encrypted-asset reference. Plain image bytes never leave the client.
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
  final _cardholderController = TextEditingController();
  final _cardNumberController = TextEditingController();
  final _expiryMonthController = TextEditingController();
  final _expiryYearController = TextEditingController();
  final _billingAddressController = TextEditingController();

  EntryType _type = EntryType.credential;
  ScriptInterpreter _interpreter = ScriptInterpreter.bash;
  String _icon = EntryVisuals.defaultIconForType(EntryType.credential);
  String? _resolvedWebsiteIcon;
  String _colorHex = EntryVisuals.defaultColorHex;
  bool _pickingIcon = false;
  bool _uploadingIcon = false;
  bool _reservingIcon = false;
  late final WebsiteIconAutoResolver _websiteIconResolver;

  bool _valueObscured = true;
  bool _passwordObscured = true;
  bool _cardNumberObscured = true;
  bool _discoverDescription = false;
  bool _exposeUsername = true;
  bool _exposeDomain = true;
  String? _urlError;

  /// Non-TOTP custom fields (managed by [CustomFieldsEditor]).
  List<CustomField> _customFields = const [];
  bool _customFieldsValid = true;

  /// TOTP fields (managed by the dedicated 2FA section).
  List<CustomField> _totpFields = const [];

  List<ScriptRef> _refs = const [];
  List<ScriptParameterDefinition> _scriptParameters = const [];
  bool _returnResultToAgent = true;

  /// Every custom field in display order — 2FA first, then the rest.
  List<CustomField> get _allCustomFields => [..._totpFields, ..._customFields];

  /// Candidate reference targets for a Script entry, loaded lazily the
  /// first time the user selects the Script type. `null` = not loaded yet.
  List<EntryEntity>? _vaultEntries;
  bool _loadingEntries = false;

  @override
  void initState() {
    super.initState();
    _websiteIconResolver = WebsiteIconAutoResolver(
      service: getIt.isRegistered<WebsiteIconService>()
          ? getIt<WebsiteIconService>()
          : null,
      onReference: (reference) {
        if (mounted) setState(() => _icon = reference);
      },
      onResolved: (reference) {
        if (mounted) setState(() => _resolvedWebsiteIcon = reference);
      },
      onAutomaticCleared: () {
        if (mounted) {
          setState(() {
            _resolvedWebsiteIcon = null;
            _icon = EntryVisuals.defaultIconForType(_type);
          });
        }
      },
    );
    _urlController.addListener(_resolveWebsiteIcon);
  }

  void _resolveWebsiteIcon() {
    if (_type == EntryType.key || _type == EntryType.credential) {
      _websiteIconResolver.resolve(_urlController.text);
    }
  }

  @override
  void dispose() {
    _websiteIconResolver.dispose();
    _valueController.clear();
    _usernameController.clear();
    _passwordController.clear();
    _notesController.clear();
    _scriptController.clear();
    for (final controller in [
      _cardholderController,
      _cardNumberController,
      _expiryMonthController,
      _expiryYearController,
      _billingAddressController,
    ]) {
      controller.clear();
    }
    _labelController.dispose();
    _descriptionController.dispose();
    _valueController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _urlController.dispose();
    _notesController.dispose();
    _scriptController.dispose();
    for (final controller in [
      _cardholderController,
      _cardNumberController,
      _expiryMonthController,
      _expiryYearController,
      _billingAddressController,
    ]) {
      controller.dispose();
    }
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
        description: _descriptionController.text,
        refs: _refs,
        scriptParameters: _scriptParameters,
        cardholderName: _cardholderController.text,
        cardNumber: _cardNumberController.text,
        expiryMonth: _expiryMonthController.text,
        expiryYear: _expiryYearController.text,
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
    scriptDescription: _descriptionController.text,
    scriptParameters: _scriptParameters,
    returnResultToAgent: _returnResultToAgent,
    cardholderName: _cardholderController.text,
    cardNumber: _cardNumberController.text,
    expiryMonth: _expiryMonthController.text,
    expiryYear: _expiryYearController.text,
    billingAddress: _billingAddressController.text,
  );

  Widget _urlField(AppLocalizations l10n, {required bool supportsDiscovery}) =>
      OnboardingTextField(
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
        suffixIcon: supportsDiscovery
            ? _discoveryButton(
                keyName: 'urlDomain',
                selected: _exposeDomain,
                onToggle: () => setState(() => _exposeDomain = !_exposeDomain),
                l10n: l10n,
              )
            : null,
      );

  Widget _discoveryButton({
    required String keyName,
    required bool selected,
    required VoidCallback onToggle,
    required AppLocalizations l10n,
  }) => _CreateDiscoveryButton(
    key: ValueKey('create-entry-discovery-$keyName'),
    selected: selected,
    onToggle: onToggle,
    visibleMessage: l10n.entryFieldAgentDiscoveryVisible,
    hiddenMessage: l10n.entryFieldAgentDiscoveryHidden,
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
        _urlField(l10n, supportsDiscovery: false),
      ],
      EntryType.credential => [
        OnboardingTextField(
          label: l10n.entryUsernameLabel,
          controller: _usernameController,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
          suffixIcon: _discoveryButton(
            keyName: 'username',
            selected: _exposeUsername,
            onToggle: () => setState(() => _exposeUsername = !_exposeUsername),
            l10n: l10n,
          ),
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
        _urlField(l10n, supportsDiscovery: true),
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
            vaultId: widget.vaultId,
            entries: _vaultEntries ?? const [],
            initial: _refs,
            onChanged: (refs) => setState(() => _refs = refs),
          ),
      ],
      EntryType.creditCard => [
        OnboardingTextField(
          label: l10n.entryCardholderNameLabel,
          controller: _cardholderController,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.fieldGap),
        OnboardingTextField(
          label: l10n.entryCardNumberLabel,
          controller: _cardNumberController,
          obscureText: _cardNumberObscured,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
          suffixIcon: EntryObscureToggle(
            obscured: _cardNumberObscured,
            onPressed: () =>
                setState(() => _cardNumberObscured = !_cardNumberObscured),
          ),
        ),
        const SizedBox(height: AppSpacing.fieldGap),
        Row(
          children: [
            Expanded(
              child: OnboardingTextField(
                label: l10n.entryExpiryMonthLabel,
                controller: _expiryMonthController,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: AppSpacing.innerGap),
            Expanded(
              child: OnboardingTextField(
                label: l10n.entryExpiryYearLabel,
                controller: _expiryYearController,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.fieldGap),
        OnboardingTextField(
          label: l10n.entryBillingAddressLabel,
          controller: _billingAddressController,
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

  Future<void> _submit() async {
    if (_reservingIcon) return;
    final supportsWebsiteIcon =
        _type == EntryType.key || _type == EntryType.credential;
    if (supportsWebsiteIcon && !_validateUrl()) return;
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

    setState(() => _reservingIcon = true);
    final reservationType = _type;
    final reservationUrl = _urlController.text;
    final reservedReference = supportsWebsiteIcon
        ? await _websiteIconResolver.ensureNow(reservationUrl)
        : null;
    if (!mounted) return;
    setState(() {
      if (reservedReference != null &&
          _type == reservationType &&
          _urlController.text == reservationUrl) {
        _icon = reservedReference;
      }
      _reservingIcon = false;
    });

    // Snapshot all presentation and secret fields after the asynchronous
    // reservation boundary so one write cannot combine stale payload bytes
    // with newer metadata. A response for an edited URL is ignored above.
    final payload = _buildPayload();
    if (!EntryFormUtils.isPayloadWithinLimit(payload)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.entryTooLarge)),
        );
      return;
    }

    final keyCopy = Uint8List.fromList(auth.privateKey!);
    final hasCustomFile = _icon.startsWith('file://');
    // Send null while a local file is pending. After creation the client can
    // bind its encrypted asset to the server-issued Entry ID and patch only
    // the opaque encrypted-asset reference into the canonical projection.
    final iconForApi = hasCustomFile ? null : _icon;
    try {
      await context.read<CreateEntryCubit>().createEntry(
        vaultId: widget.vaultId,
        label: _labelController.text,
        description: _descriptionController.text,
        icon: iconForApi,
        type: _type,
        payload: payload,
        privateKey: keyCopy,
        wrappedVK: widget.wrappedVK,
        agentFields: CustomField.agentFieldsFrom(_allCustomFields),
        exposeUsername: _exposeUsername,
        exposeDomain: _exposeDomain,
        discoverDescription: _discoverDescription,
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
      final assetKey = Uint8List.fromList(auth.privateKey!);
      try {
        final reference = await getIt<EncryptedPresentationAssetService>()
            .uploadFile(
              target: PresentationAssetTarget.entry,
              vaultId: widget.vaultId,
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
        assetKey.fillRange(0, assetKey.length, 0);
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
        final isLoading =
            state is CreateEntryLoading || _uploadingIcon || _reservingIcon;
        final isBusy = isLoading || _pickingIcon;
        final canSubmit = !isBusy && _canSubmit;

        return AppScreen.appBar(
          safeAreaBottom: false,
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
          body: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  // Title→content gap is owned by AppScreen.appBar.
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenH,
                    0,
                    AppSpacing.screenH,
                    AppSpacing.section,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Type — a select-input, consistent with the other fields.
                      EntryTypeDropdown(
                        value: _type,
                        onChanged: (next) {
                          if (next == null || next == _type) return;
                          if (next == EntryType.creditCard) {
                            _websiteIconResolver.resolve('');
                            _urlController.clear();
                          }
                          setState(() {
                            _type = next;
                            if (next == EntryType.creditCard) {
                              _urlError = null;
                            }
                            if (EntryVisuals.isCustomUrl(_icon)) return;
                            _icon = EntryVisuals.defaultIconForType(next);
                          });
                          if (next == EntryType.script) {
                            _ensureVaultEntriesLoaded();
                          }
                        },
                      ),
                      const SizedBox(height: AppSpacing.fieldGap),
                      // 2. Label — with inline entry icon + agent-visible hint.
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
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.fieldGap),
                      // 3. Description — agent-visible.
                      EntryFieldCaption(label: l10n.entryDescriptionLabel),
                      const SizedBox(height: AppSpacing.innerGap),
                      OnboardingTextField(
                        controller: _descriptionController,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.next,
                        suffixIcon: _discoveryButton(
                          keyName: 'description',
                          selected: _discoverDescription,
                          onToggle: () => setState(
                            () => _discoverDescription = !_discoverDescription,
                          ),
                          l10n: l10n,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.fieldGap),
                      // 4. Type-specific fields (+ URL / injected data).
                      ..._typeFields(l10n),
                      const SizedBox(height: AppSpacing.section),
                      // 5. Two-factor authentication (not for Script).
                      if (_type != EntryType.script) ...[
                        TotpSection(
                          initial: _totpFields,
                          onChanged: (fields) =>
                              setState(() => _totpFields = fields),
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
                        initiallyVisible: _notesController.text
                            .trim()
                            .isNotEmpty,
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
                    ],
                  ),
                ),
              ),
              Container(
                key: const ValueKey('create-entry-save-footer'),
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
          ),
        );
      },
    );
  }
}

final class _CreateDiscoveryButton extends StatefulWidget {
  const _CreateDiscoveryButton({
    super.key,
    required this.selected,
    required this.onToggle,
    required this.visibleMessage,
    required this.hiddenMessage,
  });

  final bool selected;
  final VoidCallback onToggle;
  final String visibleMessage;
  final String hiddenMessage;

  @override
  State<_CreateDiscoveryButton> createState() => _CreateDiscoveryButtonState();
}

final class _CreateDiscoveryButtonState extends State<_CreateDiscoveryButton> {
  final _tooltipKey = GlobalKey<TooltipState>();

  void _handlePressed() {
    widget.onToggle();
    _tooltipKey.currentState?.ensureTooltipVisible();
  }

  @override
  Widget build(BuildContext context) => Tooltip(
    key: _tooltipKey,
    // The tooltip describes the state produced by this tap. Keep it short;
    // explanatory prose belongs in supporting UI, not a compact tooltip.
    message: widget.selected ? widget.hiddenMessage : widget.visibleMessage,
    triggerMode: TooltipTriggerMode.manual,
    child: IconButton(
      onPressed: _handlePressed,
      icon: Icon(
        Icons.smart_toy_outlined,
        size: 17,
        color: widget.selected
            ? AppColors.vaultBlue
            : AppColors.textTertiaryMobile,
      ),
    ),
  );
}
