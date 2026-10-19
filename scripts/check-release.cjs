'use strict';
const fs = require('node:fs');
const REF_PATTERN = /^[a-zA-Z0-9][a-zA-Z0-9._/-]{0,199}$/;
const REPOSITORY_PATTERN = /^[a-z0-9-]+\/[a-z0-9._-]+$/;

async function checkRelease({ repository, requestedRef = 'latest', force = false, githubToken = '', fetchImpl = fetch }) {
  const image = String(repository || '').toLowerCase();
  if (!REPOSITORY_PATTERN.test(image)) throw new Error('构建仓库标识无效');
  if (!REF_PATTERN.test(requestedRef)) throw new Error('上游版本标识无效');
  const latest = requestedRef === 'latest';
  const endpoint = latest ? 'latest' : `tags/${encodeURIComponent(requestedRef)}`;
  const response = await fetchImpl(`https://api.github.com/repos/Javis603/token-monitor/releases/${endpoint}`, {
    headers: { Accept: 'application/vnd.github+json', 'User-Agent': 'token-monitor-hub-release-check',
      ...(githubToken ? { Authorization: `Bearer ${githubToken}` } : {}) },
    redirect: 'error', signal: AbortSignal.timeout(15000)
  });
  if (response.status === 404) {
    return latest
      ? { shouldBuild: false, reason: '上游尚无正式 Release', ref: '', marker: '' }
      : { shouldBuild: true, reason: '手动指定 tag 或提交', ref: requestedRef, marker: '' };
  }
  if (!response.ok) throw new Error(`查询上游 Release 失败：HTTP ${response.status}`);
  const release = await response.json();
  if (latest && (release.draft || release.prerelease)) {
    return { shouldBuild: false, reason: '忽略草稿或预发布版本', ref: '', marker: '' };
  }
  if (!Number.isSafeInteger(release.id) || release.id <= 0 || !REF_PATTERN.test(release.tag_name || '')) {
    throw new Error('上游 Release 响应格式无效');
  }
  const ref = latest ? release.tag_name : requestedRef;
  const marker = `release-${release.id}`;
  if (force) return { shouldBuild: true, reason: '强制重新构建', ref, marker };

  // 只把成功发布的 GHCR 标记当作已完成；不向 GHCR 传 GitHub token。
  const tokenResponse = await fetchImpl(`https://ghcr.io/token?service=ghcr.io&scope=${encodeURIComponent(`repository:${image}:pull`)}`, {
    redirect: 'error', signal: AbortSignal.timeout(15000)
  });
  if (!tokenResponse.ok) throw new Error(`获取 GHCR 读取凭据失败：HTTP ${tokenResponse.status}`);
  const { token } = await tokenResponse.json();
  if (!token) throw new Error('GHCR 读取凭据响应无效');
  const manifest = await fetchImpl(`https://ghcr.io/v2/${image}/manifests/${marker}`, {
    headers: { Authorization: `Bearer ${token}`, Accept: 'application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json' },
    redirect: 'error', signal: AbortSignal.timeout(15000)
  });
  if (manifest.status === 404) return { shouldBuild: true, reason: '正式 Release 尚未成功构建', ref, marker };
  if (!manifest.ok) throw new Error(`检查 GHCR 发布标记失败：HTTP ${manifest.status}`);
  return { shouldBuild: false, reason: '该 Release 已成功发布，跳过重复构建', ref, marker };
}

async function main() {
  const result = await checkRelease({ repository: process.env.GITHUB_REPOSITORY,
    requestedRef: process.env.REQUESTED_REF || 'latest', force: process.env.FORCE_REBUILD === 'true',
    githubToken: process.env.GH_TOKEN || '' });
  const output = `should_build=${result.shouldBuild}\nref=${result.ref}\nmarker=${result.marker}\n`;
  if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT, output);
  if (process.env.GITHUB_STEP_SUMMARY) {
    fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, `## 上游 Release 检查\n\n${result.reason}${result.ref ? `：\`${result.ref}\`` : ''}。\n\n`);
  }
  console.log(JSON.stringify(result));
}
module.exports = { checkRelease };
if (require.main === module) main().catch((error) => { console.error(error.message); process.exitCode = 1; });
