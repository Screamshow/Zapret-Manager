const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');
const assert = require('node:assert/strict');
const installer = fs.readFileSync(path.join(__dirname, '../ZapretManager_LuCI.sh'), 'utf8');
const backend = installer.split("<< 'ZM_INSTALLER_EOF'\n")[1].split('\nZM_INSTALLER_EOF')[0];
function extract(name) {
  const start = backend.indexOf(name + '() {');
  assert(start >= 0, name);
  return backend.slice(start, backend.indexOf('\n}', start) + 2);
}
function run(script) {
  const result = cp.spawnSync(process.env.SH || 'sh', ['-c', script], {encoding:'utf8'});
  assert.equal(result.status, 0, result.stderr + result.stdout);
  return result.stdout.trim().split('\n');
}
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'zm-proxy-transport-'));
try {
  const guard = path.join(dir, 'guard.uc'); fs.writeFileSync(guard, 'fixture');
  const transportGuard = extract('_zm_transport_guard').replaceAll('/usr/lib/forkop/service/proxy_transport.uc', guard);
  // Match job_start: $$ is inherited from the launcher, but /proc/self is
  // opened by the live background worker. Release must use the hold identity.
  assert.deepEqual(run(`${transportGuard}
ucode() {
  read -r actual rest < /proc/self/stat
  test "$3" = "$actual" || return 1
  test "$3" != "$$" || return 1
  case "$2" in hold) held="$3" ;; release) test "$3" = "$held" || return 1 ;; esac
}
(
  _zm_transport_guard hold || exit 1
  test "$ZM_TRANSPORT_HELD" = 1 || exit 1
  _zm_transport_guard release || exit 1
  test "$ZM_TRANSPORT_HELD" = 0 || exit 1
  echo WORKER_OWNER_OK
) &
wait $!`), ['WORKER_OWNER_OK']);
  assert.deepEqual(run(`${transportGuard}
ucode() { echo UNEXPECTED; }
if _zm_transport_guard release; then exit 1; fi
ucode() { return 1; }
if _zm_transport_guard hold; then exit 1; fi
test "\${ZM_TRANSPORT_HELD:-0}" = 0
echo FAILED_GUARD_NOT_HELD`), ['FAILED_GUARD_NOT_HELD']);
  for (const name of ['zapret','zapret2']) fs.writeFileSync(path.join(dir,name), '#!/bin/sh\necho service:$1\n', {mode:0o700});
  const service = extract('_zm_zapret_service').replaceAll('/usr/lib/forkop/service/proxy_transport.uc', guard).replaceAll('/etc/init.d/', dir + '/');
  for (const name of ['zapret','zapret2']) {
    assert.deepEqual(run(`ucode() { echo guard:$2; }; logger() { :; };\n${service}\n_zm_zapret_service ${name} restart`), ['guard:prepare','service:restart']);
    assert.deepEqual(run(`ucode() { echo guard-failed; return 1; }; logger() { :; };\n${service}\nif _zm_zapret_service ${name} start; then exit 1; fi`), ['guard-failed']);
    for (const status of [0,1]) {
      const script = `${extract('do_install_' + name)}\n` +
        `_zm_transport_guard() { echo guard:$1; case "$1" in hold) ZM_TRANSPORT_HELD=1 ;; release) ZM_TRANSPORT_HELD=0 ;; esac; }; _nochange_save() { :; };\n` +
        `_do_install_${name}_core() { echo download; _zm_transport_guard hold; echo install; ${status === 0 ? '_zm_transport_guard release; echo post-download;' : ''} return ${status}; };\n` +
        `_nochange_restore() { echo restore; }; _ft_zapret_sync() { echo sync; };\n` +
        `do_install_${name}; result=$?; echo result:$result`;
      assert.deepEqual(run(script), status === 0
        ? ['download','guard:hold','install','guard:release','post-download','restore','sync','result:0']
        : ['download','guard:hold','install','restore','sync','guard:release','result:1']);
    }
  }
  // Every supported service start/restart goes through the guard, including
  // strategy tests and package installation, rather than repairing rules later.
  assert(!/\/etc\/init\.d\/zapret2? (start|restart)\b/.test(backend));
  const preload = extract('_zm_transport_preload_deps').replaceAll('/usr/lib/forkop/service/proxy_transport.uc', guard);
  const main = path.join(dir,'main.apk'), gui = path.join(dir,'gui.apk');
  fs.writeFileSync(main,'fixture');fs.writeFileSync(gui,'fixture');
  const deps = run(`apk() { case "$2" in *main.apk) printf '  name: zapret\\n  depends: # 2\\n    - libc\\n    - libnetfilter-queue1>=1.0\\n  provides: # 0\\n' ;; *) printf '  name: luci-app-zapret\\n  depends: # 2\\n    - zapret\\n    - luci-base\\n' ;; esac; };\n` +
    `mock_install() { printf '%s\\n' "$@"; }; INSTALL=mock_install;\n${preload}\n_zm_transport_preload_deps '${main}' '${gui}'`);
  assert.deepEqual(deps,['libc','libnetfilter-queue1>=1.0','luci-base']);
  for(const name of ['zapret','zapret2']) {
    const core=extract('_do_install_'+name+'_core');
    assert(core.indexOf('_zm_transport_preload_deps') < core.indexOf('_zm_transport_guard hold'));
    assert(core.indexOf('_zm_transport_guard release') > core.indexOf('_zm_transport_guard hold'));
  }
  console.log('PASS: guarded starts; dependencies before hold; package commit held; Connection restored before further downloads; install failures repaired safely');
} finally { fs.rmSync(dir, {recursive:true,force:true}); }
