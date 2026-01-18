# PATH modifications
# Auto-loaded by oh-my-zsh from $ZSH_CUSTOM/

# Go
export GOPATH="$HOME/go"
export PATH="$HOME/go/bin:$PATH"

# Local bin
export PATH="$HOME/.local/bin:$PATH"

# JDK (if installed)
[[ -d /opt/jdk-12.0.1/bin ]] && export PATH="/opt/jdk-12.0.1/bin:$PATH"

# Krew (kubectl plugin manager)
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

# Add custom zsh functions
fpath+=~/.zfunc
