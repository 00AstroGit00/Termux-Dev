# Bash completion for termux-suite, tsuite, termux-apk-build, apk-build

_tsuite_completions() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    opts="--all --base --essentials --node --ai --ai-env --android --apk --build-apk --verify --doctor --health --test --smoke-test --prune-ndk --tune-device --tune-keys --install-hooks --clean --help -h"

    if [[ "$cur" == -* ]]; then
        mapfile -t COMPREPLY < <(compgen -W "$opts" -- "$cur")
        return 0
    fi
}

_apk_build_completions() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    opts="-p --project -m --manifest -s --src -r --res -l --lib -j --jars -o --output -i --install -u --share --min-sdk --target-sdk -k --keystore --alias --pass -h --help"

    case "$prev" in
        -p|--project|-s|--src|-r|--res|-l|--lib)
            mapfile -t COMPREPLY < <(compgen -d -- "$cur")
            return 0
            ;;
        -m|--manifest|-j|--jars|-o|--output|-k|--keystore)
            mapfile -t COMPREPLY < <(compgen -f -- "$cur")
            return 0
            ;;
    esac

    if [[ "$cur" == -* ]]; then
        mapfile -t COMPREPLY < <(compgen -W "$opts" -- "$cur")
        return 0
    fi
}

complete -F _tsuite_completions termux-suite tsuite
complete -F _apk_build_completions termux-apk-build apk-build
