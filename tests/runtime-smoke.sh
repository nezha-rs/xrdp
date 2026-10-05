#!/usr/bin/env bash
set -Eeuo pipefail
ASSETS=$(realpath "${1:?Provide the release assets directory}")
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends xserver-xorg-core libssl3t64 libpam0g libx11-6 \
  libxfixes3 libxrandr2 libxkbfile1 libibus-1.0-5 libglib2.0-0t64 libjpeg62-turbo libfuse3-4 xz-utils
cd "$ASSETS"
sha256sum -c SHA256SUMS
tar -xJf xrdp-unicode-debian13-amd64.tar.xz -C /opt
PREFIX=/opt/xrdp-unicode
for private_file in cert.pem key.pem rsakeys.ini; do
  [[ ! -e "$PREFIX/etc/xrdp/$private_file" && ! -L "$PREFIX/etc/xrdp/$private_file" ]] || exit 1
done
"$PREFIX/bin/xrdp-keygen" xrdp /tmp/test-rsakeys.ini
test -s /tmp/test-rsakeys.ini
"$PREFIX/sbin/xrdp" --version
"$PREFIX/sbin/xrdp-sesman" --version
for binary in "$PREFIX"/sbin/* "$PREFIX"/bin/* "$PREFIX"/lib/xorg/modules/*.so "$PREFIX"/lib/xorg/modules/drivers/*.so; do
  [[ -f $binary ]] || continue
  if ldd "$binary" 2>/dev/null | grep -q 'not found'; then
    echo "Missing runtime dependency: $binary" >&2
    ldd "$binary" >&2
    exit 1
  fi
done
test -s "$PREFIX/etc/X11/xrdp/xorg.conf"
echo 'Runtime linking passed; this does not test GNOME login or Unicode input.'
