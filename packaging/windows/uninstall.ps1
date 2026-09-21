$ErrorActionPreference = 'Stop'
$Destination = Join-Path $env:LOCALAPPDATA 'PAPNGViewer'
$Classes = 'HKCU:\Software\Classes'
$Extension = "$Classes\.papng"
if ((Test-Path $Extension) -and (Get-Item $Extension).GetValue('') -eq 'PAPNG.Viewer') {
    $Backup = Join-Path $Destination 'previous-progid.txt'
    $Previous = if (Test-Path $Backup) { (Get-Content -LiteralPath $Backup -Raw).Trim() } else { '' }
    if ($Previous) { Set-Item -Path $Extension -Value $Previous }
    else { (Get-Item $Extension).DeleteValue('', $false) }
}
Remove-ItemProperty -Path "$Extension\OpenWithProgids" -Name 'PAPNG.Viewer' -ErrorAction SilentlyContinue
Remove-Item -Path "$Classes\PAPNG.Viewer","$Classes\Applications\papng-viewer.exe" -Recurse -ErrorAction SilentlyContinue
foreach ($Name in @('papng-viewer.exe','icon.svg','LICENSE.txt','Godot-LICENSE.txt','Godot-COPYRIGHT.txt','README.md','previous-progid.txt','uninstall.ps1')) {
    Remove-Item -LiteralPath (Join-Path $Destination $Name) -ErrorAction SilentlyContinue
}
if ((Test-Path $Destination) -and !(Get-ChildItem -LiteralPath $Destination -Force)) { Remove-Item -LiteralPath $Destination }
Remove-Item -LiteralPath (Join-Path ([Environment]::GetFolderPath('Programs')) 'PAPNG Viewer.lnk') -ErrorAction SilentlyContinue
Write-Host 'PAPNG Viewer removed.'
