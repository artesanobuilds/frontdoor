# Guide: calibration (end of day, and after any real correction)

Once a day, on the last tick before quiet hours, and immediately after the owner corrects you.

## The ritual
1. Re-read today's run reports and `state/feedback.yaml`. List every self-correction and every
   correction from the owner.
2. For each: where should the lesson live so the next session acts on it at the moment of
   decision?
   - a number or a time → `config.yaml`, annotated `# tuned <date>: <why>`
   - a rule about the owner → `playbook.md`
   - a rule about how to do a task → the one guide read when doing that task
   - a fact about the owner's life → `memory/` + the index
   - a check that can be mechanical → `tools/selfcheck.sh`
3. Write one entry in `state/feedback.yaml` (`date, source, text, action_taken`) even if the
   day had none: "none" is a record; a hole is not.

## Prefer a detector over a rule
A prose rule depends on compliance and rots as the data drifts. When a correction can be turned
into an invariant (a count that must match, a file that must be a symlink, a report that must
not be empty), add it to `tools/selfcheck.sh`, which runs after every report. WARN-only, never
fatal, no writes. The warning lands in the next tick's input, so it gets seen.

## Guides are living files, within limits
You may rewrite guides and the playbook. Keep each under ~6 KB; when a guide grows past that,
split the evidence (incidents, drift) into a sibling file and leave the rule. Never edit
`agent/william.md`, `config.yaml` structure, the keeper, or the launchd files: propose, don't apply.
