#!/usr/bin/env bash
set -Eeuo pipefail

REPO_RAW='https://raw.githubusercontent.com/amiradineh74/abuse-defender-node-safe/main'
MANAGER='/usr/local/sbin/abuse-defender-node'
CONF_DIR='/etc/abuse-defender-node'
STATE_DIR='/var/lib/abuse-defender-node'

[[ ${EUID:-999} -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }

for c in iptables iptables-save curl systemctl systemd-run ip awk sed grep mktemp python3 dpkg-query; do
  command -v "$c" >/dev/null 2>&1 || { echo "Missing required command: $c" >&2; exit 1; }
done

for pkg in iptables-persistent netfilter-persistent; do
  status=$(dpkg-query -W -f='${db:Status-Status}' "$pkg" 2>/dev/null || true)
  if [[ "$status" == "installed" ]]; then
    echo "$pkg is installed. Purge it before continuing." >&2
    exit 2
  fi
done

if iptables -S 2>/dev/null | grep -qE '(^| )abuse-defender($|[- ])'; then
  echo 'Legacy Abuse Defender iptables rules detected. Remove them first.' >&2
  exit 2
fi
if [[ -e /root/abuse-defender-update.sh ]]; then
  echo 'Legacy /root/abuse-defender-update.sh detected. Remove it first.' >&2
  exit 2
fi
if crontab -l 2>/dev/null | grep -q '/root/abuse-defender-update.sh'; then
  echo 'Legacy Abuse Defender cron detected. Remove it first.' >&2
  exit 2
fi

mkdir -p "$CONF_DIR" "$STATE_DIR"
touch "$CONF_DIR/whitelist.txt" "$CONF_DIR/custom-block.txt"
chmod 700 "$CONF_DIR" "$STATE_DIR"
chmod 600 "$CONF_DIR/whitelist.txt" "$CONF_DIR/custom-block.txt"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
curl -fsSL "$REPO_RAW/abuse-defender-node" -o "$tmp"
bash -n "$tmp"
install -m 0755 "$tmp" "$MANAGER"

cat >/etc/systemd/system/abuse-defender-node.service <<'UNIT'
[Unit]
Description=Abuse Defender Node Safe - apply outbound abuse blocks
Wants=network-online.target
After=network-online.target docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/abuse-defender-node apply
ExecStop=/usr/local/sbin/abuse-defender-node stop
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT

cat >/etc/systemd/system/abuse-defender-node-update.service <<'UNIT'
[Unit]
Description=Abuse Defender Node Safe - refresh official list
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/abuse-defender-node update
UNIT

cat >/etc/systemd/system/abuse-defender-node-update.timer <<'UNIT'
[Unit]
Description=Daily Abuse Defender official-list update

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=15m
Unit=abuse-defender-node-update.service

[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload

backup="/root/abuse-defender-node-before-install-$(date +%Y%m%d-%H%M%S).v4"
iptables-save > "$backup"
chmod 600 "$backup"
echo "Reference firewall backup: $backup"

echo 'Starting 2-minute TEST MODE...'
"$MANAGER" test

echo
echo 'Verify SSH, Docker, PasarGuard Node status, and OUTPUT rules.'
echo 'Run: abuse-defender-node status'
echo
echo 'If everything is healthy before 2 minutes: abuse-defender-node confirm'
echo 'If you do nothing, the project hook is automatically removed after 2 minutes.'
