#!/bin/bash
# verifications.sh — sanity-check the local Docker stack security posture.
#
# Checks:
#   1. All containers up and healthy
#   2. App containers run as non-root
#   3. Published ports bound to 127.0.0.1 (not 0.0.0.0)
#   4. Services reachable from this machine
#   5. External access (skipped on WSL — see notes)
#   6. Internal services have no host port mapping
#   7. Secrets not leaked in container env

set -u

# Always run from project root, regardless of where invoked
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

# Detect WSL once
IS_WSL=false
if grep -qi microsoft /proc/version 2>/dev/null; then
  IS_WSL=true
fi

# ============================================
echo "${BOLD}=== 1. Containers healthy ===${RESET}"
# ============================================
if ! docker compose ps --quiet | grep -q .; then
  fail "No containers running. Start with: docker compose up -d"
  exit 1
fi

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
echo "${BOLD}=== 2. Non-root users (app containers) ===${RESET}"
# ============================================
for svc in vote result worker; do
  user=$(docker compose exec -T "$svc" whoami 2>/dev/null | tr -d '\r\n' || true)
  if [ -z "$user" ]; then
    fail "$svc — couldn't determine user (container down?)"
  elif [ "$user" = "root" ]; then
    fail "$svc runs as root"
  else
    pass "$svc runs as $user"
  fi
done

# ============================================
echo
echo "${BOLD}=== 3. Ports bound to localhost only ===${RESET}"
# ============================================
ports=$(docker compose ps --format "{{.Ports}}")
if echo "$ports" | grep -qE "^\s*0\.0\.0\.0|::"; then
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
for port in 8080 8081; do
  code=$(curl -sI -o /dev/null -w "%{http_code}" --max-time 3 "http://localhost:$port" 2>/dev/null || echo "000")
  if [ "$code" = "200" ]; then
    pass "localhost:$port → HTTP 200"
  else
    fail "localhost:$port → HTTP $code"
  fi
done

# ============================================
echo
echo "${BOLD}=== 5. External access ===${RESET}"
# ============================================
if [ "$IS_WSL" = true ]; then
  info "Running in WSL — automated check skipped"
  info "Loopback bindings (127.0.0.1) are not exposed by WSL2 to the LAN"
  info "To verify manually, from another device on your network try:"
  info "  http://<your-Windows-IP>:8080  → should refuse connection"
else
  HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
  if [ -z "$HOST_IP" ]; then
    warn "Could not detect host IP — skipping"
  else
    code=$(curl -sI -o /dev/null -w "%{http_code}" --max-time 3 "http://$HOST_IP:8080" 2>/dev/null || echo "000")
    if [ "$code" = "000" ]; then
      pass "$HOST_IP:8080 unreachable from outside ✓"
    else
      fail "$HOST_IP:8080 reachable from LAN — security hole!"
    fi
  fi
fi

# ============================================
echo
echo "${BOLD}=== 6. Internal services have no host port ===${RESET}"
# ============================================
for svc in redis db worker; do
  cname="$(docker compose ps --format '{{.Name}}' --status running | grep "$svc" | head -1)"
  if [ -z "$cname" ]; then
    warn "$svc — container not running"
    continue
  fi
  ports=$(docker port "$cname" 2>/dev/null || true)
  if [ -z "$ports" ]; then
    pass "$svc — no host port mapping (internal only)"
  else
    fail "$svc — has host port mapping:"
    echo "$ports" | sed 's/^/    /'
  fi
done

# ============================================
echo
echo "${BOLD}=== 7. .env not leaked into git ===${RESET}"
# ============================================
if [ -d .git ] || git rev-parse --git-dir >/dev/null 2>&1; then
  if git ls-files 2>/dev/null | grep -qx ".env"; then
    fail ".env is tracked in git!"
    info "Fix: git rm --cached .env && git commit -m 'Remove .env'"
  else
    pass ".env not in git"
  fi

  if [ -f .env.example ] && git ls-files 2>/dev/null | grep -qx ".env.example"; then
    pass ".env.example tracked (good for documentation)"
  else
    warn "No .env.example committed — consider adding one"
  fi
else
  info "Not a git repo — skipping git checks"
fi

# ============================================
echo
echo "${BOLD}=== Summary ===${RESET}"
# ============================================
printf "  ${GREEN}%d passed${RESET}   ${YELLOW}%d warnings${RESET}   ${RED}%d failed${RESET}\n" "$PASSES" "$WARNS" "$FAILS"
echo

[ "$FAILS" -eq 0 ] && exit 0 || exit 1