# Sólo para el runner descartable: WASAPI requiere un endpoint de audio real.
# VB-CABLE oficial firmado; patrón de instalación de LABSN/sound-ci-helpers.
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_OS -ne 'Windows') {
    throw 'La fixture de audio sólo se instala en GitHub Actions Windows.'
}
$pyaoAudio = Join-Path $env:RUNNER_TEMP 'pyao-audio-fixture'
New-Item -ItemType Directory -Path $pyaoAudio | Out-Null
$pyaoArchive = Join-Path $pyaoAudio 'vbcable.zip'
Invoke-WebRequest 'https://download.vb-audio.com/Download_CABLE/VBCABLE_Driver_Pack45.zip' -OutFile $pyaoArchive
if ((Get-FileHash $pyaoArchive -Algorithm SHA256).Hash -ne 'b950e39f01af1d04ea623c8f6d8eb9b6ea5c477c637295fabf20631c85116bfb') {
    throw 'SHA256 distinto para VB-CABLE.'
}
$pyaoDriver = Join-Path $pyaoAudio 'driver'
Expand-Archive -Path $pyaoArchive -DestinationPath $pyaoDriver
$pyaoDevcon = Join-Path $pyaoAudio 'devcon.exe'
Invoke-WebRequest 'https://raw.githubusercontent.com/LABSN/sound-ci-helpers/e9d6ba52163a3283714a68412036ddf33f78d49c/windows/devcon.exe' -OutFile $pyaoDevcon
if ((Get-FileHash $pyaoDevcon -Algorithm SHA256).Hash -ne '97cff42f8c0fe4fbdf991273159516bf78090625a933c3983ebd6f62284e329a') {
    throw 'SHA256 distinto para devcon.'
}
$pyaoHelperSignature = Get-AuthenticodeSignature $pyaoDevcon
if ($pyaoHelperSignature.Status -ne 'Valid' -or $pyaoHelperSignature.SignerCertificate.Subject -notmatch 'Microsoft') {
    throw 'devcon no tiene una firma Microsoft válida.'
}
$pyaoCatalog = Join-Path $pyaoDriver 'vbaudio_cable64_win10.cat'
$pyaoSignature = Get-AuthenticodeSignature $pyaoCatalog
if ($pyaoSignature.Status -ne 'Valid') { throw 'El catálogo de audio no tiene una firma válida.' }
$pyaoCertificate = Join-Path $pyaoAudio 'publisher.cer'
Export-Certificate -Cert $pyaoSignature.SignerCertificate -FilePath $pyaoCertificate | Out-Null
Import-Certificate -FilePath $pyaoCertificate -CertStoreLocation 'Cert:\LocalMachine\TrustedPublisher' | Out-Null
# El INF firmado busca los binarios en el subdirectorio de disco 222.
New-Item -ItemType Directory -Path (Join-Path $pyaoDriver '222') | Out-Null
Copy-Item (Join-Path $pyaoDriver '*win10.sys') (Join-Path $pyaoDriver '222')
$pyaoInf = Join-Path $pyaoDriver 'vbMmeCable64_win10.inf'
$pyaoInstall = Start-Process -FilePath $pyaoDevcon -ArgumentList @('install', "`"$pyaoInf`"", 'VBAudioVACWDM') -PassThru -NoNewWindow
if (-not $pyaoInstall.WaitForExit(120000)) { $pyaoInstall.Kill(); throw 'La instalación de audio agotó dos minutos.' }
if ($pyaoInstall.ExitCode -notin @(0, 1)) { throw "La instalación de audio falló: $($pyaoInstall.ExitCode)" }
Start-Service AudioEndpointBuilder
Start-Service Audiosrv
$pyaoDevices = @(Get-CimInstance Win32_SoundDevice)
$pyaoDevices | Select-Object Name, Status, PNPDeviceID | Format-Table
if (-not ($pyaoDevices | Where-Object { $_.Name -like '*VB-Audio*' -and $_.Status -eq 'OK' })) {
    throw 'No hay un endpoint virtual de audio operativo.'
}
New-Item -ItemType Directory -Path build -Force | Out-Null
$pyaoDevices | Select-Object Name, Status, PNPDeviceID | ConvertTo-Json | Set-Content build/audio-fixture.json
