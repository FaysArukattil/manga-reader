import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_reader/ui/components/physics_page_turn.dart';

void main() {
  group('PhysicsPageTurn', () {
    testWidgets('renders initial page and allows controller jump',
        (tester) async {
      final controller = PhysicsPageTurnController();
      int pageChangeCount = 0;
      int lastPage = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 800,
              child: PhysicsPageTurn(
                controller: controller,
                itemCount: 5,
                initialPage: 0,
                onPageChanged: (p) {
                  pageChangeCount++;
                  lastPage = p;
                },
                itemBuilder: (context, i) => Text('Page $i'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Page 0'), findsOneWidget);

      controller.jumpToPage(2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Page 2'), findsOneWidget);
      expect(lastPage, equals(2));
      expect(pageChangeCount, equals(1));
    });

    testWidgets('turns forward on right tap and settles with spring',
        (tester) async {
      int turnedPage = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 800,
              child: PhysicsPageTurn(
                itemCount: 3,
                initialPage: 0,
                onPageChanged: (p) => turnedPage = p,
                itemBuilder: (context, i) => Text('Page $i'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Page 0'), findsOneWidget);

      // Tap on right 15% zone (> 72% screen width)
      await tester.tapAt(const Offset(350, 400));
      await tester.pump();
      // Pump spring simulation until settled
      await tester.pumpAndSettle();

      expect(turnedPage, equals(1));
      expect(find.text('Page 1'), findsOneWidget);
    });

    testWidgets('turns backward on left tap', (tester) async {
      int turnedPage = 1;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 800,
              child: PhysicsPageTurn(
                itemCount: 3,
                initialPage: 1,
                onPageChanged: (p) => turnedPage = p,
                itemBuilder: (context, i) => Text('Page $i'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Page 1'), findsOneWidget);

      // Tap on left zone (< 28% screen width)
      await tester.tapAt(const Offset(50, 400));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(turnedPage, equals(0));
      expect(find.text('Page 0'), findsOneWidget);
    });

    testWidgets('drag past threshold completes page turn', (tester) async {
      int turnedPage = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 800,
              child: PhysicsPageTurn(
                itemCount: 3,
                initialPage: 0,
                onPageChanged: (p) => turnedPage = p,
                itemBuilder: (context, i) => Text('Page $i'),
              ),
            ),
          ),
        ),
      );

      // Drag horizontally left by 250px (> 40% of 400px width)
      await tester.timedDrag(
        find.byType(PhysicsPageTurn),
        const Offset(-250, 0),
        const Duration(milliseconds: 300),
      );
      await tester.pumpAndSettle();

      expect(turnedPage, equals(1));
      expect(find.text('Page 1'), findsOneWidget);
    });

    testWidgets('short drag falls back smoothly to original page',
        (tester) async {
      int turnedPage = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 800,
              child: PhysicsPageTurn(
                itemCount: 3,
                initialPage: 0,
                onPageChanged: (p) => turnedPage = p,
                itemBuilder: (context, i) => Text('Page $i'),
              ),
            ),
          ),
        ),
      );

      // Drag slightly: 20px (only 5% of width)
      await tester.timedDrag(
        find.byType(PhysicsPageTurn),
        const Offset(-20, 0),
        const Duration(milliseconds: 300),
      );
      await tester.pumpAndSettle();

      // Should snap back to 0 without turning
      expect(turnedPage, equals(0));
      expect(find.text('Page 0'), findsOneWidget);
    });
  });
}
