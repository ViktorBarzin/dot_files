#!/bin/bash
# Auto-renew Vault token if it exists and is renewable
VAULT_TOKEN_FILE="$HOME/.vault-token"

if [ ! -f "$VAULT_TOKEN_FILE" ]; then
    exit 0
fi

export VAULT_ADDR="https://vault.viktorbarzin.me"
export VAULT_TOKEN="$(cat "$VAULT_TOKEN_FILE")"

# Check if token is still valid and renewable, then renew
if vault token lookup -format=json 2>/dev/null | /usr/bin/python3 -c "import sys,json; d=json.load(sys.stdin)['data']; sys.exit(0 if d.get('renewable') else 1)" 2>/dev/null; then
    vault token renew > /dev/null 2>&1
fi
