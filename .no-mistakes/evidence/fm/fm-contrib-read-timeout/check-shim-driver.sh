#!/usr/bin/env bash
# The path the supervisor is actually woken from: fm-pr-check.sh registers the
# owned PR, which arms state/contributions.check.sh, and the watcher then runs
# that shim. Drive the shim itself and show what it hands the supervisor.
#
# (arm is the exact re-arm entry point fm-pr-check.sh and fm-bootstrap.sh call.)
#
# usage: check-shim-driver.sh <bin-dir> <fault>
set -u
BIN=$1
FAULT=$2
HEAD_A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-contrib-shim.XXXXXX") || exit 1
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
cp "$H/data/delivery/contributions.json" "$LAB/prior.json"
printf '%s\n' "$FAULT" > "$H/forge/fault"
printf '%s\n' "$HEAD_A" > "$H/forge/head"
cat > "$H/fakebin/gh" <<'SH'
#!/usr/bin/env bash
set -eu
fault=$(cat "$FORGE/fault" 2>/dev/null || printf none)
case "$fault:$*" in
  sigkill:'api repos/o/r/pulls/8/reviews?'*) exit 137 ;;
  down:'api repos/o/r/pulls/8/reviews?'*) printf 'HTTP 502\n' >&2; exit 1 ;;
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

env_run() {
  PATH="$H/fakebin:$PATH" FORGE="$H/forge" FM_HOME="$H" FM_ROOT_OVERRIDE="$H/root" \
    FM_STATE_OVERRIDE="$H/state" FM_DATA_OVERRIDE="$H/data" FM_CONFIG_OVERRIDE="$H/config" "$@"
}
printf '=== %s  fault=%s ===\n' "$BIN" "$FAULT"
env_run "$BIN/fm-contributions.sh" arm >/dev/null \
  || { printf -- '--- arm FAILED\n'; exit 1; }
printf -- '--- armed check shim present: %s\n' \
  "$([ -x "$H/state/contributions.check.sh" ] && printf yes || printf no)"
printf -- '--- registered checks: %s\n' "$(cd "$H/state" && echo *.check.sh)"
cp "$H/data/delivery/contributions.json" "$LAB/prior.json"
out=$(env_run bash "$H/state/contributions.check.sh" 2>&1); rc=$?
printf -- '--- check shim exit status: %s\n' "$rc"
printf -- '--- what the watcher surfaces to the supervisor: %s\n' \
  "$([ -n "$out" ] && printf '%s' "$out" || printf '(nothing - supervisor is not woken)')"
printf -- '--- record error after the check: %s\n' \
  "$(jq -c '.records[0].error' "$H/data/delivery/contributions.json")"
if cmp -s "$LAB/prior.json" "$H/data/delivery/contributions.json"; then
  printf -- '--- record: untouched by this check run\n'
else
  printf -- '--- record: rewritten by this check run\n'
fi
printf '\n'
