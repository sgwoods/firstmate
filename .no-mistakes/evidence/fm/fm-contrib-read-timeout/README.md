# Live validation: a bounded-out contribution read stays unmeasured

Branch `fm/fm-contrib-read-timeout` — base `1f3e769`, target `a9bcf7c`.

Everything below was driven against the real `bin/fm-contributions.sh` CLI in a
disposable `FM_HOME` created under `$TMPDIR` and removed in the same turn. The
only stand-in is `gh` itself: the forge client is replaced by a stub whose
failure mode is selected per run, because a real GitHub read cannot be made to
exceed its five-second cap or to die by SIGKILL on demand. Every other component
— the snapshot read, the poll's budget and reserve arithmetic, `fm-timeout-lib`
(mechanism `perl` on this host), the record writer, the `arm`-generated check
shim, and the wake path — is the shipped code.

## What an operator sees

| forge read ends as | before the fix (`1f3e769`) | after the fix (`a9bcf7c`) |
| --- | --- | --- |
| slow, killed at the 5s cap (124) | silent, record untouched | silent, record untouched |
| SIGKILLed (137) | **`contributions: observation unavailable for …` + error recorded** | silent, record untouched |
| SIGTERMed (143) | **false wake + error recorded** | silent, record untouched |
| SIGHUPed (129) | **false wake + error recorded** | silent, record untouched |
| client crash, SIGSEGV (139) | wake + error recorded | wake + error recorded |
| forge down, HTTP 502 | wake + error recorded | wake + error recorded |
| malformed core response | wake + error recorded | wake + error recorded |
| head changed mid-observation | wake + error recorded | wake + error recorded |
| URL on an unsupported forge | **false wake + error record written for a URL never read** | silent, no record, never read |

The bottom four rows are the adversarial half: the fix must not buy silence by
swallowing real evidence, and it does not.

## Files

- `poll-before-fix.txt`, `poll-after-fix.txt` — `fm-contributions.sh poll`
  transcripts for every fault mode, showing the supervisor-visible line, the
  saved record's `checked_at`/`error`, and whether the prior record survived
  byte-for-byte.
- `check-shim-wake-path.txt` — the same comparison through the path the
  supervisor is actually woken from: `arm` writes `state/contributions.check.sh`
  (the re-arm entry point `fm-pr-check.sh` and `fm-bootstrap.sh` call), then that
  shim runs. Before the fix it hands the supervisor a false unavailable line on
  an open, cleanly mergeable, unchanged PR; after the fix it hands nothing, while
  a genuine 502 still surfaces.
- `repeat-false-wake.txt` — the reported symptom shape: six polls on one healthy
  PR with healthy polls interleaved so the failure episode cannot mask the
  repeat. Base raises 3 false wakes and leaves the record carrying an error;
  target raises 0 and leaves `error: null` with the complete observation intact.
- `help-read-outcome-contract.txt` — the rendered `fm-contributions.sh --help`,
  which is where `usage()` publishes the header. Every claim in it matches the
  measured behaviour above, the bound-status enumeration appears exactly once
  (the one-owner collapse), and no removed knob is advertised.
- `new-tests-fail-on-base.txt` — the change's two new tests run against the base
  script: both fail there and both pass on the target, so they are regressions,
  not restatements.
- `fm-contributions-test.txt` — the colocated suite, 48 ok, exit 0.
- `lab-driver.sh`, `check-shim-driver.sh`, `repeat-wake-driver.sh` — the drivers,
  reproducible as `./lab-driver.sh <bin-dir> <fault> [extra-url]`.
