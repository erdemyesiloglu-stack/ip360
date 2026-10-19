import {webUrl, parseM3U, readRemote, loadXtream, filterChannels, contentType, channelCategory, sectionCategories, artworkUrl} from './core.js';
import {saveSource, getSavedSource, deleteSavedSource} from './storage.js';

const $ = id => document.getElementById(id);
const state = {channels: [], selected: null, group: '', query: '', favoritesOnly: false, limit: 100, mode: 'url', busy: false, section: 'live', expandedSection: null, view: 'player'};
const sections = {
  live: {label: 'Kanallar', search: 'Kanal ara…', empty: 'Bu kaynakta kanal bulunamadı', item: 'kanal'},
  movies: {label: 'Filmler', search: 'Film ara…', empty: 'Bu kaynakta film bulunamadı', item: 'film'},
  series: {label: 'Diziler', search: 'Dizi ara…', empty: 'Bu kaynakta dizi bulunamadı', item: 'dizi'},
};
let favorites;
try { favorites = new Set(JSON.parse(localStorage.getItem('akis-favorites-v1') || '[]').filter(x => typeof x === 'string' && /^[a-f0-9]{64}$/.test(x))); }
catch { favorites = new Set(); }
const video = $('video');
let hls, hlsPromise, attempt = 0, waitTimer, installPrompt, sourceGeneration = 0;

function message(text) { $('message').textContent = text; $('message').hidden = !text; }
function status(text) { $('play-state').textContent = text; }
function saveFavorites() {
  try { localStorage.setItem('akis-favorites-v1', JSON.stringify([...favorites])); }
  catch { message('Tarayıcı favorileri kaydedemedi. Seçimlerin bu oturumda kullanılabilir.'); }
}
function friendlyError(error) {
  const allowed = [
    'Geçerli bir HTTP/HTTPS adresi girin.', 'Listede desteklenen bir HTTP/HTTPS yayını bulunamadı.',
    'Bu güvenli sayfada HTTPS yayın adresi gerekiyor. Sağlayıcınızdan HTTPS bağlantısı isteyin.',
    'Sunucu isteği reddetti. Adresi ve hesap bilgilerini kontrol edin.',
    'Liste çok büyük. En fazla 20 MB destekleniyor.', 'Kullanıcı adı ve şifre gerekli.',
    'Xtream hesabı doğrulanamadı.', 'Kanal listesi alınamadı.', 'Hesapta canlı kanal bulunamadı.',
    'Önce bir M3U dosyası seçin.', 'M3U veya M3U8 dosyası seçin.',
    'HLS dosyası yerine yayının HTTPS bağlantısını ekleyin.',
  ];
  return allowed.includes(error.message) ? error.message : 'Kaynak yüklenemedi. Adresi, bağlantını ve sağlayıcının HTTPS/CORS desteğini kontrol et.';
}
function openSource() { $('form-error').hidden = true; $('source-dialog').showModal(); }
for (const id of ['add-source', 'start-source', 'list-source']) $(id).addEventListener('click', openSource);
$('close-source').onclick = () => $('source-dialog').close();
$('source-dialog').addEventListener('close', () => { $('password').value = ''; });
for (const id of ['help-open', 'privacy-open']) $(id).onclick = () => $('help-dialog').showModal();
$('close-help').onclick = () => $('help-dialog').close();
document.querySelectorAll('[data-tab]').forEach(button => button.onclick = () => {
  if (state.busy) return;
  state.mode = button.dataset.tab;
  document.querySelectorAll('[data-tab]').forEach(b => b.setAttribute('aria-selected', String(b === button)));
  for (const tab of ['url', 'file', 'xtream']) $(`${tab}-fields`).hidden = state.mode !== tab;
  $('form-error').hidden = true;
});

