// Makes the compiler's generated contract importable as ESM from the test files.
// build/ is gitignored, so this runs after every compile.
import { existsSync, writeFileSync, rmSync, symlinkSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const generated = resolve(here, '../build/contract');
if (!existsSync(generated)) {
  console.error('no build/contract — run `npm run build` first');
  process.exit(1);
}
// generated code is ESM but ships no package.json type field
writeFileSync(resolve(generated, 'package.json'), JSON.stringify({ type: 'module' }) + '\n');
const link = resolve(here, 'slipcontract');
if (existsSync(link)) rmSync(link, { recursive: true, force: true });
symlinkSync(generated, link, 'dir');
console.log('linked build/contract -> test/slipcontract');
