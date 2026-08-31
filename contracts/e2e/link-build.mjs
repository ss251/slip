// The compiled contract imports @midnight-ntwrk/compact-runtime relative to ITS OWN
// location, and ../build has no node_modules. Copy it in here so it resolves against
// this workspace's tree — the same trick ../test/link-build.mjs uses for the simulator.
import { cp, rm, stat } from 'node:fs/promises';
const SRC = new URL('../build/', import.meta.url);
const DST = new URL('./slip-build/', import.meta.url);
try { await stat(new URL('keys/', SRC)); } catch {
  console.error('ERROR: ../build has no keys/ — run `npm run build` in contracts/ first (build:fast uses --skip-zk and cannot deploy).');
  process.exit(1);
}
await rm(DST, { recursive: true, force: true });
await cp(SRC, DST, { recursive: true });
console.log('linked ../build -> ./slip-build');