function stop() {
  attempt++; clearTimeout(waitTimer); hls?.destroy(); hls = null;
  video.pause(); video.removeAttribute('src'); video.load();
}
async function identify(channels) {
  const identified = [];
  // Bound simultaneous crypto jobs for large provider lists.
  for (let i = 0; i < channels.length; i += 250) {
    identified.push(...await Promise.all(channels.slice(i, i + 250).map(async c => ({...c,
      id: [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(c.url)))].map(b => b.toString(16).padStart(2, '0')).join(''),
    }))));
  }
  return identified;
}
async function setChannels(channels, label, expectedGeneration = null) {
  const identified = await identify(channels);
  if (expectedGeneration !== null && expectedGeneration !== sourceGeneration) return;
  stop();
  state.channels = identified; state.selected = null; state.group = ''; state.query = ''; state.limit = 100;
  state.section = 'live';
  state.view = 'catalog';
  state.expandedSection = null;
  state.favoritesOnly = false;
  $('search').value = ''; $('category').replaceChildren(new Option('Tüm kategoriler', ''));
  updateSectionCategories();
  $('source-meta').textContent = label;
  $('clear').hidden = false; $('welcome').hidden = false; video.hidden = true;
  $('current-name').textContent = 'İzlemek için bir kanal seç';
  $('current-group').textContent = 'AKIŞ OYNATICI';
  $('retry').hidden = true; status('HAZIR'); message(''); updateFilters(); render();
}

$('source-form').addEventListener('submit', async e => {
  e.preventDefault(); if (state.busy) return;
  state.busy = true;
  sourceGeneration++;
  for (const id of ['clear', 'demo', 'forget-source']) $(id).disabled = true;
  $('submit-source').disabled = true; $('submit-source').textContent = 'Kanallar yükleniyor…';
  $('form-error').hidden = true;
  try {
    let channels, source;
    if (state.mode === 'url') {
      const url = webUrl($('playlist-url').value);
      const text = await readRemote(url);
      channels = parseM3U(text, url);
      source = {mode: 'url', url: url.href};
    } else if (state.mode === 'file') {
      const file = $('playlist-file').files[0];
      if (!file) throw new Error('Önce bir M3U dosyası seçin.');
      if (!/\.m3u8?$/i.test(file.name)) throw new Error('M3U veya M3U8 dosyası seçin.');
      if (file.size > 20 * 1024 * 1024) throw new Error('Liste çok büyük. En fazla 20 MB destekleniyor.');
      channels = parseM3U(await file.text());
      source = {mode: 'file', channels};
    } else {
      source = {mode: 'xtream', server: $('server').value, username: $('username').value.trim(), password: $('password').value};
      channels = await loadXtream(source.server, source.username, source.password);
    }
    await setChannels(channels, state.mode === 'xtream' ? 'Xtream Codes · Canlı yayınlar' : 'M3U · Kişisel kanal listesi');
    try {
      if ($('remember-source').checked) {
        await saveSource(source);
        message('Kaynak bu cihaza kaydedildi. Yeniden açtığında otomatik yüklenecek.');
      } else {
        await deleteSavedSource();
      }
    } catch {
      message('Tarayıcı kaynak kaydını güncelleyemedi. Önceki kayıt varsa korunmuş olabilir; bu listeyi bu oturumda kullanabilirsin.');
    }
    $('source-form').reset(); $('source-dialog').close();
  } catch (error) {
    $('form-error').textContent = friendlyError(error); $('form-error').hidden = false;
  } finally {
    state.busy = false; $('submit-source').disabled = false; $('submit-source').textContent = 'Kanalları yükle →';
    for (const id of ['clear', 'demo', 'forget-source']) $(id).disabled = false;
  }
});

