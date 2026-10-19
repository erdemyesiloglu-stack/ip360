import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:iptv_app/source.dart';
import 'package:iptv_app/epg.dart';
import 'package:iptv_app/ui/player_chrome.dart';
import 'package:iptv_app/ui/playback_info.dart';

void main() {
  const channel = Channel('Spor 1', 'https://example.com/live', group: 'Spor', epgId: 'sport');
  final now = DateTime(2026, 10, 20, 1, 47);
  final current = Programme('sport', 'Maç sonrası', DateTime(2026, 10, 20, 1), DateTime(2026, 10, 20, 2), 'Yorumlar');
  final next = Programme('sport', 'Spor haberleri', DateTime(2026, 10, 20, 2), DateTime(2026, 10, 20, 3), '');
  Widget screen({Channel selected = channel, List<Programme>? programmes, PlayerState state = const PlayerState(playing: true),
    Duration hideAfter = const Duration(seconds: 7), VoidCallback? back, VoidCallback? play, ValueChanged<Duration>? seek}) => MaterialApp(theme: ThemeData.dark(),
    home: PlayerChrome(video: const ColoredBox(key: Key('video'), color: Colors.black), channel: selected,
      state: state, now: now, programmes: programmes ?? [current, next], favorite: false,
      onBack: back ?? () {}, onPlayPause: play ?? () {}, onRetry: () {}, onHistory: () {}, onFavorite: () {},
      onTracks: () {}, onFit: () {}, onSeek: seek ?? (_) {}, onGuide: () {}, hideAfter: hideAfter));

  test('Technical labels only describe real available values', () {
    expect(technicalBadges(), isEmpty);
    expect(technicalBadges(width: 1920, height: 1080, fps: 50, audioChannels: 2), ['FULL HD', '1920 × 1080', '50 FPS', 'STEREO']);
    expect(technicalBadges(width: 0, height: 0, fps: double.nan, audioChannels: 0), isEmpty);
    expect(technicalBadges(fps: 59.94), ['59.94 FPS']);
    expect(playbackDate(now), '20 Eki Sal 01:47');
  });
  for (final size in [const Size(360, 800), const Size(800, 360), const Size(1280, 720)]) {
    testWidgets('Overlay fits ${size.width} x ${size.height}, keeps video full screen and shows real EPG', (tester) async {
      tester.view.physicalSize = size; tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(screen());
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byKey(const Key('video'))), size);
      expect(find.text('Maç sonrası'), findsOneWidget);
      expect(find.text('13 dk kaldı'), findsOneWidget);
      expect(find.text('02:00 – 03:00  Spor haberleri'), findsOneWidget);
      expect(find.byKey(const Key('vod-seek')), findsNothing);
      expect(find.byKey(const Key('programme-progress')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('Overlay hides automatically and touch or remote can reveal it', (tester) async {
    await tester.pumpWidget(screen(hideAfter: const Duration(milliseconds: 200)));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Maç sonrası'), findsNothing);
    expect(find.byKey(const Key('video')), findsOneWidget);
    await tester.tap(find.byKey(const Key('player-surface')));
    await tester.pump();
    expect(find.text('Maç sonrası'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(find.text('Maç sonrası'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Back hides controls first, then exits; play/pause key still works', (tester) async {
    var backs = 0, plays = 0;
    await tester.pumpWidget(screen(back: () => backs++, play: () => plays++));
    await tester.binding.handlePopRoute(); await tester.pump();
    expect(backs, 0);
    expect(find.text('Maç sonrası'), findsNothing);
    await tester.binding.handlePopRoute(); await tester.pump();
    expect(backs, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause); await tester.pump();
    expect(plays, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Missing EPG stays unknown; film slider seeks within real duration', (tester) async {
    await tester.pumpWidget(screen(programmes: []));
    expect(find.text('Program bilgisi yok'), findsOneWidget);
    expect(find.byKey(const Key('programme-progress')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    Duration? sought;
    await tester.pumpWidget(screen(selected: const Channel('Film', 'https://example.com/movie', kind: 'movies'), programmes: [],
      state: const PlayerState(playing: true, duration: Duration(minutes: 90), position: Duration(minutes: 10)), seek: (v) => sought = v));
    final slider = tester.widget<Slider>(find.byKey(const Key('vod-seek')));
    slider.onChangeEnd!(2700000);
    await tester.pump();
    expect(sought, const Duration(minutes: 45));
    expect(find.text('CANLI'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
