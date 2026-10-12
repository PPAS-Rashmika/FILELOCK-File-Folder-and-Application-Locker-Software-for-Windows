[CmdletBinding()]
param(
    [string]$PackageRoot,
    [string]$LogPath,
    [switch]$NoElevation,
    [switch]$VerifyOnly
)

. (Join-Path $PSScriptRoot 'installer-common.ps1')

try {
    if (-not $LogPath) { $LogPath = Join-Path $env:TEMP ('FileLock-install-' + [Guid]::NewGuid().ToString('N') + '.log') }
    $LogPath = [System.IO.Path]::GetFullPath($LogPath)
    if (-not $PackageRoot) {
        $PackageRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
        if (-not (Test-Path -LiteralPath (Join-Path $PackageRoot 'FileLock\FileLock.exe'))) { $PackageRoot = Join-Path $PackageRoot 'dist' }
    }
    $PackageRoot = [System.IO.Path]::GetFullPath($PackageRoot)
    if (-not (Test-FileLockAdministrator)) {
        if ($NoElevation) { throw 'Administrator approval is required to install or verify the Windows service.' }
        $arguments = @('-PackageRoot', (Get-FileLockSafeArgument $PackageRoot), '-LogPath', (Get-FileLockSafeArgument $LogPath), '-NoElevation')
        if ($VerifyOnly) { $arguments += '-VerifyOnly' }
        exit (Invoke-FileLockElevation -ScriptPath $PSCommandPath -Arguments $arguments)
    }
    Initialize-FileLockLog $LogPath
    if ($VerifyOnly) { $null = Assert-FileLockInstallation; exit 0 }
    Write-FileLockLog 'Installing FileLock native Windows path protection.'
    if (-not [Environment]::Is64BitOperatingSystem -or -not [Environment]::Is64BitProcess) { throw 'Use 64-bit Windows PowerShell on 64-bit Windows.' }
    $runtime = Join-Path $env:ProgramFiles 'dotnet\dotnet.exe'
    if (-not (Test-Path -LiteralPath $runtime -PathType Leaf)) { throw 'Install the Microsoft .NET 10 Windows Desktop Runtime (x64), then run this installer again.' }
    $runtimes = & $runtime '--list-runtimes'
    if ($LASTEXITCODE -ne 0 -or -not ($runtimes -match '^Microsoft.WindowsDesktop.App 10\.') -or -not ($runtimes -match '^Microsoft.NETCore.App 10\.')) {
        throw 'Install the Microsoft .NET 10 Windows Desktop Runtime (x64), then run this installer again.'
    }
    Assert-FileLockNoReparsePoint $PackageRoot -Tree
    foreach ($relative in @('FileLock\FileLock.exe', 'FileLock\FileLock.dll', 'FileLock\FileLock.runtimeconfig.json', 'Service\FileLock.Service.exe', 'Service\FileLock.Service.dll', 'Service\FileLock.Service.runtimeconfig.json', 'scripts\installer-common.ps1', 'scripts\install.ps1', 'scripts\uninstall.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $PackageRoot $relative) -PathType Leaf)) { throw "The published package is incomplete: $relative. Run scripts\build.ps1 first." }
    }
    if ($PackageRoot -ieq $FileLockInstallRoot -or $PackageRoot.StartsWith($FileLockInstallRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Run installation from the published package outside Program Files.' }
    Assert-FileLockTrustedInstallTree
    $existing = Get-FileLockServiceRegistration
    if ($existing) {
        $null = Assert-FileLockServiceRegistration
        $null = Get-FileLockBrokerStatus
        # An upgrade must release the installed desktop binaries before copying
        # them. Never stop an unrelated executable with the same process name.
        $installedDesktop = Join-Path $FileLockInstallRoot 'App\FileLock.exe'
        foreach ($desktop in @(Get-Process -Name FileLock -ErrorAction SilentlyContinue)) {
            if ($desktop.Path -and $desktop.Path.Equals($installedDesktop, [StringComparison]::OrdinalIgnoreCase)) {
                Stop-Process -Id $desktop.Id -ErrorAction Stop
                if (-not $desktop.WaitForExit(10000)) { throw 'Close the installed FileLock app before upgrading.' }
            }
        }
        Stop-Service -Name $FileLockServiceName -ErrorAction Stop
        (Get-Service -Name $FileLockServiceName).WaitForStatus([ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds(30))
    }
    New-Item -ItemType Directory -Path $FileLockInstallRoot -Force | Out-Null
    Set-FileLockInstallAcl $FileLockInstallRoot
    foreach ($entry in @(@('FileLock', 'App'), @('Service', 'Service'), @('scripts', 'scripts'))) {
        $destination = Join-Path $FileLockInstallRoot $entry[1]
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        foreach ($file in Get-ChildItem -LiteralPath (Join-Path $PackageRoot $entry[0]) -Force) {
            Copy-Item -LiteralPath $file.FullName -Destination $destination -Recurse -Force
        }
    }
    $setupSource = Join-Path $PackageRoot 'Setup'
    if (Test-Path -LiteralPath $setupSource -PathType Container) {
        $setupDestination = Join-Path $FileLockInstallRoot 'Setup'
        New-Item -ItemType Directory -Path $setupDestination -Force | Out-Null
        foreach ($file in Get-ChildItem -LiteralPath $setupSource -File) {
            Copy-Item -LiteralPath $file.FullName -Destination $setupDestination -Force
        }
    }
    if (Test-Path -LiteralPath (Join-Path $PackageRoot 'docs') -PathType Container) {
        Copy-Item -LiteralPath (Join-Path $PackageRoot 'docs') -Destination $FileLockInstallRoot -Recurse -Force
    }
    foreach ($relative in @('README.md', 'uninstall.cmd')) {
        if (Test-Path -LiteralPath (Join-Path $PackageRoot $relative) -PathType Leaf) { Copy-Item -LiteralPath (Join-Path $PackageRoot $relative) -Destination $FileLockInstallRoot -Force }
    }
    Set-FileLockInstallAcl $FileLockInstallRoot -Tree
    Assert-FileLockTrustedInstallTree
    $previousAuditFlags = Get-FileLockAuditFlags
    $previousHandleAuditFlags = Get-FileLockAuditFlags -Subcategory $FileLockHandleAuditGuid
    $auditStateFile = Join-Path $FileLockInstallRoot 'audit-before-install.json'
    if (-not (Test-Path -LiteralPath $auditStateFile)) {
        @{ Subcategory = $FileLockAuditGuid; Flags = $previousAuditFlags; RecordedUtc = [DateTime]::UtcNow.ToString('o'); HandleSubcategory = $FileLockHandleAuditGuid; HandleFlags = $previousHandleAuditFlags; HandleRecordedUtc = [DateTime]::UtcNow.ToString('o'); Policy = 'File System and Handle Manipulation failure auditing are retained on uninstall to preserve later administrator policy changes.' } |
            ConvertTo-Json | Set-Content -LiteralPath $auditStateFile -Encoding UTF8
        Set-FileLockInstallAcl $auditStateFile
    } else {
        $auditBefore = Get-Content -LiteralPath $auditStateFile -Raw | ConvertFrom-Json
        if ($null -eq $auditBefore.HandleFlags) {
            # An upgrade records the policy observed before its first handle-
            # auditing configuration, retaining the original file-system record.
            $auditBefore | Add-Member -NotePropertyName HandleSubcategory -NotePropertyValue $FileLockHandleAuditGuid
            $auditBefore | Add-Member -NotePropertyName HandleFlags -NotePropertyValue $previousHandleAuditFlags
            $auditBefore | Add-Member -NotePropertyName HandleRecordedUtc -NotePropertyValue ([DateTime]::UtcNow.ToString('o'))
            $auditBefore.Policy = 'File System and Handle Manipulation failure auditing are retained on uninstall to preserve later administrator policy changes.'
            $auditBefore | ConvertTo-Json | Set-Content -LiteralPath $auditStateFile -Encoding UTF8
            Set-FileLockInstallAcl $auditStateFile
        }
    }
    foreach ($auditSubcategory in @($FileLockAuditGuid, $FileLockHandleAuditGuid)) {
        $auditOutput = & (Join-Path $env:SystemRoot 'System32\auditpol.exe') '/set' (('/subcategory:' + $auditSubcategory)) '/failure:enable' 2>&1
        if ($LASTEXITCODE -ne 0 -or (((Get-FileLockAuditFlags -Subcategory $auditSubcategory) -band 2) -eq 0)) { throw ('Could not enable required Windows failure auditing (' + $auditSubcategory + '): ' + ($auditOutput -join ' ')) }
    }
    if (-not $existing) {
        New-Service -Name $FileLockServiceName -BinaryPathName ('"' + $FileLockServiceExe + '"') -DisplayName 'FileLock Path Protection' -StartupType Automatic -DependsOn EventLog -Description 'Protects selected original NTFS paths using Windows permissions and passcode access windows.' | Out-Null
    } else {
        Set-Service -Name $FileLockServiceName -StartupType Automatic
    }
    Invoke-FileLockSc -Arguments @('failure', $FileLockServiceName, 'reset=', '86400', 'actions=', 'restart/5000/restart/5000/restart/5000')
    Invoke-FileLockSc -Arguments @('failureflag', $FileLockServiceName, '1')
    Start-Service -Name $FileLockServiceName
    (Get-Service -Name $FileLockServiceName).WaitForStatus([ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromSeconds(30))
    $null = Assert-FileLockInstallation
    Register-FileLockApplication
    Write-FileLockLog ('Installation complete. Open {0} normally to configure six-digit passcodes.' -f (Join-Path $FileLockInstallRoot 'App\FileLock.exe'))
    Write-FileLockLog 'Close programs that already use a selected item before protecting it. Keep the desktop app running for PIN prompts.'
    exit 0
} catch {
    if ($script:FileLockLogPath) { Write-FileLockLog ('ERROR: ' + $_.Exception.Message) }
    else { Write-Error $_.Exception.Message }
    exit 1
}
