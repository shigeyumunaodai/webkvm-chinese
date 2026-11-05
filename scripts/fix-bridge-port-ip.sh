#!/usr/bin/env bash
# fix-bridge-port-ip.sh — recover a host that lost IPv4 management after a
# reboot while its KVM/Incus guests kept working.
#
# Root cause it repairs:
#   Debian/Ubuntu hosts that still use ifupdown (/etc/network/interfaces)
#   sometimes keep a static IP on the physical NIC *after* WebKVM (or the
#   admin) moved it into a Linux bridge (vmbr0). On the next boot the bridge
#   and its port end up with the SAME IP. Two interfaces then answer ARP for
#   the same address with different MACs ("ARP flux"), so SSH / the Web UI /
#   ping to the host are black-holed — but the kernel bridge keeps forwarding
#   guest traffic, so VMs and containers are unaffected.
#
# What this script does:
#   1. finds bridge ports that share an IPv4 address with their bridge
#   2. with --apply, backs up the network state, removes the duplicated IPs
#      from the ports and repoints the default route at the bridge
#   3. with --apply, comments out the conflicting ifupdown stanzas (so the
#      problem does not come back on reboot)
#
# Usage:
#   sudo bash scripts/fix-bridge-port-ip.sh            # dry-run (default)
#   sudo bash scripts/fix-bridge-port-ip.sh --apply    # repair
#
# Safe by design: it never touches bridges without duplicate addresses, never
# removes a bridge's own address, never touches guest interfaces (vnet*/tap*),
# and only comments ifupdown blocks for bridge ports that actually conflict.
# It does NOT reboot or restart libvirt/WebKVM; guests keep running.
set -Eeuo pipefail

APPLY=0
for arg in "$@"; do
  case "${arg}" in
    --apply) APPLY=1 ;;
    --dry-run) APPLY=0 ;;
    -h | --help)
      sed -n '2,30p' "$0"
      exit 0
      ;;
    *)
      echo "unknown option: ${arg} (use --apply, --dry-run or --help)" >&2
      exit 2
      ;;
  esac
done

log() { printf '[fix-bridge-port-ip] %s\n' "$*"; }
die() {
  printf '[fix-bridge-port-ip] ERROR: %s\n' "$*" >&2
  exit 1
}

[[ "${EUID}" -eq 0 ]] || die "run as root (sudo $0 --apply)"
command -v ip >/dev/null 2>&1 || die "the 'ip' command is required"
[[ "$(uname -s)" == "Linux" ]] || die "this tool only runs on Linux"

TS="$(date +%Y%m%d-%H%M%S)"
BACKUP="/root/webkvm-network-fix-${TS}"
MODE_LABEL="dry-run (no changes; pass --apply to repair)"
[[ "${APPLY}" -eq 1 ]] && MODE_LABEL="APPLY"
log "mode: ${MODE_LABEL}"

# Links that must never be treated as a bridge port to fix.
is_guest_iface() {
  case "$1" in
    vnet* | tap* | veth* | virbr* | incusbr* | docker* | br-* | lo) return 0 ;;
    *) return 1 ;;
  esac
}

# List bridges / ports through netlink (`ip`), which is namespace-aware.
# (The /sys/class/net view may belong to another netns in containers; `ip`
# always reflects the network namespace of this process.)
find_bridges() {
  ip -o link show type bridge 2>/dev/null | awk -F': ' '{print $2}' | cut -d'@' -f1
}

find_ports() {
  ip -o link show master "$1" 2>/dev/null | awk -F': ' '{print $2}' | cut -d'@' -f1
}

# Collect IPv4 global addresses of one interface as cidr strings.
ipv4_addrs() {
  ip -4 -o addr show dev "$1" scope global 2>/dev/null | awk '{print $4}'
}

# Remove the duplicate addresses from a bridge port and fix the default route.
fix_port() {
  local br="$1" port="$2" addr="$3"
  local before_route
  before_route="$(ip route show default 2>/dev/null || true)"
  local gateway
  gateway="$(printf '%s\n' "${before_route}" | awk '{for (i = 1; i <= NF; i++) if ($i == "via") {print $(i + 1); exit}}')"

  if [[ "${APPLY}" -eq 0 ]]; then
    log "would run: ip addr del ${addr} dev ${port}"
  else
    ip addr del "${addr}" dev "${port}" || die "cannot remove ${addr} from ${port}"
    log "removed ${addr} from port ${port}"
  fi

  # A default route bound to the bridge port is just as broken as the IP.
  if printf '%s\n' "${before_route}" | grep -qE "[[:space:]]dev[[:space:]]+${port}([[:space:]]|$)"; then
    if [[ "${APPLY}" -eq 0 ]]; then
      log "would run: ip route del default ... dev ${port}; ip route add default via ${gateway:-<gw>} dev ${br}"
    else
      ip route del default 2>/dev/null || true
      if [[ -n "${gateway}" ]]; then
        ip route add default via "${gateway}" dev "${br}" 2>&1 || \
          log "WARNING: could not add default route via ${gateway} dev ${br}; check 'ip route'"
      else
        log "WARNING: no gateway found in the old default route; check 'ip route' manually"
      fi
      log "default route moved to bridge ${br}"
    fi
  fi
}

