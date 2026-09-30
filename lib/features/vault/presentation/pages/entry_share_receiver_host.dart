import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/datasources/entry_share_recipient_datasource.dart';
import '../../data/services/entry_sharing/entry_share_crypto_service.dart';
import '../../data/services/entry_sharing/entry_share_copy_service.dart';
import '../../data/services/entry_sharing/entry_share_ingress.dart';
import '../cubit/entry_share_reception_cubit.dart';
import '../entry_share_auth_binding.dart';
import '../entry_share_account_continuation.dart';
import '../widgets/entry_share_receiver_frame.dart';
import 'entry_share_receiver_page.dart';

class EntryShareReceiverHost extends StatefulWidget {
  const EntryShareReceiverHost({
    super.key,
    required this.ingress,
    required this.crypto,
    required this.remoteFactory,
    required this.ownerReader,
    this.onClose,
    this.copyServiceFactory,
    this.accountContinuation,
    this.onAccountRoute,
  });

  final EntryShareIngress ingress;
  final VoidCallback? onClose;
  final EntryShareCopyService Function()? copyServiceFactory;
  final EntryShareAccountContinuation? accountContinuation;
  final ValueChanged<String>? onAccountRoute;
  final EntryShareCryptoService crypto;
  final EntryShareRecipientDatasource Function() remoteFactory;
  final Future<EntryShareRecipientOwner?> Function(String? principalId)
  ownerReader;

  @override
  State<EntryShareReceiverHost> createState() => _EntryShareReceiverHostState();
}

