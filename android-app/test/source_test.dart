import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iptv_app/source.dart';

void main() {
  test('Loads M3U larger than the old 20 MB limit without buffering the body', () async {
    final padding = utf8.encode('#${'x' * 65534}\n');
    Stream<List<int>> body() async* {
      yield utf8.encode('#EXTM3U\n#EXTINF:-1 group-title="Haber",Kanal\n');
      for (var i = 0; i < 321; i++) { yield padding; }
      yield utf8.encode('https://example.com/live.m3u8\n');
    }
    final client = _StreamClient(body());
    final channels = await SourceService(client).m3u('https://example.com/list.m3u');
    expect(padding.length * 321, greaterThan(20 * 1024 * 1024));
    expect(channels.single.name, 'Kanal');
    expect(channels.single.group, 'Haber');
    client.close();
  });
  test('Streaming parser retains UTF-8 and metadata across individual byte chunks', () async {
    const text = '#EXTM3U\n#EXTINF:-1 group-title="Çocuk" tvg-logo="afiş.png",Çizgi\ncanli.m3u8\n';
    final expected = parseM3u(text, base: Uri.parse('https://example.com/list.m3u'));
    final channels = await parseM3uStream(Stream.fromIterable(utf8.encode(text).map((b) => [b])), base: Uri.parse('https://example.com/list.m3u'));
    expect(channels.single.name, expected.single.name);
    expect(channels.single.group, expected.single.group);
    expect(channels.single.logo, expected.single.logo);
    expect(channels.single.url, expected.single.url);
  });
  test('Counts actual streamed bytes even without a Content-Length header', () async {
    var cancelled = false;
    Stream<List<int>> body() async* {
      try {
        yield utf8.encode('#EXTM3U\n');
        yield List.filled(32, 35);
        yield utf8.encode('https://example.com/live');
      } finally { cancelled = true; }
    }
    final client = _StreamClient(body());
    await expectLater(SourceService(client, maxBytes: 16).m3u('https://example.com/list'), throwsFormatException);
    expect(cancelled, isTrue);
    client.close();
  });

  test('M3U preserves quoted commas, artwork and relative paths', () {
    final list = parseM3u('\uFEFF#EXTM3U\r\n#EXTINF:-1 group-title="Haber, TV" tvg-logo="logo.png",Kanal, HD\r\nlive/a.m3u8', base: Uri.parse('https://example.com/list.m3u'));
    expect(list.single.name, 'Kanal, HD');
    expect(list.single.group, 'Haber, TV');
    expect(list.single.logo, 'https://example.com/logo.png');
    expect(list.single.url, 'https://example.com/live/a.m3u8');
  });
  test('Rejects unsupported protocols and keeps direct HLS manifest intact', () {
    expect(() => parseM3u('#EXTM3U\nfile:///etc/passwd'), throwsFormatException);
    expect(() => serverUri('ftp://example.com'), throwsFormatException);
    final base = Uri.parse('https://example.com/live.m3u8');
    expect(parseM3u('#EXTM3U\n#EXT-X-TARGETDURATION:6\nsegment.ts', base: base).single.url, base.toString());
  });
  test('Xtream authenticates, maps all catalogs and preserves HTTPS port 8000', () async {
    final client = MockClient((request) async {
      expect(request.url.port, 8000);
      expect(request.url.queryParameters['password'], 'p&ss');
      final action = request.url.queryParameters['action'];
      if (action == null) { return http.Response('{"user_info":{"auth":1}}', 200); }
      if (action.endsWith('categories')) { return http.Response('[{"category_id":"7","category_name":"Haber"}]', 200); }
      if (action == 'get_live_streams') { return http.Response('[{"stream_id":42,"name":"Kanal","category_id":"7"}]', 200); }
      if (action == 'get_vod_streams') { return http.Response('[{"stream_id":43,"name":"Film","category_id":"7","container_extension":"mp4"}]', 200); }
      if (action == 'get_series') { return http.Response('[{"series_id":44,"name":"Dizi","category_id":"7"}]', 200); }
      return http.Response('[]', 200);
    });
    final channels = await SourceService(client).xtream(const SourceConfig(type: 'xtream', url: 'https://example.com:8000', username: 'a b', password: 'p&ss'));
    expect(channels.map((c) => c.kind), ['live', 'movies', 'series']);
    expect(Uri.parse(channels.first.url).pathSegments, ['live', 'a b', 'p&ss', '42.ts']);
    expect(channels[1].url, contains('/movie/a%20b/p%26ss/43.mp4'));
    expect(channels.last.seriesId, '44');
    client.close();
  });
  test('Xtream rejects invalid login before requesting catalogs', () async {
    var calls = 0;
    final client = MockClient((_) async { calls++; return http.Response('{"user_info":{"auth":0}}', 200); });
    await expectLater(SourceService(client).xtream(const SourceConfig(type: 'xtream', url: 'http://example.com', username: 'u', password: 'p')), throwsFormatException);
    expect(calls, 1);
    client.close();
  });
  test('Series episodes map to direct playable addresses with season metadata', () async {
    final client = MockClient((request) async {
      expect(request.url.queryParameters['action'], 'get_series_info');
      expect(request.url.queryParameters['series_id'], '44');
      return http.Response('{"episodes":{"1":[{"id":55,"title":"Bölüm 1","container_extension":"mp4"}]}}', 200);
    });
    final episodes = await SourceService(client).episodes(const SourceConfig(type: 'xtream', url: 'https://example.com', username: 'u', password: 'p'),
      const Channel('Dizi', '', kind: 'series', seriesId: '44'));
    expect(episodes.single.url, 'https://example.com/series/u/p/55.mp4');
    expect(episodes.single.season, '1');
    client.close();
  });
  test('Native sources support both HTTP and HTTPS without provider allowlists', () {
    expect(serverUri('http://example.com:8080').port, 8080);
    expect(serverUri('https://example.com:8000').port, 8000);
    expect(categoryOf(const Channel('TRT Belgesel', 'https://example.com/a')), 'Belgesel');
    expect(categoryOf(const Channel('S Sport', 'https://example.com/a')), 'Spor');
    expect(inferKind('Filmler', 'https://example.com/movie/u/p/4.mp4'), 'movies');
  });
}

class _StreamClient extends http.BaseClient {
  _StreamClient(this.body);
  final Stream<List<int>> body;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async => http.StreamedResponse(body, 200);
}
