import 'package:flutter/material.dart';
import '../epg.dart';
import '../source.dart';

enum LiveView { logos, list, guide }

class LiveWorkspace extends StatelessWidget {
  const LiveWorkspace({super.key, required this.channels, required this.view, required this.preview,
    required this.selected, required this.epg, required this.now, required this.favorites,
    required this.onSelect, required this.onFavorite, required this.onEpg});
  final List<Channel> channels;
  final LiveView view;
  final Widget preview;
  final Channel? selected;
  final Map<String, List<Programme>> epg;
  final DateTime now;
  final Set<String> favorites;
  final ValueChanged<Channel> onSelect, onFavorite;
  final VoidCallback onEpg;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, size) {
    final content = channels.isEmpty ? const Center(child: Text('Bu görünümde kanal yok.')) : switch (view) {
      LiveView.logos => GridView.builder(padding: const EdgeInsets.all(12), itemCount: channels.length,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 210, childAspectRatio: 1.3, crossAxisSpacing: 10, mainAxisSpacing: 10),
        itemBuilder: (context, i) => _logo(context, channels[i], i)),
      LiveView.list => ListView.builder(padding: const EdgeInsets.symmetric(vertical: 8), itemCount: channels.length,
        itemBuilder: (context, i) => _row(context, channels[i], i)),
      LiveView.guide => Column(children: [_timeline(), Expanded(child: ListView.builder(itemCount: channels.length,
        itemBuilder: (context, i) => _guideRow(context, channels[i], i)))]),
    };
    if (size.maxWidth >= 760) {
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(flex: 6, child: content),
        const VerticalDivider(width: 1), Expanded(flex: 4, child: preview)]);
    }
    return Column(children: [SizedBox(height: size.maxHeight > 480 ? 250 : 150, child: preview),
      const Divider(height: 1), Expanded(child: content)]);
  });

  Widget _logo(BuildContext context, Channel channel, int index) => Card(
    color: selected?.key == channel.key ? const Color(0xFF294343) : const Color(0xFF1B222C),
    child: InkWell(autofocus: index == 0, borderRadius: BorderRadius.circular(12), onTap: () => onSelect(channel),
      focusColor: const Color(0x5579E9C2), child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        Expanded(child: _art(channel, 64)), const SizedBox(height: 8),
        Text(channel.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      ]))));

  Widget _row(BuildContext context, Channel channel, int index) {
    final current = currentProgramme(epg[channel.epgId] ?? [], now);
    return ListTile(autofocus: index == 0, selected: selected?.key == channel.key,
      selectedTileColor: const Color(0xFF243D3D), focusColor: const Color(0x5579E9C2),
      leading: SizedBox(width: 46, height: 38, child: _art(channel, 32)),
      title: Text(channel.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(current?.title ?? 'Program bilgisi yok', maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: IconButton(tooltip: 'Favori', onPressed: () => onFavorite(channel),
        icon: Icon(favorites.contains(channel.key) ? Icons.star : Icons.star_border, color: favorites.contains(channel.key) ? Colors.amber : Colors.white38)),
      onTap: () => onSelect(channel));
  }

  DateTime get _start => DateTime(now.year, now.month, now.day, now.hour, now.minute < 30 ? 0 : 30);
  Widget _timeline() => Container(color: const Color(0xFF222B36), padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(children: [const SizedBox(width: 112, child: Padding(padding: EdgeInsets.only(left: 12), child: Text('KANAL', style: TextStyle(fontSize: 11, color: Colors.white54)))),
      for (var i = 0; i < 3; i++) Expanded(child: Text(programmeTime(_start.add(Duration(minutes: i * 30))), style: const TextStyle(fontSize: 12)))]));

  Widget _guideRow(BuildContext context, Channel channel, int index) {
    final end = _start.add(const Duration(minutes: 90));
    final programmes = (epg[channel.epgId] ?? []).where((p) => p.end.isAfter(_start) && p.start.isBefore(end)).toList();
    return SizedBox(height: 76, child: Row(children: [SizedBox(width: 112, child: ListTile(autofocus: index == 0,
      selected: selected?.key == channel.key, selectedTileColor: const Color(0xFF243D3D),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12), title: Text(channel.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
      onTap: () => onSelect(channel))), Expanded(child: LayoutBuilder(builder: (context, box) => ClipRect(child: Stack(children: [
        const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF2B3541)))))),
        if (programmes.isEmpty) Positioned.fill(child: TextButton(onPressed: onEpg, child: const Text('Program bilgisi yok', style: TextStyle(fontSize: 11, color: Colors.white38)))),
        for (final p in programmes) Positioned(left: p.start.difference(_start).inSeconds / 5400 * box.maxWidth,
          width: p.end.difference(p.start).inSeconds / 5400 * box.maxWidth, top: 3, bottom: 3,
          child: Padding(padding: const EdgeInsets.only(right: 2), child: Material(color: p.contains(now) ? const Color(0xFF244540) : const Color(0xFF202A35),
            child: InkWell(onTap: () => showDialog<void>(context: context, builder: (context) => AlertDialog(title: Text(p.title),
              content: SingleChildScrollView(child: Text('${channel.name} · ${programmeTime(p.start)}–${programmeTime(p.end)}\n\n${p.description.isEmpty ? 'Açıklama bulunmuyor.' : p.description}')),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat'))])),
              child: Padding(padding: const EdgeInsets.all(8), child: Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))))))),
        Positioned(left: now.difference(_start).inSeconds / 5400 * box.maxWidth, top: 0, bottom: 0, child: const SizedBox(width: 2, child: ColoredBox(color: Color(0xFF79E9C2)))),
      ]))))]));
  }

  Widget _art(Channel channel, double size) => channel.logo.isEmpty ? Icon(Icons.live_tv, size: size, color: const Color(0xFF79E9C2)) :
    Image.network(channel.logo, fit: BoxFit.contain, cacheWidth: 240, errorBuilder: (_, error, stack) => Icon(Icons.live_tv, size: size, color: const Color(0xFF79E9C2)));
}
