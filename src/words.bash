#!/usr/bin/env bash
# pass words - Password Store Extension (https://www.passwordstore.org/)
# Copyright (C) 2020 Michael Meyer <me@entrez.cc>
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

VERSION="0.0.6"

WORD_COUNT="${PASSWORD_STORE_WORD_COUNT:-7}"
DEFAULT_WORD_LIST="${SYSTEM_EXTENSION_DIR}/words.wordlist.txt"
DEFAULT_WORD_LIST_SOURCE="https://www.eff.org/files/2016/07/18/eff_large_wordlist.txt"
WORD_LIST="${PASSWORD_STORE_WORD_LIST:-$DEFAULT_WORD_LIST}"
DEFAULT_SEPARATOR="${PASSWORD_STORE_DEFAULT_SEPARATOR}"

cmd_words_usage() {
    cat <<-_EOF
Usage:
    $PROGRAM $COMMAND [generate] [-w file,--wordlist=file] [-s sep,--seperator=sep]
            [--clip,-c] [--in-place,-i | --force,-f] pass-name [word-count]
        Generate a new password of word-count words ($WORD_COUNT if not specified)
        using the specified diceware-style formatted wordlist (by default,
        $WORD_LIST).
        Inter-word separator defaults to '$DEFAULT_SEPARATOR'$(_character_name "$DEFAULT_SEPARATOR").
        Prompt before overwriting existing password unless forced.
        Optionally replace only the first line of an existing file with a new
        password.

        The variable PASSWORD_STORE_WORD_LIST can be used to set the default
        wordlist file location; likewise, PASSWORD_STORE_DEFAULT_SEPARATOR and
        PASSWORD_STORE_WORD_COUNT can be used to define the default separator
        and word count, respectively.
_EOF
  exit 0
}

_character_name() {
    local name
    if [ -z "$1" ]; then
        name='no separator'
    else
        case $1 in
            \ ) name='space' ;;
            \.) name='period' ;;
            ,) name='comma' ;;
            -) name='hyphen' ;;
            _) name='underscore' ;;
            =) name='equals sign' ;;
            \*) name='asterisk' ;;
            /) name='slash' ;;
            \#) name='octothorpe' ;;
            \;) name='semicolon' ;;
            :) name='colon' ;;
            \\) name='backslash' ;;
            \~) name='tilde' ;;
            \`) name='backtick' ;;
            ^) name='carat' ;;
            %) name='percent sign' ;;
            @) name='at sign' ;;
            !) name='exclamation point' ;;
            \&) name='ampersand' ;;
        esac
    fi
    [ -n "$name" ] && printf ' (%s)' "$name"
}

cmd_words_generate() {
    local opts qrcode=0 clip=0 force=0 inplace=0 separator="$DEFAULT_SEPARATOR" wordlist="$WORD_LIST" pass currword
    opts="$($GETOPT -o w:s:qcif -l wordlist:,separator:,qrcode,clip,in-place,force -n "$PROGRAM" -- "$@")"
    local err=$?
    eval set -- "$opts"
    while true; do case $1 in
        -s|--separator) if [ -n "$2" ] && [ "$2" != "--" ]; then separator="$2"; shift; shift; else err=1; break; fi ;;
        -w|--wordlist) if [ -n "$2" ] && [ "$2" != "--" ]; then wordlist="$2"; shift; shift; else err=1; break; fi ;;
        -q|--qrcode) qrcode=1; shift ;;
        -c|--clip) clip=1; shift ;;
        -f|--force) force=1; shift ;;
        -i|--in-place) inplace=1; shift ;;
        --) shift; break ;;
    esac done

    [[ $err -ne 0 || ( $# -ne 2 && $# -ne 1 ) || ( $force -eq 1 && $inplace -eq 1 ) || ( $qrcode -eq 1 && $clip -eq 1 ) ]] \
        && die "Usage: $PROGRAM $COMMAND [generate] [-w file,--wordlist=file] [-s sep,--separator=sep] [--clip,-c] [--in-place,-i | --force,-f] pass-name [word-count]"

    local path="$1"
    local length="${2:-$WORD_COUNT}"
    check_sneaky_paths "$path"
    [[ $length =~ ^[0-9]+$ ]] || die "Error: word-count \"$length\" must be a number."
    [[ $length -gt 0 ]] || die "Error: word-count must be greater than zero."
    if [[ ! -e "$wordlist" ]]; then
        [[ "$wordlist" == "$DEFAULT_WORD_LIST" ]] || die "Error: wordlist file \"$wordlist\" does not exist."
        if yesno "Default wordlist file does not exist; download it now?"; then
            CURL="$(which 2>/dev/null curl)" || die "Error: curl is not installed."$'\n'"The default word list can be downloaded from <${DEFAULT_WORD_LIST_SOURCE}>."
            if ! ($CURL --create-dirs -\# -fo "$wordlist" "$DEFAULT_WORD_LIST_SOURCE" && [ -e "$wordlist" ]); then
                die "Error: could not download wordlist file."
            fi
        fi
    fi
    mkdir -p -v "$PREFIX/$(dirname -- "$path")"
    set_gpg_recipients "$(dirname -- "$path")"
    local passfile="$PREFIX/$path.gpg"
    set_git "$passfile"

    [[ $inplace -eq 0 && $force -eq 0 && -e "$passfile" ]] && yesno "An entry already exists for $path. Overwrite it?"

    local -i wlistsize lineno
    wlistsize="$(wc -l "${wordlist}" | awk '{ print $1 }')"
    for ((i=0;i<length;i++)); do
        lineno="$(($(od -vAn -N2 -tu2 < /dev/urandom) % wlistsize))"
        currword="$(sed "${lineno}q;d" "$wordlist" | awk '{ print $2 }')"
        pass+="${currword}${separator}"
    done
    [[ $i -eq $length ]] || die "Could not generate password from /dev/urandom"
    pass="${pass%%$separator}"

    if [[ $inplace -eq 0 ]]; then
        echo "$pass" | $GPG -e "${GPG_RECIPIENT_ARGS[@]}" -o "$passfile" "${GPG_OPTS[@]}" || die "Password encryption aborted."
    else
        local passfile_temp="${passfile}.tmp.${RANDOM}.${RANDOM}.${RANDOM}.${RANDOM}.--"
        if { echo "$pass"; $GPG -d "${GPG_OPTS[@]}" "$passfile" | tail -n +2; } | $GPG -e "${GPG_RECIPIENT_ARGS[@]}" -o "$passfile_temp" "${GPG_OPTS[@]}"; then
            mv "$passfile_temp" "$passfile"
        else
            rm -f "$passfile_temp"
            die "Could not reencrypt new password."
        fi
    fi
    local verb="Add"
    [[ $inplace -eq 1 ]] && verb="Replace"
    git_add_file "$passfile" "$verb generated password for ${path}."

    if [[ $clip -eq 1 ]]; then
        clip "$pass" "$path"
    elif [[ $qrcode -eq 1 ]]; then
        qrcode "$pass" "$path"
    else
        printf "\e[1mThe generated password for \e[4m%s\e[24m is:\e[0m\n\e[1m\e[93m%s\e[0m\n" "$path" "$pass"
    fi
}

cmd_words_version() {
    echo $VERSION
    exit 0
}
    

case "$1" in
    help|--help|-h) shift;    cmd_words_usage "$@" ;;
    version|--version) shift; cmd_words_version "$@" ;;
    generate) shift;          cmd_words_generate "$@" ;;
    *)                        cmd_words_generate "$@" ;;
esac
exit 0
  
# vim:et:sw=4:ts=4:sts=4:sr:
