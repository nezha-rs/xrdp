#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo 'Build inside a disposable Debian 13 container as root.' >&2; exit 1; }
. /etc/os-release
[[ $ID == debian && $VERSION_ID == 13 && $(dpkg --print-architecture) == amd64 ]] || exit 1
OUTPUT_DIR=${1:-/out}
BUILD_JOBS=${BUILD_JOBS:-2}
PREFIX=/opt/xrdp-unicode
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR=$(realpath "$OUTPUT_DIR")
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends git build-essential autoconf automake libtool pkg-config \
  libssl-dev libpam0g-dev libx11-dev libxfixes-dev libxrandr-dev libxkbfile-dev \
  libibus-1.0-dev libglib2.0-dev libjpeg-dev libfuse3-dev nasm xserver-xorg-dev \
  xutils-dev libepoxy-dev libdrm-dev libgbm-dev libegl-dev ca-certificates python3 xz-utils
STAGE=$(mktemp -d)
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
make install
make install DESTDIR="$STAGE"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
git clone https://github.com/neutrinolabs/xorgxrdp.git "$BUILD/xorgxrdp"
cd "$BUILD/xorgxrdp"
git checkout 59d0735c4321b5baff3feaa980a01f78a1c1e96f
./bootstrap
./configure --prefix="$PREFIX" --libdir="$PREFIX/lib" --sysconfdir="$PREFIX/etc" --enable-strict-locations
make -j"$BUILD_JOBS"
make install DESTDIR="$STAGE"

export STAGE PREFIX
python3 - <<'CLEAN'
import os
from pathlib import Path
conf = Path(os.environ['STAGE'] + os.environ['PREFIX']) / 'etc/xrdp'
for name in ['cert.pem', 'key.pem', 'rsakeys.ini']:
    (conf / name).unlink(missing_ok=True)
CLEAN
install -d "$STAGE$PREFIX/share/licenses/xrdp" "$STAGE$PREFIX/share/licenses/xorgxrdp"
install -m 644 "$BUILD/xrdp/COPYING" "$STAGE$PREFIX/share/licenses/xrdp/COPYING"
install -m 644 "$BUILD/xorgxrdp/COPYING" "$STAGE$PREFIX/share/licenses/xorgxrdp/COPYING"
export STAGE PREFIX OUTPUT_DIR BUILD
python3 - <<'PYCODE'
import json, os, subprocess
from pathlib import Path
manifest = {
    "os": "debian", "version": "13", "architecture": "amd64",
    "prefix": "/opt/xrdp-unicode",
    "xrdp_commit": "9cd64936f53eb7c0a876b71787b321835da09ccc",
    "xorgxrdp_commit": "59d0735c4321b5baff3feaa980a01f78a1c1e96f",
    "features": ["ibus", "ipv6", "jpeg", "fuse"],
    "xorg_version": subprocess.check_output(["pkg-config", "--modversion", "xorg-server"], text=True).strip(),
    "packages": subprocess.check_output(["dpkg-query", "-W", "-f=${Package}=${Version}\n"], text=True).splitlines(),
    "tested": "Compilation and install only; GNOME/RDP/Unicode login not certified.",
}
text = json.dumps(manifest, indent=2) + "\n"
Path(os.environ["OUTPUT_DIR"], "manifest.json").write_text(text)
Path(os.environ["STAGE"] + os.environ["PREFIX"], "manifest.json").write_text(text)
PYCODE
"$PREFIX/sbin/xrdp" --version
for path in sbin/xrdp sbin/xrdp-sesman lib/xorg/modules/libxorgxrdp.so lib/xorg/modules/drivers/xrdpdev_drv.so etc/X11/xrdp/xorg.conf; do
  test -s "$STAGE$PREFIX/$path"
done
cp -a "$BUILD/xrdp" "$BUILD/xorgxrdp" "$STAGE/"
tar -cJf "$OUTPUT_DIR/xrdp-unicode-sources.tar.xz" -C "$STAGE" xrdp xorgxrdp
tar --sort=name --owner=0 --group=0 --numeric-owner -cJf "$OUTPUT_DIR/xrdp-unicode-debian13-amd64.tar.xz" -C "$STAGE/opt" xrdp-unicode
cd "$OUTPUT_DIR"
sha256sum xrdp-unicode-debian13-amd64.tar.xz xrdp-unicode-sources.tar.xz manifest.json > SHA256SUMS
echo "Release assets ready: $OUTPUT_DIR"
