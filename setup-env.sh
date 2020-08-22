#!/bin/bash

echo "Enter root password:"
read -s password


# Get packet manager
declare -A osInfo;
osInfo[/etc/redhat-release]=dnf
osInfo[/etc/arch-release]=pacman
osInfo[/etc/gentoo-release]=emerge
osInfo[/etc/SuSE-release]=zypp
osInfo[/etc/debian_version]=apt

# for f in "${!osInfo[@]}" # bash version
for f in "${(@k)osInfo}" # zsh version
do
    if [[ -f $f ]];then
        pm=${osInfo[$f]}
    fi
done

if [[ "$pm"  == "apt" ]]; then
    sudo $pm update
fi

# Install zsh
sudo $pm install -y zsh tmux wget && \

# Setup oh-my-zsh
wget https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh && chmod +x install.sh && echo "$password" | ./install.sh && \

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

  ___ _   _  ___ ___ ___  ___ ___
 / __| | | |/ __/ __/ _ \/ __/ __|
 \__ \ |_| | (_| (_|  __/\__ \__ \
 |___/\__,_|\___\___\___||___/___/


' && \
echo 'Restart your shell to apply changes'

