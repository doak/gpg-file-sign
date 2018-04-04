#!/usr/bin/env bash


EXTENSION=".asc"
FILTER='sed "/^#/d"'


syntax() {
    cat <<EOF
SYNTAX: $0 [--help|--filter <cmd>] [--force]... <file>...
    <cmd>:  Commands to filter to-be-verified/signed data.
            (String, defaults to '${FILTER[@]}'.)
    <file>: File to verify/sign.
EOF
}

error() {
    echo "ERR: $*" >&2
    exit 1
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
            if test $# -lt 2 || [[ $2 =~ ^-- ]]; then
                error "Missig argument for '$1'."
            fi
            FILTER="$2" &&
            shift 2
            test -n "$FILTER" ||
            FILTER="cat"
            ;;
        "--force")
            let FORCE++
            shift
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
done

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
    true
done
