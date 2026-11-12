import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_reader/models/series.dart';
import 'package:manga_reader/ui/components/reading_loader.dart';
import 'package:manga_reader/ui/onboarding_page.dart';

void main() {
  testWidgets('ReadingLoader displays multi-stage progress and series info',
      (WidgetTester tester) async {
    final series = Series.create(
      id: 'test_series_1',
      url: 'https://example.com/ch1',
      title: 'Solo Leveling',
    ).copyWith(chapter: 'Chapter 150');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReadingLoader(series: series),
        ),
      ),
    );

    expect(find.text('Solo Leveling'), findsOneWidget);
    expect(find.text('Chapter 150'), findsOneWidget);
    expect(find.text('Connecting to source'), findsOneWidget);

    // Fast-forward past stage timer
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('Bypassing bot security'), findsOneWidget);
  });

  testWidgets('OnboardingPage renders interactive anime showcase and pull meter',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OnboardingPage(),
        ),
      ),
    );

    expect(find.text('ALL YOUR MANGA. ONE APP.'), findsOneWidget);
    expect(find.text('Every series you love.\nOne app.'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
  });
}

