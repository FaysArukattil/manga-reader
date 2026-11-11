import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfmark/models/series.dart';
import 'package:shelfmark/ui/components/reading_loader.dart';
import 'package:shelfmark/ui/onboarding_page.dart';

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

  testWidgets('OnboardingPage renders floating cover showcase and CTA button',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OnboardingPage(),
        ),
      ),
    );

    expect(find.text("Discover Stories\nYou'll Love"), findsOneWidget);
    expect(find.text("Let's get started"), findsOneWidget);
  });
}

