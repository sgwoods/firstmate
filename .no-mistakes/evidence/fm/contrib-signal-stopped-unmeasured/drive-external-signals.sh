#!/usr/bin/env bash
# Drive `fm-contributions.sh poll` while an external process sends a real signal
# to the blocked forge read (the gh client alone, not the poll).
# Usage: drive-external-signals.sh <worktree> <script-root-label> <bin-dir>
WT=$1; LABEL=$2; BIN=$3
sed -n '1,1351p' "$WT/tests/fm-contributions.test.sh" | sed "s#\$(dirname \"\${BASH_SOURCE\[0\]}\")#$WT/tests#" > /tmp/fmc-helpers.$$.sh
cd "$WT"; . /tmp/fmc-helpers.$$.sh; rm -f /tmp/fmc-helpers.$$.sh
for sig in KILL TERM INT HUP SEGV; do
  home=$(new_home "ext-$LABEL-$sig"); forge_home "$home"; wrap_forge "$home"
  # Replace the fault handling for the reviews read: publish our pid then block.
  sed -i '' 's|^case "\$fault:\$\*" in$|case "$fault:$*" in\n  ext:'"'"'api repos/o/r/pulls/8/reviews?'"'"'*) echo $$ > "$FORGE/read.pid"; exec sleep 30 ;;|' "$home/fakebin/gh"
  mutate_record "$home" delivery '.records[0].checked_at="2026-09-15T08:00:00Z"'
  cp "$home/data/delivery/contributions.json" "$home/prior.json"
  echo ext > "$home/forge/fault"
  ( for _ in $(seq 100); do [ -s "$home/forge/read.pid" ] && break; /bin/sleep 0.05; done
    pid=$(cat "$home/forge/read.pid"); /bin/sleep 0.3; kill -s $sig "$pid" ) &
  killer=$!
  out=$(with_home "$home" env FM_CONTRIBUTIONS_BUDGET=20 "$BIN/fm-contributions.sh" poll); rc=$?
  wait $killer
  if cmp -s "$home/prior.json" "$home/data/delivery/contributions.json"; then rec=unchanged; else rec=$(jq -c '{checked_at:.records[0].checked_at,error:.records[0].error}' "$home/data/delivery/contributions.json"); fi
  wq=$([ -s "$home/state/.wake-queue" ] && echo yes || echo no)
  printf '[%s] SIG%-4s poll_rc=%s stdout=%q record=%s wake_queued=%s\n' "$LABEL" "$sig" "$rc" "$out" "$rec" "$wq"
done
