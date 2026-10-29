// SH=/path/to/sh node tests/backend-behavior.cjs
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const cp = require('node:child_process');
const assert = require('node:assert/strict');
const installer = fs.readFileSync(path.join(__dirname, '../ZapretManager_LuCI.sh'), 'utf8');
const consoleSource = fs.readFileSync(path.join(__dirname, '../Zapret-Manager.sh'), 'utf8');
const backend = installer.split("<< 'ZM_INSTALLER_EOF'\n")[1].split('\nZM_INSTALLER_EOF')[0];
const shell = process.env.SH || 'sh';
function extract(source, name) {
  const start = source.indexOf(name + '() {');
  assert(start >= 0, name);
  return source.slice(start, source.indexOf('\n}', start) + 2);
}
function run(script, input = '') {
  const r = cp.spawnSync(shell, ['-c', script], { input, encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr + r.stdout);
  assert(!/not found|syntax error/.test(r.stderr), r.stderr);
  return r.stdout;
}
for (const script of [installer, backend, consoleSource]) {
  const r = cp.spawnSync(shell, ['-n'], { input: script, encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
}
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'zm-contract-'));
try {
  const packageHelper = extract(installer, '_zmi_pkg');
  // Forkop owns the rollback archive. The integration mode must never
  // install packages behind that archive, including when one is missing.
  run(packageHelper + '\n_zmi_has() { return 0; }\nZM_FORKOP_TRANSACTION=1\n_zmi_pkg curl unused');
  run(packageHelper + '\n_zmi_has() { return 1; }\nZM_FORKOP_TRANSACTION=1\nif _zmi_pkg missing unused; then exit 1; fi');
  const cache = path.join(dir, 'versions.json').replaceAll('\\', '/');
  fs.writeFileSync(cache, JSON.stringify({ items: [
    { name: 'Zapret Manager', installed: '4.71', latest: '4.71.1' },
    { name: 'Zapret2', installed: '1', latest: '2' },
    { name: 'Mihomo', installed: '1', latest: '2' },
    { name: 'Forkozz', installed: '1', latest: '2' },
    { name: 'DNS over HTTPS (https-dns-proxy)', installed: '1', latest: '2' }
  ] }));
  const items = run(extract(backend, '_au_items') + `\nVERSIONS_CACHE='${cache}'\n_au_items`);
  assert(items.includes('Zapret Manager') && items.includes('Zapret2'));
  assert(!/Mihomo|Forkozz|https-dns/.test(items), items);
  const cron = path.join(dir, 'cron').replaceAll('\\', '/');
  fs.writeFileSync(cron, [
    '0 * * * * /opt/zapret-manager-luci/backend.sh steer_action sync',
    '0 * * * * /opt/zapret-manager-luci/backend.sh adblock_cron',
    '0 * * * * /opt/zapret-manager-luci/backend.sh tsc_watch',
    '0 * * * * /opt/zapret-manager-luci/backend.sh test_action auto_tick x',
    '0 * * * * /opt/zapret-manager-luci/backend.sh zm_watch',
    '0 * * * * /etc/init.d/steer restart',
    '# unrelated comment'
  ].join('\n') + '\n');
  const prune = extract(installer, '_zmi_prune_panel_cron') + `\n_zmi_prune_panel_cron '${cron}'`;
  run(prune); run(prune);
  const migrated = fs.readFileSync(cron, 'utf8');
  assert(!/backend.sh (steer_action|adblock_cron|tsc_watch)/.test(migrated));
  assert(migrated.includes('test_action auto_tick') && migrated.includes('zm_watch'));
  assert(migrated.includes('/etc/init.d/steer restart') && migrated.includes('# unrelated comment'));
  const stub = path.join(dir, 'backend').replaceAll('\\', '/');
  fs.writeFileSync(stub, '#!/bin/sh\nprintf "called:%s\\n" "$1"\n');
  fs.chmodSync(stub, 0o755);
  const cli = consoleSource.replace('BACKEND="/opt/zapret-manager-luci/backend.sh"', `BACKEND='${stub}'`);
  const result = run(cli, '1\n\n');
  assert(result.includes('called:status') && result.includes('called:health'));
  assert(!/Меню Steer|Меню Mixomo|Меню ByeTube/.test(result));
  console.log('PASS: shell syntax, stale update cache filtering, scoped/idempotent cron migration and shared console backend');
} finally { fs.rmSync(dir, { recursive: true, force: true }); }
