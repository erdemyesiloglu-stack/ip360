import {test} from 'node:test';
import assert from 'node:assert/strict';
import {sealSource, unsealSource} from '../dist/storage.js';

test('Saved Xtream account survives structured cloning without plain-text credentials', async () => {
  const source = {mode: 'xtream', server: 'https://example.com', username: 'kullanıcı', password: 'p&ss'};
  const sealed = await sealSource(source);
  assert.equal(sealed.key.extractable, false);
  assert.equal('password' in sealed, false);
  assert.deepEqual(await unsealSource(structuredClone(sealed)), source);
});
test('Saved file playlist is restored with Unicode names and its sections', async () => {
  const source = {mode: 'file', channels: [{name: 'İstanbul', kind: 'movies', group: 'Filmler', url: 'https://example.com/a.mp4'}]};
  assert.deepEqual(await unsealSource(await sealSource(source)), source);
});
test('Encryption uses a new IV and key for each saved record', async () => {
  const source = {mode: 'url', url: 'https://example.com/list.m3u'};
  const a = await sealSource(source), b = await sealSource(source);
  assert.notDeepEqual(a.iv, b.iv);
  assert.notDeepEqual(a.data, b.data);
  await assert.rejects(unsealSource({...a, key: b.key}));
});
test('Corrupted ciphertext and invalid source types are rejected', async () => {
  const record = await sealSource({mode: 'url', url: 'https://example.com'});
  new Uint8Array(record.data)[0] ^= 1;
  await assert.rejects(unsealSource(record));
  await assert.rejects(unsealSource(await sealSource({mode: 'invalid'})));
});
