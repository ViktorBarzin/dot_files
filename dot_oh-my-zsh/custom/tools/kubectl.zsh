# Kubectl configuration
# Auto-loaded by oh-my-zsh from $ZSH_CUSTOM/tools/
# Note: This must run after compinit, which oh-my-zsh handles

if command -v kubectl >/dev/null 2>&1; then
    source <(kubectl completion zsh)
fi

# Load golang path if exists
[[ -f /etc/profile.d/golang_path.sh ]] && source /etc/profile.d/golang_path.sh
