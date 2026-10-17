# Bash completion for termux-suite, tsuite, termux-apk-build, apk-build

_tsuite_completions() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    opts="--all --wizard --base --essentials --node --ai --ai-env --android --apk --build-apk --adb --adb-pair --adb-connect --backup --restore --verify --doctor --health --test --smoke-test --prune-ndk --tune-device --tune-keys --install-hooks --clean --help -h"

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
    opts="-p --project -m --manifest -s --src -r --res -l --lib -j --jars -o --output -i --install -u --share --no-cache --clean-cache --min-sdk --target-sdk -k --keystore --alias --pass -h --help"

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

_wireless_adb_completions() {
    local cur opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    opts="pair connect reconnect disconnect status guide help -h --help"

    if [[ "$cur" == * ]]; then
        mapfile -t COMPREPLY < <(compgen -W "$opts" -- "$cur")
        return 0
    fi
}

complete -F _tsuite_completions termux-suite tsuite
complete -F _apk_build_completions termux-apk-build apk-build
complete -F _wireless_adb_completions termux-wireless-adb wireless-adb tw-adb