function updateFilters() {
  $('all-filter').classList.toggle('active', !state.favoritesOnly);
  $('fav-filter').classList.toggle('active', state.favoritesOnly);
  document.querySelectorAll('[data-section]').forEach(button => {
    const active = button.dataset.section === state.section;
    button.classList.toggle('rail-active', active);
    if (active) button.setAttribute('aria-current', 'page');
    else button.removeAttribute('aria-current');
  });
  $('fav-nav').classList.toggle('rail-active', state.favoritesOnly);
  $('fav-nav').setAttribute('aria-pressed', String(state.favoritesOnly));
  $('section-title').textContent = sections[state.section].label;
  $('search').placeholder = sections[state.section].search;
  $('search').setAttribute('aria-label', sections[state.section].search.replace('…', ''));
  document.querySelectorAll('[data-section]').forEach(button => {
    button.setAttribute('aria-expanded', String(button.dataset.section === state.expandedSection));
  });
  for (const section of ['live', 'movies', 'series']) {
    $(`${section}-categories`).hidden = section !== state.expandedSection;
  }
}
function updateSectionCategories() {
  $('category').replaceChildren(new Option('Tüm kategoriler', ''));
  const options = sectionCategories(state.channels, state.section);
  options.forEach(c => $('category').add(new Option(`${c.label} (${c.count})`, c.label)));
  const menu = $(`${state.section}-categories`);
  menu.replaceChildren();
  const addOption = (label, value, count) => {
    const button = document.createElement('button');
    button.className = 'sub-category'; button.dataset.category = value;
    const text = document.createElement('span'); text.textContent = label;
    const badge = document.createElement('small'); badge.textContent = count;
    button.append(text, badge);
    button.onclick = () => {
      state.group = value; state.query = ''; state.limit = 100;
      $('search').value = ''; $('category').value = value; showCatalog();
    };
    menu.append(button);
  };
  addOption('Tümü', '', state.channels.filter(c => contentType(c) === state.section).length);
  options.forEach(c => addOption(c.label, c.label, c.count));
  $('category').value = state.group;
}
function selectSection(section) {
  state.expandedSection = state.expandedSection === section ? null : section;
  if (state.section !== section) {
    state.section = section; state.group = ''; state.query = ''; state.limit = 100;
    state.favoritesOnly = false; $('search').value = '';
  }
  updateSectionCategories(); updateFilters(); showCatalog();
}
document.querySelectorAll('[data-section]').forEach(button => {
  button.onclick = () => selectSection(button.dataset.section);
});
function render() {
  const catalog = state.view === 'catalog';
  $('dashboard').classList.toggle('catalog-view', catalog);
  $('channel-list').classList.toggle('catalog-grid', catalog);
  $('channel-list').classList.toggle('logo-grid', catalog && state.section === 'live');
  $('back-catalog').hidden = catalog || !state.channels.length;
  $('page-title').textContent = catalog ? (state.group || sections[state.section].label) : 'İyi seyirler.';
  $('page-subtitle').textContent = catalog ? (state.section === 'live' ? 'İzlemek istediğin kanalı seç.' : 'İzlemek istediğin içeriği seç.') : 'Sevdiğin yayınlar, tek bir ekranda.';
  const entries = state.channels.filter(c => contentType(c) === state.section);
  const visible = filterChannels(entries, state.query, state.group, state.favoritesOnly, favorites, channelCategory);
  document.querySelectorAll('.sub-category').forEach(button => {
    const active = button.closest('.sub-categories').id === `${state.section}-categories` && button.dataset.category === state.group;
    button.classList.toggle('active', active);
    button.setAttribute('aria-pressed', String(active));
  });
  $('channel-count').textContent = visible.length;
  $('section-title').textContent = state.group || sections[state.section].label;
  $('list-footer').textContent = state.channels.length ? `${visible.length} ${sections[state.section].item} · Favoriler bu cihazda saklanır` : 'M3U & Xtream Codes desteği';
  const list = $('channel-list'); list.replaceChildren();
  if (!visible.length) {
    const empty = document.createElement('div'); empty.className = 'empty-list';
    const icon = document.createElement('span'); icon.textContent = state.favoritesOnly ? '☆' : '▤';
    const title = document.createElement('h3'); title.textContent = !state.channels.length ? 'Listen burada görünecek' : !entries.length ? sections[state.section].empty : state.group ? `${state.group}: içerik bulunamadı` : 'Eşleşen içerik bulunamadı';
    const hint = document.createElement('p'); hint.textContent = !state.channels.length ? 'Başlamak için kendi yayın kaynağını ekle.' : !entries.length ? 'Bu bölüme uygun içerik içeren bir M3U listesi ekleyebilirsin. Xtream girişi şu anda canlı kanalları yükler.' : 'Aramayı veya kategori filtresini değiştir.';
    empty.append(icon, title, hint);
    if (!state.channels.length) { const b = document.createElement('button'); b.className = 'text-button'; b.textContent = 'Kaynak ekle ↗'; b.onclick = openSource; empty.append(b); }
    list.classList.toggle('is-empty', true);
    list.append(empty); return;
  }
  list.classList.toggle('is-empty', false);
  for (const c of visible.slice(0, state.limit)) {
    const row = document.createElement('div'); row.className = `${catalog ? 'media-card' : 'channel-row'}${state.selected?.id === c.id ? ' selected' : ''}`;
    const pick = document.createElement('button'); pick.className = catalog ? 'media-pick' : 'channel-pick'; pick.onclick = () => play(c);
    pick.setAttribute('aria-label', `${c.name} oynat`);
    const avatar = document.createElement('span'); avatar.className = catalog ? `media-art ${state.section === 'live' ? 'logo-art' : 'poster-art'}` : 'channel-avatar';
    const fallback = document.createElement('span'); fallback.className = 'art-fallback';
    const initial = document.createElement('strong'); initial.textContent = c.name.slice(0, 2).toLocaleUpperCase('tr');
    const missing = document.createElement('small'); missing.textContent = state.section === 'live' ? 'Logo yok' : 'Afiş yok';
    fallback.append(initial); if (catalog) fallback.append(missing);
    avatar.append(fallback);
    const imageUrl = artworkUrl(c.poster || c.logo);
    if (imageUrl && !(location.protocol === 'https:' && new URL(imageUrl).protocol !== 'https:')) {
      const image = document.createElement('img');
      image.alt = ''; image.loading = 'lazy'; image.decoding = 'async'; image.referrerPolicy = 'no-referrer';
      image.onload = () => { fallback.hidden = true; };
      image.onerror = () => { image.remove(); fallback.hidden = false; };
      image.src = imageUrl; avatar.append(image);
    }
    if (catalog) {
      const overlay = document.createElement('span'); overlay.className = 'card-play'; overlay.textContent = '▶'; overlay.setAttribute('aria-hidden', 'true'); avatar.append(overlay);
    }
    const text = document.createElement('span'); text.className = 'channel-text';
    const title = document.createElement('strong'); title.textContent = c.name;
    const sub = document.createElement('small'); sub.textContent = c.group;
    text.append(title, sub); pick.append(avatar, text);
    const star = document.createElement('button'); star.className = `star${favorites.has(c.id) ? ' on' : ''}`;
    star.textContent = favorites.has(c.id) ? '★' : '☆';
    star.setAttribute('aria-label', `${c.name}: favori seçimi`); star.setAttribute('aria-pressed', String(favorites.has(c.id)));
    star.onclick = () => { favorites.has(c.id) ? favorites.delete(c.id) : favorites.add(c.id); saveFavorites(); render(); };
    row.append(pick, star); list.append(row);
  }
  if (visible.length > state.limit) {
    const more = document.createElement('button'); more.className = 'quiet'; more.style.width = '100%';
    more.textContent = 'Daha fazla içerik göster ↓'; more.classList.add('load-more'); more.onclick = () => { state.limit += 100; render(); }; list.append(more);
  }
}
function showCatalog() {
  if (state.view !== 'catalog') { stop(); status('HAZIR'); }
  state.view = 'catalog'; message(''); render();
}
$('back-catalog').onclick = showCatalog;
document.querySelector('.brand').onclick = e => { e.preventDefault(); if (state.channels.length) showCatalog(); };
function favoriteFilter(value) { state.favoritesOnly = value; state.limit = 100; updateFilters(); showCatalog(); }
$('all-filter').onclick = () => favoriteFilter(false);
$('fav-filter').onclick = $('fav-nav').onclick = () => favoriteFilter(true);
$('search').oninput = e => { state.query = e.target.value; state.limit = 100; render(); };
$('category').onchange = e => { state.group = e.target.value; state.limit = 100; showCatalog(); };
document.addEventListener('keydown', e => {
  if (e.key === '/' && !['INPUT', 'TEXTAREA', 'SELECT'].includes(document.activeElement.tagName) && !document.querySelector('dialog[open]')) {
    e.preventDefault(); $('search').focus();
  }
});

