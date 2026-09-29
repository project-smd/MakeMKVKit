# Specifications

This directory holds the behavioural specification of this package: what the code does today,
stated as requirements with scenarios, each pinned to the test that measures it. It follows the
[OpenSpec](https://github.com/Fission-AI/OpenSpec) layout, one capability per
`specs/<capability>/spec.md`, so the OpenSpec tooling validates it unchanged:

```sh
npx -y @fission-ai/openspec@1.13.2 validate --all --strict
python3 Scripts/spec-pins-gate.py
python3 Scripts/spec-deltas-gate.py
```

The second command checks that every path a spec pins to exists, and that every test it names
occurs in the file named. The third applies every proposed change to a scratch copy of the specs
and fails if one does not apply. CI runs all three in the `Specifications` job.

The README says how to use this package and records what was measured about MakeMKV's output and
protocol. A spec says what the code does now, and where the two disagree the spec is the checked
claim.

Two lines are added to the OpenSpec shape. Each spec's Purpose is followed by a `Documentation:`
link to what covers the capability. Each requirement ends with `Pinned by:` naming the test that
measures it; `Pinned by: nothing yet.` marks a claim that is true of the source but not yet under
test. Where the code does something that is a defect rather than a decision, the requirement
states what it does and links the issue that tracks the fix.

Two kinds of pin need saying. `CorpusTests` runs only when `MAKEMKVKIT_THEDISCDB_DATA` names a
clone of TheDiscDb's data repository, so CI skips it and a requirement pinned to it is measured
only by a run that supplies one. Anything that needs `makemkvcon` and a disc in a drive — the
driver's process handling and the engine session — has no automated test; the README says it is
exercised by hand, and its requirements are `Pinned by: nothing yet.`

Specs change through proposals, using OpenSpec's own change layout. A change that alters behaviour
carries its argument in a proposal document and its spec deltas in `openspec/changes/<change-name>/`;
[changes/README.md](changes/README.md) describes the shape. The implementing pull request applies
the deltas with `openspec archive`, which updates `specs/` and moves the change into
`changes/archive/`. A bug fix that changes a recorded requirement edits the spec in the same pull
request. The tracking issue owns the status of a change, not any file in this directory.
