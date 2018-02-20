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
alias svali_papka=download_github_folder
alias omg="sudo service NetworkManager restart"
alias omg1.1="sudo modprobe -r iwlwifi; sudo modprobe iwlwifi"
alias zsh_fix="mv ~/.zsh_history ~/.zsh_history_bad; strings ~/.zsh_history_bad > ~/.zsh_history;fc -R ~/.zsh_history; rm ~/.zsh_history_bad"
alias myip="curl ifconfig.co"
alias rmswp="find ~/.vim/tmp/ -iname \"*swp\" -delete"
alias root="sudo su -"

function download_github_folder() {
    svn checkout $(echo $1 | sed "s/\/tree\/[a-zA-Z]\+/\/trunk/")
}

function bye() {
    if ps -p $(pidof rsync) 2> /dev/null
    then
        echo 'Rsync is running, not going to sleep.'
    else
        sudo systemctl suspend
    fi
}

alias sizeof="du -sh $1"
alias mkdir="mkdir -pv"

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

alias update="sudo apt update"
alias upgrade="sudo apt upgrade"
alias install="sudo apt install"
alias remove="sudo apt remove"

# function secureme(){
#     workon ansible;
#     cd /home/viktor/ansible-play/
#     ansible-playbook -i ./hosts --extra-vars "ansible_sudo_pass=$ROOTPASS" --tags "vpn_startup" main.yml >> /dev/null
#     cd /home/viktor/;
#     sudo openvpn --config viktor.ovpn &
# }

function in(){
    if [ $# -ne 1 ] && [ $# -ne 2 ];
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
    if [ "$1" = "new" ] && [ $# -eq 2 ]
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
        docker run -it --name $container_name --publish-all=true $image_name /bin/bash
        docker attach $container_name
    else
        docker start $container_name >> /dev/null
        docker attach $container_name
        # docker exec -it $container_name /bin/bash
    fi
}

function stest(){
  : snapshot_name="rootsnap"
    mount_point="$2"

    if [ $# -ne 2 ];then
        echo "Usage:"
        echo "$0 <snapshot size> <mount point> "
        echo
        return
    fi

    if [ ${mount_point:0:1} != '/' ]; then
        echo "Mount point must be absolute path"
        return
    fi

    if [[ $(sudo lvs | grep $snapshot_name) ]]; then
        echo "$snapshot_name already exists!"
        # read -e -p "Do you want to discard it and create a new one?(y/N)" -i n should_discard
        echo "Do you want to discard it and create a new one?(y/N)"
        read  should_discard
        should_discard=${should_discard:-"n"}
        # if [ ${(L)should_discard} = 'y' ]; then
        if [ $(echo $should_discard | awk '{print tolower($0)}') = 'y' ]; then
            sudo umount $mount_point
            sudo lvremove /dev/kubuntu-vg/$snapshot_name -y
        else
            echo "Leaving old snapshot intact"
            return
        fi

    fi

    sudo lvcreate -s -n $snapshot_name /dev/kubuntu-vg/root -L $1
    sudo mount /dev/kubuntu-vg/$snapshot_name $mount_point
    sudo chroot $mount_point /bin/zsh
}

alias ifl="ifconfig|less"
# Docker aliases
alias dsl="docker swarm leave --force"
alias dsi="docker swarm init --advertise-addr=$(ifconfig wlp2s0 | grep inet | awk '/1/{print $2}')"
alias dsjtm="docker swarm join-token manager"
alias dsjtw="docker swarm join-token worker"

alias noip6="sudo sh -c 'echo 1 > /proc/sys/net/ipv6/conf/wlp2s0/disable_ipv6'"
alias yesip6="sudo sh -c 'echo 0 > /proc/sys/net/ipv6/conf/wlp2s0/disable_ipv6'"
alias dd="dd status=progress"
alias omg2="killall plasmashell; plasmashell > /dev/null 2>&1 & disown"
alias aliases="vim /home/viktor/.bash_aliases && source /home/viktor/.bash_aliases"

# alias ghcirun="ghci --make $1; ./$1"
alias lip="ifconfig $(route -n | head -n 3 | tail -n 1 | awk '{print $8}') | grep inet | awk '{print \$2}'"

function netok(){
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
alias f="free -h"
alias h="sudo htop"
alias e="exa -bghHliS"
alias hosts="sudo vim /etc/hosts"

# Source:
# https://wiki.archlinux.org/index.php/Streaming_to_twitch.tv
 streaming() {
     youtube_key="k1ms-wpmc-v652-7rjr" # Hide me
     twitch_key="live_56376159_CCAGv99vT0rr3QwiBiMuDAdoPcYB5N" # and me

     if [ "$#" -ne 1 ]; then
         echo "Choose yt/tw"
         return 1
     fi

     if [ "$1"=="yt" ]; then
         STREAM_KEY=$youtube_key
         STREAM_URI="rtmp://a.rtmp.youtube.com/live2/$STREAM_KEY"
     elif [ "$1"=="tw" ]; then
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
     OUTRES="$(xdpyinfo | awk '/dimensions/{print $2}')"
     FPS="15" # target FPS
     GOP="30" # i-frame interval, should be double of FPS,
     GOPMIN="15" # min i-frame interval, should be equal to fps,
     THREADS="2" # max 6
     CBR="1000k" # constant bitrate (should be between 1000k - 3000k)
     QUALITY="slow"  # one of the many FFMPEG preset
     AUDIO_RATE="44100"
     # STREAM_KEY="$1" # use the terminal command Streaming streamkeyhere to stream your video to twitch or justin

     ffmpeg -f x11grab -s "$INRES" -r "$FPS" -i :0.0 -f alsa -i pulse -f flv -ac 2 -ar $AUDIO_RATE \
       -vcodec libx264 -g $GOP -keyint_min $GOPMIN -b:v $CBR -minrate $CBR -maxrate $CBR -pix_fmt yuv420p\
       -s $OUTRES -preset $QUALITY -tune film -acodec libmp3lame -threads $THREADS -strict normal \
       -bufsize $CBR $STREAM_URI
 }
alias gg="xset dpms force off"

function hib(){
    # sudo swapon /dev/kubuntu-vg/swap_1 2&>/dev/null
    # sudo systemctl hibernate
    # sudo swapoff /dev/kubuntu-vg/swap_1 2&>/dev/null
    sudo swapon -a
    /bin/lock
    sleep 2
    sudo s2disk
}

alias tricks="vi ~/tricks/tricks.txt"
alias xo="xdg-open"
alias time='"time"'  # Disable bash builit
alias vix="vim -X"   # Fast vim startup wihtout x (no ystem clipboard)
