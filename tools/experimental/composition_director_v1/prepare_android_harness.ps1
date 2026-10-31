param([switch]$SyncOnly)
$ErrorActionPreference='Stop'
$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$harness=Join-Path $PSScriptRoot '.android_harness'
if (-not (Test-Path -LiteralPath $harness)) {
  New-Item -ItemType Directory -Path $harness | Out-Null
  Copy-Item -LiteralPath (Join-Path $repoRoot 'app/lib'),(Join-Path $repoRoot 'app/test'),(Join-Path $repoRoot 'app/android'),(Join-Path $repoRoot 'app/assets') -Destination $harness -Recurse
  Copy-Item -LiteralPath (Join-Path $repoRoot 'app/pubspec.yaml'),(Join-Path $repoRoot 'app/pubspec.lock'),(Join-Path $repoRoot 'app/analysis_options.yaml'),(Join-Path $repoRoot 'app/.metadata') -Destination $harness
  New-Item -ItemType Directory -Path (Join-Path $harness '.dart_tool') | Out-Null
  # Reuse existing locked, installed packages. No pub get or package additions.
  $cachedApp='C:/Users/kuson/projects/gudory/app'
  Copy-Item -LiteralPath "$cachedApp/.dart_tool/package_config.json","$cachedApp/.dart_tool/package_graph.json" -Destination (Join-Path $harness '.dart_tool')
  Copy-Item -LiteralPath "$cachedApp/.flutter-plugins-dependencies" -Destination (Join-Path $harness '.flutter-plugins-dependencies')
  New-Item -ItemType Directory -Force -Path (Join-Path $harness 'assets/clip') | Out-Null
} elseif (-not $SyncOnly) {
  throw 'Harness already exists. Use -SyncOnly to update Scene experimental sources without overwriting other files.'
}
# Only the disposable tools copy gets a separate package identity. This avoids
# replacing any installed GUDORY app; no production Android file is edited.
$gradle=Join-Path $harness 'android/app/build.gradle.kts'
$gradleText=Get-Content -LiteralPath $gradle -Raw
# Base Android project disables built-in Kotlin but omits application of the
# Kotlin Android plugin already declared in settings.gradle.kts. Apply it only
# to this disposable harness; preserve the production native project.
if (-not $gradleText.Contains('id("org.jetbrains.kotlin.android")')) {
  $gradleText=$gradleText.Replace('id("com.android.application")', "id(`"com.android.application`")`n    id(`"org.jetbrains.kotlin.android`")")
}
$gradleText=$gradleText.Replace('applicationId = "com.gaslighteam.gudory"','applicationId = "com.gaslighteam.gudory.directorv1"')
Set-Content -LiteralPath $gradle -Value $gradleText -Encoding utf8
$manifest=Join-Path $harness 'android/app/src/main/AndroidManifest.xml'
$manifestText=Get-Content -LiteralPath $manifest -Raw
$manifestText=$manifestText.Replace('android:label="구도리"','android:label="구도리 실험 V1"')
Set-Content -LiteralPath $manifest -Value $manifestText -Encoding utf8
# --no-pub also needs the existing generated Android plugin registrant.
# Its dependency versions match the copied locked package configuration.
$registrantDir=Join-Path $harness 'android/app/src/main/java/io/flutter/plugins'
New-Item -ItemType Directory -Force -Path $registrantDir | Out-Null
Copy-Item -LiteralPath 'C:/Users/kuson/projects/gudory/app/android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java' -Destination $registrantDir
$source=Join-Path $repoRoot 'app/lib/features/scene/experimental/composition_director_v1'
$target=Join-Path $harness 'lib/features/scene/experimental/composition_director_v1'
New-Item -ItemType Directory -Force -Path $target | Out-Null
Get-ChildItem -LiteralPath $source -File | Copy-Item -Destination $target
Write-Output "Disposable Android harness: $harness"