class _EntryShareReceiverHostState extends State<EntryShareReceiverHost>
    with WidgetsBindingObserver {
  late final AuthBloc _auth;
  late final StreamSubscription<AuthState> _authSubscription;
  EntryShareReceptionCubit? _cubit;
  Object? _binding;
  Animation<double>? _coverAnimation;
  int _version = 0, _epoch = 0;
  bool _opening = false, _retired = false, _clearing = false;

  bool get _foreground {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  bool get _coveredNow =>
      _coverAnimation?.status == AnimationStatus.forward ||
      _coverAnimation?.status == AnimationStatus.completed;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthBloc>();
    _version = widget.ingress.version;
    widget.ingress.addListener(_incoming);
    widget.accountContinuation?.addListener(_accountChanged);
    _authSubscription = _auth.stream.listen((state) {
      if (state is AuthError ||
          (_binding != null && entryShareAuthBinding(state) != _binding)) {
        _retire(allowAccountTransfer: true);
      } else {
        _tryOpen();
      }
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addObserver(this);
    _tryOpen();
  }

  void _incoming() {
    if (!mounted || _clearing) return;
    if (_version != widget.ingress.version) {
      _release();
      _binding = null;
      _retired = false;
      _version = widget.ingress.version;
    }
    _tryOpen();
    setState(() {});
  }

  void _tryOpen() {
    if (_retired ||
        _opening ||
        _cubit != null ||
        !_foreground ||
        _coveredNow ||
        (!widget.ingress.hasPending &&
            widget.accountContinuation?.ready != true)) {
      return;
    }
    final binding = entryShareAuthBinding(_auth.state);
    if (_auth.state is AuthError) {
      _retire();
      return;
    }
    if (binding == null) return;
    _binding = binding;
    _opening = true;
    final state = _auth.state;
    final principal = state is AuthAuthenticated ? state.userId : null;
    unawaited(_open(_epoch, _version, binding, principal));
  }

  bool _same(int epoch, int version, Object binding) =>
      mounted &&
      !_retired &&
      epoch == _epoch &&
      version == widget.ingress.version &&
      binding == entryShareAuthBinding(_auth.state);

  Future<EntryShareRecipientOwner?> _owner(
    int epoch,
    int version,
    Object binding,
    String? principal,
  ) async {
    if (!_same(epoch, version, binding)) return null;
    final owner = await widget.ownerReader(principal);
    if (!_same(epoch, version, binding) || owner?.principalId != principal) {
      return null;
    }
    return owner;
  }

  Future<void> _open(
    int epoch,
    int version,
    Object binding,
    String? principal,
  ) async {
    EntryShareInbound? incoming;
    EntryShareRecipientDatasource? remote;
    try {
      final owner = await _owner(epoch, version, binding, principal);
      if (!_same(epoch, version, binding) || !_foreground || _coveredNow) {
        return;
      }
      if (owner == null) {
        _retire();
        return;
      }
      final continuation = widget.accountContinuation;
      if (continuation?.ownsVersion(version) == true) {
        final resumed = await continuation!.take(
          version: version,
          owner: owner,
          ownerReader: () => _owner(epoch, version, binding, principal),
        );
        if (!_same(epoch, version, binding) || !_foreground || _coveredNow) {
          if (resumed != null) unawaited(resumed.close());
          return;
        }
        if (resumed == null) {
          _retire();
          return;
        }
        _cubit = resumed;
        return;
      }
      incoming = widget.ingress.take(version);
      if (incoming == null) return;
      remote = widget.remoteFactory();
      _cubit = EntryShareReceptionCubit(
        remote: remote,
        crypto: widget.crypto,
        shareId: incoming.shareId,
        secrets: incoming.secrets,
        lifetime: incoming.lifetime,
        owner: owner,
        ownerReader: () => _owner(epoch, version, binding, principal),
      );
      incoming = null;
      remote = null;
    } catch (_) {
      if (_same(epoch, version, binding)) _retire();
    } finally {
      incoming?.secrets.dispose();
      remote?.close();
      if (mounted) {
        if (epoch == _epoch) _opening = false;
        setState(() {});
      }
    }
  }

  void _release() {
    _epoch++;
    _opening = false;
    final cubit = _cubit;
    _cubit = null;
    if (cubit != null) unawaited(cubit.close());
  }

  void _retire({bool allowAccountTransfer = false}) {
    final preserve =
        allowAccountTransfer &&
        widget.accountContinuation?.ownsVersion(_version) == true;
    _retired = true;
    _binding = null;
    _release();
    if (!preserve && _version == widget.ingress.version) {
      _clearing = true;
      widget.ingress.clear();
      _version = widget.ingress.version;
      _clearing = false;
    }
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
      _retire(allowAccountTransfer: true);
      if (mounted) setState(() {});
    } else if (status == AnimationStatus.dismissed) {
      _tryOpen();
      if (mounted) setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _retire();
    } else if (state == AppLifecycleState.resumed) {
      _tryOpen();
    } else if (_opening) {
      _epoch++;
      _opening = false;
    }
    // The mounted receiver owns the narrowly scoped pre-delivery email detour.
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(EntryShareReceiverHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.ingress, widget.ingress)) {
      oldWidget.ingress.removeListener(_incoming);
      oldWidget.ingress.clear();
      _release();
      _retired = true;
      _binding = null;
      _version = widget.ingress.version;
      widget.ingress.addListener(_incoming);
      _retire();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _coverAnimation?.removeStatusListener(_covered);
    widget.ingress.removeListener(_incoming);
    widget.accountContinuation?.removeListener(_accountChanged);
    unawaited(_authSubscription.cancel());
    _retire(allowAccountTransfer: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = _cubit;
    if (cubit != null) {
      return EntryShareReceiverPage(
        key: ObjectKey(cubit),
        cubit: cubit,
        ownsCubit: false,
        copyServiceFactory: widget.copyServiceFactory,
        onAccount:
            widget.accountContinuation == null || widget.onAccountRoute == null
            ? null
            : _beginAccount,
        onClose: widget.onClose == null ? null : _close,
      );
    }
    final waiting =
        !_retired &&
        (_opening ||
            widget.ingress.hasPending ||
            widget.accountContinuation?.active == true);
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _retire();
      },
      child: EntryShareReceiverPlaceholder(
        waiting: waiting,
        onClose: widget.onClose == null ? null : _close,
      ),
    );
  }

  void _close() {
    widget.accountContinuation?.clear();
    _retire();
    widget.onClose?.call();
  }

  void _accountChanged() {
    if (!mounted) return;
    _tryOpen();
    setState(() {});
  }

  Future<void> _beginAccount(EntryShareAccountAction action) async {
    final cubit = _cubit;
    final continuation = widget.accountContinuation;
    if (cubit == null ||
        continuation == null ||
        widget.onAccountRoute == null) {
      return;
    }
    if (!await continuation.begin(cubit, action)) return;
    if (!mounted || !continuation.ownsVersion(_version)) {
      continuation.clear();
      return;
    }
    widget.onAccountRoute!(continuation.accountRoute);
  }
}
