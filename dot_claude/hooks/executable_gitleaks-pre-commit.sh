#!/usr/bin/env bash
# Shared pre-commit: scan staged changes for secrets using gitleaks.
#
# Invoked by each subrepo's .git/hooks/pre-commit (or core.hooksPath/pre-commit)
# shim. Single source of truth — edit this file to change behavior everywhere.
#
# Blocks the commit when a secret is detected. Use `git commit --no-verify` to
# bypass for known false positives (and consider adding a .gitleaksignore
# entry or a [[rules.allowlist]] block in .gitleaks.toml).

set -u

GITLEAKS="${GITLEAKS:-/home/wizard/.local/bin/gitleaks}"

# If gitleaks isn't available, warn but don't block — the hook should degrade
# gracefully on machines without the binary.
if [[ ! -x "$GITLEAKS" ]]; then
    echo "gitleaks pre-commit hook: $GITLEAKS not found, skipping scan" >&2
    exit 0
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0

# If this is the initial commit (no HEAD yet), protect on staged fails because
# there's no baseline — fall back to a working-tree scan of newly-staged files.
# Otherwise use the `protect --staged` fast path.
if git rev-parse --verify HEAD >/dev/null 2>&1; then
    "$GITLEAKS" protect --staged --redact --no-banner --source "$REPO_ROOT"
    rc=$?
else
    # First commit: scan the whole working tree once.
    "$GITLEAKS" detect --no-git --redact --no-banner --source "$REPO_ROOT"
    rc=$?
fi

if [[ $rc -ne 0 ]]; then
    cat >&2 <<'EOF'

gitleaks pre-commit hook BLOCKED the commit — a secret was detected in staged
changes (see findings above, redacted).

Options:
  1. Remove the secret from the staged diff, then re-commit.
  2. If it's a genuine false positive, add an allowlist entry to
     .gitleaks.toml or .gitleaksignore, stage it, and commit again.
  3. If you absolutely must bypass for this commit:
         git commit --no-verify
     (and then fix it properly in a follow-up).

EOF
fi

exit "$rc"
