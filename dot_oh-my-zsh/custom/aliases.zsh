# Aliases - organized by category
# Auto-loaded by oh-my-zsh from $ZSH_CUSTOM/

# ============================================================================
# Basic utilities
# ============================================================================
alias ls='ls --color=auto'
alias sl=ls
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

alias vi="vim"
alias vimdiff="vim -d"
alias vix="vim -X"  # Fast vim startup without X (no system clipboard)
alias vimrc="vim ~/.vimrc"
alias zshrc="vim ~/.zshrc"

alias sizeof='du -sh'
alias mkdir="mkdir -pv"
alias f="free -h"
alias h="sudo htop"
alias a="sudo atop"
alias e="exa -bghHliS"
alias n="sudo nethogs"
alias i="sudo iotop"
alias hosts="sudo vim /etc/hosts"
alias root="sudo su -"
alias xo="xdg-open"
alias time='"time"'  # Disable bash builtin
alias toclip="xclip -selection clipboard"

# ============================================================================
# Python
# ============================================================================
alias py='python3'
alias ipy='ipython3'
alias pmr='python manage.py runserver'
alias nopmr="ps auxw | grep runserver | awk '{print \$2}' | xargs kill"
alias pmm='python manage.py migrate'
alias pmmm='python manage.py makemigrations'

# ============================================================================
# Git
# ============================================================================
alias g='git'
alias gs='git status'
alias ga='git add'
alias gp='git push origin master'
alias gpf='git push -u forgejo master'
alias gpull='git pull --rebase origin master'
alias gl="git log --graph --abbrev-commit --decorate --format=format:'%C(bold blue)%h%C(reset) - %C(bold cyan)%aD%C(reset) %C(bold green)(%ar)%C(reset)%C(bold yellow)%d%C(reset)%n''          %C(white)%s%C(reset) %C(dim white)- %an%C(reset)' --all"
alias gd="git diff"
alias gds="git diff --staged"
alias gb="git branch"
alias gpp='git push production master'
alias git-pull-branches='git branch -r | grep -v "\->" | while read remote; do git branch --track "${remote#origin/}" "$remote"; done'

# ============================================================================
# Docker
# ============================================================================
alias dk="docker"
alias dsl="docker swarm leave --force"
alias dkon="sudo systemctl start docker"
alias dkoff="sudo systemctl stop docker"

# ============================================================================
# Kubernetes
# ============================================================================
alias kb="kubectl"
alias kbp="kubectl get pods"
alias kbpo="kubectl get pods -o wide"
alias kbs="kubectl get svc"
alias kbn="kubectl get nodes -o wide"
alias kbd="kubectl describe pods"
alias kbf="kubectl logs --all-containers --max-log-requests 50 --prefix --ignore-errors -f --since=5m"
alias kbe='kubectl exec -it $(kbp | tail -n 1 | awk "{print \$1}") -- sh'
alias kn="kubens"

# ============================================================================
# Terraform
# ============================================================================
alias tf="terraform"
alias tfa="tf apply"

# ============================================================================
# Network
# ============================================================================
alias s="ssh"
alias myip="curl https://icanhazip.com"
alias ifl="ifconfig|less"
alias whatisopen='sudo netstat -pnlt'
alias speedtest="curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python -"
alias wg="sudo wg"

# ============================================================================
# System
# ============================================================================
alias omg="sudo systemctl restart NetworkManager"
alias omg1.1="sudo rmmod iwlmvm && sudo rmmod iwlwifi; sudo modprobe iwlwifi"
alias omg2="kwin --replace &"
alias omg2.1="kquitapp5 plasmashell && kstart5 plasmashell"

alias battery="upower -i /org/freedesktop/UPower/devices/battery_BAT0 | grep -E 'time to empty|state|to\ full|percentage'"
alias bye="sudo systemctl suspend"
alias hib="sudo systemctl hibernate"
alias gg="xset dpms force off"
alias wa="watch sensors"
alias gtop="sudo intel_gpu_top"

alias vmon="sudo systemctl start vmware"
alias vmoff="sudo systemctl stop vmware"

# ============================================================================
# Misc tools
# ============================================================================
alias aliases="vim ~/.oh-my-zsh/custom/aliases.zsh && source ~/.zshrc"
alias rmswp="find ~/.vim/tmp/ -iname \"*swp\" -delete"
alias clearsessions="rm -rf ~/.vim/tmp/sessions/*"
alias zsh_fix="mv ~/.zsh_history ~/.zsh_history_bad; strings ~/.zsh_history_bad > ~/.zsh_history; fc -R ~/.zsh_history; rm ~/.zsh_history_bad"
alias server="/opt/miniserve-linux"
alias gr="go run ."
alias hg="hugo -D server --bind 0.0.0.0"
alias cr="cargo run"
alias tricks="vi ~/tricks/tricks.txt"
alias logout="qdbus org.kde.ksmserver /KSMServer logout 0 0 0"

# Shadowsocks
alias ss-tunnel="snap run shadowsocks-libev.ss-tunnel"
alias ss-local="snap run shadowsocks-libev.ss-local"

# ============================================================================
# Package manager detection (for update/install aliases)
# ============================================================================
typeset -A osInfo
osInfo[/etc/redhat-release]=dnf
osInfo[/etc/arch-release]=pacman
osInfo[/etc/gentoo-release]=emerge
osInfo[/etc/SuSE-release]=zypp
osInfo[/etc/debian_version]=apt-get

for f in "${(@k)osInfo}"; do
    if [[ -f $f ]]; then
        pm=${osInfo[$f]}
    fi
done

alias update="sudo $pm update"
alias u="update"
alias upgrade="sudo $pm upgrade"
alias install="sudo $pm install"
alias remove="sudo $pm remove"
alias reinstall="sudo $pm reinstall"

# ============================================================================
# Chezmoi (dotfiles management)
# ============================================================================
alias cmu="chezmoi update"           # Pull from remote and apply changes
alias cma="chezmoi apply"            # Apply changes from local source
alias cms="chezmoi status"           # Show what would change
alias cmd="chezmoi diff"             # Show diff of pending changes
alias cme="chezmoi edit"             # Edit a managed file
