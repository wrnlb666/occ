#!/usr/bin/env bash

# Script Working Directory
swd() {
    local SOURCE_PATH="${BASH_SOURCE[0]}"
    local SYMLINK_DIR
    local SCRIPT_DIR
    # Resolve symlinks recursively
    while [ -L "$SOURCE_PATH" ]; do
        # Get symlink directory
        SYMLINK_DIR="$(cd -P "$(dirname "$SOURCE_PATH")" >/dev/null 2>&1 && pwd)"
        # Resolve symlink target (relative or absolute)
        SOURCE_PATH="$(readlink "$SOURCE_PATH")"
        # Check if candidate path is relative or absolute
        if [[ $SOURCE_PATH != /* ]]; then
            # Candidate path is relative, resolve to full path
            SOURCE_PATH=$SYMLINK_DIR/$SOURCE_PATH
        fi
    done
    # Get final script directory path from fully resolved source path
    SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE_PATH")" >/dev/null 2>&1 && pwd)"
    echo "$SCRIPT_DIR"
}

cwd="$(swd)" # config working directory
source "${cwd}/util.sh"

# Global Variables
dir="$(cd -P "${cwd}/.." >/dev/null 2>&1 && pwd)"
config="${cwd}/config.json"
depends_all=false
declare -A all_deps=()
mapfile -t keys < <(jq -r 'keys[]' "$config")

# Helper function
_help() {
    echo "Usage: "
    echo "  ${0} [OPTION] [CONFIG]..."
    echo "  With no OPTION or CONFIG specified defaults to -h."
    echo ""
    echo "Options:"
    echo "  -h, --help, help        Print this help menu"
    echo "  -l, --list, ls, list    List current installed configs"
    echo "  -a, --all, all          Show all required depends"
    echo "  -d, --dir               Config dir, defaults to ${dir}"
}

_list() {
    local target
    printf "Available Configs:\n  "
    for key in "${keys[@]}"; do
        target="$(get_target "$key" "$config")"
        if [[ -d "${dir}/${target}" ]]; then
            printf "%s " "${key}"
        fi
    done
    echo
}

_depends() {
    local target
    local repo="$1"
    target="$(get_target "${repo}" "$config" 2>/dev/null)"
    if [[ -z "${target}" ]]; then
        echo "[ERROR] ${repo} does not exist"
        return 1
    fi

    cwd="$(pwd)"
    builtin cd "$target" || return 1
    if [[ -f "depends.sh" ]]; then
        unset depends
        source depends.sh
        for dep in "${depends[@]}"; do
            all_deps["$dep"]=1
        done
    fi
    builtin cd "$dir" || return 1
}

_depends_all() {
    local target
    [[ -d "${dir}" ]] || mkdir -p "${dir}"
    builtin cd "${dir}" || return 1
    for key in "${keys[@]}"; do
        target="$(get_target "${key}" "$config")"
        [[ -d "$target" ]] || continue
        _depends "$key"
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
    -h | --help | help)
        _help
        exit 0
        ;;
    -l | --list | ls | list)
        _list
        exit 0
        ;;
    -d | --dir)
        if [[ -z "$2" || "$2" == -* ]]; then
            echo "[ERROR] Missing directory after $1"
            _help
            exit 1
        fi
        dir="$2"
        shift
        shift
        ;;
    -a | --all | all)
        depends_all=true
        shift
        ;;
    -*)
        echo "[ERROR] Unknown option $1"
        _help
        exit 1
        ;;
    *)
        repos+=("$1")
        shift
        ;;
    esac
done

# cd into target directory
[[ -d "${dir}" ]] || mkdir -p "${dir}"
builtin cd "${dir}" || exit 1

if ${depends_all}; then
    # depends all
    _depends_all
else
    # depends selected
    for key in "${repos[@]}"; do
        _depends "$key"
    done
fi

printf '%s ' "${!all_deps[@]}"
printf '\n'
