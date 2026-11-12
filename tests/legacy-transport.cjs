const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const source = fs.readFileSync(path.join(__dirname, '../ZapretManager_LuCI.sh'), 'utf8');
const backend = source.split("<< 'ZM_INSTALLER_EOF'\n")[1].split('\nZM_INSTALLER_EOF')[0];
function extract(name) {
  const start = backend.indexOf(name + '() {');
  assert(start >= 0);
  return backend.slice(start, backend.indexOf('\n}', start) + 2);
}
function run(text, status = 0) {
  const p = cp.spawnSync(process.env.SH || 'sh', ['-c', text], {encoding:'utf8'});
  assert.equal(p.status, status, p.stdout + p.stderr);
  return p.stdout;
}
const rows = JSON.parse(fs.readFileSync(path.join(__dirname, '../docs/legacy-transport-payloads.json')));
const known = extract('_zm_transport_legacy_known');
for (const row of rows) {
  const key = [row.component, row.format === 'ipk' ? 'opkg' : row.format, row.version, row.binary, row.helper].join(':');
  run(`${known}\n_zm_transport_legacy_known '${key}'`);
  for (const bad of [key.replace(row.version, '99.99-r1'), key.replace(row.binary, '0'.repeat(64)), key.replace(row.helper, '0'.repeat(64))])
    run(`${known}\n_zm_transport_legacy_known '${bad}'`, 1);
}
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'zm-legacy-'));
try {
  const managerRoot = path.join(root, 'old-panel'); fs.mkdirSync(managerRoot);
  const oldBackend = path.join(managerRoot, 'backend.sh');
  const detection = source.slice(source.indexOf('_zm_previous_managed=0'), source.indexOf("cat > '/opt/zapret-manager-luci/backend.sh.zm-new'"))
    .replaceAll('/opt/zapret-manager-luci', managerRoot);
  assert.equal(run(`${detection}\necho $_zm_previous_managed`).trim(), '0');
  fs.writeFileSync(oldBackend, 'ZM_VERSION="4.71.5"\n');
  assert.equal(run(`${detection}\necho $_zm_previous_managed`).trim(), '0');
  fs.writeFileSync(oldBackend, 'ZM_FLAVOR="forkop-five-section-v1"\nZM_SCRIPT_URL="https://raw.githubusercontent.com/Screamshow/Zapret-Manager/main/ZapretManager_LuCI.sh"\n');
  assert.equal(run(`${detection}\necho $_zm_previous_managed`).trim(), '1');
  fs.appendFileSync(oldBackend, 'ZM_SCRIPT_URL="https://example.com/foreign"\n');
  // A duplicate assignment must not let a foreign effective update source pass.
  // The installer contracts use one literal assignment; source matching alone
  // is insufficient when later assignments can override it.
  assert.equal(run(`${detection}\necho $_zm_previous_managed`).trim(), '0');
  for (const component of ['zapret', 'zapret2']) for (const pkg of ['apk', 'opkg']) {
    const fixture = path.join(root, component + '-' + pkg);
    const componentRoot = path.join(fixture, 'opt', component);
    const binary = path.join(componentRoot, component === 'zapret' ? 'nfq/nfqws' : 'nfq2/nfqws2');
    const helper = path.join(componentRoot, 'common/nft.sh');
    const state = path.join(fixture, 'state');
    fs.mkdirSync(path.dirname(binary), {recursive:true}); fs.mkdirSync(path.dirname(helper), {recursive:true});
    fs.mkdirSync(state);
    fs.writeFileSync(binary, 'original-binary'); fs.writeFileSync(helper, 'original-helper');
    const hash = p => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
    const b = hash(binary), h = hash(helper), version = '1.0-r1';
    const functions = ['_zm_transport_record_owned', '_zm_transport_migrate_one'].map(extract)
      .join('\n').replaceAll('/opt/', fixture + '/opt/');
    const prelude = `ZM_STATE_DIR='${state}'; PKG=${pkg}\n${functions}\n` +
      `_apk_ver() { echo ${version}; }; _opkg_ver() { echo ${version}; };\n` +
      `apk() { echo "$3 is owned by ${component}-${version}"; }; opkg() { echo "${component} - $2"; };\n` +
      `_zm_transport_legacy_known() { [ "$1" = '${component}:${pkg}:${version}:${b}:${h}' ]; };\n`;
    const migrate = `${prelude}\n_zm_transport_migrate_one ${component}`;
    // Wrong package owner, changed binary/helper and symlinks are not adopted.
    run(`${prelude}\napk() { echo foreign; }; opkg() { echo foreign; }; _zm_transport_migrate_one ${component}`);
    const receipt = path.join(state, 'transport-ownership', component + '.json');
    assert(!fs.existsSync(receipt));
    for (const file of [binary, helper]) {
      const original = fs.readFileSync(file); fs.appendFileSync(file, 'changed'); run(migrate);
      assert(!fs.existsSync(receipt)); fs.writeFileSync(file, original);
    }
    const saved = binary + '.saved'; fs.renameSync(binary, saved); fs.symlinkSync(saved, binary);
    run(migrate); assert(!fs.existsSync(receipt)); fs.unlinkSync(binary); fs.renameSync(saved, binary);
    fs.mkdirSync(path.dirname(receipt), {recursive:true});
    fs.symlinkSync(path.join(fixture, 'missing-receipt'), receipt);
    run(migrate); assert(fs.lstatSync(receipt).isSymbolicLink()); fs.unlinkSync(receipt);
    const helperBackup = path.join(state, 'transport-ownership', component + '.nft.before');
    fs.symlinkSync(path.join(fixture, 'missing-backup'), helperBackup);
    run(migrate); assert(!fs.existsSync(receipt)); fs.unlinkSync(helperBackup);
    run(migrate);
    const r = JSON.parse(fs.readFileSync(receipt));
    assert.equal(r.binary_sha256, b); assert.equal(r.helper_sha256, h);
    assert.equal(fs.readFileSync(path.join(state, 'transport-ownership', component + '.nft.before'), 'utf8'), 'original-helper');
    // Existing even-invalid receipts cannot be overwritten by panel upgrade.
    fs.writeFileSync(receipt, '{"foreign":true}'); run(migrate);
    assert.equal(fs.readFileSync(receipt, 'utf8'), '{"foreign":true}');
  }
  const guard = path.join(root, 'guard.uc'); fs.writeFileSync(guard, 'fixture');
  const migrate = extract('_zm_transport_migrate_legacy').replaceAll('/usr/lib/forkop/service/proxy_transport.uc', guard);
  const prelude = `${migrate}\n_zm_transport_migrate_one() { echo migrate:$1; }; _zm_transport_guard() { echo guard:$1; return 1; };\n`;
  assert.equal(run(`${prelude}\n_zm_transport_migrate_legacy wrong`, 1), '');
  assert.equal(run(`${prelude}\n_zm_transport_migrate_legacy verified-panel-upgrade`, 1), 'migrate:zapret\nmigrate:zapret2\nguard:prepare\n');
  assert(source.includes('if [ "$_zm_previous_managed" = 1 ]; then'));
  console.log('PASS legacy payload pins; APK/IPK ownership; altered/symlink/foreign rejection; receipts; guard failures');
} finally { fs.rmSync(root, {recursive:true, force:true}); }
