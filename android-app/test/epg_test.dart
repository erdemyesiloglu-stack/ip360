import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/epg.dart';
import 'package:iptv_app/source.dart';

void main() {
  test('XMLTV offsets refer to the same UTC instant', () {
    expect(xmltvTime('20261020120000 +0300')!.toUtc(), DateTime.utc(2026, 10, 20, 9));
    expect(xmltvTime('20261020040000 -0500')!.toUtc(), DateTime.utc(2026, 10, 20, 9));
    expect(xmltvTime('202610201200'), isNull);
    expect(xmltvTime('20261020090000')!.toUtc(), DateTime.utc(2026, 10, 20, 9));
  });
  test('Guide sorts programmes, decodes text and skips invalid intervals', () {
    final guide = parseXmltv('<tv>'
      '<programme channel="trt1" start="20261020100000 +0000" stop="20261020110000 +0000"><title>Sonraki</title></programme>'
      '<programme channel="trt1" start="20261020090000 +0000" stop="20261020100000 +0000"><title>Haber &amp; Gündem</title><desc>Canlı</desc></programme>'
      '<programme channel="trt1" start="20261020110000 +0000" stop="20261020100000 +0000"><title>Geçersiz</title></programme></tv>');
    expect(guide['trt1'], hasLength(2));
    final programmes = guide['trt1']!;
    expect(currentProgramme(programmes, DateTime.utc(2026, 10, 20, 9, 30))!.title, 'Haber & Gündem');
    expect(currentProgramme(programmes, DateTime.utc(2026, 10, 20, 10))!.title, 'Sonraki');
    expect(currentProgramme(programmes, DateTime.utc(2026, 10, 20, 11)), isNull);
    expect(programmes.first.description, 'Canlı');
    expect(() => parseXmltv('<html/>'), throwsFormatException);
  });
  test('M3U keeps exact guide identifiers rather than guessing from channel names', () {
    final channels = parseM3u('#EXTM3U\n#EXTINF:-1 tvg-id="trt1.tr" group-title="Ulusal",TRT 1\nhttps://example.com/a\n#EXTINF:-1,TRT 1 HD\nhttps://example.com/b');
    expect(channels.first.epgId, 'trt1.tr');
    expect(channels.last.epgId, isEmpty);
  });
}
