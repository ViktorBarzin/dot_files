# Work - Meta-specific aliases and functions
# Auto-loaded by oh-my-zsh from $ZSH_CUSTOM/

# ============================================================================
# On-demand VMs
# ============================================================================
# Connect to first available ondemand machine via et
svmo() {
  et $(ondemand list -q | head -n 2 | tail -n 1 | awk '{print $1}')
}

# ============================================================================
# Build & deploy
# ============================================================================
alias arcb="arc build"
alias arcc="conf canary start"
alias arccc='conf canary cancel --hostname $HOSTNAME'
