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
    if test $FORCE -lt 1 -a -r "$file$EXTENSION"; then
        warn "Refuse to overwrite existing signature file '$file$EXTENSION'."
        continue
    elif test $FORCE -lt 2 && [[ $file =~ $EXTENSION$ ]]; then
        warn "Refuse to create signature for signaure file '$file'."
        continue
    fi
    (
        gen_verify_script "$FILTER"
        cat -- "$file" |
        eval "$FILTER" |
        gpg --detach --armor --sign -
    ) >"$file$EXTENSION" &&
    chmod +x "$file$EXTENSION" &&
    true
done
