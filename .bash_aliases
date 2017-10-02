alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias py='python3.6'
alias bye='systemctl suspend'
alias whatisopen='netstat -pnlt'
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

# MSR registers is responsible for lag after suspend
alias checkcpu='modprobe msr; rdmsr -a 0x19a'
alias fixcpu='wrmsr -a 0x19a 0x0'

#alias daimi="egrep --color -n -i -R $1 --exclude='*.pyc'"
alias daimi="grep -rnw $2 $1"
alias muzika="xdg-open /home/viktor/Documents/Music/njoy.m3u"
alias randomstr="tr -dc a-z1-4 </dev/urandom | tr 1-2 ' \n' | awk 'length==0 || length>50' | tr 3-4 ' ' | sed 's/^ *//' | cat -s | sed 's/ / /g' |fmt"
alias battery="upower -i /org/freedesktop/UPower/devices/battery_BAT0 | grep -E 'time to empty|state|to\ full|percentage'"
alias svali_papka=download_github_folder
alias omg="sudo service NetworkManager restart"
alias zsh_fix="mv ~/.zsh_history ~/.zsh_history_bad; strings ~/.zsh_history_bad > ~/.zsh_history;fc -R ~/.zsh_history; rm ~/.zsh_history_bad"
alias whatismyip="curl ifconfig.co"
alias rmswp="find ~/.vim/tmp/ -iname \"*swp\" -delete"

function download_github_folder() {
    svn checkout $(echo $1 | sed "s/\/tree\/[a-zA-Z]\+/\/trunk/")
}

alias sizeof="du -sh $1"
alias mkdir="mkdir -pv"

# Send ssh key to server
send_key() {
  cat ~/.ssh/id_rsa.pub | ssh $1 "mkdir -p ~/.ssh && cat >>  ~/.ssh/authorized_keys"
}

# function ls(){
#     if [[ $2 == "-l" ]]; then
#         if [[ $3 != "" ]]; then
#             exa -bghHliS $3
#         else
#             exa -bghHliS
#         fi
#     else
#         if [[ $2 != "" ]]; then
#             /bin/ls --color=auto $2
#         else
#             /bin/ls --color=auto
#         fi
#     fi
# }

alias upgrade="sudo apt upgrade"
alias install="sudo apt install"

function secureme(){
    workon ansible;
    cd /home/viktor/ansible-play/
    ansible-playbook -i ./hosts --extra-vars "ansible_sudo_pass=$ROOTPASS" --tags "vpn_startup" main.yml >> /dev/null
    cd /home/viktor/;
    sudo openvpn --config viktor.ovpn &
}
