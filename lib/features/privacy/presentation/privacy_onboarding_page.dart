import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import 'privacy_consent_sheet.dart';

/// Optional startup layer, before the router's existing setup/verification gates.
class PrivacyOnboardingPage extends StatefulWidget {
  const PrivacyOnboardingPage({super.key, this.onCompleted});
  final VoidCallback? onCompleted;
  @override
  State<PrivacyOnboardingPage> createState() => _PrivacyOnboardingPageState();
}

class _PrivacyOnboardingPageState extends State<PrivacyOnboardingPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    await showPrivacyConsentSheet(context, source: 'mobile_onboarding');
    if (!mounted) return;
    if (widget.onCompleted case final complete?) {
      complete();
    } else {
      context.read<AuthBloc>().add(const PrivacyChoicesCompleted());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.cardFill(Theme.of(context).brightness),
    body: const SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xxl),
          child: Text(
            'Palladin',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    ),
  );
}
