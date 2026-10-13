# AutoCorrect 1.0 acceptance checklist

Updated October 12, 2026. Version numbers describe release readiness; changing the number alone does not close these gates. Current development build: 0.3.13. Public download: 0.3.7 preview, still unnotarized.

| Gate | Evidence needed before 1.0 | Current evidence / remaining work |
| --- | --- | --- |
| Contextual accuracy | Positive and negative regression fixtures; honor ignored words, replacements and deliberate rewrites | Coordinated invitations and multiple invitation modifiers now covered, including slow/fast engine sequences. Complex/ambiguous syntax intentionally abstains. |
| Broader English accuracy | Freeze a fresh independently labeled chat/prose set before tuning; compare the prior release on the same host; report correct repairs, misses, wrong replacements and valid-text changes separately | Existing Wikipedia evaluation is regression data, not fresh held-out evidence. Existing evaluation planning/artifacts are preserved. No broad accuracy percentage claimed for this patch. A second macOS version and independent sentence evaluation remain open. |
| Text integrity and interaction | Physical input in TextEdit, Notes, Codex/ChatGPT, Chrome and Safari; test next-word preservation, Undo, manual rewrite, focus changes, punctuation, Unicode and fast typing | Injected engine tests pass. Current physical typing and suggestion Apply/Undo are still unverified. Each editor needs its own observed result. |
| Distribution trust | Developer ID Application signature, hardened runtime, secure timestamp, Accepted notarization, valid stapled ticket and Gatekeeper on the final extracted ZIP | Developer ID Application certificate created with owner approval; separate 0.3.13 signed artifact verified. Notarization profile entry and Apple submission are pending. Scripts enforce checks and share version/output configuration. |
| Download/install/update | Download final asset in a browser on another Mac, keep quarantine intact, launch online and offline, grant permissions, update from the prior app, restart/login, uninstall | Pending signed public artifact. Keep the local development identity stable for now; verify permission migration when changing to Developer ID. |
| Supported systems and resources | Advertised minimum macOS, current macOS, Apple silicon and Intel; sustained idle/typing CPU, memory and correction latency | Universal compilation is available; it does not prove Intel runtime behavior or battery performance. Prior resource measurements are historical. |

## Short owner typing check

Use a new disposable document or an unsent composer. Complete each fixture with a space. Record the host app/version, build, host autocorrect setting, expected and observed text. The examples below are authored fixtures, not captured typing history.

- `Let's improve this and lets work ` → `Let's improve this and let's work `.
- `Let us check it but lets not change ` → `Let us check it but let's not change `.
- `She grabs the rope and lets go ` stays unchanged.
- `Let's see how she waits and lets go ` stays unchanged.
- `lets all just go ` → `Let's all just go ` in an empty text area with capitalization enabled.
- After a correction, immediately type `next ` and verify neither word disappears. Use AutoCorrect Undo, then deliberately retype the original spelling; it should respect that occurrence.
- Repeat `tex`, Backspace, `h `; `rightnow `; `We meet tuesday `; `Use claude `.
- In sentence suggestions, inspect a proposal, move the caret or change the text, and confirm stale Apply cannot overwrite the field. Test Apply and Undo on a fresh proposal.

## Signed release sequence

1. Create/import the Developer ID Application identity and store an authorized notarytool profile locally; [setup and preflight](NOTARIZATION.md).
2. Close the accuracy, real-typing and supported-system gates above. Record actual failures and scope any unsupported hosts honestly.
3. Run tests and release preflight. Build into a separate `DIST_DIR` with `VERSION=1.0.0` only when the gates are satisfied. Require Apple's Accepted result and final ZIP verification.
4. Validate that exact browser download on another Mac. Publish the verified artifact and update the cask/checksum together when release is authorized. Preserve development builds and rollback copies separately.
