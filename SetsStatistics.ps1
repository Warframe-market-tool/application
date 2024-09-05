Param (
    [String]
    $wmUri = "https://api.warframe.market",
    [String]
    $RootPath = $PSScriptRoot,
    [Switch]
    $NoGui
)


if ($NoGui) {
    Write-Host "Running SetStatistics in no-GUI mode."
    $cookieJwtPath = "$RootPath/jwt.txt"
    $ConfigPath = "$RootPath/config.json"
    $config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
    $email         = $config.email
    $password      = $config.password

    if ([string]::IsNullOrWhiteSpace($config.email) -or [string]::IsNullOrWhiteSpace($config.password)) {
        Write-Host "Please provide both email and password in the config file."
        exit
    }

    $LoginEvent = {
        $loginResp = Invoke-WebRequest -Uri "$wmUri/v1/auth/signin" -Method Post -Headers @{
            "content-type"  = "application/json; utf-8"
            "accept"        = "application/json"
            "Authorization" = ""
        } -Body (@{
            "email"     = $email
            "password"  = $password
            "auth_type" = "header"
        } | ConvertTo-Json) -ContentType "application/json"

        if($loginResp -ne $null -and $loginResp.StatusCode -eq 200)
        {
            $authorization = $loginResp.Headers.Authorization
            $authorization | Out-File $cookieJwtPath
            $user          = ($loginResp.Content | ConvertFrom-Json).payload.user
        }
        else
        {   Write-Host "failed login $($loginResp.StatusCode) $($loginResp.StatusDescription)"
            exit
        }
    }

}

$currentDate = (Get-Date).ToString("dd-MM-yyyy")
$statsPath = "$RootPath/stats/stats_$currentDate.json"
$items = (Invoke-RestMethod -Uri "$wmUri/v1/items" -Method Get).payload.items

if((Test-Path $statsPath) -and (dir $statsPath).CreationTime.Date -eq (Get-Date).Date)
{
    return Get-Content $statsPath | ConvertFrom-Json | select -ExpandProperty SyncRoot
}
else
{
    $stats = foreach($item in ($items | ? item_name -like "* Set"))
    {
        $setStats = (Invoke-RestMethod -Uri "$wmUri/v1/items/$($item.url_name)/statistics" -Method Get).payload.statistics_closed."90days" | select -Last 1
        $setData  = (Invoke-RestMethod -Uri "$wmUri/v1/items/$($item.url_name)"            -Method Get).payload.item.items_in_set
        $piecesStats = $setData | ? quantity_for_set -gt 0 | % { 
            Start-Sleep -Milliseconds 250
            $pieceStats = (Invoke-RestMethod -Uri "$wmUri/v1/items/$($_.url_name)/statistics" -Method Get).payload.statistics_closed."90days" | select -Last 1
            [PSCustomObject]@{
                name   = $_.en.item_name
                median = $pieceStats.median * $_.quantity_for_set
                volume = $pieceStats.volume
            }
        }
        $set_median = $setStats.median
        $set_pieces_median = ($piecesStats | measure median -Sum).sum
        [PSCustomObject]@{
            name              = $item.item_name
            set_median        = $set_median
            set_volume        = $setStats.volume
            set_max_price     = $setStats.max_price
            set_min_price     = $setStats.min_price
            set_pieces_median = $set_pieces_median
            set_pieces_volume = ($piecesStats | measure volume -Sum).sum
            benefit           = $set_median - $set_pieces_median
        }
        Start-Sleep -Milliseconds 500
    }
    if(-not (Test-Path (Split-Path $statsPath)))
    {
        New-Item -Path (Split-Path $statsPath) -ItemType Directory
    }
    $stats | ConvertTo-Json | Out-File $statsPath | Out-Null
    return $stats
}