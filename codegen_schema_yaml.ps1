<#
для работы необходим   
- package: dbt-labs/codegen
  version: ">=0.14.1"

файл должен лежать в корне проекта

пример использования
.\codegen_schema_yaml.ps1` 
    -Selector "+dma__sed_zadachi"`
    -ExcludePrefixes "lod_", "trf_", "cds_", "dds__h_", "dds__l_"`
    -TagAllModels "sed"`
    -Output = ".\generated_schema.yml"
#>

param(
	[Parameter(Mandatory=$true)]
	[String]$Selector,

	[String[]]$ExcludePrefixes = @(),

	[String[]]$TagAllModels = @(),

	[String]$Output = ".\generated_schema.yml"
)

$models = @(
	dbt ls --select $Selector --resource-type model --output name -q
)

if ($LASTEXITCODE -ne 0) {
	Write-Error "dbt ls failed"
	Exit 1
}

if ($models.Count -eq 0) {
	Write-Error "no models found for selector: $Selector"
	Exit 1
}

if ($ExcludePrefixes.Count -gt 0) {
    $models = @(
        $models | Where-Object {
            $model = $_
            -not ($ExcludePrefixes | Where-Object {$model.StartsWith($_)})
        }
    )
}

if ($models.Count -eq 0) {
	Write-Error "no models found after applying ExcludePrefixes"
	Exit 1
}

Write-Host "Found $($models.Count) models:" -ForegroundColor Cyan
$models | ForEach-Object { Write-Host " $_"}

$argsObject = @{
	model_names = $models
	include_data_types = $true
}
$argsJson = $argsObject | ConvertTo-Json

$yaml = @(
    dbt run-operation codegen.generate_model_yaml --args $argsJson -q
)

if ($LASTEXITCODE -ne 0) {
	Write-Error "dbt-codegen failed"
	Exit 1
}

if ($TagAllModels.Count -gt 0) {
    $tagLines = @(
        "    config:"
        "      tags:"
    )
    foreach($tag in $TagAllModels){
        $tagLines += "        - $tag"
    }
}
$result = @()
foreach ($line in $yaml) {
    if ($line -match '^  - name: ') {
        $parts = $line.Split(':')
        $afterColon = $parts[1]
        $result += "# $afterColon"
    }
    $result += $line
    if (($line -match '^  - name: ') -and ($TagAllModels.Count -gt 0)) {
        $result += $tagLines
    }
}
$yaml = $result

$yaml | Out-File -FilePath "$Output" -Encoding utf8

Write-Host "Schema saved to $Output" -ForegroundColor Green