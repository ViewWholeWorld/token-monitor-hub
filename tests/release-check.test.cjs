'use strict';
const assert = require('node:assert/strict');
const test = require('node:test');
const { checkRelease } = require('../scripts/check-release.cjs');
const stable = { id: 123, tag_name: 'v1.2.3', draft: false, prerelease: false };
function responses(items) {
  const calls = [];
  const fetchImpl = async (url, options) => {
    calls.push({ url, options });
    assert.ok(items.length, '发生了额外网络请求');
    const [status, body = {}] = items.shift();
    return new Response(JSON.stringify(body), { status });
  };
  return { calls, fetchImpl };
}
const options = { repository: 'ViewWholeWorld/token-monitor-hub' };
test('新正式 Release 缺少成功标记时需要构建，并固定本次 tag', async () => {
  const mock = responses([[200, stable], [200, { token: 'registry-test' }], [404]]);
  const actual = await checkRelease({ ...options, ...mock, githubToken: 'github-test' });
  assert.equal(actual.shouldBuild, true);
  assert.equal(actual.ref, 'v1.2.3');
  assert.equal(actual.marker, 'release-123');
  assert.equal(mock.calls[0].options.headers.Authorization, 'Bearer github-test');
  assert.equal(mock.calls[1].options.headers, undefined);
  assert.equal(mock.calls[2].options.headers.Authorization, 'Bearer registry-test');
});
test('已有成功发布标记时跳过，失败构建没有标记因而能重试', async () => {
  const mock = responses([[200, stable], [200, { token: 'test' }], [200]]);
  const actual = await checkRelease({ ...options, ...mock });
  assert.equal(actual.shouldBuild, false);
  assert.equal(actual.marker, 'release-123');
});
test('强制构建无需查询已有镜像标记', async () => {
  const mock = responses([[200, stable]]);
  assert.equal((await checkRelease({ ...options, ...mock, force: true })).shouldBuild, true);
  assert.equal(mock.calls.length, 1);
});
test('上游没有正式 Release 时跳过', async () => {
  const mock = responses([[404]]);
  assert.equal((await checkRelease({ ...options, ...mock })).shouldBuild, false);
});
for (const key of ['draft', 'prerelease']) {
  test(`自动检查忽略 ${key}`, async () => {
    const mock = responses([[200, { ...stable, [key]: true }]]);
    assert.equal((await checkRelease({ ...options, ...mock })).shouldBuild, false);
  });
}
test('查询失败必须报错，不能假装发现新版本', async () => {
  const mock = responses([[403]]);
  await assert.rejects(checkRelease({ ...options, ...mock }), /HTTP 403/);
});
test('GHCR 临时失败必须报错，不能当作标记不存在', async () => {
  const mock = responses([[200, stable], [200, { token: 'test' }], [503]]);
  await assert.rejects(checkRelease({ ...options, ...mock }), /HTTP 503/);
});
test('手动提交仍可以构建，不伪造 Release 标记', async () => {
  const mock = responses([[404]]);
  const actual = await checkRelease({ ...options, ...mock, requestedRef: '734ce844ef1da3e36e4f9d4c5d105113e217448e' });
  assert.equal(actual.shouldBuild, true);
  assert.equal(actual.marker, '');
});
test('拒绝无效版本及响应，避免输出注入', async () => {
  await assert.rejects(checkRelease({ ...options, requestedRef: 'tag\nshould_build=true' }), /版本标识无效/);
  const mock = responses([[200, { ...stable, tag_name: 'tag\nvalue' }]]);
  await assert.rejects(checkRelease({ ...options, ...mock }), /响应格式无效/);
});
