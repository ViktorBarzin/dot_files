# Pyenv configuration
# Auto-loaded by oh-my-zsh from $ZSH_CUSTOM/tools/

export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"

if command -v pyenv >/dev/null 2>&1; then
    eval "$(pyenv init - zsh)"
fi

# Virtualenvwrapper
export VIRTUALENVWRAPPER_PYTHON=/usr/bin/python3
export VIRTUALENV_PYTHON=python3
export WORKON_HOME=$HOME/.virtualenvs

if [[ -f /usr/local/bin/virtualenvwrapper.sh ]]; then
    source /usr/local/bin/virtualenvwrapper.sh
elif [[ -f $HOME/.virtualenvwrapper.sh ]]; then
    source $HOME/.virtualenvwrapper.sh
fi

# Python debugging
export PYTHONBREAKPOINT=ipdb.set_trace
