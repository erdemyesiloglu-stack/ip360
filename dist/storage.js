// The key and encrypted record stay in this browser's IndexedDB.
// This protects against plain-text storage, not access by another user of this browser.
export async function sealSource(source) {
  const key = await crypto.subtle.generateKey({name: 'AES-GCM', length: 256}, false, ['encrypt', 'decrypt']);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const data = await crypto.subtle.encrypt({name: 'AES-GCM', iv}, key,
    new TextEncoder().encode(JSON.stringify(source)));
  return {version: 1, key, iv, data};
}

export async function unsealSource(record) {
  if (!record || record.version !== 1) throw new Error('Invalid saved source');
  const plain = await crypto.subtle.decrypt({name: 'AES-GCM', iv: record.iv}, record.key, record.data);
  const source = JSON.parse(new TextDecoder().decode(plain));
  if (!['url', 'file', 'xtream'].includes(source.mode)) throw new Error('Invalid saved source');
  if (source.mode === 'url' && typeof source.url !== 'string') throw new Error('Invalid saved source');
  if (source.mode === 'xtream' && !['server', 'username', 'password'].every(k => typeof source[k] === 'string')) throw new Error('Invalid saved source');
  if (source.mode === 'file' && !Array.isArray(source.channels)) throw new Error('Invalid saved source');
  return source;
}

function sourceRecord(operation, value) {
  return new Promise((resolve, reject) => {
    const opening = indexedDB.open('akis-sources-v1', 1);
    opening.onupgradeneeded = () => opening.result.createObjectStore('vault');
    opening.onerror = () => reject(opening.error);
    opening.onblocked = () => reject(new Error('Storage unavailable'));
    opening.onsuccess = () => {
      const db = opening.result;
      let transaction;
      try { transaction = db.transaction('vault', operation === 'get' ? 'readonly' : 'readwrite'); }
      catch (error) { db.close(); reject(error); return; }
      const store = transaction.objectStore('vault');
      const request = operation === 'get' ? store.get('source') :
        operation === 'put' ? store.put(value, 'source') : store.delete('source');
      transaction.oncomplete = () => { db.close(); resolve(request.result); };
      transaction.onabort = transaction.onerror = () => { db.close(); reject(transaction.error || new Error('Storage unavailable')); };
    };
  });
}

export async function saveSource(source) { await sourceRecord('put', await sealSource(source)); }
export async function getSavedSource() {
  const record = await sourceRecord('get');
  return record ? unsealSource(record) : null;
}
export async function deleteSavedSource() { await sourceRecord('delete'); }
