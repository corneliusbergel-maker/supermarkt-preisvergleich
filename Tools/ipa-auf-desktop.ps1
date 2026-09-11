<#
Legt die neueste unsignierte IPA aus der CI auf den Desktop.

Ersetzt eine vorhandene Preisfuchs-unsigned.ipa. Danach in 3uTools:
  Toolbox -> IPA Signature -> Apple ID Signing -> Add IPA Files -> Sign Now
  -> Download Center -> Install

Die Datei auf dem Desktop ist UNSIGNIERT. Signiert wird bei jedem Update
neu, mit der eigenen Apple-ID. Die Daten auf dem iPhone bleiben dabei
erhalten, solange die App nicht geloescht wird.
#>
$ErrorActionPreference = "Stop"

$gh       = "C:\Program Files\GitHub CLI\gh.exe"
$repo     = "corneliusbergel-maker/supermarkt-preisvergleich"
$artifact = "Preisfuchs-unsigned-ipa"

# Nur ein vollstaendig gruener Lauf: Dann ist sicher, dass die App baut und
# die Tests bestanden hat - nicht bloss, dass eine Datei entstanden ist.
$runId = & $gh run list --repo $repo --branch main --workflow CI --status success --limit 1 --json databaseId --jq '.[0].databaseId'
if (-not $runId) { throw "Kein erfolgreicher CI-Lauf gefunden." }

$temp = Join-Path $env:TEMP "preisfuchs-ipa"
if (Test-Path $temp) { Remove-Item $temp -Recurse -Force }

& $gh run download $runId --repo $repo -n $artifact -D $temp
$ipa = Join-Path $temp "Preisfuchs-unsigned.ipa"
if (-not (Test-Path $ipa)) { throw "Im Artefakt von Lauf $runId fehlt die IPA." }

$target = Join-Path ([Environment]::GetFolderPath("Desktop")) "Preisfuchs-unsigned.ipa"
Copy-Item $ipa $target -Force

"Neue IPA aus Lauf {0} liegt auf dem Desktop ({1:N0} KB)." -f $runId, ((Get-Item $target).Length / 1KB)
