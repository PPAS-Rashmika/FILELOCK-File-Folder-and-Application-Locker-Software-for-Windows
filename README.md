# FileLock

Six-digit passcode protection for files, folders and portable application executables on Windows, at their original locations.

FileLock combines a Windows desktop interface with a background permission service. Opening a protected folder through its default Explorer action shows the passcode dialog while the management window stays hidden. Supported items lock again when their observed use ends.

**Version:** 0.4.1 · **Platform:** Windows x64 · **Built with:** C#, .NET 10 and WPF

FileLock uses NTFS permissions. Protected content remains unencrypted, and other permitted programs can read it during an approved use. Read [Protection boundaries](docs/PROTECTION.md) for supported behavior and limitations.

## Features

- Protect personal files, folders and portable `.exe` applications at their existing paths.
- Use one **shared master passcode**, or a **separate six-digit passcode** for each item.
- Require a fresh master passcode when opening the FileLock management window.
- Ask for the item passcode on each FileLock-mediated opening, including the protected folder's default Explorer action.
- Relock after the last supported folder or viewer window closes, or an observed application exits.
- Recover a forgotten master passcode with a saved recovery key.
- Repair same-volume renamed or moved items using their saved identities.
- Safely clear deleted-item records after verifying deletion and restoring surviving originals' permissions.
- Install and uninstall through graphical Setup and Windows **Installed apps**.

## Requirements

