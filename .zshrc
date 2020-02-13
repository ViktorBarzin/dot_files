#[[ $TERM != "screen" ]] && exec tmux
# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
export ZSH=~/.oh-my-zsh
# unset LD_PRELOAD

# Set name of the theme to load. Optionally, if you set this to "random"
# it'll load a random theme each time that oh-my-zsh is loaded.
# See https://github.com/robbyrussell/oh-my-zsh/wiki/Themes
ZSH_THEME="bira"
# ZSH_THEME="adben"

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"
#
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

HISTSIZE=9000
HISTFILESIZE=9000
#HISTFILE="~/.bash_history"

# Uncomment the following line to use hyphen-insensitive completion. Case
# sensitive completion must be off. _ and - will be interchangeable.
HYPHEN_INSENSITIVE="true"

# Uncomment the following line to disable bi-weekly auto-update checks.
DISABLE_AUTO_UPDATE="true"

# Uncomment the following line to change how often to auto-update (in days).
# export UPDATE_ZSH_DAYS=13

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# The optional three formats: "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
HIST_STAMPS="dd.mm.yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(zsh-autosuggestion zsh-syntax-highlighting encode64 gitignore)

source $ZSH/oh-my-zsh.sh
# tmux source-file /home/viktor/.tmux.conf

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR='vim'
else
  # export EDITOR='mvim'
  export EDITOR='vim'
fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# ssh
# export SSH_KEY_PATH="~/.ssh/rsa_id"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"
#eval "$(jump shell)"

# Load aliases
. ~/.bash_aliases

# . ~/.bash_completion

# Locale settings for perl
#export LC_CTYPE=en_US.UTF-8
#export LC_ALL=C
#export LC_ALL=en_US.UTF-8

# Defined in ~/.zshenv
# PYENV_ROOT="$HOME/.pyenv"
# PATH="$PYENV_ROOT/bin:$PATH"
#eval "$(pyenv init -)"

# source /usr/local/bin/virtualenvwrapper.sh
# eval ssh-agent > /dev/null
# VIRTUALENVWRAPPER_PYTHON=python3
export PYTHONBREAKPOINT=ipdb.set_trace
source ~/.zshenv

# Color man pages
export LESS_TERMCAP_mb=$'\e[1;32m'
export LESS_TERMCAP_md=$'\e[1;32m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[01;33m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;4;31m'

# Enable extended glob
setopt extendedglob

# Enable Ctrl-x-e to edit command line
autoload -U edit-command-line
# Emacs style
zle -N edit-command-line
bindkey '^xe' edit-command-line
bindkey '^x^e' edit-command-line
# Vi style:
# zle -N edit-command-line
# bindkey -M vicmd v edit-command-line

# add GO to path
export PATH="/home/viktor/go/bin:$PATH"

# add JDK 12 go path
export PATH="/opt/jdk-12.0.1/bin:$PATH"

# add azure core tools to path
# export PATH="/opt/azure/:$PATH"

# add k8s autocompletion
# source <(kubectl completion zsh)
unset command_not_found_handle

# Load nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"# This loads nvm
[ -s "$NVM_DIR/bash_completion" ] &&   \. "$NVM_DIR/bash_completion"# This loads nvm bash_completion

export PATH="/home/viktor/.local/bin:$PATH"

# Load Z to jump around recent dirs
. ~/z.sh
