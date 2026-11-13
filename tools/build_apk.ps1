param(
  [switch]$Split,
  [string]$Flutter = "C:\dev\flutter\bin\flutter.bat"
)
$ErrorActionPreference = "Stop"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
  & $Flutter pub get
  if ($LASTEXITCODE -ne 0) { throw "flutter pub get fallo" }
  $args = @("build", "apk", "--release")
  if ($Split) { $args += "--split-per-abi" }
  & $Flutter @args
  if ($LASTEXITCODE -ne 0) { throw "flutter build apk fallo" }
  Get-ChildItem "build\app\outputs\flutter-apk\*.apk" | ForEach-Object {
    "{0}  {1:N1} MB" -f $_.Name, ($_.Length / 1MB)
  }
} finally {
  Pop-Location
}