| Requirement | Details |
| --- | --- |
| Operating system | 64-bit Windows |
| Runtime | [.NET 10 Desktop Runtime, x64](https://dotnet.microsoft.com/en-us/download/dotnet/10.0) |
| Storage | Local, fixed NTFS drives |
| Installation | Windows administrator approval to install the service |
| Building from source | .NET 10 SDK on Windows x64 |

The runtime is not bundled. Setup checks for it before installation. Current builds are unsigned.

## Install

Use `FileLock-0.4.1-Setup.exe` from a published release or a local build. Packaged downloads belong on the repository's **Releases** page.

1. Open Setup and select **Install**.
2. Approve the Windows administrator prompt.
3. Select **Open FileLock**, or open FileLock from the Start menu.
4. On first use, create a six-digit master passcode and save the recovery key.
5. Select **Protect a location** and choose a file, folder or portable executable.
6. Explicitly choose **Shared master passcode** or **Separate passcode for this location**. Enter a separate passcode twice to confirm it.

For the ZIP distribution, extract `FileLock-0.4.1-Windows.zip` and run `install.cmd`.

Install matching desktop and service versions through Setup when upgrading. Existing passcodes and recovery data are preserved. Setup installs into `C:\Program Files\FileLock`, registers the application in Windows **Installed apps**, and enables Windows failure auditing for denied-access prompts.

## Use FileLock

### Open and lock items

Double-click the original protected folder, or select an item in FileLock and choose **Unlock & open**. Enter that item's six-digit passcode. An individual item requires its own passcode; the master passcode does not replace it. Wrong passcodes and **Cancel** do not open another view or create a new access grant.

Keep FileLock running in the notification area for prompts and close detection. Close all observed Explorer views of a protected folder, including its subfolders, or close the supported document/application window to relock. Window closure normally settles for two seconds before relocking. Use **Manage → Lock now** to end access immediately.

If the background agent stops sending access heartbeats, the service relocks after its 15-second deadline. Unidentified document viewers receive a 10-second launch grace. Close detection depends on the viewer and Explorer view; some tabs, window titles and application launchers cannot be tracked reliably.

Adding a folder enables its Explorer prompt integration and starts the background agent at sign-in. This setting can be disabled in **Security & recovery**. Other Explorer navigation routes and programs may show Windows **Access denied** before FileLock displays a prompt.

### Change or recover passcodes

| Task | Action |
| --- | --- |
| Change an item's shared or individual passcode | **Manage → Change this passcode…** |
| Reset a forgotten item passcode | Sign in with the master passcode, then use **Manage → Reset a forgotten passcode…** |
| Recover the master passcode | Select **Forgot your passcode?** at the opening prompt and use the saved recovery key |

Master recovery issues a replacement recovery key. Save it; the previous key will no longer work.

If an earlier version saved an item as shared, use **Change this passcode…**, enter its current master passcode, and choose **Separate passcode for this location** to assign an individual PIN. Leading zeroes are supported.

## Troubleshooting

| Situation | What to do |
| --- | --- |
| A renamed or moved item shows **Needs attention** | Select **Manage → Repair moved location…**. If discovery fails, select the same original item at its current location on the same drive. |
| A deleted item shows **Could not find file** | Install 0.4.1 or newer, select the item, and choose **Manage → Remove protection…**. FileLock verifies its identities, restores surviving originals' permissions, and clears the old record. It does not recreate the deleted folder. |
| The item is in the Recycle Bin | Use **Remove protection…**, or restore it from the Recycle Bin before repairing its location. |
| The original drive is unavailable | Reconnect it before retrying. The recovery journal is retained until verification and restoration succeed. |
| The service is unavailable or versions do not match | Run the matching Setup application to install or repair the desktop and service. |

Repair cannot substitute an unrelated folder, a similarly named file or a copy on another volume for the original item. Repair and removal keep any remaining content.

## Uninstall

1. Remove protection from every item in every Windows account using FileLock.
2. Open Windows **Installed apps**, or select **Uninstall FileLock** in the Start menu.
3. Complete the uninstall operation.

Uninstall refuses while protected items remain. Account and recovery data is retained for reinstall. For deleted items, clear their records using **Remove protection…** first.

## Protection limits

- Original Windows permissions apply during approved use, so other permitted accounts and programs can also access the location. FileLock does not intercept every filesystem read.
- Existing file handles, mapped files and running applications may retain access after relocking.
- A Windows administrator can deliberately take ownership or use recovery privileges. SYSTEM and offline disk access are outside this protection boundary.
- Protecting an executable does not stop an existing process or protect another copy.
- System locations, profile/AppData roots, network or removable storage, reparse points, cloud placeholders, junctions, symlinks, hardlinked files and overlapping protected locations are rejected.
- Protected folders support up to 10,000 entries.
- If the permission service itself stops during approved use, restored permissions can remain until it restarts.

Keep a separate backup and close programs already using an item before protecting it. See [Protection boundaries](docs/PROTECTION.md) for details.

## Build from source

Install the Windows x64 [.NET 10 SDK](https://dotnet.microsoft.com/en-us/download/dotnet/10.0), then run these commands from the repository root in PowerShell.

Build the application and run ordinary regression suites:

```powershell
.\scripts\build.ps1 -Test
```

Create the installer and distribution archives:

```powershell
.\scripts\release.ps1 -Test
```

Build output is written to `dist`; release packages are written to `release`. Building does not install the service or change protected folders. Install the matching package before exercising original-location protection. Use `.\scripts\run.ps1` to launch the built desktop application.

The projects use framework libraries without external NuGet packages. Setup and maintenance hosts use Windows' built-in .NET Framework compiler.

| Release file | Contents |
| --- | --- |
| `FileLock-0.4.1-Setup.exe` | Graphical installer |
| `FileLock-0.4.1-Windows.zip` | Desktop, service, maintenance host and installation scripts |
| `FileLock-0.4.1-Source.zip` | Maintained source, tests, documentation and hidden configuration files |
| `SHA256SUMS.txt` | SHA-256 checksums for the release files |

### Validation

Local validation for 0.4.1 passed 11 core test groups, 67 UI checks, 88 live Windows checks, 14 setup safety checks and two Windows PowerShell 5.1 compatibility checks.

The UI count includes five optional interactive Explorer checks. Native tests use disposable folders and a temporary SYSTEM service. These checks do not establish compatibility with every third-party viewer or Explorer tab.

The [Windows workflow](.github/workflows/build.yml) builds, runs ordinary checks and uploads packages as workflow artifacts. It does not perform elevated native integration tests or automatically publish a GitHub release. See [Development and verification](docs/DEVELOPMENT.md) for opt-in checks.

## Publish the source to GitHub

Extract `FileLock-0.4.1-Source.zip` and upload its contents to the repository root, including `.gitignore` and `.github`. This file should appear as `README.md` in that root.

Keep installers and application ZIPs in **GitHub Releases**. Commit maintained source and configuration; generated packages, local state, recovery keys and private diagnostics should stay out of source commits.

See [Upload to GitHub](docs/GITHUB.md) for website and Git instructions.

## Project structure

```text
src/
  FileLock/          WPF desktop, passcode dialogs and Explorer integration
  FileLock.Shared/   Local service client and protocol
  FileLock.Service/  Permission broker, recovery and security journals
  FileLock.Setup/    Graphical installer and maintenance host
scripts/            Build, packaging, installation and verification
tests/              Core, UI and native Windows regression tests
docs/               Protection, development and GitHub guides
assets/             Application icon and icon generator
.github/workflows/  Windows build workflow
```

## සිංහලෙන් කෙටි උපදෙස්

Setup එක install කර FileLock විවෘත කරන්න. මුලින් අංක 6ක master PIN එකක් සකස් කර recovery key එක save කරන්න. **Protect a location** හරහා item එක එකතු කර shared PIN එක හෝ වෙනම individual PIN එක තෝරන්න.

Delete කළ folder එකක් නිසා error එකක් පෙන්වන්නේ නම්, 0.4.1 version එක install කර එම item එක තෝරා **Manage → Remove protection…** කරන්න. Rename හෝ move කළ item සඳහා **Repair moved location…** භාවිත කරන්න.

## License

No license has been selected. This repository does not include a `LICENSE` file.
