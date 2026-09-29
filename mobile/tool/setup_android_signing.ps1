<#
Creates the Android release signing key and hands it to local builds and
GitHub Actions. Run once, from anywhere:

    pwsh mobile/tool/setup_android_signing.ps1

It:
  1. generates a keystore with a random password in $KeyDir (outside the
     repo) - or reuses the one already there, so it's safe to rerun;
  2. copies key.properties to mobile/android/ (gitignored) so local
     release builds are signed with it;
  3. stores the keystore and its passwords as repository secrets with the
     GitHub CLI, for .github/workflows/build.yml.

BACK UP $KeyDir. Every future update must be signed with this exact key:
if it's lost, the next APK can't install over the existing app, and every
user has to export, uninstall and reinstall.
#>
param(
  [string]$KeyDir = (Join-Path $HOME '.dnd-sheet-signing'),
  [string]$Repo = 'jeyeager65/dnd-sheet',
  [string]$Alias = 'dnd-sheet'
)
$ErrorActionPreference = 'Stop'

$keystore = Join-Path $KeyDir 'dnd-sheet-release.jks'
$propsFile = Join-Path $KeyDir 'key.properties'

function Find-Keytool {
  $candidates = @()
  if ($env:JAVA_HOME) { $candidates += Join-Path $env:JAVA_HOME 'bin\keytool.exe' }
  $candidates += 'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe'
  foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
  $onPath = Get-Command keytool -ErrorAction SilentlyContinue
  if ($onPath) { return $onPath.Source }
  throw 'keytool not found. Set JAVA_HOME to a JDK (Android Studio''s is in its jbr folder).'
}

function New-Password([int]$length = 32) {
  $chars = [char[]]'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
  -join (1..$length | ForEach-Object {
    $chars[[System.Security.Cryptography.RandomNumberGenerator]::GetInt32($chars.Length)]
  })
}

$keytool = Find-Keytool

if (Test-Path $keystore) {
  Write-Host "Using the existing keystore in $KeyDir."
  if (-not (Test-Path $propsFile)) { throw "$propsFile is missing - can't reuse the keystore without its passwords." }
} else {
  New-Item -ItemType Directory -Force $KeyDir | Out-Null
  $password = New-Password
  & $keytool -genkeypair -keystore $keystore -storetype PKCS12 `
    -alias $Alias -keyalg RSA -keysize 4096 -validity 36500 `
    -storepass $password -keypass $password -dname 'CN=D&D Sheet'
  if ($LASTEXITCODE -ne 0) { throw 'keytool failed.' }
  @(
    "storeFile=$($keystore -replace '\\', '/')"
    "storePassword=$password"
    "keyAlias=$Alias"
    "keyPassword=$password"
  ) | Set-Content -Path $propsFile -Encoding ascii
  Write-Host "Created $keystore."
}

$props = @{}
foreach ($line in Get-Content $propsFile) {
  if ($line -match '^\s*([^=]+?)\s*=\s*(.*)$') { $props[$matches[1]] = $matches[2] }
}

# Local release builds.
$androidDir = Join-Path $PSScriptRoot '..\android'
Copy-Item $propsFile (Join-Path $androidDir 'key.properties') -Force
Write-Host 'Wrote mobile/android/key.properties (gitignored).'

# GitHub Actions. gh reads each secret from stdin, so none of them end up
# in the command line or shell history.
[Convert]::ToBase64String([IO.File]::ReadAllBytes($keystore)) |
  gh secret set ANDROID_KEYSTORE_BASE64 --repo $Repo
$props['storePassword'] | gh secret set ANDROID_KEYSTORE_PASSWORD --repo $Repo
$props['keyAlias'] | gh secret set ANDROID_KEY_ALIAS --repo $Repo
$props['keyPassword'] | gh secret set ANDROID_KEY_PASSWORD --repo $Repo
if ($LASTEXITCODE -ne 0) { throw 'gh secret set failed - are you logged in (gh auth status)?' }
Write-Host "Stored the signing secrets in $Repo."

Write-Host ''
$listing = & $keytool -list -keystore $keystore -storepass $props['storePassword'] -alias $props['keyAlias']
$sha = ($listing | Select-String 'SHA-256\):\s*(\S+)').Matches[0].Groups[1].Value
Write-Host "Certificate SHA-256: $(($sha -replace ':', '').ToLower())"
Write-Host "(CI's 'Show signing certificate' step prints the same digest for each APK.)"
Write-Host ''
Write-Host "BACK UP $KeyDir (e.g. in a password manager or offline drive)." -ForegroundColor Yellow
Write-Host 'Losing it means no future update can install over the existing app.' -ForegroundColor Yellow
