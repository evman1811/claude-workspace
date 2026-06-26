$firstNames = @("James","Oliver","Harry","Jack","George","Noah","Charlie","Jacob","Alfie","Freddie","Emily","Olivia","Isla","Ava","Mia","Isabella","Sophie","Ella","Grace","Lily")
$lastNames  = @("Smith","Jones","Williams","Taylor","Brown","Davies","Evans","Wilson","Thomas","Roberts","Johnson","Walker","Wright","Thompson","White","Hall","Green","Wood","Harris","Lewis")
$companies  = @("Apex Solutions Ltd","Northgate Technologies","Pemberton & Co","Redwood Consulting","Silverbridge Group","Tandem Digital","Unity Systems","Vantage Partners","Westfield Services","Yarrow Innovations","Zenith Strategies","Caldwell Enterprises","Dunmore Trading","Elmwood Advisory","Fairfax Logistics")

function Clean-UK {
    $a = Get-Random -Minimum 100 -Maximum 999
    $b = Get-Random -Minimum 100 -Maximum 999
    $c = Get-Random -Minimum 100 -Maximum 999
    return "07$a $b $c"
}

function Messy-UK {
    $a = Get-Random -Minimum 100 -Maximum 999
    $b = Get-Random -Minimum 100 -Maximum 999
    $c = Get-Random -Minimum 100 -Maximum 999
    $digits = "07$a$b$c"
    $style = Get-Random -Minimum 0 -Maximum 6
    switch ($style) {
        0 { return $digits }
        1 { return "+44$($digits.Substring(1))" }
        2 { return "+44 (0)$($digits.Substring(1,3)) $($digits.Substring(4,3)) $($digits.Substring(7))" }
        3 { return "($($digits.Substring(0,5))) $($digits.Substring(5,3))-$($digits.Substring(8))" }
        4 { return $digits.Substring(1) }
        5 { return "0$digits" }
    }
}

$rows = @()

for ($i = 0; $i -lt 35; $i++) {
    $rows += [PSCustomObject]@{
        name    = "$($firstNames | Get-Random) $($lastNames | Get-Random)"
        phone   = Clean-UK
        company = $companies | Get-Random
    }
}

for ($i = 0; $i -lt 8; $i++) {
    $rows += [PSCustomObject]@{
        name    = "$($firstNames | Get-Random) $($lastNames | Get-Random)"
        phone   = Messy-UK
        company = $companies | Get-Random
    }
}

$missingFields = @("phone","company","name")
for ($i = 0; $i -lt 4; $i++) {
    $missing = $missingFields | Get-Random
    $rows += [PSCustomObject]@{
        name    = if ($missing -eq "name")    { "" } else { "$($firstNames | Get-Random) $($lastNames | Get-Random)" }
        phone   = if ($missing -eq "phone")   { "" } else { Clean-UK }
        company = if ($missing -eq "company") { "" } else { $companies | Get-Random }
    }
}

for ($i = 0; $i -lt 3; $i++) {
    $src = $rows[(Get-Random -Minimum 0 -Maximum 35)]
    $rows += [PSCustomObject]@{ name = $src.name; phone = $src.phone; company = $src.company }
}

$rows = $rows | Sort-Object { Get-Random }

$outPath = Join-Path $PSScriptRoot "messy_leads.csv"
$rows | Export-Csv -Path $outPath -NoTypeInformation -Encoding UTF8

Write-Host "Written $($rows.Count) rows to messy_leads.csv"
Write-Host ""
Import-Csv $outPath | Select-Object -First 12 | Format-Table -AutoSize
