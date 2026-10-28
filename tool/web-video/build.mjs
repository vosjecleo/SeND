import {build} from 'esbuild';
import {copyFile, mkdir, writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
const root = fileURLToPath(new URL('../../', import.meta.url));
await mkdir(root + 'web/web-video', {recursive: true});
await build({entryPoints: [fileURLToPath(new URL('worker.mjs', import.meta.url))],
  outfile: root + 'web/web-video/worker.js', bundle: true, minify: true,
  sourcemap: 'linked', sourcesContent: true, legalComments: 'eof',
  format: 'esm', platform: 'browser', target: ['safari16.4', 'chrome94'],
  banner: {js: '/* SeND browser video worker. Includes Mediabunny 1.62.1 (MPL-2.0); see LICENSE.mediabunny and the source map. */'}});
await copyFile(new URL('node_modules/mediabunny/LICENSE', import.meta.url), root + 'web/web-video/LICENSE.mediabunny');
await writeFile(root + 'web/web-video/SOURCE.txt',
  'Mediabunny 1.62.1, MPL-2.0\nhttps://registry.npmjs.org/mediabunny/-/mediabunny-1.62.1.tgz\n' +
  'Unmodified library source is included in worker.js.map. Rebuild with npm ci && npm run build in tool/web-video.\n');
