// Run with node tests/panel-contract.cjs; never executes the installer.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../ZapretManager_LuCI.sh'), 'utf8').replace(/\r\n/g, '\n');
const files = new Map();
for (const m of source.matchAll(/cat > '([^']+)' << 'ZM_INSTALLER_EOF'\n([\s\S]*?)\nZM_INSTALLER_EOF/g)) files.set(m[1], m[2]);
assert(files.size > 10, 'installer payload extraction failed');
for (const [name, body] of files) {
  if (name.endsWith('.json')) JSON.parse(body);
  if (name.endsWith('.js')) new vm.Script('(function(){\n' + body + '\n})', { filename: name });
}
const expected = ['dashboard', 'hosts', 'strategy', 'terminal', 'zapret2'].sort();
const menu = JSON.parse(files.get('/usr/share/luci/menu.d/luci-app-zapret-manager.json'));
assert.deepEqual(Object.keys(menu).filter(k => k.split('/').length === 4).map(k => k.split('/').pop()).sort(), expected);
const app = files.get('/www/zm/app.js');
const routes = app.match(/var ROUTES = \[([\s\S]*?)\n\];/)[1];
assert.deepEqual([...routes.matchAll(/id: '([^']+)'/g)].map(m => m[1]).sort(), expected);
const common = files.get('/www/luci-static/resources/zapret-manager/common.js');
// Syntax checks do not catch stale exports such as sysFixCard: sysFixCard.
// Evaluate the LuCI modules with their declared framework dependencies.
const moduleContext = {
  baseclass: { extend: value => value },
  view: { extend: value => value },
  rpc: { declare: () => () => Promise.resolve({}) },
  window: { addEventListener() {} }, document: { addEventListener() {} },
  L: {}, E() {}, poll: {}, ui: {}, uci: {}, fs: {},
  setTimeout() {}, clearTimeout() {}, setInterval() {}, clearInterval() {}
};
const commonApi = vm.runInNewContext('(function(){\n' + common + '\n})()', moduleContext);
assert.equal(typeof commonApi.status, 'function');
const plugin = files.get('/opt/zapret-manager-luci/rpcd-plugin.zm-new');
const methods = new Set([...plugin.matchAll(/json_add_object "([^"]+)"/g)].map(m => m[1]));
const acl = JSON.parse(files.get('/usr/share/rpcd/acl.d/luci-app-zapret-manager.json'));
const granted = new Set();
for (const entry of Object.values(acl)) for (const access of ['read', 'write']) {
  for (const method of entry[access]?.ubus?.['zapret-manager'] || []) granted.add(method);
}
for (const m of common.matchAll(/object: 'zapret-manager', method: '([^']+)'/g)) {
  assert(methods.has(m[1]), 'RPC not registered: ' + m[1]);
  assert(granted.has(m[1]), 'RPC not granted: ' + m[1]);
}
const apiExports = new Set([...common.matchAll(/^\s*(\w+):/gm)].map(m => m[1]));
for (const removed of ['sysFixCard', 'catalogWatch', 'steerOffloadAsk', 'subMeta', 'linksEditor', 'routeWhere', 'hidePicker']) {
  assert(!apiExports.has(removed), 'retired UI export: ' + removed);
}
for (const name of ['/www/luci-static/resources/view/zapret-manager/style.css', '/www/zm/app.css']) {
  const css = files.get(name);
  assert(!/\.zm-(?:st-|fk-|awg-|doh-|rm-|mon-|pg-|bk-|tg-|tsc-)/.test(css), 'retired CSS namespace: ' + name);
}
for (const page of expected) {
  const body = files.get('/www/luci-static/resources/view/zapret-manager/' + page + '.js');
  assert(body, 'missing page ' + page);
  const pageModule = vm.runInNewContext('(function(){\n' + body + '\n})()', { ...moduleContext, zm: commonApi });
  assert.equal(typeof pageModule.render, 'function', page + ' must load');
  for (const m of body.matchAll(/\bzm\.(\w+)\s*\(/g)) assert(apiExports.has(m[1]), page + ': missing zm.' + m[1]);
}
const cleanup = source.slice(source.indexOf('_zmi_say "Убираем страницы,'), source.indexOf('_zmi_ok "Страницы LuCI записаны"'));
assert(cleanup.includes('doh awg tailscale steer adblock mixomo system monitor tgproxy forkozz bytetube'));
assert(!cleanup.includes('/etc/'), 'migration must preserve service configuration');
assert(!cleanup.includes('rm -rf'), 'migration must remove only explicit panel assets');
assert(source.indexOf('_zmi_say "Убираем страницы,') < source.indexOf('ZM_BUILD_ID='), 'cleanup must precede asset manifest');
assert(source.includes('# Version: 4.71.1\n'));
assert(source.includes('Screamshow/Zapret-Manager/refs/heads/main/ZapretManager_LuCI.sh'));
console.log('PASS: payload syntax, five matching menus, page dependencies, upgrade cleanup and update source');

const backend = files.get('/opt/zapret-manager-luci/backend.sh.zm-new');
assert(backend);
assert(!/^(_fk_|_st_|stl_|_ab_|_awg_|_tg_|_tsc_|_bk_|do_mixomo|do_bytetube|do_steer|do_tsc|adblock_|doh_|dns_net_).*\(\)/m.test(backend), 'retired component code remains');
const consoleSource = fs.readFileSync(path.join(__dirname, '../Zapret-Manager.sh'), 'utf8');
assert(!/STEER_MENU|MIXOMO_MENU|BYETUBE_MENU|PODKOP_menu|menu_TG|DoH_menu/.test(consoleSource));
assert(consoleSource.includes('ZM_LUCI_URL="${GH_RAW}/Screamshow/Zapret-Manager/main/ZapretManager_LuCI.sh"'));
const dispatcher = backend.slice(backend.indexOf('_zm_run_cmd()'));
for (const m of source.matchAll(/\/opt\/zapret-manager-luci\/backend\.sh ([a-z_]+)/g)) {
  assert(dispatcher.includes(m[1] + ')'), 'installer/cron calls unsupported backend method ' + m[1]);
}
console.log('PASS: no retired component implementations or console menus; installer/cron dispatch supported');
