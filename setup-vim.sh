#!/bin/bash

# Add vim 8 repository
sudo add-apt-repository ppa:jonathonf/vim
apt-get update >> /dev/null;
apt-get install vim -y;

rm -rf ~/.vim
# To uninstall and return to stock
# sudo apt install ppa-purge && sudo ppa-purge ppa:jonathonf/vim

# Download color scheme
wget https://raw.githubusercontent.com/ViktorBarzin/dot_files/master/.vimrc -O ~/.vimrc;
# Move plugins to plugins folder
mv vim-plugins ~/.vim

# Update system default link to vimrc
rm /usr/share/vim/vimrc
ln -s "/home/$USER/.vimrc" /usr/share/vim/vimrc

# mkdir -p ~/.vim/colors && cd ~/.vim/colors;
# wget -O wombat256mod.vim http://www.vim.org/scripts/download_script.php?src_id=13400;
echo 'Done!'
echo
echo 'You may use your newly setup vim!'
