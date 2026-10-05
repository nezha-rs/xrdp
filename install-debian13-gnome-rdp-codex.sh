#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "安装失败：第 $LINENO 行。请保留 SSH 会话，不要重启。" >&2' ERR

DESKTOP_USER=
DESKTOP_PASSWORD=
RDP_PORT=3389
BUILD_JOBS=2
INSTALL_MODE=binary
RELEASE_REPO=nezha-rs/xrdp
RELEASE_TAG=v1.0.0
ARCHIVE_SHA256=f0a74010206cbff763b24720aff4555c60a573847b998a8f48d4780ac35708fe
while [[ $# -gt 0 ]]; do
  case "$1" in
    --username)
      [[ $# -ge 2 ]] || { echo '--username 缺少参数。' >&2; exit 1; }
      DESKTOP_USER=$2; shift 2 ;;
    --password)
      [[ $# -ge 2 ]] || { echo '--password 缺少参数。' >&2; exit 1; }
      DESKTOP_PASSWORD=$2; shift 2 ;;
    --rdp-port)
      [[ $# -ge 2 ]] || { echo '--rdp-port 缺少参数。' >&2; exit 1; }
      RDP_PORT=$2; shift 2 ;;
    --build-jobs)
      [[ $# -ge 2 ]] || { echo '--build-jobs 缺少参数。' >&2; exit 1; }
      BUILD_JOBS=$2; shift 2 ;;
    --mode|--repo|--release|--sha256)
      [[ $# -ge 2 ]] || { echo "$1 缺少参数。" >&2; exit 1; }
      case "$1" in
        --mode) INSTALL_MODE=$2 ;;
        --repo) RELEASE_REPO=$2 ;;
        --release) RELEASE_TAG=$2 ;;
        --sha256) ARCHIVE_SHA256=$2 ;;
      esac
      shift 2 ;;
    -h|--help)
      echo "用法：$0 --username 用户名 --password 密码 [--mode binary --repo OWNER/REPO --release v1.0.0 --sha256 HASH | --mode source] [--rdp-port 3389] [--build-jobs 2]"; exit 0 ;;
    *)
      echo "未知参数：$1" >&2
      echo "用法：$0 --username 用户名 --password 密码 [--mode binary --repo OWNER/REPO --release v1.0.0 --sha256 HASH | --mode source] [--rdp-port 3389] [--build-jobs 2]" >&2
      exit 1 ;;
  esac
done
[[ -n $DESKTOP_USER ]] || { echo '必须指定 --username。'; exit 1; }
[[ -n $DESKTOP_PASSWORD ]] || { echo '必须指定 --password，且密码不能为空。'; exit 1; }
[[ $DESKTOP_USER =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || { echo '用户名格式不合法。'; exit 1; }
[[ $DESKTOP_PASSWORD != *$'\n'* && $DESKTOP_PASSWORD != *$'\r'* ]] || { echo '密码不能包含换行符。'; exit 1; }
[[ $BUILD_JOBS =~ ^[1-9][0-9]*$ ]] || { echo '--build-jobs 必须是正整数。'; exit 1; }
[[ $INSTALL_MODE == binary || $INSTALL_MODE == source ]] || { echo '--mode 必须为 binary 或 source。'; exit 1; }
if [[ $INSTALL_MODE == binary ]]; then
  [[ $RELEASE_REPO =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ && $RELEASE_TAG =~ ^[A-Za-z0-9_.-]+$ && $ARCHIVE_SHA256 =~ ^[a-fA-F0-9]{64}$ ]] || {
    echo '二进制模式必须提供 --repo OWNER/REPO --release 固定版本 --sha256 可信校验值。' >&2; exit 1;
  }
fi
[[ $(ps -p 1 -o comm=) == systemd ]] || { echo '需要 systemd 作为 PID 1；普通 Docker 容器不能运行完整安装流程。'; exit 1; }
[[ $EUID -eq 0 ]] || { echo '请以 root 执行。'; exit 1; }
. /etc/os-release
[[ ${ID:-} == debian && ${VERSION_ID:-} == 13 ]] || { echo '此脚本仅支持 Debian 13。'; exit 1; }
[[ $(dpkg --print-architecture) == amd64 ]] || { echo '此脚本仅支持 amd64。'; exit 1; }

PREFIX=/opt/xrdp-unicode
[[ $RDP_PORT =~ ^[0-9]+$ && $RDP_PORT -ge 1024 && $RDP_PORT -le 65535 ]] || { echo 'RDP_PORT 必须是 1024-65535。'; exit 1; }
if id "$DESKTOP_USER" >/dev/null 2>&1; then
  [[ $(id -u "$DESKTOP_USER") -ne 0 ]] || { echo '禁止使用 root 作为桌面用户。'; exit 1; }
else
  useradd --create-home --shell /bin/bash "$DESKTOP_USER"
fi
printf '%s:%s\n' "$DESKTOP_USER" "$DESKTOP_PASSWORD" | chpasswd
unset DESKTOP_PASSWORD
UID_NUM=$(id -u "$DESKTOP_USER")
HOME_DIR=$(getent passwd "$DESKTOP_USER" | cut -d: -f6)
[[ -d "$HOME_DIR" ]] || { echo "用户家目录不存在：$HOME_DIR"; exit 1; }
BACKUP=/root/rdp-backup-$(date +%Y%m%d-%H%M%S)
mkdir -p "$BACKUP"
for path in /etc/xrdp /etc/pam.d/xrdp-sesman /etc/systemd/system/xrdp.service /etc/systemd/system/xrdp-sesman.service /etc/systemd/system/xrdp-unicode.service /etc/systemd/system/xrdp-unicode-sesman.service; do
  [[ -e $path ]] && cp -a --parents "$path" "$BACKUP/"
done

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
  task-gnome-desktop gnome-session gnome-session-xsession gnome-terminal gdm3 \
  xserver-xorg-core xauth dbus-x11 dbus-user-session ibus ibus-gtk ibus-gtk3 ibus-gtk4 \
  fonts-noto-cjk locales sudo libpam-systemd \
  libssl3t64 libpam0g libx11-6 libxfixes3 libxrandr2 libxkbfile1 libibus-1.0-5 \
  libglib2.0-0t64 libjpeg62-turbo libfuse3-4 curl ca-certificates openssl python3 xz-utils \
  libxcb-cursor0 libxcb-keysyms1 libxcb-image0 libxcb-render-util0 libxcb-icccm4 \
  libxcb-xinerama0 libxcb-xkb1 libxkbcommon-x11-0 libgl1 libegl1 libnss3 libasound2t64

getent passwd xrdp >/dev/null || adduser --system --group --home /run/xrdp --no-create-home xrdp
getent group xrdp-login >/dev/null || groupadd --system xrdp-login
usermod -aG xrdp-login "$DESKTOP_USER"

if [[ -d $PREFIX ]]; then cp -a "$PREFIX" "$BACKUP/prefix"; fi
if [[ $INSTALL_MODE == source ]]; then
apt-get install -y git build-essential autoconf automake libtool pkg-config libssl-dev libpam0g-dev \
  libx11-dev libxfixes-dev libxrandr-dev libxkbfile-dev libibus-1.0-dev libglib2.0-dev \
  libjpeg-dev libfuse3-dev nasm xserver-xorg-dev xutils-dev libepoxy-dev libdrm-dev libgbm-dev libegl-dev
mkdir -p /usr/local/src
BUILD=$(mktemp -d /usr/local/src/rdp-unicode.XXXXXX)
mkdir -p "$BUILD"
git clone https://github.com/neutrinolabs/xrdp.git "$BUILD/xrdp"
cd "$BUILD/xrdp"
git checkout 9cd64936f53eb7c0a876b71787b321835da09ccc
git submodule update --init --recursive
./bootstrap
./configure --prefix="$PREFIX" --enable-strict-locations --sysconfdir="$PREFIX/etc" \
  --with-pamconfdir="$PREFIX/pam-template" --enable-pam-config=debian \
  --localstatedir=/var --with-socketdir=/run/xrdp-unicode --with-systemdsystemunitdir=no \
  --enable-ibus --enable-ipv6 --enable-jpeg --enable-fuse --disable-lvgl
make -j"$BUILD_JOBS"
if systemctl is-active --quiet xrdp-unicode.service || systemctl is-active --quiet xrdp-unicode-sesman.service; then
  systemctl stop xrdp-unicode.service xrdp-unicode-sesman.service || true
fi
make install
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
git clone https://github.com/neutrinolabs/xorgxrdp.git "$BUILD/xorgxrdp"
cd "$BUILD/xorgxrdp"
git checkout 59d0735c4321b5baff3feaa980a01f78a1c1e96f
./bootstrap
./configure --prefix="$PREFIX" --libdir="$PREFIX/lib" --sysconfdir="$PREFIX/etc" --enable-strict-locations
make -j"$BUILD_JOBS"
make install
else
  BINARY_TMP=$(mktemp -d)
  trap 'rm -rf "$BINARY_TMP"' EXIT
  ARCHIVE=xrdp-unicode-debian13-amd64.tar.xz
  curl --proto '=https' --tlsv1.2 -fL --retry 3 "https://github.com/$RELEASE_REPO/releases/download/$RELEASE_TAG/$ARCHIVE" -o "$BINARY_TMP/$ARCHIVE"
  printf '%s  %s\n' "$ARCHIVE_SHA256" "$BINARY_TMP/$ARCHIVE" | sha256sum -c -
  export BINARY_TMP
  python3 - <<'VERIFY'
import os, tarfile
from pathlib import PurePosixPath
with tarfile.open(os.environ['BINARY_TMP'] + '/xrdp-unicode-debian13-amd64.tar.xz') as archive:
    for member in archive.getmembers():
        path = PurePosixPath(member.name)
        if path.is_absolute() or '..' in path.parts or not path.parts or path.parts[0] != 'xrdp-unicode':
            raise RuntimeError('Unsafe archive path')
        if not (member.isfile() or member.isdir() or member.issym()):
            raise RuntimeError('Unsupported archive entry')
        if member.issym():
            target = PurePosixPath(member.linkname)
            if target.is_absolute() or '..' in target.parts:
                raise RuntimeError('Unsafe symlink')
VERIFY
  systemctl stop xrdp-unicode.service xrdp-unicode-sesman.service 2>/dev/null || true
  tar -xJf "$BINARY_TMP/$ARCHIVE" -C /opt --no-same-owner
  "$PREFIX/sbin/xrdp" --version
fi
[[ -f /etc/pam.d/xrdp-sesman ]] || install -m 644 "$PREFIX/pam-template/xrdp-sesman" /etc/pam.d/xrdp-sesman
[[ -e $PREFIX/lib/xorg/modules/libxorgxrdp.so && -e $PREFIX/lib/xorg/modules/drivers/xrdpdev_drv.so && -e $PREFIX/etc/X11/xrdp/xorg.conf ]]

if [[ ! -s $PREFIX/etc/xrdp/rsakeys.ini ]]; then
  "$PREFIX/bin/xrdp-keygen" xrdp "$PREFIX/etc/xrdp/rsakeys.ini"
fi
install -d -m 750 -o root -g xrdp "$PREFIX/etc/xrdp/tls"
if [[ ! -s $PREFIX/etc/xrdp/tls/cert.pem || ! -s $PREFIX/etc/xrdp/tls/key.pem ]]; then
  openssl req -x509 -newkey rsa:3072 -nodes -days 365 -subj "/CN=$(hostname)" \
    -keyout "$PREFIX/etc/xrdp/tls/key.pem" -out "$PREFIX/etc/xrdp/tls/cert.pem"
fi
chown root:xrdp "$PREFIX/etc/xrdp/tls/"*.pem
chmod 640 "$PREFIX/etc/xrdp/tls/"*.pem

export DESKTOP_USER UID_NUM PREFIX RDP_PORT
python3 - <<'PY'
import os, re, subprocess
from pathlib import Path
base = Path(os.environ['PREFIX']); conf = base / 'etc/xrdp'
def section(text, name, transform):
    match = re.search(r'(?ms)^\[' + re.escape(name) + r'\][^\n]*\n(.*?)(?=^\[|\Z)', text)
    if not match: raise RuntimeError('Missing section: ' + name)
    return text[:match.start(1)] + transform(match.group(1)) + text[match.end(1):]
def values(block, pairs):
    for key, value in pairs.items():
        block = re.sub(r'(?m)^\s*[#;]?\s*' + re.escape(key) + r'\s*=.*\n?', '', block)
        block += f'{key}={value}\n'
    return block + '\n'
p = conf / 'xrdp.ini'; text = p.read_text()
text = section(text, 'Globals', lambda b: values(b, {'port': os.environ['RDP_PORT'], 'runtime_user': 'xrdp', 'runtime_group': 'xrdp', 'security_layer': 'tls', 'certificate': str(conf / 'tls/cert.pem'), 'key_file': str(conf / 'tls/key.pem')}))
p.write_text(section(text, 'Logging', lambda b: values(b, {'LogFile': '/var/log/xrdp-unicode.log'})))
p = conf / 'sesman.ini'; text = p.read_text()
text = section(text, 'Security', lambda b: values(b, {'AllowRootLogin': 'false', 'AlwaysGroupCheck': 'true', 'TerminalServerUsers': 'xrdp-login', 'SessionSockdirGroup': 'root'}))
text = section(text, 'Logging', lambda b: values(b, {'LogFile': '/var/log/xrdp-unicode-sesman.log'}))
text = section(text, 'Sessions', lambda b: values(b, {'MaxSessions': '1', 'StartupWaitTime': '10000'}))
text = section(text, 'Globals', lambda b: values(b, {'EnableUserWindowManager': 'false', 'DefaultWindowManager': str(conf / 'startwm-unicode.sh')}))
modules = '/usr/lib/xorg/modules'
params = ['/usr/lib/xorg/Xorg', '-config', str(base / 'etc/X11/xrdp/xorg.conf'), '-modulepath', str(base / 'lib/xorg/modules') + ',' + modules, '-noreset', '-nolisten', 'tcp', '-logfile', '.xorgxrdp.%s.log']
text = section(text, 'Xorg', lambda b: ''.join('param=' + x + '\n' for x in params) + '\n')
text = section(text, 'SessionVariables', lambda b: values(b, {'XDG_RUNTIME_DIR': '/run/user/' + os.environ['UID_NUM'], 'DBUS_SESSION_BUS_ADDRESS': 'unix:path=/run/user/' + os.environ['UID_NUM'] + '/bus', 'GTK_IM_MODULE': 'ibus', 'QT_IM_MODULE': 'ibus', 'XMODIFIERS': '@im=ibus'}))
p.write_text(text)
PY

cat > "$PREFIX/etc/xrdp/startwm-unicode.sh" <<'EOF2'
#!/usr/bin/env bash
set -eu
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus
export GTK_IM_MODULE=ibus QT_IM_MODULE=ibus XMODIFIERS=@im=ibus
export XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=GNOME
unset SESSION_MANAGER WAYLAND_DISPLAY IBUS_ADDRESS IBUS_ADDRESS_FILE IBUS_USE_PORTAL
[[ -r /etc/default/locale ]] && . /etc/default/locale && export LANG
[[ -S $XDG_RUNTIME_DIR/bus ]] || { echo 'User D-Bus unavailable' >&2; exit 1; }
dbus-update-activation-environment --systemd DISPLAY XAUTHORITY GTK_IM_MODULE QT_IM_MODULE XMODIFIERS || true
if ! timeout 2 ibus engine >/dev/null 2>&1; then ibus-daemon --daemonize --xim --desktop=GNOME; fi
timeout 5 bash -c 'until ibus engine xkb:us::eng >/dev/null 2>&1; do sleep 0.1; done'
exec gnome-session --session=gnome
EOF2
chmod 755 "$PREFIX/etc/xrdp/startwm-unicode.sh"

cat > /etc/systemd/system/xrdp-unicode-sesman.service <<EOF2
[Unit]
Description=xrdp Unicode session manager
After=network.target
[Service]
Type=exec
RuntimeDirectory=xrdp-unicode
RuntimeDirectoryMode=0755
ExecStart=$PREFIX/sbin/xrdp-sesman --nodaemon --config $PREFIX/etc/xrdp/sesman.ini
[Install]
WantedBy=multi-user.target
EOF2
cat > /etc/systemd/system/xrdp-unicode.service <<EOF2
[Unit]
Description=xrdp with Unicode input support
Requires=xrdp-unicode-sesman.service
After=network.target xrdp-unicode-sesman.service
[Service]
Type=exec
ExecStart=$PREFIX/sbin/xrdp --nodaemon --config $PREFIX/etc/xrdp/xrdp.ini
[Install]
WantedBy=multi-user.target
EOF2
systemctl daemon-reload

TMP=$(mktemp -d)
chmod 755 "$TMP"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
CODEX_VERSION=26.803.81509
CODEX_FILE="chatgpt_${CODEX_VERSION}_amd64.deb"
CC_VERSION=v3.20.4
CC_FILE="CC-Switch-${CC_VERSION}-Linux-x86_64.deb"
curl -fL --retry 3 "https://github.com/Wangnov/codex-app-mirror/releases/download/codex-app-linux-preview-${CODEX_VERSION}/${CODEX_FILE}" -o "$CODEX_FILE"
curl -fL --retry 3 "https://github.com/farion1231/cc-switch/releases/download/${CC_VERSION}/${CC_FILE}" -o "$CC_FILE"
printf '%s  %s\n' a9bf91a368f9f7c4eea38082a9fb8fb46b8d005b719a6d7715d2e5a1982c38eb "$CODEX_FILE" 434557d3ae08b792c8138c5508f104e799f36d2ced563fb94b3a86ffbb250801 "$CC_FILE" | sha256sum -c -
chmod 644 "$CODEX_FILE" "$CC_FILE"
apt-get install -y "$TMP/$CODEX_FILE" "$TMP/$CC_FILE"
curl -fL --retry 3 https://telegram.org/dl/desktop/linux -o "$TMP/telegram.tar.xz"
chmod 644 "$TMP/telegram.tar.xz"
runuser -u "$DESKTOP_USER" -- mkdir -p "$HOME_DIR/.local/opt" "$HOME_DIR/.local/share/applications"
if [[ -d $HOME_DIR/.local/opt/Telegram ]]; then runuser -u "$DESKTOP_USER" -- cp -a "$HOME_DIR/.local/opt/Telegram" "$HOME_DIR/.local/opt/Telegram.backup-$(date +%Y%m%d-%H%M%S)"; fi
runuser -u "$DESKTOP_USER" -- tar -xJf "$TMP/telegram.tar.xz" -C "$HOME_DIR/.local/opt"
export HOME_DIR DESKTOP_USER
python3 - <<'PY'
import os, pwd
from pathlib import Path
u = pwd.getpwnam(os.environ['DESKTOP_USER']); home = Path(os.environ['HOME_DIR'])
p = home / '.local/share/applications/telegram-official.desktop'
p.write_text(f'''[Desktop Entry]\nType=Application\nName=Telegram Desktop\nExec={home}/.local/opt/Telegram/Telegram -- %u\nIcon=telegram\nTerminal=false\nCategories=Network;InstantMessaging;\nMimeType=x-scheme-handler/tg;\n''')
os.chown(p, u.pw_uid, u.pw_gid); os.chmod(p, 0o644)
PY

systemctl disable --now xrdp.service xrdp-sesman.service 2>/dev/null || true
systemctl enable --now xrdp-unicode-sesman.service xrdp-unicode.service
systemctl is-active xrdp-unicode-sesman.service xrdp-unicode.service
"$PREFIX/sbin/xrdp" --version
echo
echo '安装完成。'
echo "桌面用户：$DESKTOP_USER"
echo "RDP 端口：$RDP_PORT"
echo "备份目录：$BACKUP"
echo '请使用 RDP 客户端选择 Xorg 登录；不要使用 root。'
echo '安全组只开放给可信 IP 的 TCP 3389（或你设置的 RDP_PORT）。'
