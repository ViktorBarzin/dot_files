# Lazy-load kubectl completions (saves ~100ms startup time)
if (( $+commands[kubectl] )); then
  function kubectl() {
    unfunction kubectl
    source <(command kubectl completion zsh)
    kubectl "$@"
  }
fi

# Aliases (available immediately)
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgn='kubectl get nodes'
alias kga='kubectl get all'
alias kd='kubectl describe'
alias kl='kubectl logs'
alias kx='kubectl exec -it'
