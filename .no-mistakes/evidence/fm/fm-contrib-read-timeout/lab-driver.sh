#!/usr/bin/env bash
# Hand-driven live lab for bin/fm-contributions.sh poll.
#
# Stands up a disposable FM_HOME holding one owned, already-observed GitHub PR
# plus a stub `gh` whose behaviour is chosen by $FORGE/fault, then runs the real
# poll CLI and reports exactly what an operator would see: the poll's stdout
# (the line that wakes the supervisor), the saved record's error field, and the
# durable wake queue.
#
# usage: lab-driver.sh <bin-dir> <fault> [extra-backlog-url]
set -u
BIN=$1
FAULT=$2
EXTRA_URL=${3:-}
NOW=2026-09-16T08:00:00Z
HEAD_A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-contrib-lab.XXXXXX") || exit 1
trap 'rm -rf -- "$LAB"' EXIT
H=$LAB/home
mkdir -p "$H/data/delivery" "$H/state" "$H/config" "$H/projects" "$H/fakebin" \
  "$H/forge" "$H/root/bin" "$H/wt"
printf '#!/bin/sh\nexit 1\n' > "$H/fakebin/tmux"
printf '#!/bin/sh\nexit 0\n' > "$H/fakebin/no-mistakes"
printf '#!/bin/sh\nexit 0\n' > "$H/root/bin/fm-guard.sh"
chmod +x "$H/fakebin/"* "$H/root/bin/fm-guard.sh"
printf 'worktree=%s/wt\nkind=ship\n' "$H" > "$H/state/delivery.meta"
chmod 600 "$H/state/delivery.meta"

# The operator's backlog: one owned ship contribution on a GitHub PR.
{
  printf '# Backlog\n\n## Queued\n'
  printf -- '- [ ] delivery - Contribution delivery https://github.com/o/r/pull/8 (repo: sample) (kind: ship)\n'
  [ -z "$EXTRA_URL" ] || printf -- '- [ ] unsupported - Filed %s (repo: sample) (kind: ship)\n' "$EXTRA_URL"
} > "$H/data/backlog.md"

# The record already on file: open, cleanly mergeable, head A, no error - the
# state the user reported the false wake against. Aged so a fresh observation
# is visible as a new checked_at.
jq -n --arg head "$HEAD_A" '
  {schema:"fm-contributions.v1",task:"delivery",records:[{
    url:"https://github.com/o/r/pull/8",kind:"pr",
    checked_at:"2026-09-15T08:00:00Z",error:null,pending:[],seen:[],verdict:null,
    observation:{head:$head,state:"open",draft:false,mergeable:"mergeable",
      review_decision:"APPROVED",can_merge:false,
      checks:[{name:"test",id:1,status:"completed",conclusion:"success",
               started_at:"2026-09-15T08:00:00Z"}],
      reviews:[],events:[]}}]}' > "$H/data/delivery/contributions.json"
cp "$H/data/delivery/contributions.json" "$LAB/prior.json"

printf '%s\n' "$FAULT" > "$H/forge/fault"
printf '%s\n' "$HEAD_A" > "$H/forge/head"

cat > "$H/fakebin/gh" <<'SH'
#!/usr/bin/env bash
# Stub GitHub client. $FORGE/fault picks how one of the six independent wave
# reads (the reviews read) ends; every other call answers normally.
set -eu
fault=$(cat "$FORGE/fault" 2>/dev/null || printf none)
printf '%s\n' "$*" >> "$FORGE/calls"
case "$fault:$*" in
  slow:'api repos/o/r/pulls/8/reviews?'*)  sleep 6 ;;                 # exceeds the 5s read cap
  sigkill:'api repos/o/r/pulls/8/reviews?'*) exit 137 ;;              # read SIGKILLed
  sigterm:'api repos/o/r/pulls/8/reviews?'*) exit 143 ;;              # read SIGTERMed
  sighup:'api repos/o/r/pulls/8/reviews?'*)  exit 129 ;;              # read SIGHUPed
  segv:'api repos/o/r/pulls/8/reviews?'*)    exit 139 ;;              # client crashed
  down:'api repos/o/r/pulls/8/reviews?'*)    printf 'HTTP 502\n' >&2; exit 1 ;;
  malformed:'api repos/o/r/pulls/8')        printf '{"state":"weird"}\n'; exit 0 ;;
