import {readFile, access} from 'node:fs/promises';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('../dist/', import.meta.url));
const html = await readFile(resolve(root, 'index.html'), 'utf8');
for (const match of html.matchAll(/(?:src|href)="\.\/([^"]+)"/g)) {
  await access(resolve(root, match[1]));
}
const manifest = JSON.parse(await readFile(resolve(root, 'manifest.webmanifest'), 'utf8'));
for (const icon of manifest.icons) await access(resolve(root, icon.src));
for (const file of ['app.js', 'core.js', 'storage.js']) {
  const source = await readFile(resolve(root, file), 'utf8');
  for (const match of source.matchAll(/from ['"]\.\/([^'"]+)['"]/g)) {
    await access(resolve(root, match[1]));
  }
}
console.log('HTML, uygulama modülleri ve PWA görselleri doğrulandı. Yayın klasörü: dist');
