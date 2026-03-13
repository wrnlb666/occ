#!/usr/bin/env bash

# Script Working Directory
swd() {
    local SOURCE_PATH="${BASH_SOURCE[0]}"
    local SYMLINK_DIR
    local SCRIPT_DIR
    # Resolve symlinks recursively
    while [ -L "$SOURCE_PATH" ]; do
        # Get symlink directory
        SYMLINK_DIR="$( cd -P "$( dirname "$SOURCE_PATH" )" >/dev/null 2>&1 && pwd )"
        # Resolve symlink target (relative or absolute)
        SOURCE_PATH="$(readlink "$SOURCE_PATH")"
        # Check if candidate path is relative or absolute
        if [[ $SOURCE_PATH != /* ]]; then
            # Candidate path is relative, resolve to full path
            SOURCE_PATH=$SYMLINK_DIR/$SOURCE_PATH
        fi
    done
    # Get final script directory path from fully resolved source path
    SCRIPT_DIR="$(cd -P "$( dirname "$SOURCE_PATH" )" >/dev/null 2>&1 && pwd)"
    echo "$SCRIPT_DIR"
}

cwd="$(swd)"    # config working directory
source "${cwd}/util.sh"

# Global Variables
dir="$(cd -P "${cwd}/.." >/dev/null 2>&1 && pwd)"
config="${cwd}/config.json"
install_all=false
install_occ=false
use_http=false
mapfile -t keys < <(jq -r 'keys[]' "$config")

# Helper function
_help() {
    echo "Usage: "
    echo "  ${0} [OPTION] [CONFIG]..."
    echo "  With no OPTION or CONFIG specified defaults to -h."
    echo ""
    echo "Options:"
    echo "  -h, --help, help        Print this help menu"
    echo "  -l, --list, ls, list    List current available configs"
    echo "  -a, --all, all          Install all available configs"
    echo "  --http, --https         Clone with http or https instead of ssh"
    echo "  -d, --dir               Config dir, defaults to ${dir}"
}

_list() {
    printf "Available Configs:\n  "
    for key in "${keys[@]}"; do
        printf "%s " "${key}"
    done
    echo
}

_install() {
    local rc
    local err
    local target
    local repo="$1"
    target="$(get_target "${repo}" "$config" 2>/dev/null)"
    if [[ -z "${target}" ]]; then
        echo "[ERRO] ${repo} does not exist"
        return 1
    fi

    local url=""
    if "$use_http"; then
        url="$(get_http "${repo}" "$config")"
    else
        url="$(get_ssh "${repo}" "$config")"
    fi

    if [[ -e "$target" ]]; then
        echo "[ERRO] $(pwd)/${target} already exists. "
        exit 1
    fi
    echo "[INFO] Cloning ${repo}..."
    err="$(git clone "$url" "$target" 2>&1 1>/dev/null)"
    rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "[ERRO] git faled to clone ${repo}:"
        IFS=$'\n'
        for line in ${err}; do
            echo "  $line"
        done
        exit 1
    fi
    echo "[INFO] Installing ${repo}..."
    (builtin cd "$target" && ./install.sh)
}

_install_occ() {
    echo "[INFO] Installing occ"
    [[ -d ~/.local/bin ]] || mkdir ~/.local/bin
    ln -sf "${cwd}/occ" ~/.local/bin/occ
}

_install_all() {
    [[ -d "${dir}" ]] || mkdir -p "${dir}"
    builtin cd "${dir}" || return 1
    for key in "${keys[@]}"; do
        _install "$key"
    done
}


# Main Function
_install_jq

if [[ "$#" -eq 0 ]]; then
    _help
    exit 0
fi

declare -a repos
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help|help)
            _help
            exit 0
            ;;
        -l|--list|ls|list)
            _list
            exit 0
            ;;
        -d|--dir)
            dir="$2"
            shift
            shift
            ;;
        occ)
            install_occ=true
            shift
            ;;
        --http|--https)
            use_http=true
            shift
            ;;
        -a|--all|all)
            install_all=true
            install_occ=true
            shift
            ;;
        -*)
            echo "[ERRO] Unknown option $1"
            _help
            exit 1
            ;;
        *)
            repos+=("$1")
            shift
            ;;
    esac
done

# install occ
"$install_occ" && _install_occ

# cd into target directory
[[ -d "${dir}" ]] || mkdir -p "${dir}"
builtin cd "${dir}" || return 1

if ${install_all}; then
    _install_all
    exit 0
fi

for key in "${repos[@]}"; do
    _install "$key"
done
