#!/usr/bin/env bash
mode=$(cat "$FM_HOME/mode" 2>/dev/null || echo none)
printf '%s\t%s\n' "$mode" "$*" >> "$FM_HOME/gh-calls.log"
case "$*" in
  'api repos/'*'/pulls/'*'/reviews?'*)
    case $mode in
      term) kill -TERM $$ ;; kill) kill -KILL $$ ;; int) exec perl -e '$SIG{INT}="DEFAULT"; kill "INT", $$; sleep 2' ;; hup) kill -HUP $$ ;;
      segv) kill -SEGV $$ ;; slow) sleep 7 ;; fail) printf 'HTTP 502: Bad Gateway\n' >&2; exit 1 ;;
    esac ;;
esac
exec /opt/homebrew/bin/gh "$@"
