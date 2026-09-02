<#
.SYNOPSIS
    Regenerate the flat table-of-contents index (index-tables.csv) from the
    Kwikly HTML dictionary export.

.DESCRIPTION
    The Health Data Hub / SNDS variable dictionary is distributed by Kwikly as
    a static HTML site (skills/snds-query/references/dictionnaire/Kwikly/) :
    one category page per domain (DCIR.html, PMSI.html, CAUSE_DECES.html,
    CARTOGRAPHIE.html, VALEUR.html, AUTRE.html) listing tables as
    <tr class="thin"><td class="w15"><a class="bare"
    href="./<CATEGORIE>/<TABLE>.html"><TABLE></a></td><td><LIBELLE></td></tr>,
    plus one variable-level detail page per table under
    Kwikly/<CATEGORIE>/<TABLE>.html.

    This script does NOT parse the variable-level detail pages — it only
    rebuilds a flat CSV table-of-contents that the snds-query skill uses to
    locate a table by name/topic before opening (reading) the matching detail
    HTML page on demand. Re-run it whenever the Kwikly export is refreshed
    (footer shows "Version du DD/MM/AAAA") to pick up new/renamed/removed
    tables. Idempotent: fully regenerates the output file every run, no
    incremental state.

.PARAMETER KwiklyDir
    Folder containing the Kwikly HTML export (the *.html category files and
    their per-table subfolders). Defaults to
    skills/snds-query/references/dictionnaire/Kwikly relative to repo root.

.PARAMETER OutFile
    Destination CSV. Defaults to
    skills/snds-query/references/dictionnaire/index-tables.csv.

.EXAMPLE
    powershell -File scripts/build-kwikly-index.ps1
#>
param(
    [string]$KwiklyDir = "skills\snds-query\references\dictionnaire\Kwikly",
    [string]$OutFile   = "skills\snds-query\references\dictionnaire\index-tables.csv"
)

$ErrorActionPreference = "Stop"

$repoRoot   = Split-Path -Parent $PSScriptRoot
$kwiklyPath = Join-Path $repoRoot $KwiklyDir
$outPath    = Join-Path $repoRoot $OutFile

if (-not (Test-Path $kwiklyPath)) {
    throw "Dossier Kwikly introuvable : $kwiklyPath"
}

# Une ligne de tableau Kwikly ressemble à (libellé parfois vide) :
#   <tr class="thin"><td class="w15"><a class="bare" href="./DCIR/ER_PRS_F.html">ER_PRS_F</a></td><td>Entête Prestation</td></tr>
# NB : si un futur export Kwikly place du HTML (ex. <br/>) DANS la cellule libellé,
# ce regex s'arrêtera au premier "<" — vérifier après toute mise à jour de l'export
# (le compte de tables affiché en sortie de script doit rester plausible).
$rowPattern = '<tr class="thin"><td class="w15"><a class="bare" href="\./(?<cat>[^/"]+)/(?<table>[^."]+)\.html">[^<]*</a></td><td>(?<libelle>[^<]*)</td></tr>'

function ConvertTo-CsvField {
    param([string]$Value)
    if ($null -eq $Value) { $Value = "" }
    return '"' + ($Value -replace '"', '""') + '"'
}

# Découverte dynamique des pages de catégorie (tout *.html à la racine de Kwikly,
# sauf index.html) plutôt qu'une liste figée : un futur 7e domaine Kwikly serait
# pris en compte sans modifier ce script.
$categoryFiles = Get-ChildItem -Path $kwiklyPath -Filter "*.html" -File |
    Where-Object { $_.Name -ne "index.html" } |
    Sort-Object Name

if ($categoryFiles.Count -eq 0) {
    throw "Aucune page de catégorie (*.html) trouvée dans $kwiklyPath"
}

$rows = [System.Collections.Generic.List[pscustomobject]]::new()

foreach ($file in $categoryFiles) {
    $cat = $file.BaseName   # ex. "DCIR" pour DCIR.html

    # Les pages Kwikly sont annoncées UTF-8 (<meta charset="utf-8">) et le
    # sont réellement -> -Raw -Encoding UTF8.
    $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
    $rowMatches = [regex]::Matches($content, $rowPattern)

    if ($rowMatches.Count -eq 0) {
        Write-Warning "Aucune table trouvée dans $($file.Name) — la structure HTML a peut-être changé."
    }

    foreach ($m in $rowMatches) {
        $table   = $m.Groups['table'].Value
        $libelle = [System.Net.WebUtility]::HtmlDecode($m.Groups['libelle'].Value.Trim())
        $chemin  = "Kwikly/$cat/$table.html"

        $rows.Add([pscustomobject]@{
            categorie = $cat
            table     = $table
            libelle   = $libelle
            chemin    = $chemin
        })
    }

    Write-Host ("{0,-14} : {1,4} tables" -f $cat, $rowMatches.Count)
}

$rows = $rows | Sort-Object categorie, table

$dupes = $rows | Group-Object table | Where-Object { $_.Count -gt 1 }
if ($dupes) {
    Write-Warning ("Table(s) présente(s) dans plusieurs catégories : " + (($dupes | ForEach-Object { $_.Name }) -join ', '))
}

# ---- Écriture CSV (point-virgule, tout entre guillemets, comme les autres
# fichiers dictionnaire) — UTF-8 SANS BOM explicite (Export-Csv ajoute un BOM
# avec -Encoding UTF8 sous Windows PowerShell 5.1 ; on l'évite ici pour rester
# cohérent avec les CSV du dictionnaire ATIH et éviter les soucis de lecture
# read.csv2()/fread() côté R).
$header = @("categorie", "table", "libelle", "chemin") -join ';'
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add($header)
foreach ($r in $rows) {
    $lines.Add((@(
        (ConvertTo-CsvField $r.categorie),
        (ConvertTo-CsvField $r.table),
        (ConvertTo-CsvField $r.libelle),
        (ConvertTo-CsvField $r.chemin)
    ) -join ';'))
}

$csvContent = ($lines -join "`r`n") + "`r`n"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($outPath, $csvContent, $utf8NoBom)

Write-Host ""
Write-Host "Index régénéré : $outPath ($($rows.Count) tables, $($categoryFiles.Count) catégories)"
