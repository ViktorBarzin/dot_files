alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias py='python3'
alias ipy='ipython3'
alias whatisopen='sudo netstat -pnlt'
alias calc='gcalccmd'
alias pmr='python manage.py runserver'
alias nopmr="ps auxw | grep runserver | awk '{print \$2}' | xargs kill"
alias pmm='python manage.py migrate'
alias pmmm='python manage.py makemigrations'

# Start vim with system clipboard
#alias vim="vimx" # don't alias this - make symlink instead
alias vi="vim"
alias vimdiff="vim -d"

# git aliases
alias g='git'
alias gs='git status'
alias ga='git add'
alias gc='git commit -S'
alias gp='git push origin master'
# alias gp='for r in $(git remote); do echo "Pushing to $r" && git push $r master; done'
alias gpull='git pull --rebase origin master'
alias gl="git log --graph --abbrev-commit --decorate --format=format:'%C(bold blue)%h%C(reset) - %C(bold cyan)%aD%C(reset) %C(bold green)(%ar)%C(reset)%C(bold yellow)%d%C(reset)%n''          %C(white)%s%C(reset) %C(dim white)- %an%C(reset)' --all"
alias gd="git diff"
alias gds="git diff --staged"
alias gb="git branch"
alias gpp='git push production master' # push to production for personal website
# pull all remote branches
alias git-pull-branches='git branch -r | grep -v "\->" | while read remote; do git branch --track "${remote#origin/}" "$remote"; done'
# useful for daily stand-up
git-standup() {
    AUTHOR=${AUTHOR:="`git config user.name`"}

    since=yesterday
    if [[ $(date +%u) == 1 ]] ; then
        since="2 days ago"
    fi

    git log --all --since "$since" --oneline --author="$AUTHOR"
}

# MSR registers is responsible for lag after suspend
alias checkcpu='modprobe msr; rdmsr -a 0x19a'
alias fixcpu='wrmsr -a 0x19a 0x0'

alias muzika='xdg-open ~/Documents/Music/njoy.m3u'
alias randomstr="tr -dc a-z1-4 </dev/urandom | tr 1-2 ' \n' | awk 'length==0 || length>50' | tr 3-4 ' ' | sed 's/^ *//' | cat -s | sed 's/ / /g' |fmt"
alias battery="upower -i /org/freedesktop/UPower/devices/battery_BAT0 | grep -E 'time to empty|state|to\ full|percentage'"
alias svali_papka=download_github_folder
alias omg="sudo systemctl restart NetworkManager"
alias omg1.1="sudo rmmod iwlmvm && sudo rmmod iwlwifi; sudo modprobe iwlwifi"
alias zsh_fix="mv ~/.zsh_history ~/.zsh_history_bad; strings ~/.zsh_history_bad > ~/.zsh_history;fc -R ~/.zsh_history; rm ~/.zsh_history_bad"
alias myip="curl icanhazip.com"
alias rmswp="find ~/.vim/tmp/ -iname \"*swp\" -delete"
alias root="sudo su -"

 download_github_folder() {
    svn checkout $(echo $1 | sed "s/\/tree\/[a-zA-Z]\+/\/trunk/")
}

 bye() {
    if ps -p $(pidof rsync) 2> /dev/null
    then
        echo 'Rsync is running, not going to sleep.'
    else
        # (/bin/lock &) && sudo systemctl suspend
        sudo systemctl suspend
    fi
}

alias sizeof='du -sh'
alias mkdir="mkdir -pv"

#  ls(){
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

# Get packet manager
declare -A osInfo;
osInfo[/etc/redhat-release]=dnf
osInfo[/etc/arch-release]=pacman
osInfo[/etc/gentoo-release]=emerge
osInfo[/etc/SuSE-release]=zypp
osInfo[/etc/debian_version]=apt-get

# for f in "${!osInfo[@]}" # bash version
for f in "${(@k)osInfo}" # zsh version
do
    if [[ -f $f ]];then
        pm=${osInfo[$f]}
    fi
done
alias update="sudo $pm update"
alias u="update"
alias upgrade="sudo $pm upgrade"
alias install="sudo $pm install"
alias remove="sudo $pm remove"
alias reinstall="sudo $pm reinstall"

