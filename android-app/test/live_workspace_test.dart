import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/epg.dart';
import 'package:iptv_app/source.dart';
import 'package:iptv_app/ui/live_workspace.dart';

void main() {
  const channel = Channel('TRT 1', 'https://example.com/live', epgId: 'trt1');
  final now = DateTime(2026, 10, 20, 12, 10);
  final programme = Programme('trt1', 'Öğle haberleri', DateTime(2026, 10, 20, 11), DateTime(2026, 10, 20, 13), 'Gündem');
  for (final size in [const Size(360, 640), const Size(1280, 720)]) {
    for (final view in LiveView.values) {
      testWidgets('${view.name} fits ${size.width} and selects channels', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Channel? selected;
        await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: LiveWorkspace(
          channels: const [channel], view: view, preview: const ColoredBox(color: Colors.black, child: Center(child: Text('Önizleme'))),
          selected: null, epg: {'trt1': [programme]}, now: now, favorites: const {},
          onSelect: (value) => selected = value, onFavorite: (_) {}, onEpg: () {}))));
        expect(tester.takeException(), isNull);
        expect(find.text('Önizleme'), findsOneWidget);
        await tester.tap(find.text('TRT 1'));
        await tester.pump();
        expect(selected, channel);
        if (view == LiveView.guide) {
          await tester.tap(find.text('Öğle haberleri'));
          await tester.pumpAndSettle();
          expect(find.text('Gündem', findRichText: true), findsNothing);
          expect(find.textContaining('Gündem'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
