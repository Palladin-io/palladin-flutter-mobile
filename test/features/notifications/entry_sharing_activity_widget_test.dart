import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/theme/app_colors.dart';
import 'package:mobile_palladin/features/audit/domain/entities/audit_log_entry.dart';
import 'package:mobile_palladin/features/audit/presentation/widgets/audit_legend_sheet.dart';
import 'package:mobile_palladin/features/audit/presentation/widgets/audit_log_row.dart';
import 'package:mobile_palladin/features/notifications/domain/entities/inbox_notification.dart';
import 'package:mobile_palladin/features/notifications/presentation/widgets/notification_card.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = Platform.environment['PALLADIN_SHARING_VISUAL_FONT'];
    if (font != null) {
      await (FontLoader(
        'SharingVisualInter',
      )..addFont(File(font).readAsBytes().then(ByteData.sublistView))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });
  for (final locale in ['en', 'pl']) {
    testWidgets(
      'sharing Inbox and audit stay readable at 320px/150% in $locale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final l10n = lookupAppLocalizations(Locale(locale));
        final capture = GlobalKey();
        var taps = 0;
        final entry = AuditLogEntry(
          id: 'log',
          eventType: AuditEventType.entryShareConfirmed,
          rawEventType: 'entry-share.confirmed',
          actorType: AuditActorType.externalRecipient,
          actorName: 'Not the sender',
          resolvedObjectName: 'Synthetic credential',
          metadata: const {'shareId': '00112233-4455-4677-8899-aabbccddeeff'},
          createdAt: DateTime(2026, 9, 21),
        );
        ThemeData theme = ThemeData(
          brightness: locale == 'pl' ? Brightness.dark : Brightness.light,
          scaffoldBackgroundColor: locale == 'pl'
              ? AppColors.darkBackground
              : AppColors.lightBackground,
        );
        if (Platform.environment.containsKey('PALLADIN_SHARING_VISUAL_FONT')) {
          theme = theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'SharingVisualInter'),
          );
        }
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            theme: theme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 1100),
                textScaler: TextScaler.linear(1.5),
              ),
              child: RepaintBoundary(
                key: capture,
                child: Scaffold(
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        NotificationCard(
                          item: InboxNotification(
                            id: 'receipt',
                            type: 'entry_share_received',
                            category: NotificationCategory.update,
                            titleKey: '',
                            metadata: const {
                              'entryLabel': 'Synthetic credential',
                              'shareId': '00112233-4455-4677-8899-aabbccddeeff',
                            },
                            actionState: NotificationActionState.none,
                            occurredAt: DateTime(2026, 9, 21),
                          ),
                          onTap: () => taps++,
                        ),
                        const SizedBox(height: 16),
                        AuditLogRow(entry: entry, agentNames: const {}),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final timestamp = find.descendant(
          of: find.byType(NotificationCard),
          matching: find.byWidgetPredicate(
            (widget) => widget is Text && widget.style?.fontSize == 10,
          ),
        );
        expect(
          tester.getTopLeft(timestamp).dy,
          greaterThanOrEqualTo(
            tester.getBottomLeft(find.text(l10n.notifSubEntryShareReceived)).dy,
          ),
        );
        for (final text in [
          l10n.notifTitleEntryShareReceived,
          l10n.notifSubEntryShareReceived,
        ]) {
          expect(
            tester
                .renderObject<RenderParagraph>(find.text(text))
                .didExceedMaxLines,
            false,
          );
        }
        final auditText = find.descendant(
          of: find.byType(AuditLogRow),
          matching: find.byWidgetPredicate(
            (widget) => widget is Text && widget.textSpan != null,
          ),
        );
        expect(
          tester.renderObject<RenderParagraph>(auditText).didExceedMaxLines,
          false,
        );
        final proofText = find.text(l10n.notifDisplayNotReadProof);
        final proof = tester.renderObject<RenderParagraph>(proofText);
        expect(proof.didExceedMaxLines, false);
        expect(tester.widget<Text>(proofText).maxLines, isNull);
        expect(
          tester
              .widget<Text>(find.text(l10n.notifSubEntryShareReceived))
              .maxLines,
          isNull,
        );
        expect(find.text('Not the sender'), findsNothing);
        await tester.tap(find.text(l10n.notifTitleEntryShareReceived));
        expect(taps, 1);
        await tester.ensureVisible(find.byType(AuditLogRow));
        await tester.tap(find.byType(AuditLogRow));
        await tester.pumpAndSettle();
        expect(find.text('00112233…ddeeff'), findsNWidgets(2));
        expect(find.text('00112233-4455-4677-8899-aabbccddeeff'), findsNothing);
        final dir = Platform.environment['PALLADIN_SHARING_VISUAL_DIR'];
        if (dir != null) {
          await tester.runAsync(() async {
            final boundary =
                capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(dir).create(recursive: true);
            await File(
              '$dir/activity-$locale.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'sharing group appears in the existing audit legend in $locale',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: AuditLegendSheet()),
          ),
        );
        await tester.pumpAndSettle();
        final l10n = lookupAppLocalizations(Locale(locale));
        expect(find.text(l10n.auditGroupEntrySharing), findsOneWidget);
        expect(
          find.textContaining(l10n.auditEventEntryShareConfirmed),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
