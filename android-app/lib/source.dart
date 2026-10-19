import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

const maxPlaylistBytes = 100 * 1024 * 1024;

class SourceConfig {
  const SourceConfig({required this.type, required this.url, this.username = '', this.password = ''});
  final String type, url, username, password;
  Map<String, String> toJson() => {'type': type, 'url': url, 'username': username, 'password': password};
  factory SourceConfig.fromJson(Map<String, dynamic> json) => SourceConfig(
    type: json['type'] as String, url: json['url'] as String,
    username: json['username'] as String? ?? '', password: json['password'] as String? ?? '');
}

class Channel {
  const Channel(this.name, this.url, {this.group = 'Diğer', this.logo = '', this.kind = 'live', this.seriesId, this.season});
  final String name, url, group, logo, kind;
  final String? seriesId, season;
  String get key => seriesId == null ? url : 'series:$seriesId:$name';
}

Uri serverUri(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || !['http', 'https'].contains(uri.scheme) || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
    throw const FormatException('Geçerli bir HTTP veya HTTPS adresi girin.');
  }
  return uri;
}

String safeLogo(dynamic value, [Uri? base]) {
  if (value is! String || value.trim().isEmpty) { return ''; }
  try { return serverUri(base?.resolve(value).toString() ?? value).toString(); }
  catch (_) { return ''; }
}

String normalize(String value) => value.toLowerCase().replaceAll('ı', 'i').replaceAll('İ', 'i').replaceAll('\u0307', '')
  .replaceAll('ş', 's').replaceAll('ğ', 'g').replaceAll('ç', 'c').replaceAll('ö', 'o').replaceAll('ü', 'u');

String inferKind(String group, String url) {
  final text = normalize(group);
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
  if (path.contains('/series/') || RegExp(r'dizi|series|tv shows').hasMatch(text)) { return 'series'; }
  if (path.contains('/movie/') || RegExp(r'film|movies|sinema|vod').hasMatch(text)) { return 'movies'; }
  return 'live';
}

String categoryOf(Channel channel) {
  final group = normalize(channel.group);
  final name = normalize(channel.name);
  if (channel.kind != 'live') {
    const genres = {'Aksiyon': 'aksiyon|action', 'Komedi': 'komedi|comedy|sitcom', 'Dram': 'dram|drama',
      'Bilim Kurgu': 'bilim kurgu|sci.fi|science fiction', 'Korku': 'korku|horror', 'Gerilim': 'gerilim|thriller',
      'Animasyon': 'animasyon|animation|anime', 'Belgesel': 'belgesel|documentary'};
    for (final entry in genres.entries) { if (RegExp(entry.value).hasMatch(group)) { return entry.key; } }
    return channel.group;
  }
  final text = '$group $name';
  if (RegExp(r'belgesel|documentary|national geographic|nat geo|discovery|animal planet').hasMatch(text)) { return 'Belgesel'; }
  if (RegExp(r'spor|sport').hasMatch(text)) { return 'Spor'; }
  if (RegExp(r'haber|news|\bntv\b|\bcnn\b|bloomberg').hasMatch(text)) { return 'Haber'; }
  if (RegExp(r'cocuk|kids|cartoon|minika|nickelodeon').hasMatch(text)) { return 'Çocuk'; }
  if (RegExp(r'muzik|music').hasMatch(text)) { return 'Müzik'; }
  if (RegExp(r'ulusal|national|genel|trt ?1\b|kanal d\b|show tv|star tv|\batv\b|\btv8\b|\bnow\b|kanal 7').hasMatch(text)) { return 'Ulusal'; }
  return channel.group;
}

List<String> categoriesFor(List<Channel> channels, String kind) {
  final defaults = kind == 'live' ? ['Ulusal', 'Spor', 'Haber', 'Belgesel', 'Çocuk', 'Müzik'] :
    ['Aksiyon', 'Komedi', 'Dram', 'Bilim Kurgu', 'Korku', 'Gerilim', 'Animasyon', 'Belgesel'];
  return {...defaults, ...channels.where((c) => c.kind == kind).map(categoryOf)}.toList();
}

