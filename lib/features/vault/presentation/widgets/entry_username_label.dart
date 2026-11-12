import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/generated/app_localizations.dart';

/// Legacy compact indexes lack a typed username. Only mounted rows open a
/// bounded preview; the reader returns the username after clearing its body.
class EntryUsernameLabel extends StatefulWidget {
  const EntryUsernameLabel({super.key, required this.username, this.load});
  final String? username;
  final Future<String?> Function()? load;

  @override
  State<EntryUsernameLabel> createState() => _EntryUsernameLabelState();
}

class _EntryUsernameLabelState extends State<EntryUsernameLabel> {
  late final Future<String?>? _pending = widget.username == null
      ? widget.load?.call()
      : null;

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: _pending,
    builder: (context, snapshot) => Text(
      widget.username ??
          snapshot.data ??
          AppLocalizations.of(context)!.autofillUsernameUnavailable,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: AppColors.onSurfaceMuted(Theme.of(context).brightness),
        fontSize: 13,
      ),
    ),
  );
}
