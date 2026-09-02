<#
.SYNOPSIS
    Build a claude.ai (web) Skill upload package from a skill folder under skills/.

.DESCRIPTION
    claude.ai's Skills upload (Customize > Skills) expects a .zip whose root
    contains a single folder named after the skill (skill-name/SKILL.md,
    skill-name/references/...). This script zips skills/<SkillName>/ as-is —
    it is the same folder used to build the Claude Code plugin, kept as the
    single source of truth (see skills/<SkillName>/SKILL.md and the plugin
    README for details).

    Before zipping, it re-checks that the skill's frontmatter `description`
    fits claude.ai's 200-character limit (stricter than Claude Code, which has
    no hard cap) — a regression here would silently fail on upload.

.PARAMETER SkillName
    Folder name under skills/ to package. Defaults to snds-query.

.PARAMETER OutDir
    Output directory for the built .zip. Defaults to dist/ at the repo root.

.EXAMPLE
    powershell -File scripts/build-web-skill.ps1
    powershell -File scripts/build-web-skill.ps1 -SkillName snds-query -OutDir dist
#>
param(
    [string]$SkillName = "snds-query",
    [string]$OutDir = "dist"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$skillPath = Join-Path $repoRoot "skills\$SkillName"
$skillMdPath = Join-Path $skillPath "SKILL.md"

if (-not (Test-Path $skillMdPath)) {
    throw "SKILL.md introuvable : $skillMdPath"
}

# ---- Vérification de la limite de description (200 caractères, claude.ai) ----
$lines = Get-Content -Path $skillMdPath -Encoding UTF8
$descLines = @()
$inDescription = $false
foreach ($line in $lines) {
    if ($line -match '^description:\s*>') { $inDescription = $true; continue }
    if ($inDescription) {
        if ($line -match '^\S') { break }   # ligne non indentée = fin du bloc
        $descLines += $line.Trim()
    }
}
$description = ($descLines -join ' ').Trim()
$descLength = $description.Length

Write-Host "Description ($descLength caractères) : $description"
if ($descLength -gt 200) {
    throw "Description trop longue pour claude.ai ($descLength > 200 caractères) — corriger skills\$SkillName\SKILL.md avant de packager."
}

# ---- Packaging ----
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$zipPath = Join-Path $OutDir "$SkillName.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

Compress-Archive -Path $skillPath -DestinationPath $zipPath -CompressionLevel Optimal

$fileCount = (Get-ChildItem -Path $skillPath -Recurse -File).Count
$zipSizeMB = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)

Write-Host "Package : $zipPath ($zipSizeMB Mo, $fileCount fichiers)"
Write-Host "A uploader dans claude.ai : Customize > Skills > Upload skill."
