#!/usr/bin/env bash
# drive.sh <root> <mode> : run a real poll in the lab home with the gh wrapper in <mode>
LAB=$(dirname "$0"); root=$1; mode=$2
printf '%s\n' "$mode" > "$LAB/mode"
: > "$LAB/gh-calls.log"; rm -f "$LAB/state/.wake-queue"
rec=$LAB/data/live-pr/contributions.json
cp "$LAB/stale-record.json" "$rec"
before=$( [ -f "$rec" ] && shasum "$rec" | cut -c1-12 || echo none)
out=$(env -u NO_MISTAKES_GATE -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE \
  PATH="$LAB/bin:$PATH" FM_HOME="$LAB" "$root/bin/fm-contributions.sh" poll 2>&1); rc=$?
after=$( [ -f "$rec" ] && shasum "$rec" | cut -c1-12 || echo none)
echo "== root=$(basename "$root") mode=$mode"
echo "poll rc=$rc stdout/stderr: ${out:-<empty>}"
echo "record changed: $([ "$before" = "$after" ] && echo no || echo yes)"
[ -f "$rec" ] && jq -c '.records[] | {url,checked_at,error,state:.observation.state,mergeable:.observation.mergeable,head:(.observation.head // "" | .[0:12])}' "$rec"
echo "wake-queue: $(cat "$LAB/state/.wake-queue" 2>/dev/null || echo '<none>')"
echo "gh reads: $(wc -l < "$LAB/gh-calls.log" | tr -d ' ')$(grep -c reviews "$LAB/gh-calls.log" | sed 's/^/ (reviews reads: /;s/$/)/')"
