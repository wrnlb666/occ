#!/usr/bin/env bash

# Try installing jq if not exists
_install_jq_binary() {
    local err="[ERRO] please install jq manually"
    local required=("uname" "curl")
    for r in "${required[@]}"; do
        if [[ ! -x "$(command -v "$r")" ]]; then
            echo "$err"
            return 1
        fi
    done
    # check OS
    local OS
    local os
    OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
    case "$OS" in
        linux)
            os="linux"
            ;;
        darwin)
            os="macos"
            ;;
        *)
            echo "$err"
            return 1
            ;;
    esac
    # check ARCH
    local ARCH
    local arch
    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64)
            arch="amd64"
            ;;
        aarch64)
            arch="arm64"
            ;;
        *)
            echo "$err"
            return 1
            ;;
    esac
    # install jq from github
    [[ -d ~/.local/bin ]] || mkdir -p ~/.local/bin
    if ! curl "https://github.com/jqlang/jq/releases/latest/download/jq-${os}-${arch}" \
        -Lo ~/.local/bin/jq ; then 
        echo "$err"
        return 1
    fi
    chmod +x ~/.local/bin/jq
    export PATH="${HOME}/.local/bin:$PATH"
}

_install_jq() {
    if [[ ! -x "$(command -v jq)" ]]; then
        echo "[WARN] jq not installed"
        if [[ -x "$(command -v pacman)" ]]; then
            sudo pacman -S --noconfirm jq && return
        fi
        if [[ -x "$(command -v dnf)" ]]; then
            sudo dnf install -y jq && return
        fi
        if [[ -x "$(command -v apt)" ]]; then
            sudo apt install -y jq && return
        fi
        if [[ -x "$(command -v brew)" ]]; then
            brew install jq && return
        fi
        _install_jq_binary || exit 1
    fi
}

# Get default branch to show diff
_default_branch() {
    # Try the locally cached remote HEAD
    local ref
    ref=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null) || true
    if [ -n "$ref" ]; then
        echo "${ref#origin/}"
        return 0
    fi

    # Fallbacks
    if git show-ref --verify --quiet refs/heads/main; then
        echo "main"; return 0
    fi
    if git show-ref --verify --quiet refs/heads/master; then
        echo "master"; return 0
    fi

    echo "[ERRO] Could not determine default branch locally." >&2
    exit 1
}

# Helper functions
get_ssh() {
    local repo="$1"
    local config="$2"
    jq -r --arg repo "$repo" '.[$repo].ssh // empty' "$config"
}

get_http() {
    local repo="$1"
    local config="$2"
    jq -r --arg repo "$repo" '.[$repo].http // empty' "$config"
}

get_target() {
    local repo="$1"
    local config="$2"
    jq -r --arg repo "$repo" '.[$repo].target // empty' "$config"
}
