# Development and verification

Use Windows x64 with the .NET 10 SDK. `global.json` selects .NET 10 and permits newer stable feature bands. `NuGet.Config` clears remote feeds because production and test projects use framework libraries only.

## Ordinary checks

```powershell
.\scripts\build.ps1 -Test
```

This publishes the desktop and service, then runs the core and WPF UI regression suites. UI checks use disposable prompts and injected observations; they do not use real PINs or production service state. They cover wrong/canceled PINs, independent access prompts, explicit shared/individual selection, leading zeroes and confirmation, fresh management authentication, repeated location openings, and observed-use/close timing. Test output reports the check counts for that build.

Build tests also extract and compile the production scripts' embedded C# in fresh Windows PowerShell 5.1 processes. This catches syntax that works in PowerShell 7 but is unsupported by the Windows installer host. The check parses scripts without executing installation, registry, service or native helper operations.

The GitHub Actions workflow runs these checks on Windows and creates the installer/source archives. It uses the maintained [checkout](https://github.com/actions/checkout), [setup-dotnet](https://github.com/actions/setup-dotnet) and [upload-artifact](https://github.com/actions/upload-artifact) actions. It is configured locally; a hosted run can be confirmed only after pushing the repository.

## Live Windows checks

Install the published package once to enable File System and Handle Manipulation failure auditing. From an ordinary, non-elevated Windows PowerShell window:

```powershell
.\scripts\test-native.ps1
.\scripts\verify-folder-shell.ps1
```

The native script asks Windows for permission to start a temporary SYSTEM test service. All content and broker state use a fresh disposable `tests/.work/native-<guid>` fixture. Production passcodes, recovery material and protected items are untouched. Tests retain their permission journals and results in that ignored directory. Inspect successful restoration before deleting a failed fixture.

The native suite checks actual normal-process access to original root/nested/empty folders, files and executables, failure-audit notifications, shared/individual PIN rejection and approval, relocking and exact permission restoration. It also exercises elevated Continue-equivalent permission grant denial and migration of old/Continue-modified permissions. The real Explorer Continue button is not automated; its permission-changing operation uses an actual elevated administrator token.

The 0.4.0 broker cases cover token-only access renewal/closure, missing and stale tokens, token rotation on fresh approval, Windows-session binding, wrong PINs on already-open locations, settings sign-out, and an actual 15-second lost-heartbeat expiry followed by denied normal-process folder listing and file reads. Atomic-save fixtures check same-account/same-volume file replacement during approved use. Identity regression checks reject an unrelated replacement's saved permissions. All fixtures retain exact restoration checks. Access-session tokens are not written to test reports.

`verify-folder-shell.ps1` checks installed default folder activation and quiet management-window behavior. Deterministic UI observation tests cover the two-second close stabilization and 10-second unidentified-viewer launch grace. Set `FILELOCK_TEST_EXPLORER=1` when running the UI suite on an interactive desktop to exercise an actual Explorer folder view and its closure. The test opens a disposable empty folder and closes only its own newly created window. These checks do not establish compatibility with every third-party viewer or Explorer tab implementation.

Local 0.4.0 validation passed 11 core groups, 64 UI checks (including the five optional Explorer checks), 72 live Windows checks, and two Windows PowerShell 5.1 C# compatibility checks. The live checks use only disposable fixtures. Hosted CI runs the 59 UI checks that do not require Explorer.

Version 0.4.1 adds authenticated repair of same-volume renamed or moved roots and safe removal of deleted or recycled locations. Recovery keeps passcodes and original permission journals, rejects replacement identities and reparse/critical paths, and closes old access sessions. Deleted-item removal verifies the mounted original volume, checks every saved object identity and restores surviving originals before removing the record; unavailable volumes and incomplete restoration retain the journal. UI regressions cover approval after a root rename and safe rebasing of nested requests without allowing sibling or parent-traversal escapes. The prior 0.4.0 counts above describe that earlier validation run; test output and the new delivery's validation record establish the checks completed for 0.4.1.

Local 0.4.1 validation passed 11 core groups, 67 UI checks (62 ordinary checks plus five live Explorer checks), 88 live Windows checks, and two Windows PowerShell 5.1 compatibility checks. Deleted-root cases include a surviving child moved independently, an unrelated replacement using the old name, and authenticated broker removal of the saved record. Retired NTFS IDs returning `ERROR_INVALID_PARAMETER` require complete MFT enumeration before removal treats them as absent; failed or partial verification retains the journal.

## Release

```powershell
.\scripts\release.ps1 -Test
```

This builds the app, compiles the Windows Forms Setup/Maintenance hosts with the built-in .NET Framework compiler, verifies the embedded package, then writes the installer and application/source ZIPs into `release`. It never publishes to GitHub or modifies Windows installation/state. Setup prerequisite and payload verification use read-only command modes documented in its source.

GUI installation performs the existing audited PowerShell installation under UAC. Only the installation helper is elevated; **Open FileLock** runs through the ordinary setup process. Installation adds Start menu links and an Installed apps entry. Maintenance shadow-copies itself before uninstall so Windows can remove its installed executable. Existing broker safety checks remain responsible for refusing uninstall while items are protected.

`src/FileLock.Setup/test-install.ps1` is an opt-in integration test that installs/upgrades the application and verifies Start menu/Installed apps registration. Its uninstall-refusal check always uses the script's `-VerifyOnly` mode, which cannot remove files or stop services even if protected-item counts change concurrently. It leaves existing passcodes and protected items intact.

`src/FileLock.Setup/test-uninstall.ps1` is a separate, opt-in **real removal** test. It refuses if protected items remain, runs the maintenance GUI operation, and verifies that the service, installation, shortcuts and Installed apps entry are removed while the encrypted account/recovery state remains intact. Run this only when you intend to uninstall. The maintenance GUI and its PowerShell child use temporary working directories so they cannot keep the installation directory open during deletion.

The requested 0.4.1 delivery is saved in a separate `FileLock-0.4.1` directory. Its `Application` subdirectory contains the runnable application package; the graphical installer and Windows/source archives are alongside it. Normal release-script output remains in `release` before delivery copying.

Release builds are unsigned and require .NET 10 Desktop Runtime x64. The runtime is not bundled. Reboot, different viewers, Explorer tabs, launcher handoffs and full multi-account uninstall should be tested on a disposable Windows machine before distributing a production release broadly. The project has no selected license.
