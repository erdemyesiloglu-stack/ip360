import {readFile, writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';

const root = new URL('./', import.meta.url);
const read = name => readFile(new URL(`dist/${name}`, root), 'utf8');
let html = await read('index.html');
const css = await read('style.css');
const core = (await read('core.js')).replace(/^export /gm, '');
const storage = (await read('storage.js')).replace(/^export /gm, '');
const app = (await read('app.js')).replace(/^import .*?;\r?\n/gm, '');
const icon = `data:image/svg+xml,${encodeURIComponent(await read('icon.svg'))}`;
html = html.replace('<link rel="icon" href="./icon.svg" type="image/svg+xml">', `<link rel="icon" href="${icon}" type="image/svg+xml">`)
  .replace('<link rel="manifest" href="./manifest.webmanifest">', '')
  .replace('<link rel="stylesheet" href="./style.css">', `<style>${css}</style>`)
  .replace('<script type="module" src="./app.js"></script>', '')
  .replace('</body>', `<script>\n'use strict';\n${core}\n${storage}\n${app}\n</script>\n</body>`);
// Closing script tags in future source text must not truncate the application.
if (/<\/script/i.test(core + storage + app)) throw new Error('Inline script contains an unsafe closing tag.');
const output = new URL('./akis-iptv.html', root);
await writeFile(output, html);
console.log(`Tek dosya hazır: ${fileURLToPath(output)}`);
