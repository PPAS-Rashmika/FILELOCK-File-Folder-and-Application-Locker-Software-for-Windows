$ErrorActionPreference = 'Stop'
$FileLockServiceName = 'FileLockPathGateBroker'
$FileLockInstallRoot = [System.IO.Path]::GetFullPath((Join-Path $env:ProgramFiles 'FileLock'))
$FileLockServiceExe = Join-Path $FileLockInstallRoot 'Service\FileLock.Service.exe'
$FileLockAuditGuid = '{0CCE921D-69AE-11D9-BED3-505054503030}'
$FileLockHandleAuditGuid = '{0CCE9223-69AE-11D9-BED3-505054503030}'
$FileLockUninstallKey = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\FileLock'
$FileLockStartMenuRoot = [IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'FileLock'))

function Test-FileLockAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try { return ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
    finally { $identity.Dispose() }
}

function Assert-FileLockNoReparsePoint {
    param([Parameter(Mandatory)][string]$Path, [switch]$Tree)
    $absolute = [System.IO.Path]::GetFullPath($Path)
    $cursor = $absolute
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $entry = Get-Item -LiteralPath $cursor -Force
            if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "A symbolic link or junction is unsupported in this installation path: $cursor"
            }
        }
        $parent = [System.IO.Path]::GetDirectoryName($cursor)
        if ($parent -eq $cursor) { break }
        $cursor = $parent
    }
    if ($Tree -and (Test-Path -LiteralPath $absolute -PathType Container)) {
        foreach ($entry in Get-ChildItem -LiteralPath $absolute -Force -Recurse) {
            if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "A symbolic link or junction is unsupported in the installation: $($entry.FullName)"
            }
        }
    }
}

function Get-FileLockSafeArgument {
    param([Parameter(Mandatory)][string]$Value)
    # -File arguments are values, never PowerShell command expressions. Windows
    # paths cannot contain quotes; reject them and control characters explicitly.
    if ($Value.IndexOf('"') -ge 0 -or $Value.IndexOfAny([char[]]"`r`n") -ge 0) { throw 'Invalid installation argument.' }
    if ($Value.EndsWith('\')) { $Value += '\' }
    return '"' + $Value + '"'
}

function Invoke-FileLockElevation {
    param([Parameter(Mandatory)][string]$ScriptPath, [Parameter(Mandatory)][string[]]$Arguments)
    $powerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $all = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Get-FileLockSafeArgument $ScriptPath)) + $Arguments
    $process = Start-Process -FilePath $powerShell -ArgumentList ($all -join ' ') -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    return $process.ExitCode
}

function Write-FileLockLog {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host $Message
    if ($script:FileLockLogPath) {
        Add-Content -LiteralPath $script:FileLockLogPath -Value ('{0:u} {1}' -f [DateTime]::UtcNow, $Message) -Encoding UTF8
    }
}

function Initialize-FileLockLog {
    param([Parameter(Mandatory)][string]$Path)
    $script:FileLockLogPath = [System.IO.Path]::GetFullPath($Path)
    Assert-FileLockNoReparsePoint $script:FileLockLogPath
    if (-not (Test-Path -LiteralPath (Split-Path -Parent $script:FileLockLogPath) -PathType Container)) {
        throw 'The requested installation log directory does not exist.'
    }
}

function Assert-FileLockTrustedInstallTree {
    if (-not (Test-Path -LiteralPath $FileLockInstallRoot)) { return }
    Assert-FileLockNoReparsePoint $FileLockInstallRoot -Tree
    $entries = @((Get-Item -LiteralPath $FileLockInstallRoot -Force)) + @(Get-ChildItem -LiteralPath $FileLockInstallRoot -Force -Recurse)
    foreach ($entry in $entries) {
        $acl = Get-Acl -LiteralPath $entry.FullName
        $owner = $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
        if ($owner -notin @('S-1-5-18', 'S-1-5-32-544')) { throw "The installed path has an untrusted owner: $($entry.FullName)" }
        foreach ($rule in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
            if ($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and
                (([int]$rule.FileSystemRights -band 0x000D0156) -ne 0) -and
                $rule.IdentityReference.Value -notin @('S-1-5-18', 'S-1-5-32-544')) {
                throw "The installed broker directory must not be writable by ordinary users: $($entry.FullName)"
            }
        }
    }
}

