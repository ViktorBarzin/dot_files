#!/usr/bin/env bash
# Tests for dot_agents/bin/executable_agents-sync.
#
# Each case builds a throwaway home, a bare repo standing in for the remote,
# and a chezmoi source cloned from it. It applies the source, changes
# ~/.agents, runs agents-sync there, and checks what reached the remote.
# Nothing outside the temp dir is touched. Needs chezmoi, git and gitleaks.
#
#   .tests/agents-sync-test.sh
#
# The cases that need a secret or an internal host build the string at run
# time, so this file passes the pre-push hook and gitleaks itself.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO/dot_agents/bin/executable_agents-sync"
for tool in chezmoi git gitleaks; do
  command -v "$tool" >/dev/null || { echo "agents-sync-test: $tool is not installed"; exit 2; }
done
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_NOSYSTEM=1
fails=0
T=""
rc=0

# A home where ~/.agents was applied from a source holding core.md, the
# personal profile and one skill of Viktor's, plus an upstream skill that the
# skills lockfile names.
setup() {
  T="$(mktemp -d)"
  export HOME="$T/home"
  export GIT_CONFIG_GLOBAL="$T/gitconfig"
  mkdir -p "$HOME" && : > "$GIT_CONFIG_GLOBAL"
  local seed="$T/seed" link
  mkdir -p "$seed/dot_agents/skills/own" "$seed/dot_agents/bin" "$seed/dot_claude/skills" "$seed/.githooks"
  printf '# Core\n\nBe brief.\n' > "$seed/dot_agents/core.md"
  printf '# Personal\n\nUse the homelab tools.\n' > "$seed/dot_agents/personal.md"
  printf -- '---\nname: own\ndescription: Mine.\n---\nDo it.\n' > "$seed/dot_agents/skills/own/SKILL.md"
  cp "$SCRIPT" "$seed/dot_agents/bin/executable_agents-sync"
  printf '../../.agents/skills/own' > "$seed/dot_claude/skills/symlink_own"
  # The links every harness reads the hub through, as the repo declares them.
  for link in dot_claude/symlink_CLAUDE.md.tmpl dot_codex/symlink_AGENTS.md.tmpl private_dot_pi/agent/symlink_AGENTS.md.tmpl; do
    mkdir -p "$seed/$(dirname "$link")" && cp "$REPO/$link" "$seed/$link"
  done
  cp "$REPO/.chezmoiignore" "$seed/.chezmoiignore"
  cp "$REPO/.githooks/pre-push" "$seed/.githooks/pre-push"
  git init -q --bare -b master "$T/remote.git"
  git -C "$seed" init -q -b master
  git -C "$seed" add -A && git -C "$seed" commit -q -m seed
  git -C "$seed" push -q "$T/remote.git" master
  git clone -q "$T/remote.git" "$HOME/.local/share/chezmoi"
  chezmoi apply --force --no-tty >"$T/apply.log" 2>&1 || { echo "setup: chezmoi apply failed"; cat "$T/apply.log"; exit 2; }
  mkdir -p "$HOME/.agents/skills/upstream1"
  printf -- '---\nname: upstream1\n---\n' > "$HOME/.agents/skills/upstream1/SKILL.md"
  printf '{"version":3,"skills":{"upstream1":{"source":"someone/skills"}}}\n' > "$HOME/.agents/.skill-lock.json"
  old "$HOME/.agents/skills/upstream1"
  sync
}

sync() { "$HOME/.agents/bin/agents-sync" >"$T/run.log" 2>&1; rc=$?; }
# New files are picked up once two minutes old; age a path past that.
old() { find "$1" -exec touch -h -d '10 minutes ago' {} +; }
done_case() { rm -rf "$T"; }

expect() {
  local desc="$1"
  shift
  if "$@"; then
    printf 'ok    %s\n' "$desc"
  else
    printf 'FAIL  %s\n' "$desc"
    sed 's/^/      /' "$T/run.log"
    fails=$((fails + 1))
  fi
}
not() { ! "$@"; }
commits() { git -C "$T/remote.git" rev-list --count master; }
remote_has() { local p; for p; do git -C "$T/remote.git" cat-file -e "master:$p" 2>/dev/null || return 1; done; }
remote_has_none() { local p; for p; do remote_has "$p" && return 1; done; return 0; }
remote_says() { git -C "$T/remote.git" show "master:$1" 2>/dev/null | grep -q -- "$2"; }
remote_lists() { git -C "$T/remote.git" ls-tree -r --name-only master | grep -q -- "$1"; }
file_says() { grep -q -- "$2" "$1"; }
link_is() { [ "$(readlink "$1")" = "$2" ]; }
failed_saying() { [ "$rc" -ne 0 ] && grep -q -- "$1" "$T/run.log"; }

setup
expect "a first run on a clean home succeeds" [ "$rc" -eq 0 ]
before="$(commits)"
sync
expect "a run with nothing to save makes no commit" [ "$(commits)" = "$before" ]
expect "and succeeds" [ "$rc" -eq 0 ]
done_case

setup
printf '\nNew rule.\n' >> "$HOME/.agents/core.md"
sync
expect "an edit to a tracked file reaches the repo" remote_says dot_agents/core.md "New rule."
expect "the hub carries the edit" file_says "$HOME/.agents/AGENTS.md" "New rule."
done_case

