#!/bin/sh
set -eu
ROOT="${1:-}"
if [ -z "$ROOT" ]; then
    HERE=$(cd "$(dirname "$0")" && pwd)
else
    HERE=$ROOT
fi

install -d /usr/local/sbin /persistent/udm-sata/bin /lib/systemd/system-shutdown /etc/systemd/system
install -d /usr/lib/ubnt/hooks/system/bootup-top /usr/lib/ubnt/hooks/system/upgrade-bottom

install -m 755 "$HERE/udm-sata-env" /usr/local/sbin/udm-sata-env
install -m 755 "$HERE/udm-sata-guard" /usr/local/sbin/udm-sata-guard
install -m 755 "$HERE/udm-sata-apply-bin" /usr/local/sbin/udm-sata-apply-bin
install -m 644 "$HERE/ubnt_bin.py" /usr/local/sbin/ubnt_bin.py
install -m 755 "$HERE/udm-sata-restore-env" /lib/systemd/system-shutdown/udm-sata-restore-env
install -m 644 "$HERE/udm-sata-guard.service" /etc/systemd/system/udm-sata-guard.service
install -m 755 "$HERE/udm-sata.hook" /usr/lib/ubnt/hooks/system/bootup-top/05-udm-sata
install -m 755 "$HERE/udm-sata.hook" /usr/lib/ubnt/hooks/system/upgrade-bottom/90-udm-sata

cp -a "$HERE/." /persistent/udm-sata/bin/
chmod 755 /persistent/udm-sata/bin/udm-sata-env \
    /persistent/udm-sata/bin/udm-sata-guard \
    /persistent/udm-sata/bin/udm-sata-apply-bin \
    /persistent/udm-sata/bin/udm-sata-restore-env \
    /persistent/udm-sata/bin/udm-sata.hook \
    /persistent/udm-sata/bin/install.sh \
    /persistent/udm-sata/bin/format-os-disk.sh \
    /persistent/udm-sata/bin/inspect-bin.py || true
chmod 644 /persistent/udm-sata/bin/udm-sata-guard.service \
    /persistent/udm-sata/bin/ubnt_bin.py

systemctl daemon-reload
systemctl enable udm-sata-guard.service
/usr/local/sbin/udm-sata-guard
/usr/local/sbin/udm-sata-env restore
/usr/local/sbin/udm-sata-env show
echo "installed. later updates:  udm-sata-apply-bin /path/to/UDMPRO-x.y.z.bin"
