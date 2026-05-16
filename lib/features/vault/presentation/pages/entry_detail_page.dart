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
import '../../data/services/vault_icon_upload_service.dart'
    show VaultIconUploadErrorKind, VaultIconUploadException;
import '../../domain/entities/entry_entity.dart';
import '../cubit/edit_entry_cubit.dart';
import '../widgets/entry_form_utils.dart';
import '../widgets/entry_form_widgets.dart';
import '../widgets/entry_icon_picker.dart';
import '../widgets/vault_placeholder_tab.dart';
import '../widgets/vault_visuals.dart';

/// Result of [EntryDetailPage.push].
sealed class EntryDetailResult {}

/// The entry metadata was updated and the new entity is ready to replace
/// the stale row in the parent list.
class EntryDetailUpdated extends EntryDetailResult {
  EntryDetailUpdated(this.entry);
  final EntryEntity entry;
}

/// The entry was permanently deleted — caller should remove it from the
/// local list state.
class EntryDetailDeleted extends EntryDetailResult {
  EntryDetailDeleted(this.entryId);
  final String entryId;
}

/// Full-screen entry detail screen.
///
/// Tab 0 — Details: edit form + danger zone (delete).
/// Tab 1 — Agents: placeholder.
/// Tab 2 — Logs: placeholder.
///
/// If [cachedPayload] is provided the form pre-populates immediately.
/// Otherwise the cubit decrypts the entry on open.
class EntryDetailPage extends StatelessWidget {
  const EntryDetailPage({
    super.key,
    required this.entry,
    this.cachedPayload,
    this.wrappedVK,
  });

  final EntryEntity entry;
  final Map<String, dynamic>? cachedPayload;
  final String? wrappedVK;

  static Future<EntryDetailResult?> push(
    BuildContext context, {
    required EntryEntity entry,
    Map<String, dynamic>? cachedPayload,
    String? wrappedVK,
  }) {
    return Navigator.of(context, rootNavigator: true)
        .push<EntryDetailResult>(
      MaterialPageRoute(
        builder: (_) => EntryDetailPage(
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
          } else {
            // The vault is locked or the private key was wiped — without
            // a private key we cannot decrypt anything to populate the
            // form. Emit a cryptoFailure so the details tab renders the
            // error view instead of an infinite "Loading entry data…"
            // spinner.
            cubit.markRevealUnavailable();
          }
        }
        return cubit;
      },
      child: _EntryDetailView(entry: entry, wrappedVK: wrappedVK),
    );
  }
}

// ── Detail view ────────────────────────────────────────────────────

class _EntryDetailView extends StatefulWidget {
  const _EntryDetailView({required this.entry, this.wrappedVK});

  final EntryEntity entry;
  final String? wrappedVK;

  @override
  State<_EntryDetailView> createState() => _EntryDetailViewState();
}

