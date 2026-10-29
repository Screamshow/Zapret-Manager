// Requires jsdom (NODE_PATH may point to an isolated test installation).
// Renders the real LuCI modules against deterministic, read-only RPC fixtures.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { JSDOM } = require('jsdom');
const input = process.argv[2] || path.join(__dirname, '../ZapretManager_LuCI.sh');
const source = fs.readFileSync(input, 'utf8');
const files = new Map([...source.matchAll(/cat > '([^']+)' << 'ZM_INSTALLER_EOF'\n([\s\S]*?)\nZM_INSTALLER_EOF/g)].map(m => [m[1], m[2]]));
const app = files.get('/www/zm/app.js');
const domHelpers = app.slice(app.indexOf('function isNode('), app.indexOf('function tr('));
const fixtures = {
  status: { zapret: 'installed', zapret_running: true, zapret2: 'not_installed', pkg: 'apk', strategy: 'v4 Yv08 Dv1', zapret_version: '72.20260307' },
  system_info: { model: 'Test router', hostname: 'OpenWrt', ram_total: '1024 MB' },
  system_status: { flow_mode: 'off', zapret_installed: true, quic_blocked: true },
  hosts_status: { items: [{ id: 'telegram', name: 'Telegram', enabled: false }, { id: 'ai_openai', name: 'OpenAI', enabled: false }] },
  health: { dots: { zapret: 1 }, zapret: 1, zapret2: 0 },
  test_status: { running: false, auto: { pref: '04:00', mode: 'youtube', running: false, log: [] } },
  term_status: { installed: false, running: false, port: 7681, lan_ip: '192.0.2.1' },
  zm_update_status: { current: '4.71.1', latest: '4.71.1', newer: false },
  versions: { items: [], pending: false, mode: 'open' },
  strategy_list_v: { items: [{ id: 'v1' }, { id: 'v4' }] },
  strategy_list_youtube: { items: Array.from({ length: 32 }, (_, i) => ({ id: 'Yv' + String(i + 1).padStart(2, '0') })) },
  game_status: { items: [] }, discord_status: { items: [] }, exclusions_status: { items: [] },
  ui_flags_get: {}, zm_changelog: { pending: false }, info: { model: 'Test router', hostname: 'OpenWrt' }
};
const results = [];
async function render(page, web) {
  const browser = new JSDOM('<!doctype html><html><head></head><body></body></html>', {
    url: 'http://192.0.2.1/', runScripts: 'outside-only', pretendToBeVisual: true
  });
  const w = browser.window, context = browser.getInternalVMContext(), errors = [];
  // Font/canvas capability detection is outside this DOM regression test.
  w.HTMLCanvasElement.prototype.getContext = () => null;
  w.addEventListener('error', e => { errors.push(String(e.error || e.message)); e.preventDefault(); });
  w.addEventListener('unhandledrejection', e => { errors.push(String(e.reason)); e.preventDefault(); });
  if (web) w.document.body.className = 'zmw-body';
  const reply = method => structuredClone(fixtures[method] || {});
  Object.assign(w, {
    _: x => x,
    baseclass: { extend: x => x }, view: { extend: x => x },
    poll: { add() {}, remove() {} }, ui: { addNotification() {} },
    L: { resource: p => '/luci-static/resources/' + p, url: (...p) => '/' + p.join('/'), env: {}, resolveDefault: (p, d) => p.catch(() => d) },
    rpc: { declare: spec => (...args) => {
      if (spec.method === 'multi') return Promise.resolve({ r: String(args[0]).split('\n').map(l => reply(l.split('\t')[0])) });
      return Promise.resolve(reply(spec.method));
    } },
    scrollTo() {}, matchMedia: () => ({ matches: false, addEventListener() {} })
  });
  try {
    vm.runInContext(domHelpers, context);
    w.zm = vm.runInContext('(function(){\n' + files.get('/www/luci-static/resources/zapret-manager/common.js') + '\n})()', context);
    const mod = vm.runInContext('(function(){\n' + files.get('/www/luci-static/resources/view/zapret-manager/' + page + '.js') + '\n})()', context);
    const data = await mod.load();
    const node = await mod.render(data);
    assert(node instanceof w.Node, page + ': render must return DOM');
    w.document.body.appendChild(node);
    await new Promise(r => setTimeout(r, 40));
    if (page === 'strategy') {
      const button = [...w.document.querySelectorAll('button')].find(n => n.textContent.trim() === 'YouTube');
      assert(button, 'YouTube subtab'); button.click();
      await new Promise(r => setTimeout(r, 40));
      assert(w.document.body.textContent.includes('Yv32'), 'YouTube strategies must render');
    }
    assert.equal(errors.length, 0, page + ': ' + errors.join('\n'));
    const text = node.textContent.replace(/\s+/g, ' ').trim();
    assert(text.length > 50, page + ': empty page');
    results.push({ page, web, text, classes: [...new Set([...node.querySelectorAll('[class]')].flatMap(n => [...n.classList]))].sort() });
    console.log('PASS render', web ? 'Web' : 'LuCI', page);
  } finally { w.close(); }
}
async function shell() {
  const browser = new JSDOM('<!doctype html><html><head></head><body><div id="zmw-root"></div></body></html>', {
    url: 'http://192.0.2.1/#/dashboard', runScripts: 'outside-only', pretendToBeVisual: true
  });
  const w = browser.window, errors = [], fetched = [];
  w.HTMLCanvasElement.prototype.getContext = () => null;
  w.sessionStorage.setItem('zmw.sid', 'test-session');
  w.addEventListener('error', e => { errors.push(String(e.error || e.message)); e.preventDefault(); });
  w.matchMedia = () => ({ matches: false, addEventListener() {}, removeEventListener() {} });
  w.scrollTo = () => {};
  w.fetch = async (url, options) => {
    const u = new URL(url, w.location.href);
    fetched.push(u.pathname);
    if (u.pathname === '/ubus') {
      const request = JSON.parse(options.body), [, object, method, args] = request.params;
      let value = structuredClone(fixtures[method] || {});
      if (object === 'session' && method === 'access') value = { access: true };
      if (method === 'multi') value = { r: args.calls.split('\n').map(l => structuredClone(fixtures[l.split('\t')[0]] || {})) };
      return { ok: true, status: 200, json: async () => ({ jsonrpc: '2.0', id: request.id, result: [0, value] }) };
    }
    const content = files.get('/www' + u.pathname);
    if (content != null) return { ok: true, status: 200, text: async () => content };
    if (u.pathname === '/zm/theme.txt') return { ok: true, status: 200, text: async () => 'micro' };
    return { ok: false, status: 404, text: async () => '' };
  };
  try {
    w.eval(app);
    for (const page of ['dashboard', 'strategy', 'zapret2', 'hosts', 'terminal']) {
      w.location.hash = '#/' + page;
      await new Promise(r => setTimeout(r, 100));
      const content = w.document.getElementById('zmw-view');
      assert(content && content.querySelector('.zm-wrap'), page + ': shell failed to render ' + content?.textContent);
      assert(!/ReferenceError|is not defined|TypeError/.test(content.textContent));
      assert.equal(errors.length, 0, errors.join('\n'));
      console.log('PASS shell route', page);
    }
    assert.equal(w.document.querySelectorAll('.zmw-nav a').length, 5);
    assert(!fetched.some(p => /\/(steer|forkozz|awg|adblock|mixomo|monitor|backup)\.js$/.test(p)));
    assert(!w.document.querySelector('a[href*="stresskvn"],a[href*="stressozz_manager"]'));
  } finally { w.close(); }
}
(async () => {
  for (const web of [false, true]) for (const page of ['dashboard', 'strategy', 'zapret2', 'hosts', 'terminal']) await render(page, web);
  await shell();
  if (process.env.ZM_RENDER_OUTPUT) fs.writeFileSync(process.env.ZM_RENDER_OUTPUT, JSON.stringify(results, null, 2));
})().catch(e => { console.error(e.stack); process.exitCode = 1; });
