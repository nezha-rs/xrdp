# 发布流程与版本说明

## GitHub 操作

1. 本项目仓库为 `nezha-rs/xrdp`，上传文件时包含隐藏目录 `.github/workflows/`。
2. 不上传真实密码、私钥、用户数据或测试日志。`dist/` 是 Release 资产目录，不需要提交到 Git。
3. 在 Actions 页执行 **Build Debian 13 xrdp assets** 的手动运行，先确认构建和运行库检查成功；结果在工作流 Artifacts 中。
4. 要正式发布：创建并推送以 `v` 开头的标签，例如 `v1.0.0`。标签触发工作流，成功后创建 Release 并上传资产。
5. 仓库 Actions 的默认令牌需要允许此工作流的 `contents: write`；组织级限制可能需要仓库管理员调整。
6. 在发布说明中记录二进制包的 SHA256，让安装者通过独立可信渠道核对。

如果你使用命令行，以下命令请自行执行（用于维护者首次建立仓库；已有仓库不要重复初始化）：

```bash
git init
git add README.md RELEASE.md .gitignore .github scripts tests install-debian13-gnome-rdp-codex.sh
git commit -m "Add Debian 13 Unicode xrdp binary installer"
git branch -M main
git remote add origin https://github.com/nezha-rs/xrdp.git
git push -u origin main
git tag v1.0.0
git push origin v1.0.0
```

## 固定版本与不可覆盖

`v1.0.0` 是本次本地构建的预览包，安装器内置其 SHA256。不要覆盖已经发布的二进制附件，否则现有安装器会拒绝安装；重新构建应发布新标签，并同步安装器默认版本/校验值。Actions 不会静默覆盖同名资产。

## Release 资产

- `xrdp-unicode-debian13-amd64.tar.xz`：`/opt/xrdp-unicode` 对应的完整程序、Xorg 模块、默认配置、PAM 模板和上游许可证。
- `xrdp-unicode-sources.tar.xz`：固定提交及子模块的构建源码，用于审计和再构建。
- `manifest.json`：目标系统、固定提交、特性、构建时 Xorg 版本和包版本列表。
- `SHA256SUMS`：各发布文件校验值。
- `install-debian13-gnome-rdp-codex.sh`：单文件安装器。
- `README.md` / `RELEASE.md`：使用和发布说明。

不包含已登录账号、API Key、密码或用户家目录。TLS 私钥必须在目标服务器生成。不要把源码包或二进制包中的上游许可证删除；本项目没有替你选择自有脚本的开源许可证，发布者应自行确定。

## 本地构建与验证

机器需要 Docker，但不需要在宿主机安装 GNOME 或编译工具：

```bash
mkdir -p dist
docker run --rm -v "$PWD:/workspace:ro" -v "$PWD/dist:/out" debian:13 \
  bash /workspace/scripts/build-prebuilt.sh /out
docker run --rm -v "$PWD:/workspace:ro" debian:13 \
  bash /workspace/tests/runtime-smoke.sh /workspace/dist
```

容器会安装依赖、联网拉取固定 Git 提交；不是离线安装或逐字节可复现构建。Debian 软件源和基础镜像会更新，因此需要查看 manifest 记录的实际环境。

## 验收边界

本版本只能声明“编译、打包、运行库检查”，不得宣传为完整 GNOME/RDP/安卓中文输入已验收。发布前建议在可丢弃 Debian 13 云服务器验证：服务启动、Xorg 登录、GNOME、重新连接、中文输入、剪贴板、应用启动。

## 故障处理

```bash
journalctl -u xrdp-unicode.service -u xrdp-unicode-sesman.service -n 100 --no-pager
```

备份在安装器输出的 `/root/rdp-backup-时间/`。停止自定义服务后才能恢复文件。原版 xrdp 只有在此前已经安装且存在时才可恢复启动；全新系统并不保证有原版服务作为退路。切换服务失败不会自动回滚。
