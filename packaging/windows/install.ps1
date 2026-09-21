$ErrorActionPreference = 'Stop'
$Destination = Join-Path $env:LOCALAPPDATA 'PAPNGViewer'
New-Item -ItemType Directory -Force $Destination | Out-Null
foreach ($Name in @('papng-viewer.exe','icon.svg','LICENSE.txt','Godot-LICENSE.txt','Godot-COPYRIGHT.txt','README.md','uninstall.ps1')) {
    $Source = Join-Path $PSScriptRoot $Name
    $Target = Join-Path $Destination $Name
    if ($Source -ne $Target) { Copy-Item -LiteralPath $Source -Destination $Target -Force }
}
$Classes = 'HKCU:\Software\Classes'
$Extension = "$Classes\.papng"
$Program = "$Classes\PAPNG.Viewer"
$Backup = Join-Path $Destination 'previous-progid.txt'
if (!(Test-Path $Backup)) {
    $Previous = if (Test-Path $Extension) { (Get-Item $Extension).GetValue('') } else { '' }
    if ($Previous -ne 'PAPNG.Viewer') { Set-Content -LiteralPath $Backup -Value $Previous }
}
New-Item -Path $Program -Force | Out-Null
Set-Item -Path $Program -Value 'PAPNG Pixel Art Image'
$Command = '"' + (Join-Path $Destination 'papng-viewer.exe') + '" -- "%1"'
New-Item -Path "$Program\shell\open\command" -Force | Out-Null
Set-Item -Path "$Program\shell\open\command" -Value $Command
New-Item -Path "$Program\DefaultIcon" -Force | Out-Null
Set-Item -Path "$Program\DefaultIcon" -Value ('"' + (Join-Path $Destination 'papng-viewer.exe') + '",0')
New-Item -Path $Extension -Force | Out-Null
Set-Item -Path $Extension -Value 'PAPNG.Viewer'
New-Item -Path "$Extension\OpenWithProgids" -Force | Out-Null
New-ItemProperty -Path "$Extension\OpenWithProgids" -Name 'PAPNG.Viewer' -Value '' -PropertyType String -Force | Out-Null
$Application = "$Classes\Applications\papng-viewer.exe"
New-Item -Path "$Application\shell\open\command" -Force | Out-Null
Set-Item -Path "$Application\shell\open\command" -Value $Command
New-Item -Path "$Application\SupportedTypes" -Force | Out-Null
foreach ($Suffix in @('.papng','.png','.apng')) { New-ItemProperty -Path "$Application\SupportedTypes" -Name $Suffix -Value '' -PropertyType String -Force | Out-Null }
$Shell = New-Object -ComObject WScript.Shell
$Shortcut = $Shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Programs')) 'PAPNG Viewer.lnk'))
$Shortcut.TargetPath = Join-Path $Destination 'papng-viewer.exe'
$Shortcut.WorkingDirectory = $Destination
$Shortcut.Save()
Write-Host "Installed: $Destination"
Write-Host 'If Windows already has a default for .papng, choose PAPNG Viewer in Open with > Always.'
