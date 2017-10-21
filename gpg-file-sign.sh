#!/usr/bin/env bash


FILE="${0%.asc}"
PIPE='sed "/^#/d" "$FILE"'  # Will be set by '--pipe'.
GPG_MARK='^-----BEGIN PGP SIGNATURE-----$'


syntax() {
    cat <<EOF
SYNTAX: $0 [--help|--sign|--pipe <cmd>] [<file>]
    <cmd>:  Commands to filter to-be-verified/signed data. File name is passed in '\$FILE'.
            (String, currently defaults to '${PIPE[@]}'.)
    <file>: File to verify/sign. Defaults to script name with extension '.asc' removed.  Use '-' for stdin.
            (String, currently defaults to '$FILE'.)
EOF
}

error() {
    echo "ERR: $*" >&2
    exit 1
}

manipulate() {
    sed -i "$@" -- "$0"
}


SIGN=false
while test -n "$1"; do
    case "$1" in
        "--help")
            syntax
            exit 0
            ;;
        "--sign")
            SIGN=true
            shift
            ;;
        "--pipe")
            test -n "$2" ||
            error "Missig argument for '$1'."
            PIPE="$2" &&
            manipulate "s!^PIPE=.*\(#[^#]\\+\$\)!PIPE='$PIPE'  \\1!" &&
            shift 2
            ;;
        "--")
            shift
            break
            ;;
        "--"*)
            error "Invalid option '$1'."
            ;;
        *)
            break;
    esac
done

test -n "$1" &&
FILE="$1"

test "$FILE" != "$0" ||
error "Refuse to process script '$0' itself."

eval "$PIPE" |
if $SIGN; then
    manipulate "/$GPG_MARK/,\$d" &&
    gpg --detach --armor --sign - >>"$0"
else
    grep "$GPG_MARK" >/dev/null "$0" ||
    error "No signature had been created for file '$FILE'."
    gpg --verify "$0" -
fi
exit $?

