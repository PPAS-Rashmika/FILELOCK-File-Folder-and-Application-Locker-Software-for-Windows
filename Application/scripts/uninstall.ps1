[CmdletBinding()]
param([string]$LogPath, [switch]$NoElevation, [switch]$VerifyOnly)

. (Join-Path $PSScriptRoot 'installer-common.ps1')

try {
    if (-not $LogPath) { $LogPath = Join-Path $env:TEMP ('FileLock-uninstall-' + [Guid]::NewGuid().ToString('N') + '.log') }
    $LogPath = [System.IO.Path]::GetFullPath($LogPath)
    if (-not (Test-FileLockAdministrator)) {
        if ($NoElevation) { throw 'Administrator approval is required to remove the Windows service.' }
        $elevationArguments = @('-LogPath', (Get-FileLockSafeArgument $LogPath), '-NoElevation')
        if ($VerifyOnly) { $elevationArguments += '-VerifyOnly' }
        exit (Invoke-FileLockElevation -ScriptPath $PSCommandPath -Arguments $elevationArguments)
    }
    Initialize-FileLockLog $LogPath
    Write-FileLockLog 'Checking whether FileLock can be safely uninstalled.'
    Assert-FileLockTrustedInstallTree
    $null = Assert-FileLockServiceRegistration
    $status = Get-FileLockBrokerStatus
    if ($status.TotalProtectedItems -ne 0) { throw 'Remove protection from every item in each Windows user account before uninstalling FileLock. The service and original permission backups must remain available until then.' }
    if ($VerifyOnly) {
        Write-FileLockLog 'No protected items remain. Verification complete; no files, settings or services were removed.'
        exit 0
    }
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32;
using Microsoft.Win32.SafeHandles;
public static class FileLockUninstallShell {
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode)] private static extern int RegLoadAppKey(string path, out SafeRegistryHandle key, uint access, uint options, uint reserved);
    [DllImport("shell32.dll")] private static extern void SHChangeNotify(uint change, uint flags, IntPtr first, IntPtr second);
    public static bool OfflineGateEnabled(string path) {
        SafeRegistryHandle handle;
        int error = RegLoadAppKey(path, out handle, 0x20019, 1, 0);
        if (error != 0) throw new Win32Exception(error, "Cannot verify an offline Windows user's folder settings. Sign in to that account and disable FileLock folder prompts before uninstalling.");
        using (handle)
        using (var root = RegistryKey.FromHandle(handle))
        using (var shell = root.OpenSubKey(@"Directory\shell"))
            return shell != null && (shell.GetValue("") as string) == "FileLock.Open";
    }
    public static void Refresh() { SHChangeNotify(0x08000000, 0, IntPtr.Zero, IntPtr.Zero); }
}
'@
    foreach ($profile in Get-ChildItem 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList') {
        if ($profile.PSChildName -notmatch '^S-1-5-21-[0-9-]+$') { continue }
        $loadedClasses = [Microsoft.Win32.Registry]::Users.OpenSubKey($profile.PSChildName + '_Classes')
        if ($loadedClasses) { $loadedClasses.Dispose(); continue }
        $profilePath = [Environment]::ExpandEnvironmentVariables((Get-ItemProperty -LiteralPath $profile.PSPath).ProfileImagePath)
        $classHive = Join-Path $profilePath 'AppData\Local\Microsoft\Windows\UsrClass.dat'
        if (Test-Path -LiteralPath $classHive -PathType Leaf) {
            Assert-FileLockNoReparsePoint $classHive
            if ([FileLockUninstallShell]::OfflineGateEnabled($classHive)) {
                throw 'An offline Windows account still has FileLock folder prompts enabled. Sign in to that account and disable the folder prompt setting before uninstalling.'
            }
        }
    }
    # This operation checks the count and disables new registrations atomically
    # inside the broker, closing the zero-count / concurrent-Add race.
    $checkOutput = & $FileLockServiceExe '--admin-uninstall-check' 2>&1
    if ($LASTEXITCODE -ne 0) { throw ('The broker refused safe uninstall: ' + ($checkOutput -join ' ')) }
    # Restore this user's previous folder verb before removing its executable.
    # Other loaded Windows profiles are checked below as well, because their
    # default folder action must never be left pointing to a removed app.
    $profiles = Get-ChildItem 'Registry::HKEY_USERS' | Where-Object { $_.PSChildName -match '^S-1-5-21-[0-9-]+$' }
    foreach ($profile in $profiles) {
        $profileKey = [Microsoft.Win32.Registry]::Users.OpenSubKey($profile.PSChildName, $true)
        try {
            $shell = $profileKey.OpenSubKey('Software\Classes\Directory\shell', $true)
            $backup = $profileKey.OpenSubKey('Software\FileLock\FolderShellIntegration')
            try {
                if ($shell -and $shell.GetValue('') -eq 'FileLock.Open') {
                    if ($backup -and $backup.GetValue('HadDefault') -eq 1) {
                        $kind = if ($backup.GetValue('PreviousKind') -is [int]) { [Microsoft.Win32.RegistryValueKind]$backup.GetValue('PreviousKind') } else { [Microsoft.Win32.RegistryValueKind]::String }
                        $shell.SetValue('', $backup.GetValue('PreviousDefault', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames), $kind)
                    } else { $shell.DeleteValue('', $false) }
                }
                if ($shell) { $shell.DeleteSubKeyTree('FileLock.Open', $false) }
            } finally { if ($backup) { $backup.Dispose() }; if ($shell) { $shell.Dispose() } }
            $run = $profileKey.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Run', $true)
            try {
                if ($run -and $run.GetValue('FileLock') -is [string] -and $run.GetValue('FileLock').StartsWith('"' + (Join-Path $FileLockInstallRoot 'App\FileLock.exe') + '"', [StringComparison]::OrdinalIgnoreCase)) { $run.DeleteValue('FileLock', $false) }
            } finally { if ($run) { $run.Dispose() } }
        } finally { $profileKey.Dispose() }
    }
    foreach ($desktop in @(Get-Process -Name FileLock -ErrorAction SilentlyContinue)) {
        if ($desktop.Path -and $desktop.Path.Equals((Join-Path $FileLockInstallRoot 'App\FileLock.exe'), [StringComparison]::OrdinalIgnoreCase)) { Stop-Process -Id $desktop.Id -ErrorAction Stop }
    }
    [FileLockUninstallShell]::Refresh()
    Stop-Service -Name $FileLockServiceName -ErrorAction Stop
    (Get-Service -Name $FileLockServiceName).WaitForStatus([ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds(30))
    Invoke-FileLockSc -Arguments @('delete', $FileLockServiceName)
    $expectedRoot = [System.IO.Path]::GetFullPath((Join-Path $env:ProgramFiles 'FileLock'))
    $actualRoot = (Get-Item -LiteralPath $FileLockInstallRoot -Force).FullName
    if ($actualRoot -ine $expectedRoot -or -not $actualRoot.StartsWith([System.IO.Path]::GetFullPath($env:ProgramFiles).TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'The installation path could not be verified for removal.' }
    Assert-FileLockNoReparsePoint $actualRoot -Tree
    # The resolved target is exactly the explicitly named FileLock installation.
    # ProgramData account/recovery data is intentionally retained for reinstall.
    Remove-Item -LiteralPath $actualRoot -Recurse -Force
    Remove-FileLockApplicationRegistration
    Write-FileLockLog 'FileLock service and installed application removed. Account/recovery data remains in protected ProgramData storage.'
    Write-FileLockLog 'Windows File System and Handle Manipulation failure auditing remain enabled, preserving any later administrator audit-policy changes.'
    exit 0
} catch {
    if ($script:FileLockLogPath) { Write-FileLockLog ('ERROR: ' + $_.Exception.Message) }
    else { Write-Error $_.Exception.Message }
    exit 1
}
