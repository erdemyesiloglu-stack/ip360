import {test} from 'node:test';
import assert from 'node:assert/strict';
import {loadXtream, loadM3uSource, RELAY_MESSAGES} from '../dist/core.js';

test('HTTP relay is opt-in and keeps favorites stable across encrypted playback URLs', async () => {
  const calls = [];
  const fetcher = async (address, options) => {
    const url = new URL(address); calls.push({url, options});
    assert.equal(url.origin, 'https://app.example.com');
    assert.equal(options.credentials, 'same-origin');
    if (url.pathname.endsWith('/status')) return Response.json({ready: true});
    if (url.pathname.endsWith('/open')) return Response.json({ok: true});
    if (url.searchParams.get('action') === 'get_live_categories') return Response.json([{category_id: '7', category_name: 'Haber'}]);
    return Response.json([{stream_id: 42, category_id: '7', name: 'Test', relay_url: 'https://app.example.com/api/iptv/media?t=opaque'}]);
  };
  const result = await loadXtream('http://trsmart.net', 'u', 'p', undefined, {relay: true, origin: 'https://app.example.com', fetcher});
  assert.equal(calls.length, 4);
  assert.equal(result[0].hls, true);
  assert.equal(result[0].group, 'Haber');
  assert.equal(result[0].favoriteKey, 'http://trsmart.net/live/u/p/42.m3u8');
  assert.equal(result[0].url, 'https://app.example.com/api/iptv/media?t=opaque');
  assert.equal(calls[1].options.method, 'POST');
});
test('M3U links use the relay and never fetch the provider directly', async () => {
  const calls = [];
  const fetcher = async (address, options) => {
    const url = new URL(address); calls.push(url);
    assert.equal(url.origin, 'https://app.example.com');
    if (url.pathname.endsWith('/status')) return Response.json({ready: true});
    assert.equal(url.pathname, '/api/iptv/playlist');
    assert.equal(options.method, 'POST');
    assert.equal(JSON.parse(options.body).url, 'http://trsmart.net/get.php?username=u&password=p');
    return Response.json({channels: [{name: 'Test', kind: 'live', url: 'https://app.example.com/api/iptv/play/live/42.m3u8'}]});
  };
  const result = await loadM3uSource('http://trsmart.net/get.php?username=u&password=p', {relay: true, origin: 'https://app.example.com', fetcher});
  assert.equal(calls.length, 2);
  assert.equal(result[0].kind, 'live');
});
test('Missing secret and HTML errors produce safe specific messages', async () => {
  await assert.rejects(loadM3uSource('http://trsmart.net/get.php', {relay: true, origin: 'https://app.example.com',
    fetcher: async () => Response.json({ready: false})}), {message: RELAY_MESSAGES.RELAY_NOT_CONFIGURED});
  await assert.rejects(loadM3uSource('http://trsmart.net/get.php', {relay: true, origin: 'https://app.example.com',
    fetcher: async () => new Response('<html>upstream credentials must not appear</html>', {status: 500})}), {message: RELAY_MESSAGES.RELAY_INVALID_RESPONSE});
});
