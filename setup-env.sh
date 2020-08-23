#!/bin/bash

set -e

# Get packet manager
if [ -x "$(command -v apk)" ]; then pm=apk
elif [ -x "$(command -v apt)" ]; then pm="apt"
elif [ -x "$(command -v dnf)" ]; then pm="dnf"
elif [ -x "$(command -v zypper)" ];then pm="zypper"
else echo "FAILED TO INSTALL PACKAGE: Package manager not found. You must manually install: zsh tmux wget"
fi

# Install zsh
if which zsh 2>/dev/null > /dev/null  && which tmux 2>/dev/null >/dev/null && which wget 2>/dev/null >/dev/null; then
    echo "All needed packages are installed. Skipping install step"
else
    echo "Installing zsh, tmux and wget..."
    sudo $pm install -y zsh tmux wget
fi

# Setup oh-my-zsh
wget -O /tmp/install.sh https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh
chmod +x /tmp/install.sh
set +e
echo "exit" | /tmp/install.sh
set -e
rm /tmp/install.sh

# Setup zsh config files
wget -O ~/.zshrc https://raw.githubusercontent.com/ViktorBarzin/dot_files/master/.zshrc && \
wget -O ~/.bash_aliases https://raw.githubusercontent.com/ViktorBarzin/dot_files/master/.bash_aliases && \
wget -O ~/.zshenv https://raw.githubusercontent.com/ViktorBarzin/dot_files/master/.zshenv && \

# Setup tmux
bash -c "cd ~ && git clone https://github.com/gpakosz/.tmux.git && ln -s -f .tmux/.tmux.conf && cp .tmux/.tmux.conf.local ."

wget -O ~/.tmux.conf.local https://raw.githubusercontent.com/ViktorBarzin/dot_files/master/.tmux.conf.local && \

# Configure z (jump)
# git clone https://github.com/agkozak/zsh-z $ZSH_CUSTOM/plugins/zsh-z && \
git clone https://github.com/agkozak/zsh-z ~/.oh-my-zsh/plugins/zsh-z && \

echo '
  ___ _   _  ___ ___ ___  ___ ___
 / __| | | |/ __/ __/ _ \/ __/ __|
 \__ \ |_| | (_| (_|  __/\__ \__ \
 |___/\__,_|\___\___\___||___/___/


' && \
echo ' Run tmux to enter your newly setup environment!'

