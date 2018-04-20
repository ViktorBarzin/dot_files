alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias py='python3.6'
alias whatisopen='sudo netstat -pnlt'
alias calc='gcalccmd'
alias pmr='python manage.py runserver'
alias nopmr="netstat -pnlt | grep -E -o -e '[0-9]+/python' | cut -d '/' -f 1 | xargs kill"
alias pmm='python manage.py migrate'
alias pmmm='python manage.py makemigrations'

# git aliases
alias gs='git status'
alias ga='git add $1'
alias gc='git commit'
alias gp='git push origin master'
alias gpull='git pull origin master'

# MSR registers is responsible for lag after suspend
alias checkcpu='modprobe msr; rdmsr -a 0x19a'
alias fixcpu='wrmsr -a 0x19a 0x0'

alias daimi="grep -rnwi $2 $1"
alias muzika='xdg-open /home/viktor/Documents/Music/njoy.m3u'
alias randomstr="tr -dc a-z1-4 </dev/urandom | tr 1-2 ' \n' | awk 'length==0 || length>50' | tr 3-4 ' ' | sed 's/^ *//' | cat -s | sed 's/ / /g' |fmt"
alias battery="upower -i /org/freedesktop/UPower/devices/battery_BAT0 | grep -E 'time to empty|state|to\ full|percentage'"
alias omg="sudo service NetworkManager restart"
alias omg1.1="sudo modprobe -r iwlwifi; sudo modprobe iwlwifi"
alias zsh_fix="mv ~/.zsh_history ~/.zsh_history_bad; strings ~/.zsh_history_bad > ~/.zsh_history;fc -R ~/.zsh_history; rm ~/.zsh_history_bad"
alias myip="curl ifconfig.co"
alias rmswp="find ~/.vim/tmp/ -iname \"*swp\" -delete"
alias root="sudo su -"

function svali_papka() {
    svn checkout $(echo $1 | sed "s/\/tree\/[a-zA-Z]\+/\/trunk/")
}

function bye() {
    if ps -p $(pidof rsync) 2> /dev/null
    then
        echo 'Rsync is running, not going to sleep.'
    else
        /bin/lock && sudo systemctl suspend
    fi
}

alias sizeof="du -sh $1"
alias mkdir="mkdir -pv"

function psave() {
    sudo service bluetooth stop
    sudo service ModemManager stop  # moile broadband service
    sudo service vmware stop
    sudo service vmware-workstation-server stop
}
