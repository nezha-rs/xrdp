# Debian 13 GNOME / Unicode xrdp 一键安装

面向 **Debian 13 amd64、systemd 云服务器**。安装 GNOME X11、固定开发提交的 IBus xrdp/xorgxrdp、ChatGPT Linux Preview（含 Codex）、CC Switch 和 Telegram。

## 一键安装（root SSH）

仓库：`nezha-rs/xrdp`；当前默认固定版本为 `v1.0.0`，内置对应二进制 SHA256。

刚 DD 的极简系统可以直接执行（把 `xxxx` 替换成强密码）：

```bash
apt-get update && apt-get install -y curl ca-certificates && curl --proto '=https' --tlsv1.2 -fL --retry 3 https://github.com/nezha-rs/xrdp/releases/download/v1.0.0/install-debian13-gnome-rdp-codex.sh -o /root/install-xrdp.sh && bash /root/install-xrdp.sh --username codex --password 'xxxx'
```

上述命令通过 HTTPS 下载固定版本安装器；如需更严格的供应链校验，先下载、比对 Release 的安装器 SHA256 并阅读脚本，再执行。脚本会使用内置校验值验证二进制包。

已经下载脚本时：

```bash
bash install-debian13-gnome-rdp-codex.sh --username codex --password '替换为强密码'
```

覆盖仓库/版本时，也要明确指定该版本对应的二进制校验值：

```bash
bash install-debian13-gnome-rdp-codex.sh \
  --username codex --password '替换为强密码' \
  --repo nezha-rs/xrdp --release v1.0.0 \
  --sha256 f0a74010206cbff763b24720aff4555c60a573847b998a8f48d4780ac35708fe
```

脚本不使用 `latest`，也不会在二进制下载失败时静默转为源码编译。

密码参数可能被进程列表、shell 历史或会话审计记录看到。不要把真实密码写入仓库、Actions 工作流、截图或发布说明。用户不存在时自动创建；存在时更新密码；不会自动授予 sudo 权限。

## 参数

| 参数 | 含义 |
|---|---|
| `--username` | 必填，普通桌面用户 |
| `--password` | 必填，设置/更新用户密码 |
| `--mode binary` | 默认，下载预编译包 |
| `--repo OWNER/REPO` | 覆盖默认仓库/版本时指定 |
| `--release v1.0.0` | 覆盖默认仓库/版本时指定，固定 Release 标签 |
| `--sha256 HASH` | 覆盖默认仓库/版本时指定，可信 SHA256 |
| `--mode source` | 在目标服务器从固定源码提交编译 |
| `--rdp-port 3389` | 默认 3389，范围 1024–65535 |
| `--build-jobs 2` | 源码编译并发数，默认 2 |
| `--help` | 查看帮助，不需要 root |

源码模式（不需要本仓库的 Release）：

```bash
bash install-debian13-gnome-rdp-codex.sh \
  --username codex --password '替换为强密码' --mode source
```

## 安装与连接

1. 检查系统、架构、systemd 和参数。
2. 创建普通用户或更新密码，备份旧配置；已有自定义安装也会备份整个 `/opt/xrdp-unicode`。
3. APT 安装 GNOME、字体、IBus、桌面运行库；源码模式另外安装编译工具。
4. 校验并安装预编译包，或编译 xrdp/xorgxrdp。
5. 生成服务器自己的 TLS 证书、GNOME 启动配置、PAM 和 systemd 服务。
6. 下载并校验固定 Codex/CC Switch 包，安装 Telegram。
7. 停用系统原版 xrdp，启用自定义服务并检查状态。

保留 SSH 通道。云安全组/防火墙仅对可信来源开放 TCP RDP 端口，脚本不会自动开放端口，也不会重启服务器。RDP 客户端选择 **Xorg**，使用普通用户登录；同一用户不要同时运行其他图形会话。首次连接核对 TLS 指纹：

```bash
openssl x509 -in /opt/xrdp-unicode/etc/xrdp/tls/cert.pem -noout -fingerprint -sha256
```

## 来源与验证边界

- xrdp：`9cd64936f53eb7c0a876b71787b321835da09ccc`，启用 IBus、IPv6、JPEG、FUSE。
- xorgxrdp：`59d0735c4321b5baff3feaa980a01f78a1c1e96f`。
- Codex：压缩包提供的 `Wangnov/codex-app-mirror` 第三方镜像，ChatGPT Linux Preview `26.803.81509`。不是这里宣称的官方独立 Linux Codex 包。
- CC Switch：`farion1231/cc-switch` 的 `v3.20.4`。
- Telegram：官方 Linux 下载入口，版本会随上游变化。

固定 xrdp 提交是开发版构建，不代表官方稳定版保证。已完成依赖安装、源码编译及应用包安装测试；完整 GNOME/RDP 登录和中文 Unicode 输入尚未验收。Actions 检查编译、校验值和运行库，不检查真实 RDP 图形登录。

只支持 Debian 13 amd64；系统更新后的 Xorg/动态库兼容性仍需重新测试。完整 GNOME 元包会安装较多附带应用。不要把脚本失败后残留状态当成已自动回滚。

## 发布到 GitHub

见 `RELEASE.md`。`scripts/build-prebuilt.sh` 仅应在可丢弃的 Debian 13 构建容器中运行，不要直接在个人电脑上运行。
