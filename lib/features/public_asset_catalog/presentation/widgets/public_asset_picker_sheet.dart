import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_search_field.dart';
import '../../../../core/widgets/sheet_drag_handle.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/public_asset.dart';
import '../../domain/services/website_icon_service.dart';

/// Searchable website-icon catalog. Returns a stable `public-asset:` reference.
class PublicAssetPickerSheet extends StatefulWidget {
  const PublicAssetPickerSheet({super.key});

  static Future<String?> show(BuildContext context) =>
      showModalBottomSheet<String>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: AppColors.transparent,
        builder: (_) => const PublicAssetPickerSheet(),
      );

  @override
  State<PublicAssetPickerSheet> createState() => _PublicAssetPickerSheetState();
}

class _PublicAssetPickerSheetState extends State<PublicAssetPickerSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  int _generation = 0;
  bool _loading = false;
  List<PublicAsset> _results = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _search(String query) {
    _debounce?.cancel();
    final generation = ++_generation;
    if (query.trim().isEmpty) {
      setState(() {
        _loading = false;
        _results = const [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (mounted) setState(() => _loading = true);
      try {
        final results = await getIt<WebsiteIconService>().search(query);
        if (mounted && generation == _generation) {
          setState(() => _results = results);
        }
      } catch (_) {
        if (mounted && generation == _generation) {
          setState(() => _results = const []);
        }
      } finally {
        if (mounted && generation == _generation) {
          setState(() => _loading = false);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    return Container(
      height: MediaQuery.sizeOf(context).height * 0.72,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.fieldGap,
        AppSpacing.screenH,
        AppSpacing.screenBottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.modalBackground(brightness),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const SheetDragHandle(),
          const SizedBox(height: AppSpacing.headerGap),
          Text(
            l10n.publicAssetSearchTitle,
            style: TextStyle(
              color: AppColors.onSurface(brightness),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.fieldGap),
          AppSearchField(
            controller: _controller,
            hint: l10n.publicAssetSearchHint,
            onChanged: _search,
          ),
          const SizedBox(height: AppSpacing.fieldGap),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            Expanded(
              child: ListView.separated(
                itemCount: _results.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.cardGap),
                itemBuilder: (context, index) {
                  final asset = _results[index];
                  return ListTile(
                    key: ValueKey('public-asset-${asset.id}'),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        asset.deliveryUrl.toString(),
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(Icons.language),
                      ),
                    ),
                    title: Text(asset.name),
                    onTap: () => Navigator.of(context).pop(asset.reference),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