List<Channel> parseM3u(String text, {Uri? base}) {
  final parser = _M3uParser(base);
  for (final line in LineSplitter.split(text)) {
    parser.add(line);
  }
  return parser.finish();
}

Future<List<Channel>> parseM3uStream(Stream<List<int>> bytes, {Uri? base}) async {
  final parser = _M3uParser(base);
  await for (final line in bytes.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter())) {
    parser.add(line);
  }
  return parser.finish();
}

class _M3uParser {
  _M3uParser(this.base);
  final Uri? base;
  final channels = <Channel>[];
  var name = '', group = 'Diğer', logo = '';
  var hls = false;
  void add(String raw) {
    final line = raw.replaceFirst('\uFEFF', '').trim();
    if (RegExp(r'^#EXT-X-(TARGETDURATION|STREAM-INF|MEDIA-SEQUENCE):').hasMatch(line)) {
      hls = true;
    }
    if (hls) { return; }
    if (line.startsWith('#EXTINF:')) {
      group = RegExp(r'group-title="([^"]*)"').firstMatch(line)?.group(1) ?? 'Diğer';
      logo = safeLogo(RegExp(r'tvg-logo="([^"]*)"').firstMatch(line)?.group(1), base);
      var quoted = false;
      name = '';
      for (var i = 0; i < line.length; i++) {
        if (line[i] == '"') { quoted = !quoted; }
        if (line[i] == ',' && !quoted) { name = line.substring(i + 1).trim(); break; }
      }
    } else if (line.isNotEmpty && !line.startsWith('#')) {
      try {
        final uri = serverUri(base?.resolve(line).toString() ?? line);
        channels.add(Channel(name.isEmpty ? 'Kanal ${channels.length + 1}' : name, uri.toString(),
          group: group.isEmpty ? 'Diğer' : group, logo: logo, kind: inferKind(group, uri.toString())));
      } catch (_) { /* Desteklenmeyen protokolleri atla. */ }
      name = ''; group = 'Diğer'; logo = '';
    }
  }
  List<Channel> finish() {
    if (hls) {
      if (base == null) { throw const FormatException('HLS dosyası yerine yayın bağlantısını ekleyin.'); }
      return [Channel('HLS yayını', base.toString())];
    }
    if (channels.isEmpty) { throw const FormatException('Listede oynatılabilir HTTP/HTTPS yayını bulunamadı.'); }
    return channels;
  }
}

class SourceService {
  SourceService(this.client, {this.maxBytes = maxPlaylistBytes});
  final int maxBytes;
  final http.Client client;
  final warnings = <String>[];

