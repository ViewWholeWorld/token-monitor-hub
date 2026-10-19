# Token Monitor Node Hub 镜像

仅维护构建与部署配置。Actions 从 [Javis603/token-monitor](https://github.com/Javis603/token-monitor) 获取明确版本的公开源码，构建、测试后发布到 `ghcr.io/viewwholeworld/token-monitor-hub`。镜像保留上游 MIT 许可。

## 更新只需两步

1. 在本仓库 **Actions → 构建并发布 Hub 镜像 → Run workflow**，输入上游 tag 或提交；`latest` 表示上游最新正式 Release。等待所有测试及发布成功。
2. SSH 登录已配置的 NAS：

```sh
cd /share/homes/tromso/apps/token-monitor
sh ./hub.sh update
```

默认使用本仓库最近一次成功发布的 `latest` 镜像；它不会自行触发构建。也可从 Actions 总结复制不可变构建标签：

```sh
sh ./hub.sh update build-运行编号-尝试编号
```

NAS 会先拉取镜像，再短暂停服备份数据、切换并验收；失败时尝试自动恢复更新前快照。配置中保存实际 digest，防止浮动标签改变正在选定的版本。旧镜像不会自动清理。初次发布的 GHCR 包需设置为 Public，NAS 才能免登录拉取。

## 日常维护

```sh
sh ./hub.sh status
sh ./hub.sh logs
sh ./hub.sh backup
sh ./hub.sh rollback
```

回退恢复最近一次更新前的配置及数据快照，升级后新增数据会从当前文件中撤回；脚本会保留回退前的数据目录供找回。备份包含密钥，应保护访问权限。没有后台自动更新或定时任务。

## 一次性接入现有部署

将 `deploy/compose.image.yml` 放到现有 NAS 项目的 `deploy/hub/compose.image.yml`，将 `deploy/hub.sh` 放到项目根目录。保留原 `deploy/hub/.env`、数据目录、UID/GID 和密钥，然后执行更新。脚本适用于已存在的 `token-monitor` Compose 项目、`token-monitor-hub-1` 容器及项目内 `data/` 目录。

新的部署不应直接套用此迁移脚本：需要先按上游指南完成私有配置与数据目录初始化。NAS 不需要保存 GitHub token；同步密钥和真实数据都不进入构建仓库。

## 构建与验证

首次 push 使用 `upstream-ref.txt` 的固定提交；手动 Actions 可以选择版本。当前只发布 QNAP 本机需要的 `linux/amd64`。

发布之前会运行最终镜像中的 Hub 测试，以及独立临时容器的鉴权、双设备聚合、SSE 和重启持久化检查。测试不访问 NAS。只有检查通过的镜像会发布 `build-*`、`sha-*` 和 `latest` 标签。若未来上游入口或依赖改变，构建/测试会阻止发布，需要调整本仓库适配。

`package.json` 和 lock 只声明当前 Hub 所需的 `dotenv`，不运行上游安装脚本或下载 tokscale。修改本仓库构建文件的 push 也会重新构建固定基线；选择新的上游版本请用手动 Actions。

参考：[GitHub 镜像发布](https://docs.github.com/en/actions/tutorials/publish-packages/publish-docker-images)、[Docker Compose up](https://docs.docker.com/reference/cli/docker/compose/up/)。
