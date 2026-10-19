export function webUrl(value, base) {
  const url = new URL(value.trim(), base);
  if (!['https:', 'http:'].includes(url.protocol) || url.username || url.password) throw new Error('Geçerli bir HTTP/HTTPS adresi girin.');
  return url;
}

export function artworkUrl(value, base) {
  if (!value || typeof value !== 'string') return '';
  try { return webUrl(value, base).href; } catch { return ''; }
}

export function parseM3U(text, base) {
  if (/^#EXT-X-(?:TARGETDURATION|STREAM-INF|MEDIA-SEQUENCE):/m.test(text)) {
    if (!base) throw new Error('HLS dosyası yerine yayının HTTPS bağlantısını ekleyin.');
    return [{name: 'HLS yayını', group: 'Doğrudan yayın', url: webUrl(String(base)).href}];
  }
  const channels = [];
  let name = '', group = 'Diğer', logo = '';
  for (const raw of text.replace(/^\uFEFF/, '').split(/\r?\n/)) {
    const line = raw.trim();
    if (line.startsWith('#EXTINF:')) {
      group = /group-title="([^"]*)"/.exec(line)?.[1] || 'Diğer';
      logo = artworkUrl(/tvg-logo="([^"]*)"/.exec(line)?.[1], base);
      let quote = false;
      name = '';
      for (let i = 0; i < line.length; i++) {
        if (line[i] === '"') quote = !quote;
        if (line[i] === ',' && !quote) { name = line.slice(i + 1).trim(); break; }
      }
    } else if (line && !line.startsWith('#')) {
      try {
        channels.push({name: name || `Kanal ${channels.length + 1}`, group, url: webUrl(line, base).href, ...(logo ? {logo} : {})});
      } catch { /* Unsupported URLs are skipped. */ }
      name = ''; group = 'Diğer'; logo = '';
    }
  }
  if (!channels.length) throw new Error('Listede desteklenen bir HTTP/HTTPS yayını bulunamadı.');
  return channels;
}

export async function readRemote(url, json = false, fetcher = fetch) {
  const target = webUrl(String(url));
  if (globalThis.location?.protocol === 'https:' && target.protocol !== 'https:') {
    throw new Error('Bu güvenli sayfada HTTPS yayın adresi gerekiyor. Sağlayıcınızdan HTTPS bağlantısı isteyin.');
  }
  const response = await fetcher(target.href, {signal: AbortSignal.timeout(25000), credentials: 'omit', referrerPolicy: 'no-referrer'});
  if (!response.ok) throw new Error('Sunucu isteği reddetti. Adresi ve hesap bilgilerini kontrol edin.');
  const maxBytes = 20 * 1024 * 1024;
  if (Number(response.headers.get('content-length')) > maxBytes) {
    await response.body?.cancel();
    throw new Error('Liste çok büyük. En fazla 20 MB destekleniyor.');
  }
  // Enforce the limit while downloading, including chunked responses.
  const reader = response.body?.getReader();
  const decoder = new TextDecoder();
  let text = '', received = 0;
  if (reader) {
    try {
      while (true) {
        const {done, value} = await reader.read();
        if (done) break;
        received += value.byteLength;
        if (received > maxBytes) {
          await reader.cancel();
          throw new Error('Liste çok büyük. En fazla 20 MB destekleniyor.');
        }
        text += decoder.decode(value, {stream: true});
      }
      text += decoder.decode();
    } finally { reader.releaseLock(); }
  }
  return json ? JSON.parse(text) : text;
}

export async function loadXtream(server, username, password, reader = readRemote) {
  const root = webUrl(server);
  root.search = ''; root.hash = '';
  if (!root.pathname.endsWith('/')) root.pathname += '/';
  if (!username || !password) throw new Error('Kullanıcı adı ve şifre gerekli.');
  const api = (action) => {
    const url = new URL('player_api.php', root);
    url.search = new URLSearchParams({username, password, ...(action ? {action} : {})});
    return reader(url, true);
  };
  const auth = await api();
  if (String(auth?.user_info?.auth) !== '1') throw new Error('Xtream hesabı doğrulanamadı.');
  const categories = await api('get_live_categories');
  const names = new Map(Array.isArray(categories) ? categories.map(c => [String(c.category_id), String(c.category_name || 'Diğer')]) : []);
  const streams = await api('get_live_streams');
  if (!Array.isArray(streams)) throw new Error('Kanal listesi alınamadı.');
  const channels = streams.filter(c => /^\d+$/.test(String(c.stream_id))).map(c => ({
    kind: 'live',
    name: String(c.name || 'Kanal'), group: names.get(String(c.category_id)) || 'Diğer',
    ...(artworkUrl(c.stream_icon, root) ? {logo: artworkUrl(c.stream_icon, root)} : {}),
    url: new URL(`live/${encodeURIComponent(username)}/${encodeURIComponent(password)}/${c.stream_id}.m3u8`, root).href,
  }));
  if (!channels.length) throw new Error('Hesapta canlı kanal bulunamadı.');
  return channels;
}

