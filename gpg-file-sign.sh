#!/usr/bin/env bash

set -o pipefail

EXTENSION=".asc"
FILTER='cat'
DEF_FILTER='sed "/^#/d"'


usage() {
    local scriptname="`basename "$0"`"

    cat <<EOF
Usage: 1) $scriptname [--help|-h] [--filter [<cmd>]] [--force] [--] <file>...
       2) $scriptname --update-script <file>...
    <cmd>:  Commands to filter to-be-verified/signed data.
            (String, defaults to '${DEF_FILTER[@]}'.)
    <file>: 1) File to verify/sign.
            2) Signature script to update.

    1) Create script which is able to verify <file>. The script includes
       signature(s) and <filter> configuration. <file> will be preprocessed
       by <filter> before signing/veryifing.
    2) Update script part, but do not touch <filter> and signature(s).
EOF
}

echox() {
    local errcode=$?
    echo "$*" >&2
    exit $errcode
}

error() {
    echox "ERR: $*"
}

warn() {
    echox "WRN: $*"
}

sign_file() {
    local file="$1"
    local filter="$2"

    test -r "$file" ||
    error "Failed to access data file '$file'."
    cat -- "$file" |
    eval "$filter" |
    gpg --detach --armor --sign - &&
    true ||
    error "Failed to create signature."
}

gen_verify_script() {
    local filter="$1"
    local extension="$2"

    cat <<END_OF_FILE
#!/usr/bin/env bash

FILTER='$filter'

set -o pipefail
SIGNATURE_SCRIPT="\$0"
DATA_FILE="\${SIGNATURE_SCRIPT%$extension}"


usage() {
    cat <<EOF
Usage: \`basename "\$0"\` [--help|-h] [--append|-a]
Preprocesses corresponding file and verifies signature. Use '--append' to append
your own signature using the same preprocessing.
    Data file:    '\$DATA_FILE'
    Preprocessor: '\$FILTER'
EOF
}

error() {
    local errcode=\$?
    echo "ERR: \$*" 1>&2
    exit \$errcode
}


case "\$1" in
    "--help"|"-h")
        usage
        exit 0
        ;;
    "--append"|"-a")
        test -r "\$DATA_FILE" ||
        error "Failed to access data file '\$DATA_FILE'."
        cat -- "\$DATA_FILE" |
        eval "\$FILTER" |
        gpg --detach --armor --sign - >>"\$SIGNATURE_SCRIPT" ||
        error "Failed to append signature."
        ;;
    "")
        test -r "\$DATA_FILE" ||
        error "Failed to read data file '\$DATA_FILE'."
        cat -- "\$DATA_FILE" |
        eval "\$FILTER" |
        gpg --verify "\$SIGNATURE_SCRIPT" - ||
        error "There are INVALID signatures."
        ;;
    *)
        error "Invalid argument '\$1'."
        ;;
esac
exit \$?

END_OF_FILE
}

update_script() {
    local script="$1"
    local extension="$2"
    local tmp="`mktemp`"

    local filter="`grep -oP "^FILTER='\\K[^']+" -- "$script"`" ||
    error "Failed to get previous filter from '$script'."
    (
        gen_verify_script "$filter" "$extension"
        sed -n '/^-----BEGIN PGP SIGNATURE-----$/,$p' -- "$script"
    ) >"$tmp" &&
    mv -- "$tmp" "$script" &&
    chmod +x -- "$script" &&
    true
}


FORCE=false
UPDATE=false
while test -n "$1"; do
    case "$1" in
        "--help"|"-h")
            usage
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
        "--update-script")
            UPDATE=true
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
    SIGNATURE_SCRIPT="$file$EXTENSION"

    if ! test -r "$file"; then
        error "Failed to read file '$file'."
    elif $UPDATE; then
        update_script "$file" "$EXTENSION" ||
        error "Failed to update script of signature script '$file'."
        continue
    elif ! $FORCE && [[ $file =~ $EXTENSION$ ]]; then
        warn "Refuse to create signature script for file '$file'."
        continue
    elif ! $FORCE && test -r "$SIGNATURE_SCRIPT"; then
        warn "Refuse to overwrite existing signature script '$SIGNATURE_SCRIPT'."
        continue
    fi

    rm -f -- "$SIGNATURE_SCRIPT" && {
        gen_verify_script "$FILTER" "$EXTENSION" &&
        sign_file "$file" "$FILTER" &&
        true
    } >"$SIGNATURE_SCRIPT" &&
    chmod +x -- "$SIGNATURE_SCRIPT" &&
    true ||
    error "Failed to create signature script for '$file'."
done
