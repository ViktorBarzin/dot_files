#!/bin/bash
apt-get update >> /dev/null;
apt-get install git -y;
apt-get install vim-gnome -y;

# Remove default vimrc
rm /usr/share/vim/vimrc

# Download color scheme
wget https://raw.githubusercontent.com/ViktorBarzin/dot_files/master/.vimrc -O ~/.vimrc;
# mkdir -p ~/.vim/colors && cd ~/.vim/colors;
# wget -O wombat256mod.vim http://www.vim.org/scripts/download_script.php?src_id=13400;
git clone https://github.com/ViktorBarzin/dot_files.git
rm -rf ~/.vim
mv dot_files/vim-plugins ~/.vim
rm -rf dot_files
echo 'Done!'
echo
echo 'You may use your newly setup vim!'
