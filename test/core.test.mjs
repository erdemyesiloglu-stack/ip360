import {test} from 'node:test';
import assert from 'node:assert/strict';
import {parseM3U, webUrl, loadXtream, readRemote, filterChannels, contentType, channelCategory, sectionCategories, artworkUrl} from '../dist/core.js';

test('M3U handles BOM, CRLF, quoted commas and relative streams', () => {
  const channels = parseM3U('\uFEFF#EXTM3U\r\n#EXTINF:-1 group-title="Haber, TV",Kanal, HD\r\nstream/live.m3u8', 'https://example.com/list.m3u');
  assert.deepEqual(channels, [{name: 'Kanal, HD', group: 'Haber, TV', url: 'https://example.com/stream/live.m3u8'}]);
});
test('M3U resets metadata and rejects dangerous protocols', () => {
  const channels = parseM3U('#EXTINF:-1 group-title="A",One\nhttps://example.com/one\nhttps://example.com/two\n#EXTINF:-1,evil\njavascript:alert(1)');
  assert.equal(channels.length, 2);
  assert.equal(channels[1].group, 'Diğer');
  assert.equal(channels[1].name, 'Kanal 2');
  assert.throws(() => parseM3U('#EXTM3U\nfile:///tmp/secret'));
  assert.throws(() => webUrl('https://user:password@example.com'));
});
test('Direct HLS playlists play the original URL rather than segments', () => {
  const hls = '#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXTINF:10,\nsegment.ts';
  assert.equal(parseM3U(hls, 'https://example.com/live.m3u8')[0].url, 'https://example.com/live.m3u8');
  assert.throws(() => parseM3U(hls), /HTTPS/);
});
test('Xtream authenticates, maps categories and encodes credentials', async () => {
  const requests = [];
  const reader = async url => {
    requests.push(url);
    assert.equal(url.searchParams.get('password'), 'p&ss');
    if (!url.searchParams.has('action')) return {user_info: {auth: 1}};
    if (url.searchParams.get('action') === 'get_live_categories') return [{category_id: 7, category_name: 'Haber'}];
    return [{stream_id: 42, name: 'Kanal', category_id: 7}, {stream_id: '../../bad'}];
  };
  const channels = await loadXtream('https://example.com/base', 'a b', 'p&ss', reader);
  assert.equal(requests.length, 3);
  assert.deepEqual(channels, [{kind: 'live', name: 'Kanal', group: 'Haber', url: 'https://example.com/base/live/a%20b/p%26ss/42.m3u8'}]);
});
test('Xtream stops after authentication rejection', async () => {
  let calls = 0;
  await assert.rejects(loadXtream('https://example.com', 'a', 'b', async () => { calls++; return {user_info: {auth: 0}}; }), /doğrulanamadı/);
  assert.equal(calls, 1);
});
test('Remote requests omit cookies and referrer and handle failure', async () => {
  assert.equal(await readRemote('https://example.com', false, async (url, options) => {
    assert.equal(options.credentials, 'omit');
    assert.equal(options.referrerPolicy, 'no-referrer');
    return new Response('#EXTM3U');
  }), '#EXTM3U');
  await assert.rejects(readRemote('https://example.com', false, async () => new Response('', {status: 403})), /reddetti/);
});
test('Filters Turkish names, category and favorites together', () => {
  const channels = [{id: 'a', name: 'İstanbul', group: 'Haber'}, {id: 'b', name: 'İstanbul 2', group: 'Film'}];
  assert.deepEqual(filterChannels(channels, 'istanbul', 'Haber', true, new Set(['a'])), [channels[0]]);
});
test('Stops chunked downloads above the byte limit without content-length', async () => {
  let cancelled = false;
  const stream = new ReadableStream({
    pull(controller) { controller.enqueue(new Uint8Array(11 * 1024 * 1024)); },
    cancel() { cancelled = true; },
  });
  await assert.rejects(readRemote('https://example.com/list', false,
    async () => new Response(stream)), /20 MB/);
  assert.equal(cancelled, true);
});
test('Decodes Turkish UTF-8 correctly when a character spans network chunks', async () => {
  const bytes = new TextEncoder().encode('İstanbul');
  const stream = new ReadableStream({start(c) {
    c.enqueue(bytes.slice(0, 1)); c.enqueue(bytes.slice(1)); c.close();
  }});
  assert.equal(await readRemote('https://example.com/list', false,
    async () => new Response(stream)), 'İstanbul');
});
test('Sections classify M3U groups and Xtream-style paths', () => {
  assert.equal(contentType({group: 'Türkçe Filmler', url: 'https://example.com/a'}), 'movies');
  assert.equal(contentType({group: 'Yabancı Diziler', url: 'https://example.com/a'}), 'series');
  assert.equal(contentType({group: 'Arşiv', url: 'https://example.com/movie/u/p/1.mp4'}), 'movies');
  assert.equal(contentType({group: 'Arşiv', url: 'https://example.com/series/u/p/1.mp4'}), 'series');
  assert.equal(contentType({group: 'Haber', url: 'https://example.com/live'}), 'live');
  assert.equal(contentType({kind: 'live', group: 'Sinema TV', url: 'https://example.com/live'}), 'live');
});
test('Channel genres normalize provider groups and recognize common Turkish channels', () => {
  const channel = (name, group = 'TR') => ({name, group, kind: 'live'});
  assert.equal(channelCategory(channel('Kanal', 'TR | SPOR FHD')), 'Spor');
  assert.equal(channelCategory(channel('Kanal', 'TR - ULUSAL')), 'Ulusal');
  assert.equal(channelCategory(channel('TRT 1 HD')), 'Ulusal');
  assert.equal(channelCategory(channel('NTV FHD')), 'Haber');
  assert.equal(channelCategory(channel('National Geographic HD')), 'Belgesel');
  assert.equal(channelCategory(channel('TRT Çocuk')), 'Çocuk');
  assert.equal(channelCategory(channel('Kanal', 'MÜZİK')), 'Müzik');
  assert.equal(channelCategory(channel('Yerel TV', 'Bölgesel')), 'Bölgesel');
  assert.equal(channelCategory(channel('Unknown TV')), 'Diğer');
});
test('Sidebar categories count channels and filtering uses canonical category names', () => {
  const channels = [
    {id: 'a', kind: 'live', name: 'S Sport', group: 'TR', url: 'https://example.com/a'},
    {id: 'b', kind: 'live', name: 'TRT Spor', group: 'TR SPORT', url: 'https://example.com/b'},
    {id: 'c', kind: 'live', name: 'NTV', group: 'TR', url: 'https://example.com/c'},
    {id: 'd', kind: 'movies', name: 'Film', group: 'Aksiyon', url: 'https://example.com/movie/a'},
  ];
  const categories = sectionCategories(channels, 'live');
  assert.equal(categories.find(c => c.label === 'Spor').count, 2);
  assert.equal(categories.find(c => c.label === 'Haber').count, 1);
  assert.equal(categories.find(c => c.label === 'Belgesel').count, 0);
  assert.deepEqual(filterChannels(channels, '', 'Spor', false, new Set(), channelCategory).map(c => c.id), ['a', 'b']);
  assert.deepEqual(filterChannels(channels, 'trt', 'Spor', true, new Set(['b']), channelCategory).map(c => c.id), ['b']);
  assert.equal(sectionCategories(channels, 'movies').find(c => c.label === 'Aksiyon').count, 1);
  assert.equal(sectionCategories(channels, 'series').find(c => c.label === 'Komedi').count, 0);
});
test('Film and series subcategories normalize genres and preserve provider-specific groups', () => {
  const channels = [
    {id: 'm1', kind: 'movies', group: 'Filmler | ACTION', name: 'Film', url: 'https://example.com/movie/1'},
    {id: 'm2', kind: 'movies', group: 'Bilim Kurgu Filmler', name: 'Film 2', url: 'https://example.com/movie/2'},
    {id: 's1', kind: 'series', group: 'Diziler | Comedy', name: 'Dizi', url: 'https://example.com/series/1'},
    {id: 's2', kind: 'series', group: 'Kore Dizileri', name: 'Dizi 2', url: 'https://example.com/series/2'},
  ];
  assert.equal(channelCategory(channels[0]), 'Aksiyon');
  assert.equal(channelCategory(channels[1]), 'Bilim Kurgu');
  assert.equal(channelCategory(channels[2]), 'Komedi');
  assert.equal(channelCategory(channels[3]), 'Kore Dizileri');
  assert.equal(sectionCategories(channels, 'series').find(c => c.label === 'Komedi').count, 1);
  assert.equal(sectionCategories(channels, 'series').find(c => c.label === 'Kore Dizileri').count, 1);
  assert.deepEqual(filterChannels(channels, '', 'Komedi', false, new Set(), channelCategory).map(c => c.id), ['s1']);
});
test('M3U preserves source artwork, resolves relative artwork and resets it between entries', () => {
  const channels = parseM3U('#EXTINF:-1 tvg-logo="images/logo.png" group-title="Ulusal",Kanal\nhttps://example.com/a\n#EXTINF:-1,İkinci\nhttps://example.com/b', 'https://example.com/list.m3u');
  assert.equal(channels[0].logo, 'https://example.com/images/logo.png');
  assert.equal(channels[1].logo, undefined);
  assert.equal(artworkUrl('javascript:alert(1)'), '');
  assert.equal(artworkUrl('data:image/svg+xml,bad'), '');
});
test('Xtream preserves a channel logo from the provider', async () => {
  const reader = async url => {
    const action = url.searchParams.get('action');
    if (!action) return {user_info: {auth: 1}};
    if (action === 'get_live_categories') return [];
    return [{stream_id: 42, name: 'Kanal', stream_icon: 'https://example.com/logo.png'}];
  };
  const channels = await loadXtream('https://example.com', 'u', 'p', reader);
  assert.equal(channels[0].logo, 'https://example.com/logo.png');
});
