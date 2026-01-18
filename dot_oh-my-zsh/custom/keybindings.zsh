# Key bindings
# Auto-loaded by oh-my-zsh from $ZSH_CUSTOM/

# Enable Ctrl-x-e to edit command line in $EDITOR
autoload -U edit-command-line
zle -N edit-command-line
bindkey '^xe' edit-command-line
bindkey '^x^e' edit-command-line

# Zsh autosuggestions (if plugin is installed)
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
bindkey '^[0' autosuggest-accept
bindkey '^[9' autosuggest-fetch
