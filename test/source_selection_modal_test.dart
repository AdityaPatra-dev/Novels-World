import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/extractors/source_registry.dart';
import 'package:novels_world/ui/widgets/source_selection_modal.dart';

void main() {
  testWidgets('SourceSelectionModal displays search bar, filters and sources', (tester) async {
    final currentSource = SourceRegistry.getDefaultSource();
    dynamic selectedSource;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                SourceSelectionModal.show(
                  context: context,
                  currentSource: currentSource,
                  onSourceSelected: (src) {
                    selectedSource = src;
                  },
                );
              },
              child: const Text('Open Sources'),
            ),
          ),
        ),
      ),
    );

    // Tap to open modal
    await tester.tap(find.text('Open Sources'));
    await tester.pumpAndSettle();

    // Verify Title & Search Bar
    expect(find.text('Select Source'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    // Verify Filter Chips
    expect(find.textContaining('All Types'), findsOneWidget);
    expect(find.textContaining('Novels'), findsOneWidget);
    expect(find.textContaining('Books & PDF'), findsOneWidget);
    expect(find.textContaining('All Languages'), findsOneWidget);

    // Verify "All Sources (Global Search)" card is NOT present in source selection modal
    expect(find.text('All Sources (Global Search)'), findsNothing);

    // Filter by search query "ocean"
    await tester.enterText(find.byType(TextField), 'ocean');
    await tester.pumpAndSettle();

    expect(find.text('OceanofPDF'), findsOneWidget);
    expect(find.text('ReadNovelFull'), findsNothing);

    // Tap on OceanofPDF to select it
    await tester.tap(find.text('OceanofPDF'));
    await tester.pumpAndSettle();

    // Verify selection callback was fired and modal closed
    expect(selectedSource, isNotNull);
    expect(selectedSource.id, 'oceanofpdf');
  });

  testWidgets('SourceSelectionModal selects a source from list', (tester) async {
    final currentSource = SourceRegistry.getDefaultSource();
    bool callbackFired = false;
    dynamic selectedSource;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                SourceSelectionModal.show(
                  context: context,
                  currentSource: currentSource,
                  onSourceSelected: (src) {
                    callbackFired = true;
                    selectedSource = src;
                  },
                );
              },
              child: const Text('Open Sources'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Sources'));
    await tester.pumpAndSettle();

    // Verify modal title has no subtitle text
    expect(find.text('Select Source'), findsOneWidget);
    expect(find.text('Browse webnovels, light novels, and digital books'), findsNothing);

    // Tap on a source card (e.g. LibRead or Royal Road)
    final sourceCard = find.text('Royal Road');
    if (sourceCard.evaluate().isNotEmpty) {
      await tester.tap(sourceCard);
      await tester.pumpAndSettle();
      expect(callbackFired, isTrue);
      expect(selectedSource?.id, 'royalroad');
    }
  });

  testWidgets('SourceSelectionModal filters by language', (tester) async {
    final currentSource = SourceRegistry.getDefaultSource();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                SourceSelectionModal.show(
                  context: context,
                  currentSource: currentSource,
                  onSourceSelected: (_) {},
                );
              },
              child: const Text('Open Sources'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Sources'));
    await tester.pumpAndSettle();

    // Find and tap on Japanese language chip if available
    final jaFinder = find.textContaining('Japanese');
    if (jaFinder.evaluate().isNotEmpty) {
      await tester.ensureVisible(jaFinder);
      await tester.pumpAndSettle();
      await tester.tap(jaFinder);
      await tester.pumpAndSettle();

      expect(find.text('Kakuyomu'), findsOneWidget);
      expect(find.text('ReadNovelFull'), findsNothing);
    }
  });
}
