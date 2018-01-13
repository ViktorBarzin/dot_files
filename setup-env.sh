#!/bin/bash

echo "Enter root password:"
read -s password

# Install zsh
sudo apt update
sudo apt upgrade --assume-yes
sudo apt install zsh \
                python-pip --assume-yes
# Setup oh-my-zsh
wget https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh && chmod +x install.sh && echo "$password" | ./install.sh && \

# Setup config files
cp .zshrc ~/ && \
cp  .bash_aliases ~/  && \
sudo cp  virtualenvwrapper.sh /usr/local/bin/  && \
cp  .zshenv ~/ && \
cp bira.zsh-theme ~/.oh-my-zsh/themes/

# Configure j (jump)
# Debian like
wget https://github.com/gsamokovarov/jump/releases/download/v0.18.0/jump_0.18.0_amd64.deb && \
sudo dpkg -i jump_0.18.0_amd64.deb && \

# RHEL like
# wget https://github.com/gsamokovarov/jump/releases/download/v0.18.0/jump-0.18.0-1.x86_64.rpm
# sudo rpm -i jump-0.18.0-1.x86_64.rpm
# Setup vim


# Setup pyenv
git clone https://github.com/pyenv/pyenv.git ~/.pyenv && \
# Install python
# pyenv install 3.6.4 # throws some error? :/

# Install pip
sudo pip install --upgrade pip && \
sudo pip install virtualenvwrapper && \

source ~/.zshrc && \
echo '


  ___ _   _  ___ ___ ___  ___ ___
 / __| | | |/ __/ __/ _ \/ __/ __|
 \__ \ |_| | (_| (_|  __/\__ \__ \
 |___/\__,_|\___\___\___||___/___/


' && \
echo 'Restart your shell to apply changes'