esac
case "$*" in
  'pr view '*headRefOid,reviewDecision*)
    jq -n --arg head "$(cat "$FORGE/head")" '{headRefOid:$head,reviewDecision:"APPROVED"}' ;;
  'api repos/o/r/pulls/8')
    jq -n --arg head "$(cat "$FORGE/head")" '{state:"open",user:{login:"author"},
      head:{sha:$head},draft:false,mergeable:true,merged_at:null}'
    # A new commit landing mid-observation: the closing head read disagrees.
    [ "$fault" != headchange ] || printf 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n' > "$FORGE/head" ;;
  'api repos/o/r/issues/'*'/comments?'*) printf '[[]]\n' ;;
  'api repos/o/r/pulls/'*'/reviews?'*) printf '[[]]\n' ;;
  'api repos/o/r/pulls/'*'/comments?'*) printf '[[]]\n' ;;
  'api repos/o/r/commits/'*'/check-runs?'*)
    printf '[{"check_runs":[{"name":"test","id":1,"status":"completed","conclusion":"success","started_at":"2026-09-16T08:00:00Z"}]}]\n' ;;
  'api repos/o/r/commits/'*'/statuses?'*) printf '[[]]\n' ;;
  'api repos/o/r') printf '{"permissions":{"push":false}}\n' ;;
  *) printf 'unexpected gh call: %s\n' "$*" >&2; exit 1 ;;
esac
SH
chmod +x "$H/fakebin/gh"

printf '=== %s  fault=%s%s ===\n' "$BIN" "$FAULT" \
  "$([ -z "$EXTRA_URL" ] || printf '  extra=%s' "$EXTRA_URL")"
printf -- '--- timeout mechanism: %s\n' \
  "$(. "$BIN/fm-timeout-lib.sh"; fm_timeout_mechanism)"
out=$(PATH="$H/fakebin:$PATH" FORGE="$H/forge" \
  FM_HOME="$H" FM_ROOT_OVERRIDE="$H/root" FM_STATE_OVERRIDE="$H/state" \
  FM_DATA_OVERRIDE="$H/data" FM_CONFIG_OVERRIDE="$H/config" \
  FM_CONTRIBUTIONS_NOW="$NOW" FM_CONTRIBUTIONS_BUDGET=20 \
  "$BIN/fm-contributions.sh" poll 2>&1)
rc=$?
printf -- '--- poll exit status: %s\n' "$rc"
printf -- '--- supervisor-visible poll output: %s\n' \
  "$([ -n "$out" ] && printf '%s' "$out" || printf '(silent)')"
printf -- '--- durable wake queue: %s\n' \
  "$([ -s "$H/state/.wake-queue" ] && cat "$H/state/.wake-queue" || printf '(empty)')"
printf -- '--- delivery record checked_at/error: %s\n' \
  "$(jq -c '.records[0] | {checked_at,error}' "$H/data/delivery/contributions.json")"
if cmp -s "$LAB/prior.json" "$H/data/delivery/contributions.json"; then
  printf -- '--- delivery record: byte-identical to the prior record (untouched)\n'
else
  printf -- '--- delivery record: rewritten by this poll\n'
fi
if [ -n "$EXTRA_URL" ]; then
  if [ -e "$H/data/unsupported/contributions.json" ]; then
    printf -- '--- unsupported-forge record WRITTEN: %s\n' \
      "$(jq -c '.records[0] | {url,checked_at,error}' "$H/data/unsupported/contributions.json")"
  else
    printf -- '--- unsupported-forge record: none written\n'
  fi
  printf -- '--- unsupported forge read? %s\n' \
    "$(grep -c gitlab "$H/forge/calls" 2>/dev/null || printf 0)"
fi
printf '\n'
