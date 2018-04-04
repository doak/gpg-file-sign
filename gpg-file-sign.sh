#!/usr/bin/env bash

set -o pipefail

EXTENSION=".asc"
FILTER='cat'
DEF_FILTER='sed "/^#/d"'


syntax() {
    cat <<EOF
SYNTAX: $0 [--help] [--filter [<cmd>]] [--force]* [--] <file>...
    <cmd>:  Commands to filter to-be-verified/signed data.
            (String, defaults to '${DEF_FILTER[@]}'.)
    <file>: File to verify/sign.
EOF
}

error() {
    local errcode=$?
    echo "ERR: $*" >&2
    exit $errcode
}

warn() {
    local errcode=$?
    echo "WRN: $*" >&2
    return $errcode
}

gen_verify_script() {
    local filter="$1"

    cat <<EOF
#!/usr/bin/env bash

set -o pipefail

cat -- "\${0%$EXTENSION}" |
eval '$filter' |
gpg --verify "\$0" -
exit \$?

EOF
}


FORCE=0
while test -n "$1"; do
    case "$1" in
        "--help")
            syntax
            exit 0
            ;;
        "--filter")
            if [[ $2 =~ ^-- ]]; then
                FILTER="$DEF_FILTER"
            else
                FILTER="$2"
                shift
            fi
            ;;
        "--force")
            let FORCE++
            ;;
        "--")
            shift
            break
            ;;
        "--"*)
            error "Invalid option '$1'."
            ;;
        *)
            break
            ;;
    esac
    shift
done
test $# -ne 0 ||
error "Missing files."

for file in "$@"; do
    SIGNATURE_FILE="$file$EXTENSION"
    SKIP_VERIFY_SCRIPT=false
    if ! test -r "$file"; then
        error "Failed to read file '$file'."
    elif test $FORCE -lt 2 && [[ $file =~ $EXTENSION$ ]]; then
        warn "Refuse to create signature for file '$file'."
        continue
    elif test -r "$SIGNATURE_FILE"; then
        if test $FORCE -lt 1; then
            warn "Refuse to append to existing signature file '$SIGNATURE_FILE'."
            continue
        elif test $FORCE -ge 2; then
            rm -- "$SIGNATURE_FILE"
        else
            SKIP_VERIFY_SCRIPT=true
            PREVIOUS_FILTER="`grep -oP "^eval '\\K[^']+" -- "$SIGNATURE_FILE"`"
            if test -n "$PREVIOUS_FILTER" -a "$PREVIOUS_FILTER" != "$FILTER"; then
                warn "Refuse to append to existing signature file '$SIGNATURE_FILE' using a different filter: '$PREVIOUS_FILTER' != '$FILTER'."
                continue
            fi
        fi
    fi

    (
        $SKIP_VERIFY_SCRIPT ||
        gen_verify_script "$FILTER"
        cat -- "$file" |
        eval "$FILTER" |
        gpg --detach --armor --sign -
    ) >>"$SIGNATURE_FILE" &&
    chmod +x -- "$SIGNATURE_FILE" &&
    true || {
        rm -f "$SIGNATURE_FILE"
        error "Failed to create signature for '$file'."
    }
done