  Stream<List<int>> _download(Uri uri) async* {
    final response = await client.send(http.Request('GET', uri)).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      await response.stream.listen(null).cancel();
      throw const FormatException('Sağlayıcı isteği reddetti. Adresi ve hesap bilgilerini kontrol edin.');
    }
    var received = 0;
    await for (final chunk in response.stream.timeout(const Duration(seconds: 60))) {
      received += chunk.length;
      if (received > maxBytes) { throw const FormatException('Liste cihaz kapasitesi sınırını aşıyor (100 MB). Sağlayıcıdan daha küçük liste veya Xtream bilgilerini isteyin.'); }
      yield chunk;
    }
  }
  Future<String> _get(Uri uri) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in _download(uri)) {
      bytes.add(chunk);
    }
    return utf8.decode(bytes.takeBytes(), allowMalformed: true);
  }

  Future<List<Channel>> m3u(String url) async {
    final uri = serverUri(url);
    return parseM3uStream(_download(uri), base: uri);
  }
  Uri _root(SourceConfig config) {
    final base = serverUri(config.url);
    return base.replace(path: base.path.endsWith('/') ? base.path : '${base.path}/', query: '', fragment: '');
  }
  Future<dynamic> _api(SourceConfig config, [String? action, String? seriesId]) async {
    final uri = _root(config).resolve('player_api.php').replace(queryParameters: {
      'username': config.username, 'password': config.password,
      if (action != null) 'action': action, if (seriesId != null) 'series_id': seriesId,
    });
    return jsonDecode(await _get(uri));
  }
  String _stream(SourceConfig config, String kind, String id, String extension) =>
    _root(config).resolve('$kind/${Uri.encodeComponent(config.username)}/${Uri.encodeComponent(config.password)}/$id.$extension').toString();

  Future<List<Channel>> xtream(SourceConfig config) async {
    if (config.username.isEmpty || config.password.isEmpty) { throw const FormatException('Kullanıcı adı ve şifre gerekli.'); }
    warnings.clear();
    final account = await _api(config);
    if (account is! Map || account['user_info'] is! Map || '${account['user_info']['auth']}' != '1') {
      throw const FormatException('Xtream hesabı doğrulanamadı.');
    }
    Future<List<Channel>> catalog(String kind, String categoryAction, String streamAction, String label) async {
      try {
        final data = await Future.wait([_api(config, categoryAction), _api(config, streamAction)]);
        final groups = <String, String>{};
        if (data[0] is List) {
          for (final row in (data[0] as List).whereType<Map>()) { groups['${row['category_id']}'] = '${row['category_name'] ?? 'Diğer'}'; }
        }
        if (data[1] is! List) { throw const FormatException('Katalog alınamadı.'); }
        final items = <Channel>[];
        for (final row in (data[1] as List).whereType<Map>()) {
          final id = '${row[kind == 'series' ? 'series_id' : 'stream_id'] ?? ''}';
          if (!RegExp(r'^\d+$').hasMatch(id)) { continue; }
          var extension = '${row['container_extension'] ?? 'mp4'}';
          if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(extension)) { extension = 'mp4'; }
          final url = kind == 'series' ? '' : _stream(config, kind == 'live' ? 'live' : 'movie', id, kind == 'live' ? 'ts' : extension);
          items.add(Channel('${row['name'] ?? 'İçerik'}', url,
            group: groups['${row['category_id']}'] ?? 'Diğer', kind: kind,
            logo: safeLogo(row[kind == 'series' ? 'cover' : 'stream_icon'], _root(config)),
            seriesId: kind == 'series' ? id : null));
        }
        return items;
      } catch (_) { warnings.add('$label kataloğu alınamadı.'); return []; }
    }
    final results = await Future.wait([
      catalog('live', 'get_live_categories', 'get_live_streams', 'Kanallar'),
      catalog('movies', 'get_vod_categories', 'get_vod_streams', 'Filmler'),
      catalog('series', 'get_series_categories', 'get_series', 'Diziler'),
    ]);
    final items = results.expand((list) => list).toList();
    if (items.isEmpty) { throw const FormatException('Hesapta içerik bulunamadı veya sağlayıcı katalogları alınamadı.'); }
    return items;
  }

  Future<List<Channel>> episodes(SourceConfig config, Channel show) async {
    final response = await _api(config, 'get_series_info', show.seriesId);
    if (response is! Map || response['episodes'] is! Map) { throw const FormatException('Dizi bölümleri alınamadı.'); }
    final result = <Channel>[];
    for (final entry in (response['episodes'] as Map).entries) {
      if (entry.value is! List) { continue; }
      for (final episode in (entry.value as List).whereType<Map>()) {
        final id = '${episode['id'] ?? ''}';
        if (!RegExp(r'^\d+$').hasMatch(id)) { continue; }
        var extension = '${episode['container_extension'] ?? 'mp4'}';
        if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(extension)) { extension = 'mp4'; }
        result.add(Channel('${episode['title'] ?? 'Bölüm ${episode['episode_num'] ?? ''}'}',
          _stream(config, 'series', id, extension), group: show.name, kind: 'series', logo: show.logo, season: '${entry.key}'));
      }
    }
    if (result.isEmpty) { throw const FormatException('Bu dizi için bölüm bulunamadı.'); }
    return result;
  }
}
