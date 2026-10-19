import {test} from 'node:test';
import assert from 'node:assert/strict';
import {handleRequest} from '../dist/_worker.js';

const env = {IPTV_SESSION_SECRET: 'unit-test-only-secret-value-at-least-32-characters'};
const origin = 'https://app.example.com';
const openRequest = (server = 'http://trsmart.net', site = origin) => new Request(origin + '/api/iptv/open', {
  method: 'POST', headers: {'Content-Type': 'application/json', Origin: site},
  body: JSON.stringify({server, username: 'test-user', password: 'test-password'}),
});
const authenticated = (path, cookie, headers = {}) => new Request(new URL(path, origin), {headers: {cookie, ...headers}});

test('Relay fails closed until a server secret is configured', async () => {
  const response = await handleRequest(openRequest(), {});
  assert.equal(response.status, 503);
  assert.equal((await response.json()).code, 'RELAY_NOT_CONFIGURED');
});
test('Relay rejects other providers, cross-origin requests and unauthenticated playback', async () => {
  assert.equal((await handleRequest(openRequest('http://127.0.0.1'), env)).status, 400);
  assert.equal((await handleRequest(openRequest('http://trsmart.net.evil.example'), env)).status, 400);
  assert.equal((await handleRequest(openRequest('http://trsmart.net', 'https://evil.example'), env)).status, 403);
  assert.equal((await handleRequest(new Request(origin + '/api/iptv/media?t=invalid'), env)).status, 401);
});
test('Relay authenticates, hides credentials, rewrites HLS segments and keys and streams bytes', async () => {
  const original = globalThis.fetch;
  const targets = [];
  globalThis.fetch = async (address, options) => {
    const url = new URL(address); targets.push(url);
    assert.equal(url.hostname, 'trsmart.net');
    if (url.pathname === '/player_api.php') {
      assert.equal(url.searchParams.get('username'), 'test-user');
      assert.equal(url.searchParams.get('password'), 'test-password');
      const action = url.searchParams.get('action');
      return Response.json(!action ? {user_info: {auth: 1}} : action === 'get_live_categories' ?
        [{category_id: 7, category_name: 'Haber'}] : [{stream_id: 42, name: 'Test Kanal', category_id: 7}]);
    }
    if (url.pathname.endsWith('.m3u8')) return new Response('#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n#EXTINF:6,\nsegment.ts', {headers: {'Content-Type': 'application/vnd.apple.mpegurl'}});
    if (url.pathname.endsWith('segment.ts')) {
      assert.equal(options.headers.Range, 'bytes=0-2');
      return new Response(new Uint8Array([1,2,3]), {status: 206, headers: {'Content-Type': 'video/mp2t', 'Content-Range': 'bytes 0-2/3'}});
    }
    throw new Error('Unexpected upstream path');
  };
  try {
    const opened = await handleRequest(openRequest(), env);
    assert.equal(opened.status, 200);
    const cookieHeader = opened.headers.get('set-cookie');
    assert.match(cookieHeader, /HttpOnly; Secure; SameSite=Strict/);
    assert.ok(!cookieHeader.includes('test-password'));
    const cookie = cookieHeader.split(';')[0];
    const streams = await (await handleRequest(authenticated('/api/iptv/api?action=get_live_streams', cookie), env)).json();
    assert.equal(streams.length, 1);
    assert.ok(!JSON.stringify(streams).includes('test-password'));
    const playlist = await (await handleRequest(authenticated(streams[0].relay_url, cookie), env)).text();
    assert.ok(!playlist.includes('test-user'));
    assert.ok(!playlist.includes('trsmart.net'));
    assert.match(playlist, /URI="https:\/\/app.example.com\/api\/iptv\/media\?t=/);
    const segment = playlist.split('\n').find(line => line.startsWith('https://'));
    const response = await handleRequest(authenticated(segment, cookie, {Range: 'bytes=0-2'}), env);
    assert.equal(response.status, 206);
    assert.deepEqual([...new Uint8Array(await response.arrayBuffer())], [1,2,3]);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    const otherSession = await handleRequest(openRequest(), env);
    const otherCookie = otherSession.headers.get('set-cookie').split(';')[0];
    assert.equal((await handleRequest(authenticated(segment, otherCookie), env)).status, 403);
  } finally { globalThis.fetch = original; }
});
test('Provider authentication rejection never creates a session', async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async () => Response.json({user_info: {auth: 0}});
  try {
    const response = await handleRequest(openRequest(), env);
    assert.equal(response.status, 401);
    assert.equal(response.headers.get('set-cookie'), null);
  } finally { globalThis.fetch = original; }
});
test('Redirects to another host are rejected before fetching that host', async () => {
  const original = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = async () => { calls++; return new Response(null, {status: 302, headers: {Location: 'http://127.0.0.1/admin'}}); };
  try {
    assert.equal((await handleRequest(openRequest(), env)).status, 502);
    assert.equal(calls, 1);
  } finally { globalThis.fetch = original; }
});
test('Closing a source expires its browser relay cookie without provider requests', async () => {
  const response = await handleRequest(new Request(origin + '/api/iptv/close', {
    method: 'POST', headers: {Origin: origin},
  }), {});
  assert.equal(response.status, 200);
  assert.match(response.headers.get('set-cookie'), /Max-Age=0/);
});
test('M3U link imports live channels, films and series without returning credentials', async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async address => {
    const url = new URL(address);
    assert.equal(url.hostname, 'trsmart.net');
    if (url.pathname === '/player_api.php') return Response.json({user_info: {auth: 1}});
    if (url.pathname === '/get.php') return new Response('#EXTM3U\n#EXTINF:-1 group-title="Ulusal",Kanal\nhttp://trsmart.net/live/test-user/test-password/42.ts\n#EXTINF:-1 group-title="Aksiyon Filmler",Film\nhttp://trsmart.net/movie/test-user/test-password/43.mp4\n#EXTINF:-1 group-title="Diziler",Dizi\nhttp://trsmart.net/series/test-user/test-password/44.mp4');
    throw new Error('Unexpected URL');
  };
  try {
    const response = await handleRequest(new Request(origin + '/api/iptv/playlist', {
      method: 'POST', headers: {'Content-Type': 'application/json', Origin: origin},
      body: JSON.stringify({url: 'http://trsmart.net/get.php?username=test-user&password=test-password&type=m3u_plus'}),
    }), env);
    assert.equal(response.status, 200);
    const result = await response.json();
    assert.deepEqual(result.channels.map(c => c.kind), ['live','movies','series']);
    assert.equal(result.channels[0].hls, true);
    assert.equal(result.channels[0].url, origin + '/api/iptv/play/live/42.m3u8');
    assert.ok(!JSON.stringify(result).includes('test-password'));
    assert.ok(!JSON.stringify(result).includes('test-user'));
    assert.match(response.headers.get('set-cookie'), /HttpOnly/);
  } finally { globalThis.fetch = original; }
});
test('Readiness reports configuration without exposing secrets', async () => {
  const missing = await (await handleRequest(new Request(origin + '/api/iptv/status'), {})).json();
  const ready = await (await handleRequest(new Request(origin + '/api/iptv/status'), env)).json();
  assert.equal(missing.ready, false);
  assert.equal(ready.ready, true);
  assert.ok(!JSON.stringify(ready).includes(env.IPTV_SESSION_SECRET));
});
test('Provider response format failures are returned as diagnostic codes without raw content', async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async () => new Response('<html>sensitive provider response</html>');
  try {
    const response = await handleRequest(openRequest(), env);
    const result = await response.json();
    assert.equal(result.code, 'PROVIDER_INVALID_RESPONSE');
    assert.ok(!JSON.stringify(result).includes('sensitive'));
  } finally { globalThis.fetch = original; }
});