function Set-FileLockInstallAcl {
    param([Parameter(Mandatory)][string]$Path, [switch]$Tree)
    $entries = @((Get-Item -LiteralPath $Path -Force))
    if ($Tree) { $entries += @(Get-ChildItem -LiteralPath $Path -Force -Recurse) }
    foreach ($entry in $entries) {
        if ($entry.PSIsContainer) {
            $acl = New-Object Security.AccessControl.DirectorySecurity
            $inheritance = [Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit'
        } else {
            $acl = New-Object Security.AccessControl.FileSecurity
            $inheritance = [Security.AccessControl.InheritanceFlags]::None
        }
        $acl.SetAccessRuleProtection($true, $false)
        $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
        foreach ($permission in @(@('S-1-5-18', 'FullControl'), @('S-1-5-32-544', 'FullControl'), @('S-1-5-32-545', 'ReadAndExecute'))) {
            $sid = New-Object Security.Principal.SecurityIdentifier($permission[0])
            $rule = New-Object Security.AccessControl.FileSystemAccessRule($sid, [Security.AccessControl.FileSystemRights]$permission[1], $inheritance,
                [Security.AccessControl.PropagationFlags]::None, [Security.AccessControl.AccessControlType]::Allow)
            $acl.AddAccessRule($rule)
        }
        Set-Acl -LiteralPath $entry.FullName -AclObject $acl
    }
}

function Get-FileLockServiceRegistration {
    return Get-CimInstance -ClassName Win32_Service -Filter "Name='FileLockPathGateBroker'" -ErrorAction Stop
}

function Assert-FileLockServiceRegistration {
    $service = Get-FileLockServiceRegistration
    if (-not $service) { throw 'The FileLock service is not installed.' }
    if ($service.PathName -cne ('"' + $FileLockServiceExe + '"') -or $service.StartName -ne 'LocalSystem') {
        throw 'An unexpected FileLock service registration exists. Refusing to replace it.'
    }
    return $service
}

function Invoke-FileLockSc {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $output = & (Join-Path $env:SystemRoot 'System32\sc.exe') @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Service configuration failed (exit $LASTEXITCODE): $($output -join ' ')" }
}

function Get-FileLockBrokerStatus {
    $null = Assert-FileLockServiceRegistration
    $output = & $FileLockServiceExe '--admin-status' 2>&1
    if ($LASTEXITCODE -ne 0) { throw "The installed FileLock broker could not confirm its status: $($output -join ' ')" }
    try { $status = ($output -join "`n") | ConvertFrom-Json }
    catch { throw 'The installed FileLock broker returned an invalid status.' }
    if (-not $status.ServiceAvailable -or $null -eq $status.TotalProtectedItems) { throw 'The installed FileLock broker status is incomplete.' }
    return $status
}

function Initialize-FileLockAuditApi {
    if ('FileLockInstaller.AuditPolicy' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace FileLockInstaller {
    public static class AuditPolicy {
        [StructLayout(LayoutKind.Sequential)] private struct Info { public Guid Subcategory; public uint Flags; public Guid Category; }
        [StructLayout(LayoutKind.Sequential)] private struct Luid { public uint Low; public int High; }
        [StructLayout(LayoutKind.Sequential)] private struct Privilege { public uint Count; public Luid Id; public uint Attributes; }
        [DllImport("advapi32.dll", SetLastError=true)] [return: MarshalAs(UnmanagedType.U1)] private static extern bool AuditQuerySystemPolicy(ref Guid subcategory, uint count, out IntPtr result);
        [DllImport("advapi32.dll")] private static extern void AuditFree(IntPtr value);
        [DllImport("kernel32.dll")] private static extern IntPtr GetCurrentProcess();
        [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr handle);
        [DllImport("advapi32.dll", SetLastError=true)] private static extern bool OpenProcessToken(IntPtr process, uint rights, out IntPtr token);
        [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern bool LookupPrivilegeValue(string system, string name, out Luid id);
        [DllImport("advapi32.dll", SetLastError=true)] private static extern bool AdjustTokenPrivileges(IntPtr token, bool disableAll, ref Privilege privilege, uint length, IntPtr previous, IntPtr returnedLength);
        private static void EnableAuditPrivilege() {
            IntPtr token;
            if (!OpenProcessToken(GetCurrentProcess(), 0x28, out token)) throw new Win32Exception(Marshal.GetLastWin32Error());
            try {
                Luid id;
                if (!LookupPrivilegeValue(null, "SeSecurityPrivilege", out id)) throw new Win32Exception(Marshal.GetLastWin32Error());
                var privilege = new Privilege { Count=1, Id=id, Attributes=2 };
                if (!AdjustTokenPrivileges(token, false, ref privilege, 0, IntPtr.Zero, IntPtr.Zero)) throw new Win32Exception(Marshal.GetLastWin32Error());
                var error = Marshal.GetLastWin32Error();
                if (error != 0) throw new Win32Exception(error);
            } finally { CloseHandle(token); }
        }
        public static uint Query(string subcategory) {
            EnableAuditPrivilege();
            var guid = new Guid(subcategory); IntPtr result;
            if (!AuditQuerySystemPolicy(ref guid, 1, out result)) throw new Win32Exception(Marshal.GetLastWin32Error());
            if (result == IntPtr.Zero) throw new InvalidOperationException("Windows returned no audit policy.");
            try { return ((Info)Marshal.PtrToStructure(result, typeof(Info))).Flags; }
            finally { AuditFree(result); }
        }
    }
}
'@
}

function Get-FileLockAuditFlags {
    param([string]$Subcategory = $FileLockAuditGuid)
    Initialize-FileLockAuditApi
    return [FileLockInstaller.AuditPolicy]::Query($Subcategory)
}

function Assert-FileLockInstallation {
    Assert-FileLockTrustedInstallTree
    $service = Assert-FileLockServiceRegistration
    if ($service.State -ne 'Running' -or $service.ProcessId -eq 0 -or $service.StartMode -ne 'Auto') { throw 'The FileLock service is not running with automatic startup.' }
    $process = Get-CimInstance Win32_Process -Filter ('ProcessId={0}' -f $service.ProcessId)
    if (-not $process -or $process.ExecutablePath -ine $FileLockServiceExe) { throw 'The running service executable is not the protected installed broker.' }
    if (((Get-FileLockAuditFlags) -band 2) -eq 0) { throw 'Windows File System failure auditing is disabled.' }
    if (((Get-FileLockAuditFlags -Subcategory $FileLockHandleAuditGuid) -band 2) -eq 0) { throw 'Windows Handle Manipulation failure auditing is disabled.' }
    $status = Get-FileLockBrokerStatus
    if (-not $status.ProtectionAvailable -or $status.Backend -ne 'Windows NTFS permissions') {
        throw ('The FileLock service is installed but native protection is unavailable: ' + $status.Message)
    }
    Write-FileLockLog ('Verified: automatic LocalSystem service, protected binary directory, File System and Handle Manipulation failure auditing, native backend; protected items: {0}.' -f $status.TotalProtectedItems)
    return $status
}

function Register-FileLockApplication {
    $app = Join-Path $FileLockInstallRoot 'App\FileLock.exe'
    $maintenance = Join-Path $FileLockInstallRoot 'Setup\FileLock.Maintenance.exe'
    if (-not (Test-Path -LiteralPath $maintenance -PathType Leaf)) { return }
    Assert-FileLockNoReparsePoint $FileLockStartMenuRoot -Tree
    New-Item -ItemType Directory -Path $FileLockStartMenuRoot -Force | Out-Null
    Set-FileLockInstallAcl $FileLockStartMenuRoot
    $shell = New-Object -ComObject WScript.Shell
    try {
        foreach ($entry in @(@('FileLock.lnk', $app, ''), @('Uninstall FileLock.lnk', $maintenance, '--uninstall'))) {
            $shortcut = $shell.CreateShortcut((Join-Path $FileLockStartMenuRoot $entry[0]))
            $shortcut.TargetPath = $entry[1]
            $shortcut.Arguments = $entry[2]
            $shortcut.WorkingDirectory = [IO.Path]::GetDirectoryName($entry[1])
            $shortcut.IconLocation = $app + ',0'
            $shortcut.Description = if ($entry[2]) { 'Remove FileLock after removing protection from all items.' } else { 'FileLock file and folder protection' }
            $shortcut.Save()
            [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) | Out-Null
        }
    } finally { [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) | Out-Null }
    Set-FileLockInstallAcl $FileLockStartMenuRoot -Tree
    $key = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey($FileLockUninstallKey)
    try {
        $key.SetValue('DisplayName', 'FileLock')
        $key.SetValue('DisplayVersion', (Get-Item -LiteralPath (Join-Path $FileLockInstallRoot 'App\FileLock.dll')).VersionInfo.ProductVersion)
        $key.SetValue('Publisher', 'FileLock')
        $key.SetValue('InstallLocation', $FileLockInstallRoot)
        $key.SetValue('DisplayIcon', $app + ',0')
        $key.SetValue('UninstallString', '"' + $maintenance + '" --uninstall')
        $key.SetValue('NoModify', 1, [Microsoft.Win32.RegistryValueKind]::DWord)
        $key.SetValue('NoRepair', 1, [Microsoft.Win32.RegistryValueKind]::DWord)
        $size = (Get-ChildItem -LiteralPath $FileLockInstallRoot -File -Recurse | Measure-Object Length -Sum).Sum
        $key.SetValue('EstimatedSize', [int][Math]::Ceiling($size / 1KB), [Microsoft.Win32.RegistryValueKind]::DWord)
    } finally { $key.Dispose() }
    Write-FileLockLog 'Registered FileLock in Windows Installed apps and the Start menu.'
}

function Remove-FileLockApplicationRegistration {
    $expected = [IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'FileLock'))
    if ($FileLockStartMenuRoot -ine $expected) { throw 'Cannot verify the FileLock Start menu directory.' }
    if (Test-Path -LiteralPath $expected -PathType Container) {
        Assert-FileLockNoReparsePoint $expected -Tree
        foreach ($name in @('FileLock.lnk', 'Uninstall FileLock.lnk')) {
            $target = [IO.Path]::GetFullPath((Join-Path $expected $name))
            if ([IO.Path]::GetDirectoryName($target) -ine $expected) { throw 'Cannot verify the FileLock shortcut path.' }
            if (Test-Path -LiteralPath $target -PathType Leaf) { Remove-Item -LiteralPath $target -Force }
        }
        if (@(Get-ChildItem -LiteralPath $expected -Force).Count -eq 0) { Remove-Item -LiteralPath $expected -Force }
    }
    [Microsoft.Win32.Registry]::LocalMachine.DeleteSubKeyTree($FileLockUninstallKey, $false)
}
