#!/bin/bash

echo -n Enter root password:
read -s password
# Install zsh
sudo apt update
sudo apt upgrade --assume-yes
sudo apt install zsh \
                python-pip
# Setup oh-my-zsh
echo $password | sh -c "$(wget https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh -O -)" && \
# Password prompt

# Setup config files
git clone https://github.com/ViktorBarzin/dot_files.git && \
cp -i .zshrc ~/ && \
cp -i .bash_aliases ~/  && \
sudo cp -i virtualenvwrapper.sh /usr/local/bin/  && \
cp -i .zshenv ~/ && \

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
sudo pip install virtualenvwrapper

