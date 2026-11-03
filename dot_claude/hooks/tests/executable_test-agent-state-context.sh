#!/bin/bash
# Regression tests for agent-state-context.sh.
#
# The hook runs on the critical path of every prompt, so the property under
# test is latency: it must serve from cache and never wait on the network.
# Transcript evidence before the cache was added: 69 timeouts at the 5s budget,
# 100% of the recorded runs, injecting nothing on those turns.
#
# Stubs stand in for bd and presence so the tests neither touch the Dolt server
# nor depend on how many beads happen to be open.

set -uo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/agent-state-context.sh"
PASS=0
FAIL=0

setup() {
    TMP="$(mktemp -d)"
    export AGENT_STATE_CACHE_DIR="$TMP/cache"
    export AGENT_STATE_TTL=60
    export AGENT_STATE_BD="$TMP/bd-stub"
    export AGENT_STATE_PRESENCE="$TMP/presence-stub"
    ME="$(id -un)@$(hostname -s)"
    echo '[{"is_me":false,"resource_label":"node:example-node","session_id":"other","purpose":"stub","claimed_at":"now"}]' > "$TMP/claims.json"

    cat > "$AGENT_STATE_BD" <<'STUB'
#!/bin/bash
sleep "${STUB_DELAY:-0}"
echo "○ code-aaaa ● P1 a stubbed open bead"
STUB
    cat > "$AGENT_STATE_PRESENCE" <<'STUB'
#!/bin/bash
sleep "${STUB_DELAY:-0}"
cat "$(dirname "$0")/claims.json"
STUB
    chmod +x "$AGENT_STATE_BD" "$AGENT_STATE_PRESENCE"
}

teardown() { rm -rf "$TMP"; }