setup
printf '# Notes\n' > "$HOME/.agents/notes.md"
old "$HOME/.agents/notes.md"
sync
expect "a new file reaches the repo" remote_has dot_agents/notes.md
done_case

setup
printf 'draft\n' > "$HOME/.agents/draft.md"
sync
expect "a file written in the last two minutes waits" not remote_has dot_agents/draft.md
old "$HOME/.agents/draft.md"
sync
expect "and goes in once it settles" remote_has dot_agents/draft.md
done_case

setup
mkdir -p "$HOME/.agents/skills/fresh"
printf -- '---\nname: fresh\ndescription: New.\n---\n' > "$HOME/.agents/skills/fresh/SKILL.md"
old "$HOME/.agents/skills/fresh"
sync
expect "a new skill reaches the repo" remote_has dot_agents/skills/fresh/SKILL.md
expect "Claude Code gets a link to it" link_is "$HOME/.claude/skills/fresh" ../../.agents/skills/fresh
expect "the link is declared in the repo" remote_has dot_claude/skills/symlink_fresh
done_case

setup
printf 'more\n' >> "$HOME/.agents/skills/upstream1/SKILL.md"
mkdir -p "$HOME/.agents/skills/own/scripts/__pycache__"
printf 'x' > "$HOME/.agents/skills/own/scripts/__pycache__/tool.cpython-312.pyc"
old "$HOME/.agents/skills"
sync
expect "an upstream skill stays out" not remote_lists upstream1
expect "a cache stays out" not remote_lists __pycache__
expect "the hub stays out" not remote_lists '^dot_agents/AGENTS.md$'
expect "the lockfile stays out" not remote_lists skill-lock
done_case

setup
rm -rf "$HOME/.agents/skills/own"
sync
sync
expect "a deleted skill leaves the repo" not remote_has dot_agents/skills/own/SKILL.md
expect "its link leaves the repo" not remote_has dot_claude/skills/symlink_own
expect "and the disk" not [ -L "$HOME/.claude/skills/own" ]
expect "and the skill stays deleted" not [ -e "$HOME/.agents/skills/own" ]
done_case

setup
printf '# Scratch\n' > "$HOME/.agents/scratch.md"
old "$HOME/.agents/scratch.md"
sync
rm "$HOME/.agents/scratch.md"
sync
expect "a file added by an earlier run and then deleted leaves the repo" not remote_has dot_agents/scratch.md
done_case

setup
# With ~/.agents gone the timer has no script to run, so try the repo's copy.
rm -rf "$HOME/.agents"
"$HOME/.local/share/chezmoi/dot_agents/bin/executable_agents-sync" >"$T/run.log" 2>&1
expect "a missing ~/.agents is never copied into the repo as a deletion" \
  remote_has dot_agents/core.md dot_agents/skills/own/SKILL.md
done_case

setup
for i in 1 2 3 4 5 6 7 8 9 10 11; do printf 'n\n' > "$HOME/.agents/note$i.md"; done
old "$HOME/.agents"
sync
rm -f "$HOME"/.agents/note*.md
sync
expect "more than ten deletions at once are held" remote_has dot_agents/note1.md dot_agents/note11.md
expect "and reported" failed_saying AGENTS_SYNC_DELETE_MANY
AGENTS_SYNC_DELETE_MANY=1 sync
expect "until they are confirmed" remote_has_none dot_agents/note1.md dot_agents/note11.md
done_case

setup
rm -f "$HOME/.config/chezmoi/chezmoistate.boltdb"
rm -rf "$HOME/.agents/skills/own"
sync
expect "on a fresh machine a missing file is applied" [ -f "$HOME/.agents/skills/own/SKILL.md" ]
expect "and stays in the repo" remote_has dot_agents/skills/own/SKILL.md
done_case

setup
token="ghp_$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 36)"
printf 'token: %s\n' "$token" > "$HOME/.agents/leak.md"
printf '# Fine\n' > "$HOME/.agents/fine.md"
old "$HOME/.agents/leak.md"
old "$HOME/.agents/fine.md"
sync
expect "a file with a secret is held back" not remote_has dot_agents/leak.md
expect "the run reports it and fails" failed_saying leak.md
expect "the other new file still goes in" remote_has dot_agents/fine.md
expect "the secret is not left in the source either" not grep -rq -- "$token" "$HOME/.local/share/chezmoi/dot_agents"
done_case

setup
host=nas
domain=lan
printf '\nThe box is %s.%s.\n' "$host" "$domain" >> "$HOME/.agents/personal.md"
printf '\nAnother rule.\n' >> "$HOME/.agents/core.md"
sync
expect "an edit naming an internal host is held back" not remote_says dot_agents/personal.md "The box is"
expect "the edit stays in ~/.agents" file_says "$HOME/.agents/personal.md" "The box is"
expect "the other edit still goes in" remote_says dot_agents/core.md "Another rule."
done_case

if [ "$fails" -eq 0 ]; then echo "agents-sync-test: all passed"; else echo "agents-sync-test: $fails failed"; fi
[ "$fails" -eq 0 ]
