#!/usr/bin/env bash
set -Eeuo pipefail

MANAGER=/usr/local/sbin/abuse-defender-node
CONF_DIR=/etc/abuse-defender-node
STATE_DIR=/var/lib/abuse-defender-node
SERVICE=/etc/systemd/system/abuse-defender-node.service
UPDATE_SERVICE=/etc/systemd/system/abuse-defender-node-update.service
TIMER=/etc/systemd/system/abuse-defender-node-update.timer

[[ ${EUID:-999} -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }

for c in iptables curl systemctl ip awk sed grep mktemp python3; do
  command -v "$c" >/dev/null 2>&1 || { echo "Missing required command: $c" >&2; exit 1; }
done

legacy=0
if iptables -S 2>/dev/null | grep -qE '(^| )abuse-defender($|[- ])'; then
  echo 'Legacy Abuse Defender iptables chains/rules detected.' >&2; legacy=1
fi
if [[ -e /root/abuse-defender-update.sh ]]; then
  echo 'Legacy /root/abuse-defender-update.sh detected.' >&2; legacy=1
fi
if crontab -l 2>/dev/null | grep -q '/root/abuse-defender-update.sh'; then
  echo 'Legacy Abuse Defender cron detected.' >&2; legacy=1
fi
if dpkg-query -W -f='${db:Status-Status}\n' iptables-persistent netfilter-persistent 2>/dev/null | grep -q 'installed'; then
  echo 'iptables-persistent/netfilter-persistent is installed. Purge it before continuing.' >&2; legacy=1
fi
if [[ $legacy -ne 0 ]]; then
  echo 'Aborting to avoid mixing the safe version with the legacy version.' >&2
  exit 2
fi

mkdir -p "$CONF_DIR" "$STATE_DIR"
touch "$CONF_DIR/whitelist.txt" "$CONF_DIR/custom-block.txt"
chmod 700 "$CONF_DIR" "$STATE_DIR"
chmod 600 "$CONF_DIR/whitelist.txt" "$CONF_DIR/custom-block.txt"

cat > "$MANAGER" <<'SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
PATH=/usr/sbin:/usr/bin:/sbin:/bin
UPSTREAM='https://raw.githubusercontent.com/Kiya6955/Abuse-Defender/main/abuse-ips.ipv4'
CONF_DIR=/etc/abuse-defender-node
STATE_DIR=/var/lib/abuse-defender-node
LIST_FILE="$STATE_DIR/abuse-ips.ipv4"
WL_FILE="$CONF_DIR/whitelist.txt"
CUSTOM_FILE="$CONF_DIR/custom-block.txt"
CHAIN='PGAD_ABUSE_GUARD'
HOSTS_MARK='# abuse-defender-node-safe'
IPT=(iptables -w 10)

log(){ printf '[abuse-defender-node] %s\n' "$*"; }
die(){ printf '[abuse-defender-node] ERROR: %s\n' "$*" >&2; exit 1; }
root(){ [[ ${EUID:-999} -eq 0 ]] || die 'Run as root.'; }

ensure_dirs(){
  mkdir -p "$CONF_DIR" "$STATE_DIR"
  touch "$WL_FILE" "$CUSTOM_FILE"
  chmod 700 "$CONF_DIR" "$STATE_DIR"
  chmod 600 "$WL_FILE" "$CUSTOM_FILE"
}

validate_file(){
  local f=$1
  [[ -s "$f" ]] || return 1
  python3 - "$f" <<'PY'
import ipaddress, sys
p=sys.argv[1]
items=[]
with open(p, encoding='utf-8') as fh:
    for raw in fh:
        s=raw.split('#',1)[0].strip()
        if not s:
            continue
        items.extend(s.split())
if len(items) < 20 or len(items) > 10000:
    raise SystemExit(2)
for item in items:
    n=ipaddress.ip_network(item, strict=False)
    if n.version != 4:
        raise SystemExit(3)
print(len(items))
PY
}

fetch_list(){
  ensure_dirs
  local t count
  t=$(mktemp "$STATE_DIR/.abuse-ips.XXXXXX")
  trap 'rm -f "$t"' RETURN
  curl --fail --silent --show-error --location        --connect-timeout 10 --max-time 30 --retry 3 --retry-delay 2        "$UPSTREAM" -o "$t"
  count=$(validate_file "$t") || die 'Downloaded upstream list failed validation; current cached list/rules were left untouched.'
  mv -f "$t" "$LIST_FILE"
  chmod 600 "$LIST_FILE"
  trap - RETURN
  log "Official list updated ($count IPv4 networks)."
}

valid_cidr(){
  python3 - "$1" <<'PY' >/dev/null
import ipaddress, sys
n=ipaddress.ip_network(sys.argv[1], strict=False)
assert n.version == 4
PY
}

file_entries(){
  local f=$1
  [[ -f "$f" ]] || return 0
  sed 's/#.*$//' "$f" | awk 'NF {for(i=1;i<=NF;i++) print $i}'
}

dynamic_whitelist(){
  echo '127.0.0.0/8'
  ip -o -4 addr show 2>/dev/null | awk '{split($4,a,"/"); if (a[1] != "") print a[1]"/32"}'
  ip -4 route show default 2>/dev/null | awk '/^default/ && $3 ~ /^[0-9.]+$/ {print $3"/32"; exit}'
  ip -4 route show table main scope link 2>/dev/null | awk '$1 ~ /^[0-9]+\./ {print $1}'
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    docker network ls -q 2>/dev/null | while read -r id; do
      [[ -n "$id" ]] || continue
      docker network inspect "$id" --format '{{range .IPAM.Config}}{{if .Subnet}}{{.Subnet}}{{"\n"}}{{end}}{{end}}' 2>/dev/null || true
    done
  fi
}

ensure_hosts(){
  grep -Fq "127.0.0.1 appclick.co $HOSTS_MARK" /etc/hosts 2>/dev/null || echo "127.0.0.1 appclick.co $HOSTS_MARK" >> /etc/hosts
  grep -Fq "127.0.0.1 pushnotificationws.com $HOSTS_MARK" /etc/hosts 2>/dev/null || echo "127.0.0.1 pushnotificationws.com $HOSTS_MARK" >> /etc/hosts
}
remove_hosts(){ sed -i "\\|$HOSTS_MARK|d" /etc/hosts; }
ensure_chain(){ "${IPT[@]}" -N "$CHAIN" 2>/dev/null || true; }
remove_output_hooks(){
  while "${IPT[@]}" -C OUTPUT -j "$CHAIN" 2>/dev/null; do
    "${IPT[@]}" -D OUTPUT -j "$CHAIN"
  done
}

apply_rules(){
  root; ensure_dirs
  [[ -s "$LIST_FILE" ]] || fetch_list
  validate_file "$LIST_FILE" >/dev/null || die 'Cached official list is invalid.'
  ensure_chain
  "${IPT[@]}" -F "$CHAIN"

  {
    dynamic_whitelist
    file_entries "$WL_FILE"
  } | awk 'NF && !seen[$0]++' | while read -r cidr; do
    valid_cidr "$cidr" || die "Invalid whitelist CIDR: $cidr"
    "${IPT[@]}" -A "$CHAIN" -d "$cidr" -j RETURN
  done

  file_entries "$CUSTOM_FILE" | awk '!seen[$0]++' | while read -r cidr; do
    valid_cidr "$cidr" || die "Invalid custom block CIDR: $cidr"
    "${IPT[@]}" -A "$CHAIN" -d "$cidr" -j DROP
  done

  file_entries "$LIST_FILE" | while read -r cidr; do
    valid_cidr "$cidr" || die "Invalid upstream CIDR: $cidr"
    "${IPT[@]}" -A "$CHAIN" -d "$cidr" -j DROP
  done

  "${IPT[@]}" -A "$CHAIN" -j RETURN
  remove_output_hooks
  "${IPT[@]}" -I OUTPUT 1 -j "$CHAIN"
  ensure_hosts
  log 'Rules applied safely to OUTPUT.'
}

stop_rules(){
  root
  remove_output_hooks
  if "${IPT[@]}" -L "$CHAIN" -n >/dev/null 2>&1; then
    "${IPT[@]}" -F "$CHAIN" || true
    "${IPT[@]}" -X "$CHAIN" || true
  fi
  log 'Safe Abuse Defender rules removed; other firewall rules were not touched.'
}

update_rules(){ root; fetch_list; apply_rules; }

schedule_rollback(){
  local unit="abuse-defender-node-rollback-$(date +%s)-$$"
  systemd-run --quiet --unit="$unit" --on-active=2m "$0" stop >/dev/null
  printf '%s\n' "$unit" > "$STATE_DIR/rollback-unit"
  log "TEST MODE active. Automatic rollback scheduled in 2 minutes ($unit)."
  log "If SSH, Docker and PasarGuard Node are healthy, run: $0 confirm"
}

cancel_rollback(){
  local unit=''
  [[ -f "$STATE_DIR/rollback-unit" ]] && unit=$(cat "$STATE_DIR/rollback-unit" 2>/dev/null || true)
  if [[ -n "$unit" ]]; then
    systemctl stop "$unit.timer" 2>/dev/null || true
    systemctl stop "$unit.service" 2>/dev/null || true
    systemctl reset-failed "$unit.service" 2>/dev/null || true
  fi
  rm -f "$STATE_DIR/rollback-unit"
}

confirm_rules(){
  root
  cancel_rollback
  systemctl enable --now abuse-defender-node.service abuse-defender-node-update.timer >/dev/null
  log 'Confirmed. Boot apply + daily official-list update enabled.'
}

status_rules(){
  echo '=== OUTPUT hook ==='
  "${IPT[@]}" -S OUTPUT 2>/dev/null | grep -F "$CHAIN" || echo 'Not hooked'
  echo
  echo '=== Chain counters ==='
  "${IPT[@]}" -L "$CHAIN" -n -v --line-numbers 2>/dev/null || echo 'Chain absent'
  echo
  echo '=== Cached official list ==='
  if [[ -f "$LIST_FILE" ]]; then
    wc -l "$LIST_FILE"
    stat -c 'mtime: %y' "$LIST_FILE" 2>/dev/null || true
  else
    echo 'No cached list'
  fi
  echo
  echo '=== systemd ==='
  systemctl is-enabled abuse-defender-node.service 2>/dev/null || true
  systemctl is-enabled abuse-defender-node-update.timer 2>/dev/null || true
  systemctl is-active abuse-defender-node-update.timer 2>/dev/null || true
}

add_whitelist(){
  root; ensure_dirs
  local cidr=${1:-}; [[ -n "$cidr" ]] || die 'Usage: add-whitelist CIDR'
  valid_cidr "$cidr" || die 'Invalid IPv4 CIDR.'
  grep -Fxq "$cidr" "$WL_FILE" || echo "$cidr" >> "$WL_FILE"
  apply_rules
}

add_block(){
  root; ensure_dirs
  local cidr=${1:-}; [[ -n "$cidr" ]] || die 'Usage: add-block CIDR'
  valid_cidr "$cidr" || die 'Invalid IPv4 CIDR.'
  grep -Fxq "$cidr" "$CUSTOM_FILE" || echo "$cidr" >> "$CUSTOM_FILE"
  apply_rules
}

uninstall_all(){
  root
  cancel_rollback
  systemctl disable --now abuse-defender-node-update.timer 2>/dev/null || true
  systemctl disable abuse-defender-node.service 2>/dev/null || true
  stop_rules
  remove_hosts
  rm -f /etc/systemd/system/abuse-defender-node.service         /etc/systemd/system/abuse-defender-node-update.service         /etc/systemd/system/abuse-defender-node-update.timer
  systemctl daemon-reload
  log 'Uninstalled runtime/systemd integration. Config/list files were kept.'
}

usage(){
  cat <<'USAGE'
Usage: abuse-defender-node {test|confirm|apply|update|stop|status|fetch|add-whitelist CIDR|add-block CIDR|uninstall}
USAGE
}

root
case "${1:-}" in
  test) fetch_list; apply_rules; schedule_rollback ;;
  confirm) confirm_rules ;;
  apply) apply_rules ;;
  update) update_rules ;;
  stop) stop_rules ;;
  status) status_rules ;;
  fetch) fetch_list ;;
  add-whitelist) add_whitelist "${2:-}" ;;
  add-block) add_block "${2:-}" ;;
  uninstall) uninstall_all ;;
  *) usage; exit 1 ;;
esac
SCRIPT
chmod 0755 "$MANAGER"

cat > "$SERVICE" <<'UNIT'
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

cat > "$UPDATE_SERVICE" <<'UNIT'
[Unit]
Description=Abuse Defender Node Safe - refresh official list
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/abuse-defender-node update
UNIT

cat > "$TIMER" <<'UNIT'
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
echo 'Verify SSH, docker ps, and that the node is Online in PasarGuard.'
echo 'Also run: abuse-defender-node status'
echo
echo 'If healthy, confirm before 2 minutes:'
echo '  abuse-defender-node confirm'
echo
echo 'If you do nothing, the Abuse Defender hook is automatically removed after 2 minutes.'
