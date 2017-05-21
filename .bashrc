# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
#shopt -s globstar

# make less more friendly for non-text input files, see lesspipe(1)
#[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color) color_prompt=yes;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
	# We have color support; assume it's compliant with Ecma-48
	# (ISO/IEC-6429). (Lack of such support is extremely rare, and such
	# a case would tend to support setf rather than setaf.)
	color_prompt=yes
    else
	color_prompt=
    fi
fi

if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;31m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    # Ne znam kakvo e tova otdolu, no ne raboti ;\
    # test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias utorrent='utserver -settingspath /opt/utorrent-servealpha-v3_3/'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'
    alias pycharm='bash /usr/share/pycharm-community-2016.2.3/bin/pycharm.sh'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
	alias android-studio='bash /usr/share/android-studio/bin/studio.sh'
	alias hackbg-python='cd /home/viktor/Documents/Software_Development/python/HackBulgaria-Python/'
    alias violent-python='cd /home/viktor/Documents/Software_Development/python/violent-python'
    alias django='cd /home/viktor/Documents/Software_Development/python/HackBulgaria-Django/'
	alias py='python3.6'
	alias bye='systemctl suspend'
	alias whatisopen='netstat -pnlt'
    alias calc='gcalccmd'
    alias pmr='python manage.py runserver'
    alias nopmr="netstat -pnlt | grep -E -o -e '[0-9]+/python' | cut -d '/' -f 1 | xargs kill"

    # git aliases
    alias gs='git status'
    alias ga='git add .'
    alias gc='git commit'
    alias gp='git push origin master'

    # MSR registers is responsible for lag after suspend
    alias checkcpu='modprobe msr; rdmsr -a 0x19a'
    alias fixcpu='wrmsr -a 0x19a 0x0'
	alias daimi="egrep --color -n -i -R $1 --exclude='*.pyc'"
    alias muzika="xdg-open /home/viktor/Documents/Music/njoy.m3u"
    alias randomstr="tr -dc a-z1-4 </dev/urandom | tr 1-2 ' \n' | awk 'length==0 || length>50' | tr 3-4 ' ' | sed 's/^ *//' | cat -s | sed 's/ / /g' |fmt"
    alias battery="upower -i /org/freedesktop/UPower/devices/battery_BAT0 | grep -E 'time to empty|state|to\ full|percentage'"
    alias svali_papka=download_github_folder

    function download_github_folder(){
        svn checkout $(echo $1 | sed "s/\/tree\/[a-zA-Z]\+/\/trunk/")
    }


fi


# some more ls aliases
#alias ll='ls -l'
#alias la='ls -A'
#alias l='ls -CF'

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

export NVM_DIR="/root/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"  # This loads nvm

alias omg="service NetworkManager restart"

VIRTUALENVWRAPPER_PYTHON=/usr/bin/python3.5
export VIRTUALENVWRAPPER_PYTHON
export WORKON_HOME=$HOME/.virtualenvs
source /usr/local/bin/virtualenvwrapper.sh
