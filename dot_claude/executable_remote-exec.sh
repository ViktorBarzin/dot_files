#!/bin/bash
# Simple Remote Execution Daemon
#
# Usage:
#   remote-exec.sh daemon                    - Start the daemon
#   remote-exec.sh status                    - Show status and test connection
#   remote-exec.sh config <host>             - Set default host
#   remote-exec.sh <workdir> exec <command>  - Execute and wait for result
#   remote-exec.sh <workdir> run <command>   - Queue command (async)
#
# Each command carries its own workdir, so the daemon can handle
# commands for different directories.
#
# Results written to ~/.claude/remote-results/<filename>

set -uo pipefail

BASE_DIR="$HOME/.claude"
CONFIG_FILE="$BASE_DIR/remote-config"
COMMANDS_DIR="$BASE_DIR/remote-commands"
RESULTS_DIR="$BASE_DIR/remote-results"
POLL_INTERVAL=0.5
MAX_RESULTS=50

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

error() { echo -e "${RED}Error: $1${NC}" >&2; exit 1; }
info() { echo -e "${GREEN}$1${NC}" >&2; }
warn() { echo -e "${YELLOW}$1${NC}" >&2; }

mkdir -p "$COMMANDS_DIR" "$RESULTS_DIR"

# Default config
DEFAULT_HOST="10.0.10.10"

get_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi
    HOST="${HOST:-$DEFAULT_HOST}"
}

usage() {
    cat << 'EOF'
Simple Remote Execution Daemon

Usage:
  remote-exec.sh daemon                    Start the daemon
  remote-exec.sh status                    Show status
  remote-exec.sh config <host>             Set default host
  remote-exec.sh <workdir> exec <command>  Execute and wait
  remote-exec.sh <workdir> run <command>   Queue command (async)

Examples:
  remote-exec.sh daemon
  remote-exec.sh /home/user/project exec "pytest tests/ -v"
  remote-exec.sh /home/user/project run "python main.py dump-listings"
  remote-exec.sh config 10.0.10.10

Command files: Just drop a file in ~/.claude/remote-commands/
  - Content is the command(s) to run
  - Use "--parallel" on first line for parallel execution
EOF
    exit 1
}

cmd_config() {
    local host="$1"

    cat > "$CONFIG_FILE" << EOF
HOST="$host"
EOF
    info "Config saved: host=$host"

    echo -n "Testing SSH connection... "
    if ssh -o ConnectTimeout=5 -o BatchMode=yes "$host" "echo ok" >/dev/null 2>&1; then
        info "OK"
    else
        warn "SSH test failed"
    fi
}

