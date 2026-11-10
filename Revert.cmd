@echo off
rem ==========================================================================
rem  Platinum Explorer - Revert.cmd
rem  Puts the stock File Explorer icon back on the taskbar and Start Menu
rem  shortcuts and removes %LOCALAPPDATA%\PlatinumExplorer.
rem ==========================================================================
setlocal EnableExtensions DisableDelayedExpansion
title Platinum Explorer - Revert
set "PE_SELF=%~f0"

rem --- Self-elevate -------------------------------------------------------
fltmc >nul 2>&1 && goto :admin
echo  Requesting administrator rights...
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Start-Process -FilePath $env:PE_SELF -Verb RunAs -ErrorAction Stop } catch { exit 1 }"
if errorlevel 1 (
    echo  [x] Administrator rights are required - elevation was cancelled.
    echo.
    pause
)
exit /b

:admin
echo.
echo  Platinum Explorer - Revert
echo  --------------------------
echo.

set "PE_MODE=revert"
call :engine
if errorlevel 1 goto :done

set "PE_MODE=refresh"
call :engine

echo.
echo  Done. File Explorer is back to the stock icon.

:done
echo.
pause
exit /b

rem --- Run the PowerShell engine embedded at the end of this file ---------
:engine
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s = [IO.File]::ReadAllText($env:PE_SELF); iex $s.Substring($s.LastIndexOf(':PSCODE') + 7)"
exit /b %errorlevel%

rem ==========================================================================
rem  Everything below is PowerShell. cmd never runs past this point.
rem  The same engine is embedded in Apply.cmd and Revert.cmd.
rem ==========================================================================
:PSCODE
$ErrorActionPreference = 'Stop'

$AppDir    = Join-Path $env:LOCALAPPDATA 'PlatinumExplorer'
$IconDst   = Join-Path $AppDir 'explorer-icon.ico'
$BakDir    = Join-Path $AppDir 'backup'
$Manifest  = Join-Path $BakDir 'manifest.txt'
$OurIcon   = '*\PlatinumExplorer\explorer-icon.ico*'
$StockIcon = '%windir%\explorer.exe,0'
$FeClsid   = [Guid]'52205fd8-5dfb-447d-801a-d0b52f2e83e1'   # shell:::{...} = File Explorer
$Utf8      = New-Object System.Text.UTF8Encoding $false
$SessionId = (Get-Process -Id $PID).SessionId
$Wsh       = New-Object -ComObject WScript.Shell

