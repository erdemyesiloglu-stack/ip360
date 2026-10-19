const COOKIE = 'ip360_relay';
const TTL = 2 * 60 * 60 * 1000;
const HOST = 'trsmart.net';

function failure(status, message, code = 'RELAY_ERROR') {
  return Response.json({message, code}, {status, headers: {'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer'}});
}
function allowed(value) {
  const url = new URL(value);
  if (url.hostname !== HOST || url.username || url.password || !['http:', 'https:'].includes(url.protocol) ||
      !['', '80', '443', '8080', '8443'].includes(url.port)) throw new Error('Forbidden upstream');
  return url;
}
function encode(bytes) { return btoa(String.fromCharCode(...bytes)).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, ''); }
function decode(value) {
  if (!/^[A-Za-z0-9_-]+$/.test(value) || value.length > 16000) throw new Error('Invalid token');
  return Uint8Array.from(atob(value.replaceAll('-', '+').replaceAll('_', '/')), c => c.charCodeAt(0));
}
async function encryptionKey(secret) {
  const hash = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(secret));
  return crypto.subtle.importKey('raw', hash, 'AES-GCM', false, ['encrypt', 'decrypt']);
}
async function seal(value, key, purpose) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const data = await crypto.subtle.encrypt({name: 'AES-GCM', iv, additionalData: new TextEncoder().encode(purpose)}, key,
    new TextEncoder().encode(JSON.stringify(value)));
  return encode(new Uint8Array([...iv, ...new Uint8Array(data)]));
}
async function unseal(value, key, purpose) {
  const bytes = decode(value);
  const plain = await crypto.subtle.decrypt({name: 'AES-GCM', iv: bytes.slice(0, 12), additionalData: new TextEncoder().encode(purpose)}, key, bytes.slice(12));
  const data = JSON.parse(new TextDecoder().decode(plain));
  if (!Number.isFinite(data.expires) || data.expires <= Date.now()) throw new Error('Expired token');
  return data;
}
async function upstream(url, headers = {}, method = 'GET') {
  let target = allowed(url);
  for (let i = 0; i < 4; i++) {
    const response = await fetch(target.href, {method, headers, redirect: 'manual', signal: AbortSignal.timeout(25000)});
    if (![301, 302, 303, 307, 308].includes(response.status)) return {response, url: target};
    const location = response.headers.get('location');
    await response.body?.cancel();
    if (!location) throw new Error('Invalid redirect');
    target = allowed(new URL(location, target));
  }
  throw new Error('Too many redirects');
}
async function limitedText(response, limit) {
  if (Number(response.headers.get('content-length')) > limit) { await response.body?.cancel(); throw new Error('Response too large'); }
  const reader = response.body?.getReader();
  if (!reader) return '';
  const decoder = new TextDecoder(); let size = 0, text = '';
  try {
    while (true) {
      const {value, done} = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > limit) { await reader.cancel(); throw new Error('Response too large'); }
      text += decoder.decode(value, {stream: true});
    }
    return text + decoder.decode();
  } finally { reader.releaseLock(); }
}
async function providerApi(session, action) {
  const url = new URL('player_api.php', session.server);
  url.search = new URLSearchParams({username: session.username, password: session.password, ...(action ? {action} : {})});
  const {response} = await upstream(url);
  if (!response.ok) { await response.body?.cancel(); throw new Error('Provider unavailable'); }
  return JSON.parse(await limitedText(response, 20 * 1024 * 1024));
}
async function mediaAddress(target, session, key, origin) {
  const url = allowed(target);
  const token = await seal({url: url.href, sessionId: session.id, expires: session.expires}, key, `${origin}:media`);
  return `${origin}/api/iptv/media?t=${token}`;
}
async function rewritePlaylist(text, base, session, key, origin) {
  const lines = [];
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (line && !line.startsWith('#')) {
      lines.push(await mediaAddress(new URL(line, base), session, key, origin));
    } else if (line.startsWith('#')) {
      let output = raw;
      for (const match of [...raw.matchAll(/URI="([^"]+)"/g)]) {
        const address = await mediaAddress(new URL(match[1], base), session, key, origin);
        output = output.replace(match[0], `URI="${address}"`);
      }
      lines.push(output);
    } else lines.push(raw);
  }
  return lines.join('\n');
}