function loadHls() {
  if (globalThis.Hls) return Promise.resolve(globalThis.Hls);
  if (hlsPromise) return hlsPromise;
  hlsPromise = new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = 'https://cdn.jsdelivr.net/npm/hls.js@1.5.18/dist/hls.min.js';
    script.referrerPolicy = 'no-referrer';
    const timer = setTimeout(() => { script.remove(); reject(new Error('hls')); }, 18000);
    script.onload = () => { clearTimeout(timer); resolve(globalThis.Hls); };
    script.onerror = () => { clearTimeout(timer); script.remove(); reject(new Error('hls')); };
    document.head.append(script);
  }).catch(error => { hlsPromise = null; throw error; });
  return hlsPromise;
}
function playbackError() {
  clearTimeout(waitTimer); status('AÇILAMADI'); $('retry').hidden = false;
  message('Yayın açılamadı. Sağlayıcının HTTPS/CORS iznini ve HLS desteğini kontrol et. Bazı kodekler tarayıcıda oynatılamaz.');
}
function requestPlay(token) {
  if (token !== attempt) return;
  video.play().catch(error => {
    if (token !== attempt || error.name === 'AbortError') return;
    if (error.name === 'NotAllowedError') { status('BAŞLAT'); message('İzlemek için oynatıcının oynat düğmesine dokun.'); }
    else playbackError();
  });
}
async function play(channel) {
  stop(); const token = attempt;
  state.view = 'player';
  state.selected = channel;
  $('welcome').hidden = true; video.hidden = false; $('retry').hidden = true;
  $('current-name').textContent = channel.name; $('current-group').textContent = channel.group.toLocaleUpperCase('tr');
  status('BAĞLANIYOR'); message(''); render();
  try {
    const url = webUrl(channel.url);
    if (location.protocol === 'https:' && url.protocol !== 'https:') {
      status('HTTPS GEREKLİ'); message('Bu yayın HTTP kullanıyor. Sağlayıcından HTTPS yayın adresi iste.'); return;
    }
    waitTimer = setTimeout(() => { if (token === attempt) playbackError(); }, 30000);
    if (/\.m3u8(?:$|\?)/i.test(url.href) && !video.canPlayType('application/vnd.apple.mpegurl')) {
      const Hls = await loadHls(); if (token !== attempt) return;
      if (!Hls?.isSupported()) { playbackError(); return; }
      hls = new Hls({enableWorker: true, xhrSetup: xhr => { xhr.withCredentials = false; }});
      hls.on(Hls.Events.ERROR, (_, data) => { if (data.fatal && token === attempt) { hls?.destroy(); hls = null; playbackError(); } });
      hls.on(Hls.Events.MANIFEST_PARSED, () => requestPlay(token));
      hls.loadSource(url.href); hls.attachMedia(video);
    } else { video.src = url.href; requestPlay(token); }
  } catch { if (token === attempt) playbackError(); }
}
video.addEventListener('playing', () => { if (!state.selected) return; clearTimeout(waitTimer); status('OYNATILIYOR'); message(''); $('retry').hidden = true; });
video.addEventListener('waiting', () => { if (state.selected) status('YÜKLENİYOR'); });
video.addEventListener('pause', () => { if (state.selected && video.currentSrc) status('DURAKLATILDI'); });
video.addEventListener('ended', () => status('BİTTİ'));
video.addEventListener('error', () => { if (video.getAttribute('src') && state.selected) playbackError(); });
$('retry').onclick = () => { if (state.selected) play(state.selected); };
$('demo').onclick = async () => {
  sourceGeneration++;
  await setChannels([
    {name: 'HLS · Açık test yayını', group: 'Demo · Açık test içerikleri', url: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8'},
    {name: 'Big Buck Bunny · Kısa film', kind: 'movies', group: 'Demo · Açık test içerikleri', url: 'https://storage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4'},
  ], 'Demo · Herkese açık test içerikleri');
  await play(state.channels[0]);
};
$('clear').onclick = () => {
  sourceGeneration++;
  stop(); state.channels = []; state.selected = null; state.query = ''; state.group = ''; state.favoritesOnly = false;
  state.view = 'player';
  $('search').value = ''; $('category').replaceChildren(new Option('Tüm kategoriler', ''));
  $('source-meta').textContent = 'Henüz kaynak eklenmedi'; $('clear').hidden = true;
  $('welcome').hidden = false; video.hidden = true; $('retry').hidden = true;
  $('current-name').textContent = 'Henüz bir kanal seçilmedi'; $('current-group').textContent = 'AKIŞ OYNATICI';
  message(''); status('HAZIR'); updateSectionCategories(); updateFilters(); render();
  deleteSavedSource().catch(() => message('Ekran temizlendi ancak cihazdaki kaynak kaydı silinemedi. Tarayıcı site verilerini temizleyebilirsin.'));
};
$('forget-source').onclick = async () => {
  sourceGeneration++;
  try { await deleteSavedSource(); $('forget-source').textContent = 'Kayıtlı kaynak silindi'; }
  catch { message('Kayıt silinemedi. Tarayıcı site verilerini temizleyebilirsin.'); }
};
$('forget').onclick = () => { favorites.clear(); saveFavorites(); render(); $('forget').textContent = 'Bu cihazdaki favoriler silindi'; };
window.addEventListener('beforeinstallprompt', e => { e.preventDefault(); installPrompt = e; $('install').hidden = false; });
$('install').onclick = async () => {
  if (!installPrompt) return;
  await installPrompt.prompt(); installPrompt = null; $('install').hidden = true;
};
if (['http:', 'https:'].includes(location.protocol) && 'serviceWorker' in navigator) {
  navigator.serviceWorker.register('./sw.js').catch(() => {});
}
updateSectionCategories(); updateFilters(); render();
async function restoreSource() {
  const generation = sourceGeneration;
  try {
    const source = await getSavedSource();
    if (!source || generation !== sourceGeneration) return;
    message('Kayıtlı kaynak yükleniyor…');
    let channels;
    if (source.mode === 'url') channels = parseM3U(await readRemote(source.url), source.url);
    else if (source.mode === 'xtream') channels = await loadXtream(source.server, source.username, source.password);
    else channels = source.channels;
    if (generation !== sourceGeneration) return;
    await setChannels(channels, source.mode === 'xtream' ? 'Xtream Codes · Kayıtlı kaynak' : 'M3U · Kayıtlı kaynak', generation);
    if (generation === sourceGeneration) message('Kayıtlı kaynak yüklendi. İzlemek için bir içerik seç.');
  } catch {
    if (generation === sourceGeneration) message('Kayıtlı kaynak yüklenemedi veya bu tarayıcıda kayıt desteği yok. Kaynak ekle üzerinden yeniden deneyebilirsin.');
  }
}
restoreSource();