export function filterChannels(channels, query, group, favoritesOnly, favorites, categoryOf = c => c.group) {
  const term = query.toLocaleLowerCase('tr');
  return channels.filter(c => (!group || categoryOf(c) === group) &&
    (!favoritesOnly || favorites.has(c.id)) && c.name.toLocaleLowerCase('tr').includes(term));
}

export function contentType(channel) {
  if (['live', 'movies', 'series'].includes(channel.kind)) return channel.kind;
  const group = (channel.group || '').toLocaleLowerCase('tr');
  let path = '';
  try { path = new URL(channel.url).pathname.toLowerCase(); } catch { /* No path hint. */ }
  if (/(?:^|\/)series\//.test(path) || /(?:dizi|series|tv shows)/.test(group)) return 'series';
  if (/(?:^|\/)movie\//.test(path) || /(?:film|movies|sinema|vod)/.test(group)) return 'movies';
  return 'live';
}

function categoryText(value) {
  return String(value || '').toLocaleLowerCase('tr').normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '').replace(/ı/g, 'i').replace(/[^a-z0-9]+/g, ' ').trim();
}

export const LIVE_CATEGORIES = ['Ulusal', 'Spor', 'Haber', 'Belgesel', 'Çocuk', 'Müzik'];
export const VOD_CATEGORIES = ['Aksiyon', 'Komedi', 'Dram', 'Bilim Kurgu', 'Korku', 'Gerilim', 'Animasyon', 'Belgesel'];

export function channelCategory(channel) {
  const group = categoryText(channel.group);
  if (contentType(channel) !== 'live') {
    const genres = [
      ['Bilim Kurgu', /\b(bilim kurgu|science fiction|sci fi|scifi)\b/],
      ['Aksiyon', /\b(aksiyon|action)\b/],
      ['Komedi', /\b(komedi|comedy|sitcom)\b/],
      ['Dram', /\b(dram|drama)\b/],
      ['Korku', /\b(korku|horror)\b/],
      ['Gerilim', /\b(gerilim|thriller)\b/],
      ['Animasyon', /\b(animasyon|animation|animated|anime)\b/],
      ['Belgesel', /\b(belgesel|documentary|documentaries)\b/],
    ];
    return genres.find(([, pattern]) => pattern.test(group))?.[0] || channel.group || 'Diğer';
  }
  const match = value => {
    if (/\b(spor|sport|sports|sportif)\b/.test(value)) return 'Spor';
    if (/\b(haber|news)\b/.test(value)) return 'Haber';
    if (/\b(belgesel|documentary|documentaries|docu|national geographic|nat geo|natgeo|discovery|animal planet|viasat)\b/.test(value)) return 'Belgesel';
    if (/\b(cocuk|kids|children|cartoon)\b/.test(value)) return 'Çocuk';
    if (/\b(muzik|music)\b/.test(value)) return 'Müzik';
    if (/\b(ulusal|national|genel|general)\b/.test(value)) return 'Ulusal';
    return null;
  };
  const knownGroup = match(group);
  if (knownGroup) return knownGroup;
  const name = categoryText(channel.name).replace(/\b(uhd|fhd|hd|sd|4k|tr)\b/g, '').trim();
  const knownName = match(name);
  if (knownName) return knownName;
  if (/\b(bein sports?|eurosport|s sport|tivibu spor)\b/.test(name)) return 'Spor';
  if (/\b(ntv|cnn|bloomberg|haberturk|tele 1|tele1)\b/.test(name)) return 'Haber';
  if (/\b(discovery|national geographic|nat geo|natgeo|animal planet|viasat)\b/.test(name)) return 'Belgesel';
  if (/\b(nickelodeon|minika|baby tv|babytv|disney junior)\b/.test(name)) return 'Çocuk';
  if (/^(trt 1|trt1|kanal d|show tv|show|star tv|star|atv|tv8|now|fox|kanal 7|teve2|beyaz tv|tv 360|360)(\s|$)/.test(name)) return 'Ulusal';
  if (!group || /^(diger|tr|turkiye|turkey|turkish|kanallar|canli|live|tumu|tum kanallar)$/.test(group)) return 'Diğer';
  return channel.group;
}

export function sectionCategories(channels, section) {
  const entries = channels.filter(c => contentType(c) === section);
  const defaults = section === 'live' ? LIVE_CATEGORIES : VOD_CATEGORIES;
  const counts = new Map(defaults.map(label => [label, 0]));
  for (const channel of entries) {
    const category = channelCategory(channel);
    counts.set(category, (counts.get(category) || 0) + 1);
  }
  return [...counts].map(([label, count]) => ({label, count}));
}
