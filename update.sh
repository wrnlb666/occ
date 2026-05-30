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
update_all=false
update_occ=false
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

_show_default_branch_diff() {
    local db
    local before
    local after

    db="$(_default_branch)"
    if git show-ref --verify --quiet "refs/remotes/origin/${db}"; then
        before=$(git rev-parse "origin/${db}")
    else
        before=""
    fi
    git fetch origin --quiet
    after=$(git rev-parse "origin/${db}")
    [[ -n "$before" && "$before" != "$after" ]] && git diff "$before" "$after"
}

_rebase_tracking_branches() {
    local rc
    local err
    local branch

    for branch in $(git branch --format="%(refname:short)"); do
        if ! git show-ref --verify --quiet "refs/remotes/origin/${branch}"; then
            continue
        fi
        if [[ \
                "$(git rev-parse "${branch}")" == \
                "$(git rev-parse "origin/${branch}")" \
            ]]; then
            continue
        fi
        echo "[INFO] Rebasing onto branch ${branch}"
        git checkout "$branch" > /dev/null 2> /dev/null
        err="$(git rebase --autostash "origin/${branch}" 2>&1 1>/dev/null)"
        rc=$?
        if [[ $rc -ne 0 ]]; then
            echo "[ERRO] git failed to rebase onto branch ${branch}:"
            IFS=$'\n'
            for line in ${err}; do
                echo "  $line"
            done
            git rebase --abort >/dev/null
            return 1
        fi
    done
}

_update() {
    local cb
    local target
    local repo="$1"
    target="$(get_target "${repo}" "$config" 2>/dev/null)"
    if [[ -z "${target}" ]]; then
        echo "[ERRO] ${repo} does not exist"
        return 1
    fi

    echo "[INFO] Fetching ${repo} from remote..."
    cwd="$(pwd)"
    builtin cd "$target" || return 1
    cb="$(git branch --show-current)"
    _show_default_branch_diff
    if ! _rebase_tracking_branches; then
        builtin cd "$dir" || return 1
        return 1
    fi
    git checkout "$cb" > /dev/null 2> /dev/null
    if [[ -f "update.sh" ]]; then
        echo "[INFO] Executing update.sh for ${repo}"
        ./update.sh
    fi
    builtin cd "$dir" || return 1
}

_update_occ() {
    local cb

    echo "[INFO] Fetching occ from remote"
    builtin cd "${cwd}" || return 1
    cb="$(git branch --show-current)"
    _show_default_branch_diff
    if ! _rebase_tracking_branches; then
        builtin cd "$dir" || return 1
        exit 1
    fi
    git checkout "$cb" > /dev/null 2> /dev/null
    builtin cd "$dir" || return 1
}

_update_all() {
    local target
    [[ -d "${dir}" ]] || mkdir -p "${dir}"
    builtin cd "${dir}" || return 1
    for key in "${keys[@]}"; do
        target="$(get_target "${key}" "$config")"
        [[ -d "$target" ]] || continue
        _update "$key"
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
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "[ERRO] Missing directory after $1"
                _help
                exit 1
            fi
            dir="$2"
            shift
            shift
            ;;
        -a|--all|all)
            update_all=true
            update_occ=true
            shift
            ;;
        occ)
            update_occ=true
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

# update occ
"$update_occ" && _update_occ

# cd into target directory
[[ -d "${dir}" ]] || mkdir -p "${dir}"
builtin cd "${dir}" || exit 1

# update all
if ${update_all}; then
    _update_all
    exit 0
fi

# update selected
for key in "${repos[@]}"; do
    _update "$key"
done