#  secureme(){
#     workon ansible;
#     cd /home/viktor/ansible-play/
#     ansible-playbook -i ./hosts --extra-vars "ansible_sudo_pass=$ROOTPASS" --tags "vpn_startup" main.yml >> /dev/null
#     cd /home/viktor/;
#     sudo openvpn --config viktor.ovpn &
# }

 function in(){
    if [ $# -lt 2 ];
    then
        echo "Usage:"
        echo "To start existing container:"
        echo "in <os you want>"
        echo
        echo "To start new container:"
        echo "in new <os you want>"
        return
    fi

    if [ $# -eq 1 ]
    then
        container_name="${1/:/_}"
    else
        container_name="${2/:/_}"
    fi

    # Check if recreating a container or reuse existing
    if [ "$1" = "new" ]
    then
        image_name=$2
        if [[ $(docker container ls -a | grep "$container_name") ]]
        then
            if [[ $(docker ps | grep $container_name) ]]
            then
                docker stop $container_name >> /dev/null
            fi
            docker rm $container_name >> /dev/null
        fi

        if [ -z "$3" ]
        then
            cmd="/bin/bash"
        else
            cmd="$3"
        fi
        echo "Running $cmd in $container_name"
        # docker run -it --name $container_name --publish-all=true $image_name "$cmd" && docker attach $container_name

        xhost +local:root  # allow gui apps
        docker run -it --name $container_name -e DISPLAY=$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix $image_name "$cmd"
        xhost -local:root
    else
        xhost +local:root
        docker start $container_name >> /dev/null && docker attach $container_name
        xhost -local:root
    fi
}

#  stest(){
    # snapshot_name="rootsnap"
    # mount_point="$2"

    # if [ $# -ne 2 ];then
    #     echo "Usage:"
    #     echo "$0 <snapshot size> <mount point> "
    #     echo
    #     return
    # fi

    # if [ ${mount_point:0:1} != '/' ]; then
    #     echo "Mount point must be absolute path"
    #     return
    # fi

    # if [[ $(sudo lvs | grep $snapshot_name) ]]; then
    #     echo "$snapshot_name already exists!"
    #     # read -e -p "Do you want to discard it and create a new one?(y/N)" -i n should_discard
    #     echo "Do you want to discard it and create a new one?(y/N)"
    #     read  should_discard
    #     should_discard=${should_discard:-"n"}
    #     # if [ ${(L)should_discard} = 'y' ]; then
    #     if [ $(echo $should_discard | awk '{print tolower($0)}') = 'y' ]; then
    #         sudo umount $mount_point
    #         sudo lvremove /dev/kubuntu-vg/$snapshot_name -y
    #     else
    #         echo "Leaving old snapshot intact"
    #         return
    #     fi

    # fi

    # sudo lvcreate -s -n $snapshot_name /dev/kubuntu-vg/root -L $1
    # sudo mount /dev/kubuntu-vg/$snapshot_name $mount_point
    # sudo chroot $mount_point /bin/zsh
# }
wifi_int_name="$(cat /proc/net/wireless | perl -ne '/(\w+):/ && print $1')"

alias ifl="ifconfig|less"
# Docker aliases
alias dsl="docker swarm leave --force"
alias dsi="docker swarm init --advertise-addr=$wifi_int_name"
alias dsjtm="docker swarm join-token manager"
alias dsjtw="docker swarm join-token worker"

alias noip6="sudo sh -c 'echo 1 > /proc/sys/net/ipv6/conf/$wifi_int_name/disable_ipv6'"
alias yesip6="sudo sh -c 'echo 0 > /proc/sys/net/ipv6/conf/$wifi_int_name/disable_ipv6'"

# alias omg2="killall plasmashell; plasmashell > /dev/null 2>&1 & disown"
alias omg2="kwin --replace &"
alias omg2.1="kquitapp5 plasmashell && kstart5 plasmashell"
alias aliases="vim ~/.bash_aliases && source ~/.bash_aliases"

# alias ghcirun="ghci --make $1; ./$1"
alias lip="ifconfig $(route -n | head -n 3 | tail -n 1 | awk '{print $8}') | grep inet | awk '{print \$2}'"

 netok(){
    # ping google.com
    echo 'Testing DNS settings.'
    timeout 1 ping google.com -W 1 -c 1 &>> /dev/null
    if (( $? == 0 )); then
        echo 'Internet is up.'
        return 0
    fi
    # ping 8.8.8.8
    echo 'Pinging 8.8.8.8'
    ping 8.8.8.8 -W 1 -c 1 &>> /dev/null
    if (( $? == 0 )); then
        echo 'Issue spoted in DNS settings'
        return 0
    fi
    # ping gateway
    gateway=$(echo $(route -n | sed -n '3p' | awk '{print $2}'))
    echo 'Pinging ' $gateway
    ping $gateway -W 1 -c 2 &>> /dev/null
    if (($? == 0 )); then
        echo 'Gateway connectivity issues or being firewalled.'
        return 0
    else
        echo 'Cant reach default gateway.'
        return 0
    fi
    # deteemine issue
}

#alias tldr="rm -r /home/viktor/.tldr_cache/ &> /dev/null; tldr"
alias sl=ls
alias vimrc="vim ~/.vimrc"
alias zshrc="vim ~/.zshrc"
alias f="free -h"
alias h="sudo htop"
alias a="sudo atop"
alias e="exa -bghHliS"
alias n="sudo nethogs"
alias hosts="sudo vim /etc/hosts"

# Source:
# https://wiki.archlinux.org/index.php/Streaming_to_twitch.tv
 streaming() {
     youtube_key="k1ms-wpmc-v652-7rjr" # Ancient, not used anymore
     twitch_key="live_56376159_CCAGv99vT0rr3QwiBiMuDAdoPcYB5N" # Ancient, not user anymore

     if [ "$#" -ne 1 ]; then
         echo "Choose yt/tw"
         return 1
     fi

     if [ "$1" = "yt" ]; then
         STREAM_KEY=$youtube_key
         STREAM_URI="rtmp://a.rtmp.youtube.com/live2/$STREAM_KEY"
     elif [ "$1" = "tw" ]; then
         STREAM_KEY=$twitch_key
         SERVER="live-fra" # twitch server in frankfurt, see http://bashtech.net/twitch/ingest.php for list
         STREAM_URI="rtmp://$SERVER.twitch.tv/app/$STREAM_KEY"
     else
         echo "Invalid media\nChoose yt/tw"
         exit 1
     fi

     # INRES="1920x1080" # input resolution
     # OUTRES="1920x1080" # output resolution
     INRES="$(xdpyinfo | awk '/dimensions/{print $2}')"
     # OUTRES="$(xdpyinfo | awk '/dimensions/{print $2}')"
     # OUTRES="1280x720"
     OUTRES="2560x1440"
     # OUTRES="3840x2160"
     FPS="15" # target FPS
     GOP="29" # i-frame interval, should be double of FPS,
     GOPMIN="15" # min i-frame interval, should be equal to fps,
     THREADS="0" # max 6
     CBR="4000k" # constant bitrate (yuvj444p)
     QUALITY="ultrafast"  # one of the many FFMPEG preset
     AUDIO_RATE="44100"
     # STREAM_KEY="$1" # use the terminal command Streaming streamkeyhere to stream your video to twitch or justin

     ffmpeg -thread_queue_size 512 -f x11grab -s "$INRES" -r "$FPS" -i :0.0 -f alsa -i pulse -f flv -ac 2 -ar $AUDIO_RATE \
       -vcodec libx264 -g $GOP -keyint_min $GOPMIN -b:v $CBR -minrate $CBR -maxrate $CBR -pix_fmt yuv444p\
       -s $OUTRES -preset $QUALITY -tune zerolatency -acodec libmp3lame -threads $THREADS -strict normal \
       -bufsize $CBR $STREAM_URI
 }
alias gg="xset dpms force off"

alias hib="sudo systemctl hibernate"
# where systemctl doesn't work
 # hib(){
 #    # sudo swapon /dev/kubuntu-vg/swap_1 2&>/dev/null
 #    # sudo systemctl hibernate
 #    # sudo swapoff /dev/kubuntu-vg/swap_1 2&>/dev/null
 #    sudo swapon -a
 #    /bin/lock
 #    sleep 2
 #    sudo s2disk 2>1 > /dev/null
# }

alias tricks="vi ~/tricks/tricks.txt"
alias ftricks="vi ~/tricks/fedora.txt"
alias xo="xdg-open"
alias time='"time"'  # Disable bash builit
alias vix="vim -X"   # Fast vim startup wihtout x (no ystem clipboard)
alias reso="xrandr --output HDMI-1 --scale-from 1920x1080"
alias zoomit="gromit-mpx"
alias dk="docker"

alias lk="sudo logkeys -u --start --output /home/viktor/tt --device /dev/input/event4"   # integrated keyboard
alias lk1="sudo logkeys --start --output /home/viktor/tt --device /dev/input/event17"  # usb keyboard

 psave() {
    sudo service bluetooth stop
    sudo service vmware-workstation-server stop
    sudo service vmware stop
    sudo service ModemManager stop
}

 camelcase() {
    perl -pe 's#(_|^)(.)#\u$2#g'
}

 rem_known() {
    "ssh-keygen -f '/home/viktor/.ssh/known_hosts' -R $1"
}

alias s="ssh"
ytplaylist(){
        # if error try updating youtube-dl with: sudo youtube-dl -U
        # youtube-dl -o - $1 -f best | /snap/bin/vlc -
        youtube-dl -o - -f best $@ | vlc -
        # youtube-dl --get-id "$1" | awk '{print "https://www.youtube.com/watch?v=" $0;}' | /snap/bin/vlc -
}

function certinfo {
    # curl --insecure -v "$1" 2>&1;
    curl --insecure -v https://"$1" 2>&1 | awk 'BEGIN { cert=0 } /^\* SSL connection/ { cert=1 } /^\*/ { if (cert) print }';
}

alias speedtest="curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py |python -"
alias backupnas="rsync -az --progress --delete /home nas:/volume1/Backup/Viki/laptop/yuhu-fedora; rsync -az --progress --delete /opt nas:/volume1/Backup/Viki/laptop/yuhu-fedora"

function c(){
   # pass any arguments to gcc and afterwards run executable
   gcc "$@" && ./a.out
}

function dang_gcc(){
    gcc "$@" -fno-stack-protector -z execstack
}

function encrypt() {
    tar -czvf $1.tar.gz $1 && \
    gpg --symmetric --armor $1.tar.gz && \
    echo "Deleting $1 and $1.tar.gz" && \
    rm -rf $1 $1.tar.gz
}

function decrypt() {
    gpg --decrypt $1 | tar xzvf -
}

# use avr-gcc for latfortuna, but gcc works as well
function make_tags() {
avr-gcc -M $* | sed -e 's/[\\ ]/\n/g' | \
        sed -e '/^$/d' -e '/\.o:[ \t]*$/d' | ctags -L - --c++-kinds=+p --fields=+iaS --extra=+q
}
#alias server="python3 -m http.server --bind 0.0.0.0 8000"
alias server="/opt/miniserve-linux"
alias gr="go run"
alias hg="hugo -D server --bind 0.0.0.0"
alias logout="qdbus org.kde.ksmserver /KSMServer logout 0 0 0"
alias sucss="cd ~/pentesting/sucss-19 && workon sucss-playground-webapp"
alias i="sudo iotop"
alias ssucss="ssh sucss.ecs.soton.ac.uk"
alias gpc="globalprotect connect; sudo sed -i '1 i\\nameserver 152.78.110.110' /etc/resolv.conf"
alias gpd="globalprotect disconnect; sudo sed -i '1d' /etc/resolv.conf"

function whoishome() {
    # echo "Finding connected devices..."
    ips=$(nmap -sn 192.168.0.1/24 | grep for | awk '{print $5}')

    # echo "Getting entries from ARP table..."
    # Get entries in arp table
    python3 -c '
import sys
users={
    "C8:21:58:98:29:25": "lubo-laptop",
    "18:F0:E4:2A:CB:B0": "lubo-phone",
    "2C:0E:3D:A7:C1:19": "viktor-phone",
    "48:89:E7:18:0E:66": "viktor-laptop",
    "A0:32:99:C4:0E:38": "nasko-phone",
    "44:03:2C:6B:04:5E": "nasko-laptop",
    "48:01:C5:39:A6:3D": "ioana-phone",
    "F4:0F:24:2B:FE:14": "ioana-laptop",
    "50:EB:71:23:BC:11": "gabi-laptop",
    "FE:43:0A:04:03:BA": "gabi-phone",
}
# print("Connected device: ")
for line in sys.argv[1].split("\n"):
    ip = line.split()[1].replace("(", "").replace(")", "")
    mac = line.split()[3].upper()
    if mac in users:
        print(f"{users[mac]}:{ip}")
' "$(arp -a | grep -v incomplete)"
}

alias wa="watch sensors"
alias gtop="sudo intel_gpu_top"

ZSH_AUTOSUGGEST_STRATEGY=(history completion)
bindkey '^[0' autosuggest-accept;
# bindkey '^[9' forward-word;
bindkey '^[9' autosuggest-fetch;
# bindkey '^[9' autosuggest-clear;
#bindkey '^ ' autosuggest-fetch
alias sp="snapper -c home"

function snp(){
    # Runs a command wrapped in btrfs snapper pre-post snapshots.
    # Usage: $ snp <commands>
    # e.g.: $ snp dnf install htop

    cmd="$@"

    snapshot_nbr=$(snapper -c home create --type=pre --cleanup-algorithm=number --print-number --description="${cmd}")
    # snapshot_nbr=$(sudo snapper create --type=pre --cleanup-algorithm=number --print-number --description="${cmd}")

    eval "$cmd"

    snapshot_nbr=$(snapper -c home create --type=post --cleanup-algorithm=number --print-number --pre-number="$snapshot_nbr")
    # snapshot_nbr=$(sudo snapper create --type=post --cleanup-algorithm=number --print-number --pre-number="$snapshot_nbr")
}

function waitfor() {
    while pidof $1 > /dev/null; do sleep 2; done;
}
alias toclip="xclip -selection clipboard"
alias clearsessions="rm -rf ~/.vim/tmp/sessions/*"
#alias restore_virtualenv_post_scripts="find /home/.snapshots/337/snapshot/viktor/.virtualenvs -name 'postactivate' | sed 's/\/home\/.snapshots\/337\/snapshot\/viktor\///' | xargs -I % rsync -va /home/.snapshots/337/snapshot/viktor/% ~/"

# `clear` can be seen and flicker is annoying
# function watch() {
#     while sleep 1; do
#         clear;
#         ${SHELL-/bin/sh} -c "$*"
#     done;
# }
alias vmon="sudo systemctl start vmware"
alias vmoff="sudo systemctl stop vmware"
alias dkon="sudo systemctl start docker"
alias dkoff="sudo systemctl stop docker"
alias tf="terraform"
function b64() {
    echo $1 | base64 -d
}
# alias fuck='sudo $(history -p !!)'
alias fuck='sudo $(fc -ln -1)'
alias curlb='curl -s -o /dev/null -w "%{time_starttransfer}\n" "$@"'
alias nomicautoadjust='while sleep 0.5; do pacmd set-source-volume alsa_input.pci-0000_00_1f.3.analog-stereo 20000; done'

# Needs to send dbus msg not sure how
# function toggleLidClose() {
#     # If action is none, make it suspend and vice-versa
#     if grep 'lidAction=0' ~/.config/powermanagementprofilesrc > /dev/null; then
#         sed -i 's/lidAction=0/lidAction=1/' ~/.config/powermanagementprofilesrc
#     else
#         sed -i 's/lidAction=1/lidAction=0/' ~/.config/powermanagementprofilesrc
#     fi
# }

# Games
alias medieval="sh -c 'cd ~/.wine/drive_c/Program\ Files\ \(x86\)/SEGA/Medieval\ II\ Total\ War/ && wine medieval2.exe'"

alias kb="kubectl"
alias kbp="kubectl get pods"
alias kn="kubens"
function cephpw() {
    kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o yaml | grep "password:" | grep -v '{}'| awk '{print $2}' | base64 --decode
}

alias k8srole="ansible-playbook -i hosts.yaml linux.yml -e host='10.0.20.100' -t "
alias wgon="wg-quick up ~/vpn-certs/viktor.conf"
alias wgoff="wg-quick down ~/vpn-certs/viktor.conf"