ok()   { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s\n     %s\n' "$1" "$2"; }

payload() {
    printf '{"session_id":"%s","hook_event_name":"UserPromptSubmit","prompt":"a normal length prompt"}' "${1:-sess-test}"
}

# Runs the refresh in the foreground, as the detached refresh would.
refresh_now() { "$HOOK" --refresh </dev/null >/dev/null 2>&1; }

# Runs the hook; sets MS and HOOK_OUT in the caller's shell (no subshell, so
# both survive) — the hook's stdout lands in a file we then read back.
run_hook() {
    local s e
    s=$(date +%s%N)
    payload | timeout 20 "$HOOK" > "$TMP/out" 2>/dev/null
    e=$(date +%s%N)
    MS=$(( (e - s) / 1000000 ))
    HOOK_OUT="$(cat "$TMP/out")"
}

# The cache holds the finished payload, so seeding it means seeding JSON.
CACHE_FILE_NAME="context.json"
warm_cache() {
    python3 -c "
import json, sys
print(json.dumps({'hookSpecificOutput': {
    'hookEventName': 'UserPromptSubmit', 'additionalContext': sys.argv[1]}}))
" "$1" > "$AGENT_STATE_CACHE_DIR/$CACHE_FILE_NAME"
}

echo "== agent-state-context.sh =="

# 1 — the headline property: a warm cache must not pay for the network.
setup
mkdir -p "$AGENT_STATE_CACHE_DIR"
warm_cache "IN PROGRESS: something"
touch "$AGENT_STATE_CACHE_DIR/$CACHE_FILE_NAME"
STUB_DELAY=10 run_hook; ms=$MS
if (( ms < 500 )); then
    ok "warm cache serves in ${ms}ms (< 500ms) even with a 10s-slow backend"
else
    bad "warm cache should serve in <500ms" "took ${ms}ms — the hook is still waiting on the backend"
fi
teardown

# 2 — output contract.
setup
mkdir -p "$AGENT_STATE_CACHE_DIR"
warm_cache "IN PROGRESS: the-marker-string"
run_hook; ms=$MS
if echo "$HOOK_OUT" | python3 -c '
import json,sys
d = json.load(sys.stdin)
o = d["hookSpecificOutput"]
assert o["hookEventName"] == "UserPromptSubmit", o
assert "the-marker-string" in o["additionalContext"], o
' 2>/dev/null; then
    ok "emits valid UserPromptSubmit JSON carrying the cached context"
else
    bad "output contract" "got: ${HOOK_OUT:0:200}"
fi
teardown

# 3 — cold start must inject nothing rather than an empty block.
setup
run_hook; ms=$MS
if [[ -z "$HOOK_OUT" ]]; then
    ok "cold cache emits no output (${ms}ms)"
else
    bad "cold cache should emit nothing" "got: ${HOOK_OUT:0:200}"
fi
teardown

# 4 — the background refresh must not hold Claude Code's stdout pipe open.
#     A child inheriting stdout means the harness waits for EOF until timeout.
setup
mkdir -p "$AGENT_STATE_CACHE_DIR"
warm_cache "IN PROGRESS: x"
touch -d '1 hour ago' "$AGENT_STATE_CACHE_DIR/$CACHE_FILE_NAME"   # stale -> refresh fires
s=$(date +%s%N)
STUB_DELAY=10 payload | timeout 20 "$HOOK" 2>/dev/null | cat > /dev/null
e=$(date +%s%N); ms=$(( (e - s) / 1000000 ))
if (( ms < 500 )); then
    ok "stdout pipe closes in ${ms}ms — refresh is detached"
else
    bad "detached refresh" "pipe stayed open ${ms}ms; a child is holding stdout"
fi
teardown

# 5 — a stale cache actually gets refreshed (in the background).
setup
mkdir -p "$AGENT_STATE_CACHE_DIR"
warm_cache "stale content"
touch -d '1 hour ago' "$AGENT_STATE_CACHE_DIR/$CACHE_FILE_NAME"
payload | timeout 20 "$HOOK" >/dev/null 2>&1
for _ in $(seq 40); do
    grep -q "stubbed open bead" "$AGENT_STATE_CACHE_DIR/$CACHE_FILE_NAME" 2>/dev/null && break
    sleep 0.25
done
if grep -q "stubbed open bead" "$AGENT_STATE_CACHE_DIR/$CACHE_FILE_NAME" 2>/dev/null; then
    ok "stale cache is refreshed in the background"
else
    bad "background refresh" "cache still: $(cat "$AGENT_STATE_CACHE_DIR/$CACHE_FILE_NAME" 2>/dev/null)"
fi
teardown

# 6 — a fresh cache must not trigger a refresh (no stampede on the Dolt server).
setup
mkdir -p "$AGENT_STATE_CACHE_DIR"
warm_cache "fresh content"
before=$(stat -c %Y "$AGENT_STATE_CACHE_DIR/$CACHE_FILE_NAME")
payload | timeout 20 "$HOOK" >/dev/null 2>&1
sleep 2
after=$(stat -c %Y "$AGENT_STATE_CACHE_DIR/$CACHE_FILE_NAME")
if [[ "$before" == "$after" ]]; then
    ok "fresh cache does not re-query the backend"
else
    bad "fresh cache should not refresh" "mtime moved $before -> $after"
fi
teardown

# 7 — a session never sees its own claims as another session's, and does see
#     the claims of the user's other concurrent sessions. The cache is shared
#     by all of one user's sessions, so the split has to happen per session.
setup
cat > "$TMP/claims.json" <<JSON
[{"is_me":false,"resource_label":"stack:mine","session_id":"$ME@sess-test","purpose":"my apply","claimed_at":"now"},
 {"is_me":false,"resource_label":"stack:sibling","session_id":"$ME@sess-sibling","purpose":"sibling apply","claimed_at":"now"}]
JSON
refresh_now
payload sess-test | timeout 20 "$HOOK" > "$TMP/out-a" 2>/dev/null
payload sess-sibling | timeout 20 "$HOOK" > "$TMP/out-b" 2>/dev/null
payload sess-fresh | timeout 20 "$HOOK" > "$TMP/out-c" 2>/dev/null
if grep -q "stack:sibling" "$TMP/out-a" && ! grep -q "stack:mine" "$TMP/out-a" \
   && grep -q "stack:mine" "$TMP/out-b" && ! grep -q "stack:sibling" "$TMP/out-b" \
   && grep -q "stack:mine" "$TMP/out-c" && grep -q "stack:sibling" "$TMP/out-c"; then
    ok "each session sees the other sessions' claims and not its own"
else
    bad "per-session claim filter" "a: $(cat "$TMP/out-a") | b: $(cat "$TMP/out-b") | c: $(cat "$TMP/out-c")"
fi
teardown

# 8 — a session whose only claims are its own, with nothing else to report,
#     gets no block (not the shared one listing its own claim).
setup
echo "[{\"is_me\":false,\"resource_label\":\"stack:mine\",\"session_id\":\"$ME@sess-test\",\"purpose\":\"my apply\",\"claimed_at\":\"now\"}]" > "$TMP/claims.json"
printf '#!/bin/bash\n' > "$AGENT_STATE_BD"   # no beads
refresh_now
payload sess-test | timeout 20 "$HOOK" > "$TMP/out" 2>/dev/null
if [[ ! -s "$TMP/out" ]]; then
    ok "own claims alone inject nothing"
else
    bad "own claims alone should inject nothing" "got: $(cat "$TMP/out")"
fi
teardown

# 9 — a session id that is not a plain token cannot name a file outside the cache.
setup
refresh_now
payload '../../x' | timeout 20 "$HOOK" > "$TMP/out" 2>/dev/null
if grep -q "node:example-node" "$TMP/out"; then
    ok "odd session id falls back to the shared block"
else
    bad "odd session id" "got: $(cat "$TMP/out")"
fi
teardown

echo
echo "  $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