# Comment out ifupdown blocks for one interface (keep all other stanzas).
comment_ifupdown_iface() {
  local iface="$1" file changed=0
  local files=(/etc/network/interfaces)
  shopt -s nullglob
  files+=(/etc/network/interfaces.d/*)
  shopt -u nullglob
  for file in "${files[@]}"; do
    [[ -f "${file}" ]] || continue
    grep -qE "^[[:space:]]*(auto|allow-hotplug)[[:space:]]+([^#]*[[:space:]])?${iface}([[:space:]]|$)|^[[:space:]]*iface[[:space:]]+${iface}([[:space:]]|$)" "${file}" 2>/dev/null || continue
    if [[ "${APPLY}" -eq 0 ]]; then
      log "would comment out ifupdown stanzas for ${iface} in ${file}"
      continue
    fi
    mkdir -p "${BACKUP}"
    local bak="${BACKUP}/$(echo "${file}" | tr '/' '_')"
    [[ -f "${bak}" ]] || cp -a "${file}" "${bak}"
    python3 - "${file}" "${iface}" "${TS}" <<'PY'
import re
import sys

path, iface, ts = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(path, encoding="utf-8").read().splitlines()
out = []
in_block = False
changed = False
iface_re = re.compile(rf"^[ \t]*iface[ \t]+{re.escape(iface)}(?:[ \t]|$)")
auto_re = re.compile(rf"^[ \t]*(?:auto|allow-hotplug)[ \t]+.*\b{re.escape(iface)}\b")
for line in lines:
    stripped = line.strip()
    if iface_re.match(line) or auto_re.match(line):
        in_block = True
    elif stripped and not line[:1].isspace() and not stripped.startswith("#"):
        in_block = False
    if in_block:
        if line.strip() and not line.lstrip().startswith("#"):
            out.append("#" + line)
            changed = True
            continue
    out.append(line)
if changed:
    header = f"# disabled by scripts/fix-bridge-port-ip.sh at {ts}: bridge port must not have an IP; managed by systemd-networkd"
    if out and not out[0].startswith("# disabled by scripts/fix-bridge-port-ip.sh"):
        out.insert(0, header)
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
PY
    changed=1
    log "commented out ifupdown stanzas for ${iface} in ${file} (backup: ${bak})"
  done
  [[ "${changed}" -eq 1 || "${APPLY}" -eq 0 ]] || log "no ifupdown stanza found for ${iface}"
}

# --------------------------------------------------------------------------
# Scan
# --------------------------------------------------------------------------
mapfile -t BRIDGES < <(find_bridges || true)
if [[ "${#BRIDGES[@]}" -eq 0 ]]; then
  log "no Linux bridge found on this host — nothing to do"
  exit 0
fi

ISSUES=0
FIXED=0
for br in "${BRIDGES[@]}"; do
  mapfile -t br_addrs < <(ipv4_addrs "${br}" || true)
  [[ "${#br_addrs[@]}" -gt 0 ]] || continue
  while IFS= read -r port; do
    [[ -n "${port}" ]] || continue
    is_guest_iface "${port}" && continue
    mapfile -t port_addrs < <(ipv4_addrs "${port}" || true)
    for addr in "${port_addrs[@]}"; do
      duplicate=0
      for br_addr in "${br_addrs[@]}"; do
        [[ "${addr}" == "${br_addr}" ]] && duplicate=1
      done
      [[ "${duplicate}" -eq 1 ]] || continue
      ISSUES=$((ISSUES + 1))
      log "DUPLICATE IPv4 ${addr} on bridge ${br} and port ${port}"
      fix_port "${br}" "${port}" "${addr}"
      comment_ifupdown_iface "${port}"
      [[ "${APPLY}" -eq 1 ]] && FIXED=$((FIXED + 1))
    done
  done < <(find_ports "${br}")
done

if [[ "${ISSUES}" -eq 0 ]]; then
  log "no duplicate bridge-port IPv4 address found — host networking looks sane"
  exit 0
fi

echo ""
if [[ "${APPLY}" -eq 0 ]]; then
  log "dry-run complete: ${ISSUES} issue(s) found. Re-run with --apply to repair."
  log "tip: also inspect 'ip -br addr', 'ip route' and /etc/network/interfaces before applying."
  exit 0
fi

mkdir -p "${BACKUP}"
{
  echo "# webkvm bridge-port IP fix ${TS}"
  ip -br addr
  echo
  ip route
  echo
  ip -6 route
} >"${BACKUP}/state-after.txt" 2>&1 || true
log "repair applied to ${FIXED} interface(s); network state saved under ${BACKUP}"
log "verify now: ping -c1 <gateway> && curl -kfsS https://127.0.0.1:8080/api/health"
log "guests (VMs/containers) were not touched; reboot is NOT required."
exit 0
