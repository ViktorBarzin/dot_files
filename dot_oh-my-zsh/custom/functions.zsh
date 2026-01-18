# Shell functions
# Auto-loaded by oh-my-zsh from $ZSH_CUSTOM/

# ============================================================================
# Git functions
# ============================================================================

# Useful for daily stand-up
git-standup() {
    AUTHOR=${AUTHOR:="$(git config user.name)"}
    since=yesterday
    if [[ $(date +%u) == 1 ]]; then
        since="2 days ago"
    fi
    git log --all --since "$since" --oneline --author="$AUTHOR"
}

# ============================================================================
# Network functions
# ============================================================================

netok() {
    echo 'Testing DNS settings.'
    timeout 1 ping google.com -W 1 -c 1 &>> /dev/null
    if (( $? == 0 )); then
        echo 'Internet is up.'
        return 0
    fi
    echo 'Pinging 8.8.8.8'
    ping 8.8.8.8 -W 1 -c 1 &>> /dev/null
    if (( $? == 0 )); then
        echo 'Issue spotted in DNS settings'
        return 0
    fi
    gateway=$(echo $(route -n | sed -n '3p' | awk '{print $2}'))
    echo 'Pinging ' $gateway
    ping $gateway -W 1 -c 2 &>> /dev/null
    if (($? == 0 )); then
        echo 'Gateway connectivity issues or being firewalled.'
        return 0
    else
        echo 'Cannot reach default gateway.'
        return 0
    fi
}

certinfo() {
    curl --insecure -v https://"$1" 2>&1 | awk 'BEGIN { cert=0 } /^\* SSL connection/ { cert=1 } /^\*/ { if (cert) print }'
}

# ============================================================================
# Wireguard VPN
# ============================================================================

wgon() {
    wg-quick up ~/vpn-certs/viktor.conf
    # Add ipv4 precedence because vpn is v4 only for now
    bash -c "grep -qxF 'precedence ::ffff:0:0/96 100' /etc/gai.conf || echo 'precedence ::ffff:0:0/96 100' | sudo tee -a /etc/gai.conf"
    # Add dns if missing
    ns_str="nameserver 10.0.20.1 # Added by wgon function"
    search_str="search viktorbarzin.lan # Added by wgon function"
    resolv_conf="/etc/resolv.conf"
    bash -c "grep -qxF '$search_str' $resolv_conf || echo '$search_str' | sudo tee -a $resolv_conf"
    bash -c "grep -qxF '$ns_str' $resolv_conf || echo '$ns_str' | sudo sed -i -e '1i $ns_str' $resolv_conf"
}

wgoff() {
    wg-quick down ~/vpn-certs/viktor.conf
    ns_str="nameserver 10.0.20.1 # Added by wgon function"
    search_str="search viktorbarzin.lan # Added by wgon function"
    resolv_conf="/etc/resolv.conf"
    sudo sed -i '/precedence ::ffff:0:0\/96 100/d' /etc/gai.conf
    sudo sed -i "/$search_str/d" $resolv_conf
    sudo sed -i "/$ns_str/d" $resolv_conf
}

wgs() {
    kubectl scale -n wireguard deployment wireguard --replicas=$1
}

# ============================================================================
# Kubernetes
# ============================================================================

cephpw() {
    kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o yaml | grep "password:" | grep -v '{}' | awk '{print $2}' | base64 --decode
}

kbop() {
    kb -n rook-ceph delete pods $(kbp | grep opera | awk '{print $1}')
    kb -n rook-ceph logs -f $(kbp | grep operator | awk '{print $1}')
}

# ============================================================================
# Compilation / Development
# ============================================================================

c() {
    # Pass any arguments to gcc and afterwards run executable
    gcc "$@" && ./a.out
}

dang_gcc() {
    gcc "$@" -fno-stack-protector -z execstack
}

make_tags() {
    avr-gcc -M $* | sed -e 's/[\\ ]/\n/g' | \
        sed -e '/^$/d' -e '/\.o:[ \t]*$/d' | ctags -L - --c++-kinds=+p --fields=+iaS --extra=+q
}

# ============================================================================
# File encryption
# ============================================================================

encrypt() {
    tar -czvf $1.tar.gz $1 && \
    gpg --symmetric --armor $1.tar.gz && \
    echo "Deleting $1 and $1.tar.gz" && \
    rm -rf $1 $1.tar.gz
}

decrypt() {
    gpg --decrypt $1 | tar xzvf -
}

# ============================================================================
# Utilities
# ============================================================================

camelcase() {
    perl -pe 's#(_|^)(.)#\u$2#g'
}

waitfor() {
    while pidof $1 > /dev/null; do sleep 2; done
}

b64() {
    echo $1 | base64 -d
}

# Include helper - source file if it exists
include() {
    [[ -f "$1" ]] && source "$1"
}

# Download GitHub folder using svn
download_github_folder() {
    svn checkout $(echo $1 | sed "s/\/tree\/[a-zA-Z]\+/\/trunk/")
}
alias svali_papka=download_github_folder

# Snapper wrapper for btrfs snapshots
snp() {
    cmd="$@"
    snapshot_nbr=$(snapper -c home create --type=pre --cleanup-algorithm=number --print-number --description="${cmd}")
    eval "$cmd"
    snapshot_nbr=$(snapper -c home create --type=post --cleanup-algorithm=number --print-number --pre-number="$snapshot_nbr")
}

alias sp="snapper -c home"

# YouTube playlist player
ytplaylist() {
    youtube-dl -o - -f best $@ | vlc -
}
