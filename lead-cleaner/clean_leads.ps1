$inputPath  = Join-Path $PSScriptRoot "messy_leads.csv"
$outputPath = Join-Path $PSScriptRoot "clean_leads.csv"

function Normalise-Phone($raw) {
    $digits = $raw -replace '\D', ''

    if ($digits.Length -eq 12 -and $digits.StartsWith('44')) {
        $digits = '0' + $digits.Substring(2)
    } elseif ($digits.Length -eq 14 -and $digits.StartsWith('0044')) {
        $digits = '0' + $digits.Substring(4)
    }

    if ($digits.Length -eq 10 -and $digits.StartsWith('7')) {
        $digits = '0' + $digits
    }

    if ($digits.Length -eq 11 -and $digits.StartsWith('07')) {
        return "$($digits.Substring(0,5)) $($digits.Substring(5))"
    }

    return $null
}

$rows = Import-Csv $inputPath
$totalIn = $rows.Count

$seen = @{}
$duplicatesRemoved = 0
$flagged = 0
$output = @()

foreach ($row in $rows) {
    $name    = $row.name.Trim()
    $phone   = $row.phone.Trim()
    $company = $row.company.Trim()

    $key = "$name|$phone|$company"
    if ($seen.ContainsKey($key)) {
        $duplicatesRemoved++
        continue
    }
    $seen[$key] = $true

    $fixedPhone = if ($phone) { Normalise-Phone $phone } else { $null }

    $flags = @()
    if (-not $name)    { $flags += 'missing_name' }
    if (-not $phone)   { $flags += 'missing_phone' }
    elseif ($null -eq $fixedPhone) { $flags += 'unfixable_phone' }
    if (-not $company) { $flags += 'missing_company' }

    if ($flags.Count -gt 0) { $flagged++ }

    $output += [PSCustomObject]@{
        name    = $name
        phone   = if ($fixedPhone) { $fixedPhone } else { $phone }
        company = $company
        flags   = $flags -join '|'
    }
}

$output | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8

Write-Host "Rows in:            $totalIn"
Write-Host "Duplicates removed: $duplicatesRemoved"
Write-Host "Rows out:           $($output.Count)"
Write-Host "Flagged rows:       $flagged"
Write-Host ""
Write-Host "Output written to: $outputPath"

$flaggedRows = $output | Where-Object { $_.flags }
if ($flaggedRows) {
    Write-Host ""
    Write-Host "Flagged rows:"
    foreach ($r in $flaggedRows) {
        Write-Host "  [$($r.flags)]  name='$($r.name)'  phone='$($r.phone)'  company='$($r.company)'"
    }
}
