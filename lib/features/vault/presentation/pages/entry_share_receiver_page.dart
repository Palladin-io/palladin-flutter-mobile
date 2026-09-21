import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/permissions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/secure_clipboard.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/sheet_action_buttons.dart';
import '../../../../core/widgets/sheet_drag_handle.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../onboarding/presentation/widgets/onboarding_text_field.dart';
import '../../domain/entities/entry_share.dart';
import '../../domain/entities/entry_share_list.dart';
import '../../data/services/entry_sharing/entry_share_copy_service.dart';
import '../cubit/entry_share_copy_cubit.dart';
import '../cubit/entry_share_reception_cubit.dart';
import '../entry_share_auth_binding.dart';
import '../entry_share_account_continuation.dart';
import '../widgets/entry_share_creation_form.dart';
import '../widgets/entry_share_field_card.dart';
import '../widgets/entry_share_receiver_frame.dart';
import '../widgets/entry_share_copy_panel.dart';

class EntryShareReceiverPage extends StatefulWidget {
  const EntryShareReceiverPage({
    super.key,
    required this.cubit,
    this.ownsCubit = true,
    this.onClose,
    this.copyServiceFactory,
    this.onAccount,
  });
  final EntryShareReceptionCubit cubit;
  final bool ownsCubit;
  final VoidCallback? onClose;
  final EntryShareCopyService Function()? copyServiceFactory;
  final Future<void> Function(EntryShareAccountAction)? onAccount;

  @override
  State<EntryShareReceiverPage> createState() => _EntryShareReceiverPageState();
}