cmd_status() {
    get_config
    echo "Remote Executor Status"
    echo "  Host: $HOST"
    echo "  Workdir: $WORKDIR"
    echo "  Commands dir: $COMMANDS_DIR"
    echo "  Results dir: $RESULTS_DIR"

    local pending=$(ls -1 "$COMMANDS_DIR"/*.txt 2>/dev/null | wc -l | tr -d ' ')
    local results=$(ls -1 "$RESULTS_DIR"/*.txt 2>/dev/null | wc -l | tr -d ' ')
    echo "  Pending commands: $pending"
    echo "  Cached results: $results"

    echo -n "  SSH connection: "
    if ssh -o ConnectTimeout=3 -o BatchMode=yes "$HOST" "echo ok" >/dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
    fi

    # Check if daemon is running
    echo -n "  Daemon: "
    if pgrep -f "remote-exec.sh daemon" >/dev/null 2>&1; then
        echo -e "${GREEN}running${NC}"
    else
        echo -e "${YELLOW}not running${NC}"
    fi
}

cmd_run() {
    local command="$*"

    local cmd_id="cmd-$(date +%s%N)"
    local cmd_file="$COMMANDS_DIR/$cmd_id.txt"

    # Store workdir and command (first line is workdir, rest is command)
    {
        echo "WORKDIR:$WORKDIR"
        echo "$command"
    } > "$cmd_file"
    echo "$cmd_id"
}

cmd_exec() {
    local command="$*"

    local cmd_id=$(cmd_run "$command")
    local result_file="$RESULTS_DIR/$cmd_id.txt"

    # Wait for result
    local timeout=240
    local elapsed=0
    while [[ ! -f "$result_file" ]] && [[ $elapsed -lt $timeout ]]; do
        sleep 0.5
        elapsed=$((elapsed + 1))
    done

    if [[ ! -f "$result_file" ]]; then
        error "Timeout waiting for result (is daemon running?)"
    fi

    # Wait for completion
    while ! grep -q "^EXIT_CODE:" "$result_file" 2>/dev/null; do
        sleep 0.5
        elapsed=$((elapsed + 1))
        if [[ $elapsed -ge $timeout ]]; then
            error "Timeout waiting for command completion"
        fi
    done

    cat "$result_file"
}

run_daemon() {
    get_config

    echo -e "${BLUE}Remote Execution Daemon${NC}"
    echo "  Host: $HOST"
    echo "  Workdir: (per-command)"
    echo "  Commands dir: $COMMANDS_DIR"
    echo "  Results dir: $RESULTS_DIR"
    echo "  Polling every ${POLL_INTERVAL}s"
    echo ""

    # Test SSH connectivity
    echo "Testing SSH connection..."
    echo "  Host: $HOST"

    SSH_OUTPUT=$(ssh -v -o ConnectTimeout=5 -o BatchMode=yes "$HOST" "echo ok" 2>&1)
    SSH_EXIT=$?

    if [[ $SSH_EXIT -eq 0 ]]; then
        echo -e "  SSH: ${GREEN}OK${NC}"
    else
        echo -e "  SSH: ${RED}FAILED (exit code: $SSH_EXIT)${NC}"
        echo "  --- SSH Debug Output ---"
        echo "$SSH_OUTPUT" | grep -E "(debug1: Authentications|debug1: Trying|debug1: Authentication|Permission denied|Connection refused|No route|Could not resolve)" | head -20
        echo "  -------------------------"
        warn "SSH connection failed - commands will fail until this is fixed"
        echo ""
        echo "Troubleshooting:"
        echo "  1. Check SSH agent: ssh-add -l"
        echo "  2. Test manually: ssh $HOST hostname"
        echo "  3. Check key permissions: ls -la ~/.ssh/"
    fi
    echo ""
    echo "Waiting for commands..."

    while true; do
        for cmd_file in "$COMMANDS_DIR"/*.txt; do
            [[ -e "$cmd_file" ]] || continue

            filename=$(basename "$cmd_file" .txt)
            result_file="$RESULTS_DIR/$filename.txt"

            # Read workdir from first line if present (format: WORKDIR:/path)
            first_line=$(head -n 1 "$cmd_file")
            if [[ "$first_line" == WORKDIR:* ]]; then
                CMD_WORKDIR="${first_line#WORKDIR:}"
                remaining=$(tail -n +2 "$cmd_file")
            else
                CMD_WORKDIR="$WORKDIR"
                remaining=$(cat "$cmd_file")
            fi

            # Check for --parallel flag
            first_remaining=$(echo "$remaining" | head -n 1)
            if [[ "$first_remaining" == "--parallel" ]]; then
                PARALLEL=true
                commands=$(echo "$remaining" | tail -n +2)
            else
                PARALLEL=false
                commands="$remaining"
            fi

            # Preview
            cmd_preview=$(echo "$commands" | head -n 1 | head -c 60)
            if [[ "$PARALLEL" == "true" ]]; then
                echo -n "[$(date '+%H:%M:%S')] [parallel] $cmd_preview... "
            else
                echo -n "[$(date '+%H:%M:%S')] $cmd_preview... "
            fi

            # Execute
            {
                echo "=== Remote Execution ==="
                echo "Host: $HOST"
                echo "Workdir: $CMD_WORKDIR"
                echo "Command: $commands"
                echo "========================"
                echo ""

                if [[ "$PARALLEL" == "true" ]]; then
                    PIDS=()
                    while IFS= read -r cmd || [[ -n "$cmd" ]]; do
                        [[ -z "$cmd" ]] && continue
                        ssh -v -o BatchMode=yes "$HOST" "cd '$CMD_WORKDIR' && $cmd" 2>&1 &
                        PIDS+=($!)
                    done <<< "$commands"

                    FINAL_EXIT=0
                    for pid in "${PIDS[@]}"; do
                        if ! wait "$pid"; then
                            FINAL_EXIT=1
                        fi
                    done
                    echo ""
                    echo "---"
                    echo "EXIT_CODE: $FINAL_EXIT"
                else
                    FINAL_EXIT=0
                    while IFS= read -r cmd || [[ -n "$cmd" ]]; do
                        [[ -z "$cmd" ]] && continue
                        if ! ssh -v -o BatchMode=yes "$HOST" "cd '$CMD_WORKDIR' && $cmd" 2>&1; then
                            FINAL_EXIT=$?
                        fi
                    done <<< "$commands"
                    echo ""
                    echo "---"
                    echo "EXIT_CODE: $FINAL_EXIT"
                fi
            } > "$result_file" 2>&1

            rm "$cmd_file"

            # Display status
            exit_code=$(grep "^EXIT_CODE:" "$result_file" | tail -1 | cut -d' ' -f2)
            if [[ "$exit_code" == "0" ]]; then
                echo -e "${GREEN}ok${NC}"
            else
                echo -e "${RED}failed (exit: $exit_code)${NC}"
            fi

            # Cleanup old results
            result_count=$(ls -1 "$RESULTS_DIR" 2>/dev/null | wc -l)
            if [[ $result_count -gt $MAX_RESULTS ]]; then
                ls -1t "$RESULTS_DIR" | tail -n +$((MAX_RESULTS + 1)) | while read -r old; do
                    rm -f "$RESULTS_DIR/$old"
                done
            fi
        done

        sleep "$POLL_INTERVAL"
    done
}

# Main dispatch
[[ $# -ge 1 ]] || usage

# Handle special commands that don't need workdir
case "$1" in
    config|setup)
        shift
        [[ $# -ge 1 ]] || error "Usage: remote-exec.sh config <host>"
        cmd_config "$1"
        exit 0
        ;;
    daemon|start)
        get_config
        WORKDIR=""  # Daemon reads workdir from each command file
        run_daemon
        exit 0
        ;;
    status|info)
        get_config
        WORKDIR="(per-command)"
        cmd_status
        exit 0
        ;;
    help|--help|-h)
        usage
        ;;
esac

# exec/run commands require workdir as first param
[[ $# -ge 2 ]] || usage

WORKDIR="$1"
shift
ACTION="$1"
shift

get_config

case "$ACTION" in
    run|queue|async)
        [[ $# -ge 1 ]] || error "Usage: remote-exec.sh <workdir> run <command>"
        cmd_run "$@"
        ;;
    exec|execute|sync)
        [[ $# -ge 1 ]] || error "Usage: remote-exec.sh <workdir> exec <command>"
        cmd_exec "$@"
        ;;
    *)
        error "Unknown action: $ACTION"
        ;;
esac
