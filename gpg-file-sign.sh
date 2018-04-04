#!/usr/bin/env bash

set -o pipefail

EXTENSION=".asc"
FILTER='cat'
DEF_FILTER='sed "/^#/d"'


syntax() {
    cat <<EOF
SYNTAX: $0 [--help] [--filter [<cmd>]] [--force] [--] <file>...
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

sign_file() {
    local file="$1"
    local filter="$2"
    local signature_file="$3"
    local prefix_content="${4:-false}"
    local signature

    test -r "$file" ||
    error "Failed to read data file '$file'."
    signature="$(
        cat -- "$file" |
        eval "$filter" |
        gpg --detach --armor --sign -
    )" &&
    (
        $prefix_content &&
        cat
        echo "$signature"
    ) >>"$signature_file" &&
    true
}

verify_file() {
    local file="$1"
    local filter="$2"
    local signature_file="$3"
    local signature

    test -r "$file" ||
    error "Failed to read data file '$file'."
    signature="$(
        cat -- "$file" |
        eval "$filter"
    )" ||
    error "Failed to preprocess with '$filter'."
    echo "$signature" | gpg --verify "$signature_file" -
}

gen_verify_script() {
    local filter="$1"
    local extension="$2"

    cat <<END_OF_FILE
#!/usr/bin/env bash

FILTER='$filter'
set -o pipefail

usage() {
    cat <<EOF
Usage: \`basename "\$0"\` [--help|-h] [--append|-a]
Preprocesses corresponding file and verifies signature. Use '--append' to append
your own signature using the same preprocessing.
    Data file:    '\$DATA_FILE'
    Preprocessor: '\$FILTER'
EOF
}

`declare -pf error`

`declare -pf sign_file`

`declare -pf verify_file`

SIGNATURE_FILE="\$0"
DATA_FILE="\${SIGNATURE_FILE%$extension}"

case "\$1" in
    "--help"|"-h")
        usage
        exit 0
        ;;
    "--append"|"-a")
        sign_file "\$DATA_FILE" "\$FILTER" "\$SIGNATURE_FILE"
        ;;
    "")
        verify_file "\$DATA_FILE" "\$FILTER" "\$SIGNATURE_FILE"
        ;;
    *)
        error "Invalid argument '\$1'."
        ;;
esac
exit \$?

END_OF_FILE
}


FORCE=false
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
            FORCE=true
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
    if ! test -r "$file"; then
        error "Failed to read data file '$file'."
    elif ! $FORCE && [[ $file =~ $EXTENSION$ ]]; then
        warn "Refuse to create signature for file '$file'."
        continue
    elif ! $FORCE && test -r "$SIGNATURE_FILE"; then
        warn "Refuse to overwrite existing signature file '$SIGNATURE_FILE'."
        continue
    fi

    rm -f -- "$SIGNATURE_FILE" &&
    gen_verify_script "$FILTER" "$EXTENSION" |
    sign_file "$file" "$FILTER" "$SIGNATURE_FILE" true &&
    chmod +x -- "$SIGNATURE_FILE" &&
    true ||
    error "Failed to create signature for '$file'."
done
