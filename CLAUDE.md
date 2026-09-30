# AutoCorrect: instructions for Claude

Read [docs/CLAUDE-HANDOFF.md](docs/CLAUDE-HANDOFF.md), then the latest entries in [docs/WORK-LOG.md](docs/WORK-LOG.md), before changing this project. The handoff contains the owner's request, project history, implementation map, known failures, verification boundaries, and release workflow. These instructions also apply when returning to the project after a context reset.

## Required continuity after every task

For **every user prompt and every completed fix or meaningful investigation**, append a dated entry to `docs/WORK-LOG.md` before ending your response. Include the request, findings, files changed, tests and their actual results, unresolved issues, GitHub/build/install/release status, and exact next steps. Log no-change investigations and blocked work too. Never record passwords, private keys, private messages, or captured user typing.

At the start of a substantial task, add an `IN PROGRESS` entry with its scope and starting commit. Finish that entry with the outcome and evidence; append a separate entry for the next task. Leave a checkpoint before a context reset or interruption whenever possible. Preserve completed historical entries; append corrections instead of silently rewriting past results.

Keep the `Current resume state` at the top of the work log current. Record source commits, installed version, and public release separately. A commit cannot contain its own final hash: use the starting/implementation hash and describe the accompanying documentation commit, then record later hashes in the next entry. Do not create endless logging-only commits to chase a self-reference.

The owner wants independent input and actual improvements to spelling accuracy, compatibility, reliability, responsiveness, and resource use. Make general, evidence-backed improvements, not just a growing list of patches for individual example words. Inspect the current implementation before accepting prior explanations. Preserve typed text, user overrides, privacy, and bounded resource use.

Keep GitHub current with validated, scoped source/documentation changes. Never commit secrets, raw typing traces, ignored build outputs, or unrelated local changes. Follow the handoff's release process; a source push is not an installed update or a published release. Do not call an unnotarized build stable or call a passing unit test an all-app compatibility pass.

Do not post or send anything to LinkedIn. Previous authorization was to prepare a draft only. Do not resume marketing work unless the user asks.
