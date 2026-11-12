import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_reader/services/update_service.dart';
import 'package:manga_reader/ui/components/play_store_update_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('UpdateService singleton initializes with correct package name', () {
    expect(UpdateService.instance, isNotNull);
    expect(UpdateService.playStorePackage, 'com.faysarukattil.mangareader');
  });

  testWidgets('PlayStoreUpdateCard renders app info and update actions', (tester) async {
    bool dismissed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayStoreUpdateCard(
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    );

    expect(find.text('Google Play'), findsOneWidget);
    expect(find.text('Update Available'), findsOneWidget);
    expect(find.text('Shelfmark Manga Reader'), findsOneWidget);
    expect(find.text('Update on Play Store'), findsOneWidget);
    expect(find.text('Not Now'), findsOneWidget);

    await tester.tap(find.text('Not Now'));
    await tester.pump();
    expect(dismissed, isTrue);
  });
}
