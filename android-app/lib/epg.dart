import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'source.dart';

class Programme {
  const Programme(this.channelId, this.title, this.start, this.end, this.description);
  final String channelId, title, description;
  final DateTime start, end;
  bool contains(DateTime time) => !time.isBefore(start) && time.isBefore(end);
}

DateTime? xmltvTime(String value) {
  final match = RegExp(r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(?:\s*([+-])(\d{2})(\d{2}))?$').firstMatch(value.trim());
  if (match == null) { return null; }
  final utc = DateTime.utc(int.parse(match[1]!), int.parse(match[2]!), int.parse(match[3]!), int.parse(match[4]!), int.parse(match[5]!), int.parse(match[6] ?? '0'));
  final offset = Duration(hours: int.parse(match[8] ?? '0'), minutes: int.parse(match[9] ?? '0'));
  return (match[7] == '-' ? utc.add(offset) : utc.subtract(offset)).toLocal();
}

Map<String, List<Programme>> parseXmltv(String text) {
  final doc = XmlDocument.parse(text);
  if (doc.rootElement.name.local != 'tv') { throw const FormatException('Geçerli bir XMLTV dosyası gerekli.'); }
  final result = <String, List<Programme>>{};
  for (final node in doc.rootElement.findElements('programme')) {
    final id = node.getAttribute('channel') ?? '';
    final start = xmltvTime(node.getAttribute('start') ?? '');
    final end = xmltvTime(node.getAttribute('stop') ?? '');
    if (id.isEmpty || start == null || end == null || !end.isAfter(start)) { continue; }
    final title = node.getElement('title')?.innerText.trim() ?? '';
    (result[id] ??= []).add(Programme(id, title.isEmpty ? 'İsimsiz program' : title, start, end, node.getElement('desc')?.innerText ?? ''));
  }
  for (final programmes in result.values) { programmes.sort((a, b) => a.start.compareTo(b.start)); }
  return result;
}

Programme? currentProgramme(List<Programme> programmes, DateTime now) {
  for (final p in programmes) {
    if (p.contains(now)) { return p; }
    if (p.start.isAfter(now)) { break; }
  }
  return null;
}

class EpgService {
  EpgService(this.client);
  final http.Client client;
  Future<Map<String, List<Programme>>> load(String url) async {
    final response = await client.send(http.Request('GET', serverUri(url))).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      await response.stream.listen(null).cancel();
      throw const FormatException('Yayın rehberi alınamadı. XMLTV adresini kontrol edin.');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream.timeout(const Duration(seconds: 60))) {
      if (bytes.length + chunk.length > 30 * 1024 * 1024) { throw const FormatException('XMLTV rehberi en fazla 30 MB olabilir.'); }
      bytes.add(chunk);
    }
    return compute(parseXmltv, utf8.decode(bytes.takeBytes(), allowMalformed: true));
  }
}

String programmeTime(DateTime time) => '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
