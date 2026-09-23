# Repository history correction — 2026-09-23

The early development history, including the 0.1–0.4 releases, was previously
kept in a local archive rather than included in the public main branch. It has
now been restored as ancestry of the original public 0.9.16 snapshot. The two
README edits separating that snapshot from its historical parent are preserved.

Commits and annotated tags created with the old local identity
`tavi <claude@tavimedia.net>` have been corrected to
`VosjeCleo <VosjeCleo@proton.me>`. This corrects an obsolete repository setting;
it does not identify a separate contributor. Other identities, including the
GitHub committer on GitHub-created commits, are preserved.

## What changed

- Author/committer/tagger identity for the exact old placeholder above.
- Commit parent references and tag targets, as required by the new hashes.
- The previously squashed root now has its preserved historical merge as parent.
- One historical GitHub commit signature was removed because its parent changed;
  retaining it would falsely suggest that the rewritten commit was signed. The
  original signed object is retained in the maintainer's offline backup. The
  unchanged, signed initial GitHub commit is preserved as-is.

All rewritten commit trees and messages were verified against their originals.
Timestamps were preserved, and every release tag still names an identical source
tree. No release binaries were rebuilt or replaced, and no deployed application
or release-channel selection changed. Old CI records and embedded build hashes
refer to the original commit IDs, not the rewritten IDs.

## Existing clones

This is a non-fast-forward history migration. A fresh clone is the simplest
option. Before replacing a clone, save any uncommitted changes and local-only
commits. Do not merge the old main branch into the new one: doing so would
reintroduce the old history. Local branches and pinned commit IDs may need
explicit migration; contact the maintainer if you need the old-to-new mapping.

The maintainer retained verified Git bundles, an object/ref mapping, remote ref
snapshots and release metadata for rollback and traceability. Experimental
branches and stashes are not being published as new public feature work.
