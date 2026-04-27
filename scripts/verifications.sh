#!/bin/bash
# verifications.sh — generic Docker compose stack security verifier.
# Drop into any compose project's scripts/ folder, no edits needed.

set -u

# Always run from project root
cd "$(dirname "$0")/.." || exit 1

# ---- Colors ----
if [ -t 1 ]; then
  GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
  GREEN=''; RED=''; YELLOW=''; BOLD=''; DIM=''; RESET=''
fi
pass() { printf "  ${GREEN}✓${RESET} %s\n" "$1"; PASSES=$((PASSES + 1)); }
fail() { printf "  ${RED}✘${RESET} %s\n" "$1"; FAILS=$((FAILS + 1)); }
warn() { printf "  ${YELLOW}⚠${RESET} %s\n" "$1"; WARNS=$((WARNS + 1)); }
info() { printf "  ${DIM}•${RESET} %s\n" "$1"; }
PASSES=0; FAILS=0; WARNS=0

# ---- Detect services from compose ----
ALL_SERVICES=$(docker compose config --services 2>/dev/null || echo "")
if [ -z "$ALL_SERVICES" ]; then
  fail "No docker-compose.yml found, or it has errors"
  exit 1
fi

# Detect WSL
IS_WSL=false
grep -qi microsoft /proc/version 2>/dev/null && IS_WSL=true

# Discover which services have published ports (= "frontend" services)
# and which don't (= "internal" services)
PUBLISHED_SERVICES=""
INTERNAL_SERVICES=""
PUBLISHED_PORTS=""
for svc in $ALL_SERVICES; do
  cname=$(docker compose ps --format '{{.Name}}' --status running | grep -m1 "[-_]$svc[-_0-9]*$" || true)
  [ -z "$cname" ] && continue
  port_info=$(docker port "$cname" 2>/dev/null || true)
  if [ -n "$port_info" ]; then
    PUBLISHED_SERVICES+="$svc "
    # Extract host ports from output like "8000/tcp -> 127.0.0.1:8080"
    host_ports=$(echo "$port_info" | grep -oE ':[0-9]+$' | tr -d ':' | sort -u)
    PUBLISHED_PORTS+="$host_ports "
  else
    INTERNAL_SERVICES+="$svc "
  fi
done

# ============================================
echo "${BOLD}=== 1. Containers healthy ===${RESET}"
# ============================================
unhealthy=$(docker compose ps --format "{{.Name}}\t{{.State}}" | grep -v "running" || true)
if [ -z "$unhealthy" ]; then
  pass "All containers running"
else
  fail "Some containers not running:"
  echo "$unhealthy" | sed 's/^/    /'
fi
docker compose ps

# ============================================
echo
echo "${BOLD}=== 2. Non-root users ===${RESET}"
# ============================================
for svc in $ALL_SERVICES; do
  user=$(docker compose exec -T "$svc" whoami 2>/dev/null | tr -d '\r\n' || true)
  if [ -z "$user" ]; then
    info "$svc — couldn't run whoami (likely a base-image without shell, e.g. postgres/redis)"
  elif [ "$user" = "root" ]; then
    # Skip well-known images that legitimately must run as root (postgres, redis use internal users)
    case "$svc" in
      db|database|postgres|mysql|redis|*cache*) info "$svc — runs as root (acceptable for managed DB/cache images)" ;;
      *) fail "$svc runs as root" ;;
    esac
  else
    pass "$svc runs as $user"
  fi
done

# ============================================
echo
echo "${BOLD}=== 3. Ports bound to localhost only ===${RESET}"
# ============================================
ports=$(docker compose ps --format "{{.Ports}}")
if echo "$ports" | grep -qE "^\s*0\.0\.0\.0|^\s*::\b"; then
  fail "Some ports bound to 0.0.0.0 / :: (visible to LAN!)"
  echo "$ports" | grep -E "0\.0\.0\.0|::" | sed 's/^/    /'
elif echo "$ports" | grep -q "127.0.0.1"; then
  pass "All published ports bound to 127.0.0.1"
  echo "$ports" | grep "127.0.0.1" | sed 's/^/    /'
else
  warn "No published ports detected"
fi

# ============================================
echo
echo "${BOLD}=== 4. Reachable from this machine ===${RESET}"
# ============================================
if [ -z "$PUBLISHED_PORTS" ]; then
  info "No published ports to test"
else
  for port in $PUBLISHED_PORTS; do
    code=$(curl -sI -o /dev/null -w "%{http_code}" --max-time 3 "http://localhost:$port" 2>/dev/null || echo "000")
    if [ "$code" = "200" ] || [ "$code" = "301" ] || [ "$code" = "302" ]; then
      pass "localhost:$port → HTTP $code"
    elif [ "$code" = "000" ]; then
      fail "localhost:$port → no response"
    else
      warn "localhost:$port → HTTP $code (responds, but unexpected status)"
    fi
  done
fi

# ============================================
echo
echo "${BOLD}=== 5. External access ===${RESET}"
# ============================================
if [ "$IS_WSL" = true ]; then
  info "Running in WSL — automated check skipped"
  info "Loopback bindings (127.0.0.1) are not exposed by WSL2 to the LAN"
  info "To verify manually, from another device on your LAN try"
  info "  http://<your-windows-ip>:<port>  → should refuse connection"
else
  HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
  first_port=$(echo "$PUBLISHED_PORTS" | awk '{print $1}')
  if [ -z "$HOST_IP" ] || [ -z "$first_port" ]; then
    info "Skipping (no detectable host IP or published port)"
  else
    code=$(curl -sI -o /dev/null -w "%{http_code}" --max-time 3 "http://$HOST_IP:$first_port" 2>/dev/null || echo "000")
    if [ "$code" = "000" ]; then
      pass "$HOST_IP:$first_port unreachable from outside"
    else
      fail "$HOST_IP:$first_port reachable from LAN — security hole!"
    fi
  fi
fi

# ============================================
echo
echo "${BOLD}=== 6. Internal services have no host port ===${RESET}"
# ============================================
if [ -z "$INTERNAL_SERVICES" ]; then
  info "No internal-only services detected"
else
  for svc in $INTERNAL_SERVICES; do
    pass "$svc — no host port mapping (internal only)"
  done
fi

# ============================================
echo
echo "${BOLD}=== 7. .env not leaked into git ===${RESET}"
# ============================================
if git rev-parse --git-dir >/dev/null 2>&1; then
  if git ls-files 2>/dev/null | grep -qx ".env"; then
    fail ".env is tracked in git!"
    info "Fix: git rm --cached .env && git commit -m 'Remove .env'"
  else
    pass ".env not in git"
  fi

  if [ -f .env.example ] && git ls-files 2>/dev/null | grep -qx ".env.example"; then
    pass ".env.example tracked"
  elif [ -f .env.example ]; then
    warn ".env.example exists but not tracked — consider committing"
  else
    info "No .env.example found"
  fi
else
  info "Not a git repo — skipping git checks"
fi

# ============================================
echo
echo "${BOLD}=== Summary ===${RESET}"
# ============================================
printf "  ${GREEN}%d passed${RESET}   ${YELLOW}%d warnings${RESET}   ${RED}%d failed${RESET}\n" \
  "$PASSES" "$WARNS" "$FAILS"
echo

[ "$FAILS" -eq 0 ] && exit 0 || exit 1