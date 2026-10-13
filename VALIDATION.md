# FileLock 0.4.2 validation

- Release desktop/service: zero warnings/errors.
- Core regression groups: 11 passed.
- UI regression checks: 80 passed, including legacy-audit bursts, cancellation and repeat-prompt rejection, fresh explicit PIN openings, safe file/folder target selection, context-command quoting, and native viewer windows.
- Live Windows checks: 91 passed in an isolated SYSTEM service. Mixed-session background-denial bursts and retries beyond the former cooldown do not create challenges or change locked permissions; correct PINs and automatic relocking continue to work.
- Windows PowerShell 5.1 compatibility definitions: two passed.
- Setup package/safety checks: 14 passed.

Five optional Explorer-window ownership checks were inconclusive under the current shell reuse behavior and are excluded from the pass count. Tests never close a pre-existing user window. Viewer and Explorer-tab compatibility remains bounded as described in Application/docs/PROTECTION.md.

Source packages exclude protected runtime state, recovery material, diagnostics and generated test fixtures. Builds are unsigned and require .NET 10 Desktop Runtime x64.
## Installed upgrade

The real graphical Setup upgrade passed eight checks. Installed desktop and service versions are 0.4.2 and their binaries match the verified package. Existing account initialization and protected-item count were retained. An in-memory comparison against the private encrypted backup verified that master/individual passcode verifiers and recovery data are unchanged; credential material is not included in this delivery.

The updated background agent is running, and its owned Explorer file command is configured without replacing the default file verb. Actual protected content was not unlocked or removed during verification.