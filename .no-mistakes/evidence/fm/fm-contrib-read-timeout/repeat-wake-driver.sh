#!/usr/bin/env bash
# The reported symptom shape: repeated false wakes across an afternoon on a PR
# that is open, cleanly mergeable and unchanged. One home, several polls, with a
# healthy poll in between so the failure episode cannot suppress the repeat.
#
# usage: repeat-wake-driver.sh <bin-dir>
set -u
BIN=$1
HEAD_A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-contrib-repeat.XXXXXX") || exit 1
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
{ printf '# Backlog\n\n## Queued\n'
  printf -- '- [ ] delivery - Contribution delivery https://github.com/o/r/pull/8 (repo: sample) (kind: ship)\n'
} > "$H/data/backlog.md"
jq -n --arg head "$HEAD_A" --arg at "$(date -u -v-2H +%Y-%m-%dT%H:%M:%SZ)" '
  {schema:"fm-contributions.v1",task:"delivery",records:[{
    url:"https://github.com/o/r/pull/8",kind:"pr",checked_at:$at,error:null,
    pending:[],seen:[],verdict:null,
    observation:{head:$head,state:"open",draft:false,mergeable:"mergeable",
      review_decision:"APPROVED",can_merge:false,
      checks:[{name:"test",id:1,status:"completed",conclusion:"success",started_at:$at}],
      reviews:[],events:[]}}]}' > "$H/data/delivery/contributions.json"
printf '%s\n' "$HEAD_A" > "$H/forge/head"
cat > "$H/fakebin/gh" <<'SH'
#!/usr/bin/env bash
set -eu
fault=$(cat "$FORGE/fault" 2>/dev/null || printf none)
case "$fault:$*" in
  sigkill:'api repos/o/r/pulls/8/reviews?'*) exit 137 ;;
esac
case "$*" in
  'pr view '*headRefOid,reviewDecision*)
    jq -n --arg head "$(cat "$FORGE/head")" '{headRefOid:$head,reviewDecision:"APPROVED"}' ;;
  'api repos/o/r/pulls/8')
    jq -n --arg head "$(cat "$FORGE/head")" '{state:"open",user:{login:"author"},
      head:{sha:$head},draft:false,mergeable:true,merged_at:null}' ;;
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
printf '=== %s ===\n' "$BIN"
false_wakes=0
i=0
for fault in sigkill none sigkill none sigkill sigkill; do
  i=$((i + 1))
  printf '%s\n' "$fault" > "$H/forge/fault"
  out=$(PATH="$H/fakebin:$PATH" FORGE="$H/forge" FM_HOME="$H" FM_ROOT_OVERRIDE="$H/root" \
    FM_STATE_OVERRIDE="$H/state" FM_DATA_OVERRIDE="$H/data" FM_CONFIG_OVERRIDE="$H/config" \
    FM_CONTRIBUTIONS_BUDGET=20 "$BIN/fm-contributions.sh" poll 2>&1)
  printf -- 'poll %s (read %s): %s\n' "$i" \
    "$([ "$fault" = sigkill ] && printf 'SIGKILLed' || printf 'answered normally')" \
    "$([ -n "$out" ] && printf '%s' "$out" || printf 'silent')"
  if [ "$fault" = sigkill ] && [ -n "$out" ]; then false_wakes=$((false_wakes + 1)); fi
done
printf -- '--- false supervision wakes raised on the open, mergeable, unchanged PR: %s\n' "$false_wakes"
printf -- '--- final record state: %s\n' \
  "$(jq -c '.records[0] | {error, state: .observation.state, mergeable: .observation.mergeable}' \
     "$H/data/delivery/contributions.json")"
printf '\n'
