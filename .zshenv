# export PYENV_ROOT="$HOME/.pyenv"
# export PATH="$PYENV_ROOT/bin:$PATH"
# eval "$(pyenv init -)"

#export PATH="/home/viktor/.pyenv/bin:$PATH"
#eval "$(pyenv init -)"
#eval "$(pyenv virtualenv-init -)"


export VIRTUALENVWRAPPER_PYTHON=/usr/bin/python3
export VIRTUALENV_PYTHON=python3
export WORKON_HOME=$HOME/.virtualenvs
# export VIRTUALENV_PYTHON=python

if [ -f $HOME/.virtualenvwrapper.sh ]; then
    source $HOME/.virtualenvwrapper.sh
fi