class _EntryDetailViewState extends State<_EntryDetailView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Form controllers
  final _labelController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _valueController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _urlController = TextEditingController();
  final _notesController = TextEditingController();

  EntryType _type = EntryType.credential;
  String _icon = EntryVisuals.defaultIconName;
  String? _urlError;
  XFile? _pendingIconFile;
  bool _pickingIcon = false;
  bool _uploadingIcon = false;
  bool _valueObscured = true;
  bool _passwordObscured = true;
  bool _populated = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
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

  bool _validateUrl() {
    final valid = EntryFormUtils.isValidUrl(_urlController.text);
    setState(() => _urlError =
        valid ? null : AppLocalizations.of(context)!.entryUrlInvalid);
    return valid;
  }

  bool get _canSubmit => EntryFormUtils.canSubmit(
        type: _type,
        label: _labelController.text,
        value: _valueController.text,
        username: _usernameController.text,
        password: _passwordController.text,
      );

  Map<String, dynamic> _buildPayload() => EntryFormUtils.buildPayload(
        type: _type,
        value: _valueController.text,
        username: _usernameController.text,
        password: _passwordController.text,
        url: _urlController.text,
        notes: _notesController.text,
      );

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
    if (!_validateUrl()) return;
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated || auth.privateKey == null) {
      _showSnackBar(AppLocalizations.of(context)!.entryErrorCrypto);
      return;
    }

    final keyCopy = Uint8List.fromList(auth.privateKey!);
    final urlDomain = EntryFormUtils.extractDomain(_urlController.text);
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
            // Preserve the original createdAt — repository would otherwise
            // default to now() and wipe the real creation timestamp.
            createdAt: widget.entry.createdAt,
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
      } on VaultIconUploadException catch (e) {
        // S3 upload failed — the metadata PUT already went through with
        // `icon: null` (which the backend ignores under patch semantics),
        // so the server-side icon is unchanged. Restore the previous
        // icon locally so the list row keeps its old artwork until the
        // next refetch instead of flashing to a default.
        entry = entry.copyWith(icon: widget.entry.icon);
        if (mounted) {
          final l = AppLocalizations.of(context)!;
          final msg = switch (e.kind) {
            VaultIconUploadErrorKind.unsupportedFormat => l.vaultIconUploadFormatError,
            VaultIconUploadErrorKind.fileTooLarge => l.vaultIconUploadSizeError,
            _ => l.vaultIconUploadError,
          };
          _showSnackBar(msg);
        }
      } catch (_) {
        // Same rationale as above — keep the original icon in the
        // returned entity so the parent list does not drop the artwork.
        entry = entry.copyWith(icon: widget.entry.icon);
        if (mounted) _showSnackBar(AppLocalizations.of(context)!.vaultIconUploadError);
      } finally {
        if (mounted) setState(() => _uploadingIcon = false);
      }
    }

    if (mounted) Navigator.of(context).pop(EntryDetailUpdated(entry));
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
      Navigator.of(context).pop(EntryDetailDeleted(widget.entry.id));
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    // Populate form from the cubit's payload via a BlocListener — keeps
    // UI rendering and side effects cleanly separated, avoiding the
    // `addPostFrameCallback`-inside-`BlocBuilder` anti-pattern that
    // schedules a fresh callback on every rebuild.
    return BlocConsumer<EditEntryCubit, EditEntryState>(
      listenWhen: (prev, next) =>
          next is EditEntryReady && !_populated,
      listener: (context, state) {
        if (state is EditEntryReady && !_populated) {
          setState(() => _populateFrom(state.entry, state.payload));
        }
      },
      builder: (context, state) {
        return Container(
          decoration:
              BoxDecoration(gradient: AppColors.backgroundGradient(brightness)),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: _EntryDetailAppBar(
              label: widget.entry.label,
              tabController: _tabController,
              onBack: () => Navigator.of(context).pop(),
              l10n: l10n,
              brightness: brightness,
            ),
            body: SafeArea(
              top: false,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildDetailsTab(l10n, brightness, state),
                  VaultPlaceholderTab(
                    icon: Icons.security,
                    message: l10n.vaultAgentsEmpty,
                  ),
                  VaultPlaceholderTab(
                    icon: Icons.history,
                    message: l10n.vaultLogsEmpty,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailsTab(
    AppLocalizations l10n,
    Brightness brightness,
    EditEntryState state,
  ) {
    // Show loading spinner while decrypting the payload.
    if (!_populated &&
        (state is EditEntryInitial || state is EditEntryRevealing)) {
      return Center(
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
      );
    }

    // Reveal error — only show if we never managed to populate.
    if (!_populated && state is EditEntryError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            EntryFormUtils.errorMessage(l10n, state.kind),
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

    // No per-entry color on the backend — see add_entry_page.dart for
    // rationale on dropping the color picker.
    final accentColor = VaultVisuals.colorFor(EntryVisuals.defaultColorHex);
    final isLoading = state is EditEntryLoading || _uploadingIcon;
    final isBusy = isLoading || _pickingIcon;
    final canSubmit = !isBusy && _canSubmit;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
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
            onPickCustom:
                (_pickingIcon || _uploadingIcon) ? null : _pickCustomIcon,
            isLoadingCustom: _pickingIcon || _uploadingIcon,
          ),
          const SizedBox(height: 16),
          EntryTypeDropdown(
            value: _type,
            onChanged: (next) {
              if (next == null || next == _type) return;
              setState(() => _type = next);
            },
          ),
          const SizedBox(height: 16),
          if (_type == EntryType.key) ...[
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
              suffixIcon: EntryObscureToggle(
                obscured: _passwordObscured,
                onPressed: () =>
                    setState(() => _passwordObscured = !_passwordObscured),
              ),
            ),
          ],
          const SizedBox(height: 16),
          EntryNotesField(
            controller: _notesController,
            label: l10n.entryNotesLabel,
          ),
          const SizedBox(height: 20),
          EntryEncryptionNotice(message: l10n.entryEncryptionNotice),
          if (state is EditEntryError) ...[
            const SizedBox(height: 12),
            Text(
              EntryFormUtils.errorMessage(l10n, state.kind),
              style: const TextStyle(color: AppColors.brandRed, fontSize: 12),
            ),
          ],
          const SizedBox(height: 20),
          EntrySaveButton(
            isLoading: isLoading,
            onPressed: canSubmit ? _submit : null,
          ),
          // ── Danger Zone ────────────────────────────────────────────
          const SizedBox(height: 32),
          _DangerZone(
            label: l10n.entryDangerZone,
            deleteLabel: isLoading ? l10n.entryDeleting : l10n.entryDeleteAction,
            onDelete: isBusy ? null : _confirmDelete,
            brightness: brightness,
          ),
        ],
      ),
    );
  }

}

// ── AppBar ─────────────────────────────────────────────────────────

class _EntryDetailAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _EntryDetailAppBar({
    required this.label,
    required this.tabController,
    required this.onBack,
    required this.l10n,
    required this.brightness,
  });

  final String label;
  final TabController tabController;
  final VoidCallback onBack;
  final AppLocalizations l10n;
  final Brightness brightness;

  static const double _tabBarHeight = 44;

  @override
  Size get preferredSize =>
      const Size.fromHeight(kToolbarHeight + _tabBarHeight);

  @override
  Widget build(BuildContext context) {
    final onSurface = AppColors.onSurface(brightness);
    final subtle = AppColors.onSurfaceSubtle(brightness);

    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleSpacing: 0,
      iconTheme: IconThemeData(color: onSurface),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 18),
        onPressed: onBack,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: onSurface,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(_tabBarHeight),
        child: SizedBox(
          height: _tabBarHeight,
          child: TabBar(
            controller: tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelPadding: const EdgeInsets.symmetric(horizontal: 14),
            labelColor: AppColors.brandRed,
            unselectedLabelColor: subtle,
            indicatorColor: AppColors.brandRed,
            indicatorSize: TabBarIndicatorSize.label,
            indicatorWeight: 2,
            dividerColor: AppColors.navBorder(brightness),
            labelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            tabs: [
              Tab(text: l10n.entryTabDetails),
              Tab(text: l10n.vaultTabAgents),
              Tab(text: l10n.vaultTabLogs),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Danger zone ────────────────────────────────────────────────────

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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.brandRed.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.brandRed.withValues(alpha: 0.25),
        ),
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
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: OutlinedButton(
              onPressed: onDelete,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.brandRed,
                disabledForegroundColor: AppColors.brandRed.withValues(alpha: 0.4),
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

// Form sub-widgets live in `widgets/entry_form_widgets.dart` and are
// shared with `add_entry_page.dart`.
