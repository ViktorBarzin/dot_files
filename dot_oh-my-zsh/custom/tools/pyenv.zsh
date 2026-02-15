# Pyenv configuration (lazy-loaded)
# Auto-loaded by oh-my-zsh from $ZSH_CUSTOM/tools/

export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"

if (( $+commands[pyenv] )); then
    function pyenv() {
        unfunction pyenv
        eval "$(command pyenv init - zsh)"
        pyenv "$@"
    }
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