class _EntryShareReceiverPageState extends State<EntryShareReceiverPage>
    with WidgetsBindingObserver {
  final _secret = TextEditingController();
  final _otp = TextEditingController();
  late final AuthBloc _auth;
  Object? _initialAuth;
  late final StreamSubscription<AuthState> _authSubscription;
  late final StreamSubscription<EntryShareReceptionState> _flowSubscription;
  Timer? _authorityCheck;
  Animation<double>? _coverAnimation;
  BuildContext? _sheetContext;
  bool _invalidated = false, _copying = false, _ending = false;
  bool _secretError = false, _otpError = false;
  String? _message;
  bool _displayScheduled = false;
  EntryShareCopyCubit? _copyCubit;
  bool _openingCopy = false, _savedCopy = false;
  EntryShareReceptionCubit get _cubit => widget.cubit;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthBloc>();
    _initialAuth = entryShareAuthBinding(_auth.state);
    _authSubscription = _auth.stream.listen((state) {
      if (entryShareAuthBinding(state) != _initialAuth) {
        _discard();
      } else if (_active) {
        unawaited(_cubit.revalidate());
      }
    });
    _flowSubscription = _cubit.stream.listen((state) {
      if (state.phase == EntryShareReceptionPhase.unavailable ||
          state.phase == EntryShareReceptionPhase.ended) {
        _clearLocal();
      }
    });
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if ((_auth.state is! AuthAuthenticated &&
            _auth.state is! AuthUnauthenticated) ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
      _discard();
    } else {
      _authorityCheck = Timer.periodic(const Duration(seconds: 5), (_) {
        if (_active) unawaited(_cubit.revalidate());
      });
    }
  }

  bool get _active =>
      mounted &&
      !_invalidated &&
      !_cubit.state.suspended &&
      _cubit.state.phase != EntryShareReceptionPhase.unavailable &&
      _cubit.state.phase != EntryShareReceptionPhase.ended;

  void _clearLocal() {
    _invalidated = true;
    _initialAuth = null;
    _authorityCheck?.cancel();
    _secret.clear();
    _otp.clear();
    _copyCubit?.clear();
    _message = null;
    final sheet = _sheetContext;
    _sheetContext = null;
    if (sheet != null && sheet.mounted) {
      final route = ModalRoute.of(sheet);
      if (route != null && route.isActive) {
        Navigator.of(sheet).removeRoute(route);
      }
    }
  }

  void _discard() {
    _clearLocal();
    _cubit.clear();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.secondaryAnimation;
    if (!identical(animation, _coverAnimation)) {
      _coverAnimation?.removeStatusListener(_covered);
      _coverAnimation = animation;
      animation?.addStatusListener(_covered);
    }
  }

  void _covered(AnimationStatus status) {
    if (status == AnimationStatus.forward ||
        status == AnimationStatus.completed) {
      _discard();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_invalidated) unawaited(_cubit.resumeFromEmail());
      return;
    }
    _secret.clear();
    _otp.clear();
    _message = null;
    if (state == AppLifecycleState.detached || !_cubit.suspendForEmail()) {
      _discard();
    }
  }

  @override
  void didUpdateWidget(EntryShareReceiverPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.cubit, widget.cubit)) {
      if (oldWidget.ownsCubit) unawaited(oldWidget.cubit.close());
      _discard();
    }
  }

  @override
  void dispose() {
    _initialAuth = null;
    _authorityCheck?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _coverAnimation?.removeStatusListener(_covered);
    unawaited(_authSubscription.cancel());
    unawaited(_flowSubscription.cancel());
    if (widget.ownsCubit) unawaited(_cubit.close());
    _copyCubit?.clear();
    _secret.clear();
    _otp.clear();
    _secret.dispose();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<EntryShareReceptionOutcome> Function() action,
  ) async {
    if (!_active) return;
    setState(() => _message = null);
    final failure = AppLocalizations.of(context)!.sharingReceiveError;
    final outcome = await action();
    if (_active && outcome == EntryShareReceptionOutcome.failed) {
      setState(() => _message = failure);
    }
  }

  Future<void> _verifySecret() async {
    final pin = _cubit.state.protection == 'pin';
    final valid = pin
        ? RegExp(r'^[0-9]{6,128}$').hasMatch(_secret.text)
        : _secret.text.length >= 8 && _secret.text.length <= 128;
    setState(() => _secretError = !valid);
    if (!valid) return;
    final value = _secret.text;
    _secret.clear();
    await _run(() => _cubit.verifySecret(value));
  }

  Future<void> _verifyOtp() async {
    final value = _otp.text.trim();
    final valid = RegExp(r'^[0-9]{6}$').hasMatch(value);
    setState(() => _otpError = !valid);
    if (!valid) return;
    _otp.clear();
    await _run(() => _cubit.verifyOtp(value));
  }

  Future<bool> _mayUseCopy(EntryShareSnapshot snapshot) async =>
      _active &&
      await _cubit.revalidate() &&
      _active &&
      identical(snapshot, _cubit.state.snapshot);

  bool get _canSaveCopy {
    final auth = _auth.state;
    return widget.copyServiceFactory != null &&
        auth is AuthAuthenticated &&
        !auth.isVaultLocked &&
        auth.emailVerified &&
        auth.isOnboarded &&
        auth.privateKey != null &&
        (auth.permissions & Permissions.vaultManage) != 0;
  }

  Future<EntrySharingSession?> _copyOwner() async {
    if (!_active ||
        !_canSaveCopy ||
        !await _cubit.revalidate() ||
        !_active ||
        !_canSaveCopy) {
      return null;
    }
    final owner = _cubit.owner;
    final principal = owner.principalId,
        organization = owner.organizationId,
        authorization = owner.authorizationGeneration;
    if (principal == null || organization == null || authorization == null) {
      return null;
    }
    return (
      principalId: principal,
      organizationId: organization,
      authorizationGeneration: authorization,
      keyGeneration: owner.keyGeneration,
    );
  }

  Uint8List _copyPrivateKey() {
    final auth = _auth.state;
    if (!_active || !_canSaveCopy || auth is! AuthAuthenticated) {
      throw StateError('Sharing session unavailable');
    }
    return Uint8List.fromList(auth.privateKey!);
  }

  Future<void> _startSave() async {
    final snapshot = _cubit.state.snapshot;
    if (!_active ||
        !_canSaveCopy ||
        _openingCopy ||
        _copyCubit != null ||
        _savedCopy ||
        _cubit.state.busy ||
        snapshot == null) {
      return;
    }
    setState(() => _openingCopy = true);
    try {
      final owner = await _copyOwner();
      if (owner == null || !await _mayUseCopy(snapshot)) return;
      final copy = EntryShareCopyCubit(
        service: widget.copyServiceFactory!(),
        snapshot: snapshot,
        owner: owner,
        ownerReader: _copyOwner,
        copyMemberPrivateKey: _copyPrivateKey,
        lifetime: _cubit.lifetime,
        canCreateDefaultVault:
            (_auth.state as AuthAuthenticated).permissions &
                Permissions.vaultCreate !=
            0,
      );
      setState(() => _copyCubit = copy);
    } catch (_) {
      if (_active) {
        setState(
          () => _message = AppLocalizations.of(context)!.sharingCopySaveError,
        );
      }
    } finally {
      if (mounted) setState(() => _openingCopy = false);
    }
  }

  void _leaveSave({bool saved = false}) {
    if (!_active) return;
    final copy = _copyCubit;
    if (copy == null ||
        (saved
            ? copy.state.phase != EntryShareCopyPhase.saved
            : copy.state.phase != EntryShareCopyPhase.editing)) {
      return;
    }
    setState(() {
      _savedCopy = saved;
      _copyCubit = null;
    });
    copy.clear();
  }

  Future<void> _copy(EntryShareSnapshot snapshot, EntryShareField field) async {
    if (_copying || !_active) return;
    setState(() {
      _copying = true;
      _message = null;
    });
    final l10n = AppLocalizations.of(context)!;
    try {
      if (!await _mayUseCopy(snapshot)) return;
      await SecureClipboard.copy(field.value);
      if (await _mayUseCopy(snapshot)) {
        setState(() => _message = l10n.sharingCopiedValue);
      }
    } catch (_) {
      if (await _mayUseCopy(snapshot)) {
        setState(() => _message = l10n.sharingCopyError);
      }
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  void _scheduleConfirmation(EntryShareSnapshot snapshot) {
    if (_displayScheduled) return;
    _displayScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!await _mayUseCopy(snapshot)) return;
      await _cubit.confirmDisplay();
    });
  }

  Future<void> _end() async {
    if (!_active || _ending || _cubit.state.busy) return;
    _ending = true;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppColors.modalBackground(Theme.of(context).brightness),
      builder: (sheetContext) {
        _sheetContext = sheetContext;
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: SheetDragHandle()),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.screenH),
                  child: Text(l10n.sharingEndNotice),
                ),
                SheetActionButtons(
                  onCancel: () => Navigator.of(sheetContext).pop(false),
                  onConfirm: () => Navigator.of(sheetContext).pop(true),
                  confirmLabel: l10n.sharingEndConfirm,
                  confirmColor: AppColors.brandRed,
                  equalActions: true,
                ),
              ],
            ),
          ),
        );
      },
    );
    _sheetContext = null;
    _ending = false;
    if (confirmed == true && _active) await _run(_cubit.end);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _discard();
      },
      child: EntryShareReceiverFrame(
        onClose: widget.onClose == null
            ? null
            : () {
                _discard();
                widget.onClose!();
              },
        child: BlocBuilder<EntryShareReceptionCubit, EntryShareReceptionState>(
          bloc: _cubit,
          builder: (context, state) {
            if (state.suspended) return const SizedBox.shrink();
            final snapshot = state.snapshot;
            if (snapshot != null && !state.busy) {
              _scheduleConfirmation(snapshot);
            }
            final terminal =
                state.phase == EntryShareReceptionPhase.unavailable ||
                state.phase == EntryShareReceptionPhase.ended;
            final copy = _copyCubit;
            if (!terminal && copy != null && snapshot != null) {
              return EntryShareCopyPanel(
                key: ObjectKey(copy),
                cubit: copy,
                snapshot: snapshot,
                onCancel: () => _leaveSave(),
                onSaved: () => _leaveSave(saved: true),
              );
            }
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.screenH),
                    children: [
                      if (state.phase == EntryShareReceptionPhase.welcome)
                        Text(l10n.sharingReceiveWelcome),
                      if (state.phase == EntryShareReceptionPhase.unavailable)
                        Text(l10n.sharingReceiveUnavailable),
                      if (state.phase == EntryShareReceptionPhase.ended)
                        Text(l10n.sharingEnded),
                      if (!terminal &&
                          widget.onAccount != null &&
                          (_auth.state is AuthUnauthenticated ||
                              _auth.state is AuthAuthenticated &&
                                  (!(_auth.state as AuthAuthenticated)
                                          .isOnboarded ||
                                      !(_auth.state as AuthAuthenticated)
                                          .emailVerified ||
                                      (_auth.state as AuthAuthenticated)
                                          .isVaultLocked))) ...[
                        const SizedBox(height: AppSpacing.fieldGap),
                        Text(l10n.sharingAccountNotice),
                        if (_auth.state is AuthUnauthenticated) ...[
                          TextButton(
                            onPressed: state.busy
                                ? null
                                : () => widget.onAccount!(
                                    EntryShareAccountAction.register,
                                  ),
                            child: Text(l10n.sharingRegister),
                          ),
                          TextButton(
                            onPressed: state.busy
                                ? null
                                : () => widget.onAccount!(
                                    EntryShareAccountAction.login,
                                  ),
                            child: Text(l10n.sharingLogin),
                          ),
                        ] else
                          TextButton(
                            onPressed: state.busy
                                ? null
                                : () => widget.onAccount!(
                                    EntryShareAccountAction.continueAccount,
                                  ),
                            child: Text(l10n.sharingContinueAccount),
                          ),
                      ],
                      if (state.phase == EntryShareReceptionPhase.verification)
                        ..._proofs(state, l10n),
                      if (snapshot != null) ...[
                        if (_savedCopy) ...[
                          Text(l10n.sharingCopySaved),
                          const SizedBox(height: AppSpacing.fieldGap),
                        ],
                        Text(
                          snapshot.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.fieldGap),
                        Text(l10n.sharingReceivedNotice),
                        const SizedBox(height: AppSpacing.section),
                        for (final field in snapshot.fields)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.cardGap,
                            ),
                            child: EntryShareFieldCard(
                              key: ValueKey(field.id),
                              label: entryShareFieldLabel(
                                l10n,
                                field.id,
                                field.label,
                              ),
                              type: field.type,
                              value: field.value,
                              enabled: !state.busy && !_copying,
                              beforeReveal: () => _mayUseCopy(snapshot),
                              trailing: IconButton(
                                tooltip: l10n.sharingCopyValue,
                                onPressed: state.busy || _copying
                                    ? null
                                    : () => _copy(snapshot, field),
                                icon: const Icon(Icons.copy_outlined, size: 18),
                              ),
                            ),
                          ),
                        if (state.confirmation ==
                            EntryShareConfirmation.failed) ...[
                          Text(l10n.sharingConfirmationFailed),
                          TextButton(
                            onPressed: state.busy
                                ? null
                                : () => _run(_cubit.confirmDisplay),
                            child: Text(l10n.sharingRetryConfirmation),
                          ),
                        ],
                      ],
                      if (_message != null && !terminal) ...[
                        const SizedBox(height: AppSpacing.fieldGap),
                        Text(_message!),
                      ],
                      if (state.gatesReady && !terminal)
                        TextButton(
                          onPressed: state.busy ? null : _end,
                          child: Text(l10n.sharingEnd),
                        ),
                    ],
                  ),
                ),
                if (snapshot != null &&
                    !terminal &&
                    _canSaveCopy &&
                    !_savedCopy)
                  EntryShareActionFooter(
                    label: l10n.sharingSaveCopy,
                    busy: _openingCopy,
                    onPressed: state.busy || _openingCopy ? null : _startSave,
                  ),
                if (state.phase == EntryShareReceptionPhase.welcome ||
                    state.phase == EntryShareReceptionPhase.verification &&
                        state.gatesReady)
                  EntryShareActionFooter(
                    label: state.phase == EntryShareReceptionPhase.welcome
                        ? l10n.sharingOpen
                        : l10n.sharingReceive,
                    busy: state.busy,
                    onPressed: state.busy
                        ? null
                        : () => _run(
                            state.phase == EntryShareReceptionPhase.welcome
                                ? _cubit.open
                                : _cubit.receive,
                          ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _proofs(EntryShareReceptionState state, AppLocalizations l10n) {
    final language = Localizations.localeOf(context).languageCode == 'pl'
        ? 'pl'
        : 'en';
    return [
      if (state.recipientMode == 'namedRecipient' && !state.emailVerified) ...[
        Text(l10n.sharingOtpNotice),
        const SizedBox(height: AppSpacing.fieldGap),
        PrimaryButton(
          label: state.otpRetry
              ? l10n.sharingRetryOtp
              : state.otpRequested
              ? l10n.sharingResendOtp
              : l10n.sharingSendOtp,
          onPressed: state.busy
              ? null
              : () => _run(() => _cubit.requestOtp(language)),
        ),
        if (state.otpRequested && !state.otpRetry) ...[
          const SizedBox(height: AppSpacing.fieldGap),
          OnboardingTextField(
            controller: _otp,
            label: l10n.sharingOtpCode,
            keyboardType: TextInputType.number,
            enabled: !state.busy,
            feedbackReserveSpace: false,
            feedbackVisible: _otpError,
            feedbackChild: Text(l10n.sharingOtpFormatError),
            onChanged: (_) {
              if (_otpError) setState(() => _otpError = false);
            },
          ),
          const SizedBox(height: AppSpacing.fieldGap),
          PrimaryButton(
            label: l10n.sharingVerifyOtp,
            onPressed: state.busy ? null : _verifyOtp,
          ),
        ],
        const SizedBox(height: AppSpacing.section),
      ],
      if ({'password', 'pin'}.contains(state.protection) &&
          !state.secretVerified) ...[
        OnboardingTextField(
          controller: _secret,
          label: state.protection == 'pin'
              ? l10n.sharingProtectionPin
              : l10n.sharingProtectionPassword,
          obscureText: true,
          enabled: !state.busy,
          feedbackReserveSpace: false,
          keyboardType: state.protection == 'pin'
              ? TextInputType.number
              : TextInputType.visiblePassword,
          feedbackVisible: _secretError,
          feedbackChild: Text(
            state.protection == 'pin'
                ? l10n.sharingPinError
                : l10n.sharingPasswordError,
          ),
          onChanged: (_) {
            if (_secretError) setState(() => _secretError = false);
          },
        ),
        const SizedBox(height: AppSpacing.fieldGap),
        PrimaryButton(
          label: l10n.sharingVerifySecret,
          onPressed: state.busy ? null : _verifySecret,
        ),
        const SizedBox(height: AppSpacing.section),
      ],
      if (!{'namedRecipient', 'anyoneWithLink'}.contains(state.recipientMode) ||
          !{'none', 'password', 'pin'}.contains(state.protection))
        Text(l10n.sharingUnsupportedGate),
      if (state.gatesReady) Text(l10n.sharingReadyToReceive),
    ];
  }
}
