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
  const archFile = path.join(dir, 'apk-arch');
  const apkArch = extract(backend, '_zm_apk_arch').replaceAll('/etc/apk/arch', archFile);
  const unifiedHelper = apkArch + '\n' + extract(backend, '_zm_managed_arm64');
  fs.writeFileSync(archFile, 'aarch64_cortex-a73\n');
  assert.equal(run(unifiedHelper + '\napk() { echo aarch64; }\n_zm_apk_arch').trim(), 'aarch64_cortex-a73');
  fs.unlinkSync(archFile);
  const archHelper = unifiedHelper + '\n' + extract(backend, '_zapret_archive_arch');
  for (const arch of ['aarch64', 'aarch64_cortex-a73', 'aarch64_cortex-a53', 'x86_64']) {
    const result = run(unifiedHelper + `\nPKG=apk\napk() { echo ${arch}; }\nif _zm_managed_arm64; then echo yes; else echo no; fi`);
    assert.equal(result.trim(), ['aarch64', 'aarch64_cortex-a73'].includes(arch) ? 'yes' : 'no');
  }
  const z2Support = unifiedHelper + '\n' + extract(backend, '_z2_supported');
  run(z2Support + '\nPKG=apk\napk() { echo aarch64; }\n_z2_arch() { echo aarch64_cortex-a73; }\n_z2_supported');
  run(z2Support + '\nPKG=opkg\n_z2_arch() { echo aarch64_cortex-a53; }\n_z2_supported');
  run(z2Support + '\nPKG=opkg\n_z2_arch() { echo aarch64_cortex-a73; }\nif _z2_supported; then exit 1; fi');
  const crypto = require('node:crypto');
  const fixtureDir = path.join(dir, 'packages');
  fs.mkdirSync(fixtureDir);
  let armPackageHelper = extract(backend, '_zm_arm64_packages');
  armPackageHelper = armPackageHelper.replace(/([\w.-]+\.apk):(\d+):([a-f0-9]{64})/g, (_, name) => {
    const data = Buffer.from('fixture ' + name);
    fs.writeFileSync(path.join(fixtureDir, name), data);
    return name + ':' + data.length + ':' + crypto.createHash('sha256').update(data).digest('hex');
  });
  for (const arch of ['aarch64', 'aarch64_cortex-a73']) for (const component of ['zapret', 'zapret2']) {
    for (const mode of ['ok', 'corrupt', 'missing', 'dependencies']) {
      const destination = path.join(dir, arch + '-' + component + '-' + mode);
      const simulation = path.join(dir, arch + '-' + component + '-' + mode + '-simulate');
      const result = run(armPackageHelper + `
_zm_apk_arch() { echo ${arch}; }
_zm_get() { case "$1" in *"/${arch === 'aarch64' ? 'unified-aarch64' : 'a73'}/"*) ;; *) return 1 ;; esac; ${mode === 'missing' ? 'return 1' : `cp '${fixtureDir}/'"\$\{1##*/\}" "$2"`} ; ${mode === 'corrupt' ? 'echo corruption >> "$2"' : ':'}; }
apk() { touch '${simulation}'; ${mode === 'dependencies' ? 'return 1' : 'return 0'}; }
if _zm_arm64_packages ${component} '${destination}'; then echo RESULT_OK; else echo RESULT_FAIL; fi
`);
      assert(result.includes(mode === 'ok' ? 'RESULT_OK' : 'RESULT_FAIL'), result);
      assert.equal(fs.existsSync(simulation), ['ok', 'dependencies'].includes(mode));
    }
  }
  assert.equal(run(archHelper + '\nPKG=apk\napk() { echo aarch64_cortex-a53; }\n_zapret_archive_arch aarch64_cortex-a73').trim(), 'aarch64_cortex-a53');
  assert.equal(run(archHelper + '\nPKG=opkg\nopkg() { printf "arch all 1\\narch aarch64_cortex-a53 10\\narch aarch64_cortex-a73 20\\n"; }\n_zapret_archive_arch aarch64_cortex-a73').trim(), 'aarch64_cortex-a53');
  for (const pm of ['apk', 'opkg']) {
    run(archHelper + `\nPKG=${pm}\napk() { echo aarch64_cortex-a73; }\nopkg() { printf 'arch all 1\\narch aarch64_cortex-a53 0\\narch aarch64_cortex-a73 10\\n'; }\nif _zapret_archive_arch aarch64_cortex-a73; then exit 1; fi`);
  }
  assert.equal(run(archHelper + '\n_zapret_archive_arch x86_64').trim(), 'x86_64');
  // Execute the installer with isolated paths and failed downloads. A running
  // service must never be stopped, and missing assets must not be retried.
  const installCore = extract(backend, '_do_install_zapret_core')
    .replaceAll('/etc/init.d/zapret', dir + '/service-zapret')
    .replaceAll('/etc/openwrt_release', dir + '/openwrt_release');
  fs.writeFileSync(path.join(dir, 'openwrt_release'), "DISTRIB_ARCH='x86_64'\n");
  const stopped = path.join(dir, 'stopped');
  fs.writeFileSync(path.join(dir, 'service-zapret'), `#!/bin/sh\ntouch '${stopped}'\n`);
  fs.chmodSync(path.join(dir, 'service-zapret'), 0o755);
  for (const code of [404, 504]) {
    const output = run(archHelper + '\n' + installCore + `
_ensure_deps() { :; }
_zm_fetch() { echo FETCH; ZM_FETCH_ERR='ошибка (HTTP ${code})'; return 1; }
unzip() { return 1; }
PKG=opkg; UPDATE=true; ZAPRET_VER=72.20260307; GH_MAIN=https://github.com
JOBS_DIR='${dir}'
if _do_install_zapret_core; then exit 1; fi
`);
    assert.equal((output.match(/^FETCH$/gm) || []).length, code === 404 ? 1 : 5);
    assert(!fs.existsSync(stopped), 'download failure stopped running zapret');
  }
  // Exercise the real built-ins through both candidate collection modes.
  const definitions = backend.match(/^strategy_v\d+\(\).*$/gm) || [];
  assert.equal(definitions.length, 10);
  const candidates = path.join(dir, 'candidates');
  const flowseal = path.join(dir, 'flowseal');
  fs.writeFileSync(flowseal, '#general1\n--filter-tcp=80\n');
  const helpers = definitions.join('\n') + '\n' + extract(backend, '_test_build_candidates');
  for (const mode of ['v', 'v_flowseal']) {
    run(helpers + `\n_flowseal_file() { echo '${flowseal}'; }\n_test_build_candidates ${mode} '${candidates}'`);
    const output = fs.readFileSync(candidates, 'utf8');
    assert.deepEqual(output.match(/^#v\d+$/gm), Array.from({length: 10}, (_, i) => '#v' + (i + 1)));
    assert.equal((output.match(/^--filter-tcp=443$/gm) || []).length, 10);
    assert.equal(output.includes('#general1'), mode === 'v_flowseal');
  }
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
