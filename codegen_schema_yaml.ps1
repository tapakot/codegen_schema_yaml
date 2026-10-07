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
    -Output = ".\generated_schema.yml"`
    -ExcludeSchemaName`
    -GuessReferences
#>

param(
	[Parameter(Mandatory=$true)]
	[String]$Selector,

	[String[]]$ExcludePrefixes = @(),

	[String[]]$TagAllModels = @(),

	[String]$Output = ".\generated_schema.yml",

	[switch]$ExcludeSchemaName,

	[switch]$GuessReferences
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

# обогащение полученного yml
$result = @()
foreach ($line in $yaml) {
    if ($line -match '^  - name: ') { # новая модель
        # сбор информации о модели
        $parts = $line.Split(':')
        $afterColon = $parts[1].Trim()
        $nameParts = $afterColon -split '__'
        $schemaName = $nameParts[0].Trim()
        if ($schemaName -eq 'dds') {
            $typeAndName = $nameParts[1].Split('_')
            $DataVaultTableType = $typeAndName[0]
            $entityName = $typeAndName[1..($typeAndName.Length - 1)] -join '_'
            if ($DataVaultTableType -eq 'l') {
                $rightEntityName = $nameParts[2]
            }
        }

        # комментарий с именем модели
        $result += "# $afterColon"

        # название модели
        $result += $line

        # теги
        if ($TagAllModels.Count -gt 0) {
            $result += $tagLines
        }

        # meta: schema и тип таблицы в Data Vault
        if (-not $ExcludeSchemaName){
            $result += "    meta:"
            $result += "      schema: " + $schemaName
            if ($schemaName -eq 'dds') {
                switch ($DataVaultTableType) {
                    'h' { $result += "      type: hub" }
                    'l' { $result += "      type: link" }
                    's' { $result += "      type: satellite" }
                    default { $result += "      type: " + $DataVaultTableType }  # Опционально
                }
            }
        }
    } elseif ($line -match '^      - name: ') { # новый столбец
        # сбор информации о столбце
        $parts = $line.Split(':')
        $columnName = $parts[1].Trim()

        # название столбца
        $result += $line

        # meta: связь в Data Vault
        if ($GuessReferences) {
            if ($schemaName -eq 'dds') {
                if ($DataVaultTableType -eq 's') {
                    if ($columnName -eq $entityName + '_id') {
                        $result += "        meta:"
                        $result += "          data_vault:"
                        $result += "            role: foreign_key"
                        $result += "            references:"
                        $result += "              model: dds__h_"+$entityName
                        $result += "              column: "+$columnName
                    }
                } elseif ($DataVaultTableType -eq 'l') {
                    if ($columnName -eq $entityName + '_id') {
                        $result += "        meta:"
                        $result += "          data_vault:"
                        $result += "            role: foreign_key"
                        $result += "            references:"
                        $result += "              model: dds__h_"+$entityName
                        $result += "              column: "+$columnName
                    } elseif ($columnName -eq $rightEntityName + '_id') {
                        $result += "        meta:"
                        $result += "          data_vault:"
                        $result += "            role: foreign_key"
                        $result += "            references:"
                        $result += "              model: dds__h_"+$rightEntityName
                        $result += "              column: "+$columnName
                    }
                }
            }
        }
    } elseif ($line -match '^        data_type: ') { # замена типов данных
        $line = $line -replace "character varying", "varchar"
        $line = $line -replace "timestamp with time zone", "timestamptz"
        $line = $line -replace "timestamp without time zone", "timestamp"
        $result += $line
    } else {
        $result += $line
    }

}
$yaml = $result

$yaml | Out-File -FilePath "$Output" -Encoding utf8

Write-Host "Schema saved to $Output" -ForegroundColor Green