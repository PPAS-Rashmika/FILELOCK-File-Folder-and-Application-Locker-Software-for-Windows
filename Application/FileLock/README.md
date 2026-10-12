# FileLock

A Windows desktop application that protects files, folders and application executables at their **original locations**. FileLock opens require a six-digit passcode. Original folder opening shows the passcode dialog while the management window stays hidden, and access relocks when the observed use ends.

## Install

1. Download `FileLock-0.4.1-Setup.exe` from the project's GitHub Releases, or use the locally built file in `release`.
2. Open Setup, choose **Install**, and approve the Windows administrator prompt.
3. Choose **Open FileLock**, or find **FileLock** in the Start menu.
4. Create a six-digit master passcode and save the recovery key.
5. Add a file, folder or executable. Choose the shared master passcode or its own six-digit passcode.

Requirements: Windows x64, local fixed NTFS storage, and [.NET 10 Desktop Runtime x64](https://dotnet.microsoft.com/en-us/download/dotnet/10.0). Setup checks the runtime before installation and provides its download link. The desktop and service are framework-dependent; the .NET runtime is not bundled. Setup itself uses Windows' .NET Framework. This build is unsigned.

The ZIP package is also available: extract `FileLock-0.4.1-Windows.zip`, run `install.cmd`, then open FileLock from the Start menu. Setup installs the app and its automatic Windows service under `C:\Program Files\FileLock` and registers it in Windows **Installed apps**. It enables File System and Handle Manipulation failure auditing for denied-access prompts.

**Sinhala:** Setup.exe open karala **Install** click karanna. Windows prompt eka approve karala **Open FileLock** click karanna. Anka 6ka passcode ekak hadala recovery key eka save karanna. File/folder eka add karanna. Locked folder eka open karaddi passcode dialog eka witharak penwanawa.

## Use and recover

- Opening FileLock from its launcher or notification-area icon asks for the master passcode each time before showing the management window. The first opening guides an unconfigured account through passcode setup.
- When adding or changing a location's passcode, explicitly choose **Shared master passcode** or **Separate passcode for this location**. A separate passcode requires six digits and matching confirmation; leading zeroes are supported. The master passcode does not unlock an individual location.
- Open a protected item through FileLock, or double-click the original protected folder, and enter its location passcode every time. This also applies when the location is already open. A wrong passcode or Cancel does not open another view or create a new access grant.
- Close all observed Explorer views of a protected folder, including its subfolders, to relock it automatically. Viewer/window closure normally settles for two seconds before relocking. An observed application process exit closes its access on the next check. If the background agent loses its heartbeat, the service's 15-second deadline closes access.
- File viewers must expose an identifiable document window title for close detection. An unidentifiable viewer gets a bounded 10-second launch grace before FileLock relocks. See [the protection boundaries](docs/PROTECTION.md) for window/tab limitations.
- Use **Lock now** to end access immediately. Use **Remove protection** to restore the saved original Windows permissions permanently.
- If a protected item is renamed or moved on the same NTFS volume, FileLock can find it using its saved identity and repair the path when relocking. For an item showing **Needs attention**, choose **Manage → Repair moved location**. If automatic discovery fails, select that same item at its current path. Repair keeps its passcode and saved original permissions, relocks it, and does not open it. An unrelated replacement cannot replace the saved item.
- After installing version 0.4.1 or newer, choose **Manage → Remove protection** for a protected item you deleted or moved to the Recycle Bin. FileLock verifies its original volume and every saved object identity, restores permissions on surviving original objects, then safely removes the record. Remaining content is kept. If its drive is unavailable or restoration cannot complete, the recovery record stays available for retry.
- Adding a folder enables its Explorer prompt setting and starts the prompt agent quietly when you sign in. Disable this in **Security & recovery** to restore the previous folder default action.
- Recover the master passcode using the saved recovery key; recovery creates a replacement key. After signing in with the master passcode, use **Reset forgotten passcode** for an individual item.
- Existing passcodes are preserved during upgrades. If an earlier version saved an item as **Shared passcode**, use **Manage → Change passcode**, enter its current master passcode, and choose **Separate passcode for this location** to set the intended individual passcode.
- Before uninstalling, remove protection from every item in every Windows account. Then use Windows **Installed apps** or **Uninstall FileLock** in the Start menu. Uninstall refuses while protected items remain. Account/recovery data is retained for reinstall.

During an approved use, the original Windows permissions apply, so other permitted programs can also read the location. Every FileLock-mediated opening asks for a passcode; this version does not intercept every program's read. Keep a separate backup and close programs already using the item before protecting it.

## Build

Install the Windows x64 [.NET 10 SDK](https://dotnet.microsoft.com/en-us/download/dotnet/10.0). Open `FileLock.slnx` in an editor, or use Windows PowerShell:

```powershell
.\scripts\build.ps1 -Test
.\scripts\run.ps1
```

The projects use built-in framework libraries with no external NuGet packages. Build output is `dist`. To build the graphical installer and both distribution archives:

```powershell
.\scripts\release.ps1 -Test
```

Outputs in `release`:

- `FileLock-0.4.1-Setup.exe`: graphical installer.
- `FileLock-0.4.1-Windows.zip`: application, broker, maintenance host and install scripts.
- `FileLock-0.4.1-Source.zip`: source-only GitHub upload archive, including hidden configuration files.
- `SHA256SUMS.txt`: checksums for those files.

The installer host is compiled with Windows' .NET Framework C# compiler; no third-party installer compiler is needed. Building does not install services or change protected folders. [Development and validation](docs/DEVELOPMENT.md) covers the opt-in Windows integration checks.

## GitHub

The workspace is a Git repository with generated files excluded. Upload the extracted contents of `FileLock-0.4.1-Source.zip` into a new repository, or push this repository using your own GitHub remote. See [the upload guide](docs/GITHUB.md).

The Windows GitHub Actions workflow builds, checks the ordinary test suites and uploads the installer and archives as workflow artifacts. It does not install the service, run elevated live checks or publish a public release. Release binaries belong in GitHub Releases, not in source commits.

No license has been selected for this project.

## Source

| Location | Purpose |
| --- | --- |
| `src/FileLock` | WPF desktop and passcode dialogs |
| `src/FileLock.Shared` | Local service client and bounded protocol |
| `src/FileLock.Service` | SYSTEM permission broker, recovery and durable journals |
| `src/FileLock.Setup` | Graphical installer and uninstall host |
| `scripts` | Build, release, installation and verification |
| `tests` | Passcode, permissions, broker and UI regression tests |
| `assets` | Application icon and its generator |