export async function handleRequest(request, env) {
  const url = new URL(request.url);
  if (!url.pathname.startsWith('/api/iptv/')) return env.ASSETS ? env.ASSETS.fetch(request) : new Response('Not found', {status: 404});
  if (request.headers.get('sec-fetch-site') === 'cross-site') return failure(403, 'Bu bağlantıya izin verilmedi.');
  if (url.pathname === '/api/iptv/close') {
    if (request.method !== 'POST' || request.headers.get('origin') !== url.origin) return failure(403, 'Bu bağlantıya izin verilmedi.');
    return Response.json({ok: true}, {headers: {'Cache-Control': 'no-store', 'Set-Cookie': `${COOKIE}=; Path=/api/iptv; Max-Age=0; HttpOnly; Secure; SameSite=Strict`}});
  }
  if (typeof env.IPTV_SESSION_SECRET !== 'string' || env.IPTV_SESSION_SECRET.length < 32) {
    return failure(503, 'HTTP bağlantı desteği için sunucu yapılandırması tamamlanmalı.', 'RELAY_NOT_CONFIGURED');
  }
  const key = await encryptionKey(env.IPTV_SESSION_SECRET);
  if (url.pathname === '/api/iptv/open') {
    if (request.method !== 'POST') return failure(405, 'İstek yöntemi desteklenmiyor.');
    if (request.headers.get('origin') !== url.origin || !request.headers.get('content-type')?.startsWith('application/json')) return failure(403, 'Bu bağlantıya izin verilmedi.');
    let input;
    try { input = JSON.parse(await limitedText(request, 8192)); } catch { return failure(400, 'Hesap bilgileri okunamadı.'); }
    let server;
    try { server = allowed(input.server); } catch { return failure(400, 'Aracı bağlantı şu anda yalnızca trsmart.net için kullanılabilir.'); }
    if (server.pathname !== '/' || !input.username || !input.password ||
        typeof input.username !== 'string' || typeof input.password !== 'string' || input.username.length > 256 || input.password.length > 256) {
      return failure(400, 'Sunucu adresini ve hesap bilgilerini kontrol edin.');
    }
    const session = {id: crypto.randomUUID(), server: server.origin + '/', username: input.username, password: input.password, expires: Date.now() + TTL};
    try {
      const auth = await providerApi(session);
      if (String(auth?.user_info?.auth) !== '1') return failure(401, 'Xtream hesabı doğrulanamadı.');
      const token = await seal(session, key, `${url.origin}:session`);
      return Response.json({ok: true}, {headers: {'Cache-Control': 'no-store', 'Set-Cookie': `${COOKIE}=${token}; Path=/api/iptv; Max-Age=7200; HttpOnly; Secure; SameSite=Strict`}});
    } catch { return failure(502, 'Sağlayıcıya aracı bağlantı kurulamadı.'); }
  }
  if (request.method !== 'GET') return failure(405, 'İstek yöntemi desteklenmiyor.');
  const token = request.headers.get('cookie')?.split(';').map(c => c.trim()).find(c => c.startsWith(`${COOKIE}=`))?.slice(COOKIE.length + 1);
  let session;
  try { session = await unseal(token || '', key, `${url.origin}:session`); allowed(session.server); }
  catch { return failure(401, 'Aracı oturumu sona erdi. Kaynağı yeniden yükleyin.'); }
  try {
    if (url.pathname === '/api/iptv/api') {
      const action = url.searchParams.get('action');
      if (!['get_live_categories', 'get_live_streams'].includes(action)) return failure(400, 'Desteklenmeyen katalog isteği.');
      const result = await providerApi(session, action);
      if (!Array.isArray(result)) return failure(502, 'Kanal listesi alınamadı.');
      const output = [];
      for (const row of result) {
        if (action === 'get_live_categories') { output.push({category_id: row.category_id, category_name: row.category_name}); continue; }
        if (!/^\d+$/.test(String(row.stream_id))) continue;
        const path = `live/${encodeURIComponent(session.username)}/${encodeURIComponent(session.password)}/${row.stream_id}.m3u8`;
        let logo = '';
        try {
          const image = new URL(row.stream_icon);
          if (image.protocol === 'https:') logo = image.href;
          else if (image.hostname === HOST) logo = await mediaAddress(image, session, key, url.origin);
        } catch { /* Missing artwork. */ }
        output.push({stream_id: row.stream_id, category_id: row.category_id, name: row.name,
          stream_icon: logo, relay_url: await mediaAddress(new URL(path, session.server), session, key, url.origin)});
      }
      return Response.json(output, {headers: {'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer'}});
    }
    if (url.pathname === '/api/iptv/media') {
      const target = await unseal(url.searchParams.get('t') || '', key, `${url.origin}:media`);
      if (target.sessionId !== session.id) return failure(403, 'Bu yayına erişim izni yok.');
      const range = request.headers.get('range');
      const {response, url: finalUrl} = await upstream(target.url, range ? {Range: range} : {});
      if (!response.ok) { await response.body?.cancel(); return failure(502, 'Yayın sağlayıcısı yanıt vermedi.'); }
      const type = response.headers.get('content-type') || 'application/octet-stream';
      if (/mpegurl/i.test(type) || /\.m3u8$/i.test(finalUrl.pathname)) {
        const raw = await limitedText(response, 2 * 1024 * 1024);
        if (!raw.trimStart().startsWith('#EXTM3U')) throw new Error('Not an HLS playlist');
        const playlist = await rewritePlaylist(raw, finalUrl, session, key, url.origin);
        return new Response(playlist, {headers: {'Content-Type': 'application/vnd.apple.mpegurl', 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer', 'X-Content-Type-Options': 'nosniff'}});
      }
      const safeType = /^(video\/|audio\/|image\/(png|jpeg|gif|webp|avif|bmp|x-icon)(;|$))/i.test(type) ? type : 'application/octet-stream';
      const headers = new Headers({'Content-Type': safeType, 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer', 'X-Content-Type-Options': 'nosniff', 'Content-Security-Policy': "default-src 'none'; sandbox"});
      for (const name of ['content-length', 'content-range', 'accept-ranges']) if (response.headers.has(name)) headers.set(name, response.headers.get(name));
      return new Response(response.body, {status: response.status, headers});
    }
    return failure(404, 'Bağlantı bulunamadı.');
  } catch { return failure(502, 'Aracı bağlantı isteği tamamlanamadı.'); }
}
export default {fetch: handleRequest};
