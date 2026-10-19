'use strict';
const assert = require('node:assert/strict');
const base = 'http://127.0.0.1:17321';
const headers = { Authorization: `Bearer ${process.env.TOKEN_MONITOR_SECRET}` };
async function json(path, options = {}) {
  const response = await fetch(base + path, { ...options, headers: { ...headers, ...options.headers }, signal: AbortSignal.timeout(10000) });
  assert.ok(response.ok, `${path}: ${response.status}`);
  return response.json();
}
async function main() {
  // Docker restart 返回时 Node 进程可能仍在启动，允许有限重试。
  for (let attempt = 0; ; attempt += 1) {
    try { await json('/api/health'); break; }
    catch (error) { if (attempt >= 20) throw error; await new Promise((resolve) => setTimeout(resolve, 250)); }
  }
  const health = await json('/api/health');
  assert.equal(health.secretRequired, true);
  assert.equal(health.runtime, 'node-hub');
  assert.equal((await fetch(base + '/api/stats')).status, 401);
  if (process.argv[2] === 'upload') {
    const controller = new AbortController();
    const stream = await fetch(base + '/api/stats/stream', { headers, signal: controller.signal });
    assert.equal(stream.status, 200);
    const reader = stream.body.getReader();
    let timer;
    const events = (async () => {
      let text = '';
      while (!text.includes('event: stats')) {
        const { value, done } = await reader.read();
        assert.equal(done, false);
        text += Buffer.from(value).toString('utf8');
      }
    })();
    try {
      for (const [index, deviceId] of ['smoke-a', 'smoke-b'].entries()) {
        await json('/api/ingest', { method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ deviceId, updatedAt: new Date().toISOString(), today: { totalTokens: 111 * (index + 1) } }) });
      }
      await Promise.race([events, new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('SSE 未更新')), 10000); })]);
    } finally {
      clearTimeout(timer);
      controller.abort();
      await events.catch(() => {});
    }
  }
  const stats = await json('/api/stats');
  assert.equal(stats.devices.length, 2);
  assert.equal(stats.periods.today.totalTokens, 333);
  console.log('PASS 鉴权、双设备聚合、SSE / 重启后数据保留');
}
main().catch((error) => { console.error(error); process.exitCode = 1; });
