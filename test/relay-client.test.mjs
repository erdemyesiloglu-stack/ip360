import {test} from 'node:test';
import assert from 'node:assert/strict';
import {loadXtream} from '../dist/core.js';

test('HTTP relay is opt-in and keeps favorites stable across encrypted playback URLs', async () => {
  const calls = [];
  const fetcher = async (address, options) => {
    const url = new URL(address); calls.push({url, options});
    assert.equal(url.origin, 'https://app.example.com');
    assert.equal(options.credentials, 'same-origin');
    if (url.pathname.endsWith('/open')) return Response.json({ok: true});
    if (url.searchParams.get('action') === 'get_live_categories') return Response.json([{category_id: '7', category_name: 'Haber'}]);
    return Response.json([{stream_id: 42, category_id: '7', name: 'Test', relay_url: 'https://app.example.com/api/iptv/media?t=opaque'}]);
  };
  const result = await loadXtream('http://trsmart.net', 'u', 'p', undefined, {relay: true, origin: 'https://app.example.com', fetcher});
  assert.equal(calls.length, 3);
  assert.equal(result[0].hls, true);
  assert.equal(result[0].group, 'Haber');
  assert.equal(result[0].favoriteKey, 'http://trsmart.net/live/u/p/42.m3u8');
  assert.equal(result[0].url, 'https://app.example.com/api/iptv/media?t=opaque');
  assert.equal(calls[0].options.method, 'POST');
});
