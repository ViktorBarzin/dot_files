# NVM (Node Version Manager) configuration
# Auto-loaded by oh-my-zsh from $ZSH_CUSTOM/tools/
# Lazy-loaded: defers nvm init until first use

export NVM_DIR="$HOME/.nvm"

if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    function nvm() {
        unfunction nvm
        \. "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
        nvm "$@"
    }
fi