$QuickLaunch = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch'
$Roots = @(
    @{ Label = 'Taskbar';                Deep = $false; Path = (Join-Path $QuickLaunch 'User Pinned\TaskBar') }
    @{ Label = 'Start Menu';             Deep = $true;  Path = (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs') }
    @{ Label = 'Start Menu (all users)'; Deep = $true;  Path = (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs') }
    @{ Label = 'Start pins';             Deep = $false; Path = (Join-Path $QuickLaunch 'User Pinned\StartMenu') }
    @{ Label = 'Quick Launch';           Deep = $false; Path = $QuickLaunch }
)

function Say([string]$Tag, [string]$Msg, [ConsoleColor]$Color) { Write-Host (' [{0}] {1}' -f $Tag, $Msg) -ForegroundColor $Color }
function Ok([string]$m)   { Say '+' $m Green }
function Info([string]$m) { Say '*' $m Cyan }
function Warn([string]$m) { Say '!' $m Yellow }
function Bad([string]$m)  { Say 'x' $m Red }

function Get-SessionProcess([string[]]$Name) {
    Get-Process -Name $Name -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $SessionId }
}

# File Explorer shortcuts are identified by what they launch, not by file
# name, so localized or renamed shortcuts are found as well.
function Test-ExplorerLink([string]$Path) {
    try { $b = [IO.File]::ReadAllBytes($Path) } catch { return $false }
    if ($b.Length -lt 0x62 -or [BitConverter]::ToUInt32($b, 0) -ne 0x4C) { return $false }
    $flags = [BitConverter]::ToUInt32($b, 0x14)
    # Windows 11 stock shortcut: target ID list rooted at the File Explorer CLSID
    if (($flags -band 1) -and [BitConverter]::ToUInt16($b, 0x4E) -ge 0x14 -and $b[0x50] -eq 0x1F) {
        if ([Guid]::new([byte[]]$b[0x52..0x61]) -eq $FeClsid) { return $true }
    }
    # Classic shortcut: %windir%\explorer.exe without arguments
    try {
        $l = $Wsh.CreateShortcut($Path)
        $t = [Environment]::ExpandEnvironmentVariables([string]$l.TargetPath)
        if ($t -and -not ([string]$l.Arguments).Trim() -and
            [IO.Path]::GetFileName($t) -ieq 'explorer.exe' -and
            $t.StartsWith($env:windir, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    } catch { }
    return $false
}

function Get-ExplorerLinks {
    $seen = @{}
    foreach ($r in $Roots) {
        if (-not (Test-Path -LiteralPath $r.Path)) { continue }
        $files = Get-ChildItem -LiteralPath $r.Path -Filter '*.lnk' -File -Force -Recurse:$r.Deep -ErrorAction SilentlyContinue
        foreach ($f in $files) {
            $key = $f.FullName.ToLowerInvariant()
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            if (Test-ExplorerLink $f.FullName) { [pscustomobject]@{ Label = $r.Label; Path = $f.FullName } }
        }
    }
}

function Read-Manifest {
    $map = [ordered]@{}
    if (Test-Path -LiteralPath $Manifest) {
        foreach ($line in [IO.File]::ReadAllLines($Manifest, $Utf8)) {
            $p = $line.Split([char[]]'|', 2)
            if ($p.Count -eq 2 -and $p[1]) { $map[$p[1].ToLowerInvariant()] = [pscustomobject]@{ File = $p[0]; Path = $p[1] } }
        }
    }
    return ,$map
}

# Elevating with a different account would patch that account's profile.
function Assert-SameUser {
    try {
        $owner = Get-Process -Name explorer -IncludeUserName -ErrorAction Stop |
                 Where-Object { $_.SessionId -eq $SessionId -and $_.UserName } |
                 Select-Object -First 1 -ExpandProperty UserName
    } catch { return }
    if ($owner -and ($owner -split '\\')[-1] -ine $env:USERNAME) {
        Bad "This window runs as $env:USERNAME, but the desktop belongs to $owner."
        Bad 'Sign in as an administrator account and run the script from there.'
        exit 4
    }
}

function Invoke-Apply {
    $build = [Environment]::OSVersion.Version.Build
    if ($build -lt 22000) { Warn "Windows build $build detected - this icon is made for Windows 11." }

    $links = @(Get-ExplorerLinks)
    if ($links.Count -eq 0) {
        Warn 'No File Explorer shortcut found on the taskbar or in the Start Menu.'
        Warn 'Pin File Explorer to the taskbar, then run Apply.cmd again.'
        return 2
    }

    New-Item -ItemType Directory -Path $BakDir -Force | Out-Null
    Copy-Item -LiteralPath $env:PE_SRC -Destination $IconDst -Force
    Ok "Icon installed  $IconDst"

    $map  = Read-Manifest
    $done = 0
    foreach ($k in $links) {
        try {
            $l   = $Wsh.CreateShortcut($k.Path)
            $was = [string]$l.IconLocation -like $OurIcon
            $key = $k.Path.ToLowerInvariant()
            if (-not $was -and -not $map.Contains($key)) {
                $name = '{0}.lnk' -f ($map.Count + 1)
                Copy-Item -LiteralPath $k.Path -Destination (Join-Path $BakDir $name) -Force
                [IO.File]::AppendAllText($Manifest, ('{0}|{1}' -f $name, $k.Path) + "`r`n", $Utf8)
                $map[$key] = [pscustomobject]@{ File = $name; Path = $k.Path }
            }
            $l.IconLocation = "$IconDst,0"
            $l.Save()
            $verb = if ($was) { 'Re-applied' } else { 'Patched   ' }
            Ok ('{0}  {1,-22} {2}' -f $verb, $k.Label, $k.Path)
            $done++
        } catch {
            Bad ('Failed      {0,-22} {1}' -f $k.Label, $k.Path)
            Bad ('            ' + $_.Exception.Message)
        }
    }
    if ($done -eq 0) { return 3 }
    if (-not ($links | Where-Object { $_.Label -eq 'Taskbar' })) {
        Warn 'File Explorer is not pinned to the taskbar - only the Start Menu was patched.'
    }
    return 0
}

function Invoke-Revert {
    $changed = 0
    $map = Read-Manifest
    foreach ($e in @($map.Values)) {
        $bak = Join-Path $BakDir $e.File
        if (-not (Test-Path -LiteralPath $e.Path)) { Info ('Gone        {0}' -f $e.Path); continue }
        if (-not (Test-Path -LiteralPath $bak)) { continue }
        try {
            Copy-Item -LiteralPath $bak -Destination $e.Path -Force
            Ok ('Restored    {0}' -f $e.Path)
            $changed++
        } catch {
            Bad ('Failed      {0}' -f $e.Path)
            Bad ('            ' + $_.Exception.Message)
        }
    }
    # Anything still pointing at the platinum icon (no backup) -> stock icon
    foreach ($k in @(Get-ExplorerLinks)) {
        try {
            $l = $Wsh.CreateShortcut($k.Path)
            if ([string]$l.IconLocation -like $OurIcon) {
                $l.IconLocation = $StockIcon
                $l.Save()
                Ok ('Reset       {0,-22} {1}' -f $k.Label, $k.Path)
                $changed++
            }
        } catch {
            Bad ('Failed      {0,-22} {1}' -f $k.Label, $k.Path)
            Bad ('            ' + $_.Exception.Message)
        }
    }
    if (Test-Path -LiteralPath $AppDir) {
        try {
            Remove-Item -LiteralPath $AppDir -Recurse -Force
            Ok "Removed     $AppDir"
            $changed++
        } catch { Warn "Could not remove $AppDir - delete it by hand." }
    }
    if ($changed -eq 0) {
        Info 'Nothing to revert - File Explorer already uses the stock icon.'
        return 2
    }
    return 0
}

function Invoke-Refresh {
    Info 'Restarting Explorer and clearing the icon cache...'
    Get-SessionProcess explorer, StartMenuExperienceHost | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    $files = @()
    $dir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
    if (Test-Path -LiteralPath $dir) {
        $files += @(Get-ChildItem -LiteralPath $dir -File -Force -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -like 'iconcache*.db' -or $_.Name -like 'thumbcache*.db' })
    }
    $legacy = Join-Path $env:LOCALAPPDATA 'IconCache.db'
    if (Test-Path -LiteralPath $legacy) { $files += Get-Item -LiteralPath $legacy -Force }
    $gone = 0; $busy = 0
    foreach ($f in $files) {
        try { Remove-Item -LiteralPath $f.FullName -Force; $gone++ } catch { $busy++ }
    }
    Ok "Icon cache cleared ($gone files)"
    if ($busy) { Warn "$busy cache file(s) in use - Windows rebuilds them at next sign-in." }

    # Started from an elevated process, explorer.exe hands itself off to an
    # unelevated instance, so the desktop does not run as admin.
    if (-not (Get-SessionProcess explorer)) { Start-Process -FilePath (Join-Path $env:windir 'explorer.exe') }
    for ($i = 0; $i -lt 20 -and -not (Get-SessionProcess explorer); $i++) { Start-Sleep -Milliseconds 500 }
    $ie4 = Join-Path $env:windir 'System32\ie4uinit.exe'
    if (Test-Path -LiteralPath $ie4) { try { & $ie4 -show } catch { } }

    if (Get-SessionProcess explorer) { Ok 'Explorer restarted' }
    else { Warn 'Explorer did not come back - press Ctrl+Shift+Esc, Run new task, explorer.exe' }
    return 0
}

$rc = 1
try {
    switch ($env:PE_MODE) {
        'apply'   { Assert-SameUser; $rc = Invoke-Apply }
        'revert'  { Assert-SameUser; $rc = Invoke-Revert }
        'refresh' { $rc = Invoke-Refresh }
        default   { Bad "Unknown mode '$env:PE_MODE'" }
    }
} catch {
    Bad $_.Exception.Message
    $rc = 1
}
exit $rc
