Param (
    [String]
    $wmUri = "https://api.warframe.market",
    [String]
    $RootPath = $PSScriptRoot
)

$statsPath = "$RootPath/stats/riven-stats_$(Get-Date -Format "dd-MM-yyyy").json"
$attributes = (Invoke-restmethod -Uri "$wmUri/v1/riven/attributes" -Method GET).payload.attributes
$rivens = (Invoke-restmethod -Uri "$wmUri/v1/riven/items" -Method GET).payload.items | ? item_name -in @(
    "Phage",
	"Paracyst",
	"Synapse",
	"Dread",
	"Hate",
	"Boar",
	"Paris",
	"Burston",
	"Gorgon",
	"Boar",
	"Latron",
	"Boltor",
	"Zenith",
	"Torid"
)

$stats = @()
foreach($riven in $rivens)
{
    if($_.item_name -ne "phage" or ($_.item_name -ne "hate"))
    {
        continue
    }
    $stats += [PSCustomObject]@{
        name  = $riven.item_name
        stats = ($attributes | ? {$_.search_only -eq $false -and ($_.exclusive_to -eq $null -or $_.exclusive_to -Contains $riven.riven_type)} | % {
            $rivenUri = "$wmUri/v1/auctions/search?type=riven&weapon_url_name=$($riven.url_name)&buyout_policy=direct&sort_by=price_asc"
            $rivenStats = @()
            #Write-Host "$($_.positive_only) - $($_.negative_only)"
            if($_.positive_only -eq $true -or ($_.positive_only -eq $false -and $_.negative_only -eq $false))
            {
                Start-Sleep -milliseconds 250
                $auctions = (Invoke-restmethod -Uri "$rivenUri&positive_stats=$($_.url_name)" -Method GET).payload.auctions | ? {$_.private -eq $false -and $_.owner.status -ne "offline"} | sort buyout_price
                if($auctions.Count -ge 1)
                {
                    $rivenStats += [PSCustomObject]@{
                        name   = $riven.item_name
                        type   = "positive"
                        effect = $_.effect
                        min    = $auctions | select -ExpandProperty buyout_price -First 1
                        max    = $auctions | select -ExpandProperty buyout_price -Last 1
                        median = $auctions[[int]($auctions.Count / 2) - 1] | select -ExpandProperty buyout_price
                    }
                    #Write-Host "$rivenUri&positive_stats=$($_.url_name)"
                }
            }
            if($_.negative_only -eq $true -or ($_.positive_only -eq $false -and $_.negative_only -eq $false))
            {
                Start-Sleep -milliseconds 250
                $auctions = (Invoke-restmethod -Uri "$rivenUri&negative_stats=$($_.url_name)" -Method GET).payload.auctions | ? {$_.private -eq $false -and $_.owner.status -ne "offline"} | sort buyout_price
                if($auctions.Count -ge 1)
                {
                    $rivenStats += [PSCustomObject]@{
                        name   = $riven.item_name
                        type   = "negative"
                        effect = $_.effect
                        min    = $auctions | select -ExpandProperty buyout_price -First 1
                        max    = $auctions | select -ExpandProperty buyout_price -Last 1
                        median = $auctions[[int]($auctions.Count / 2) - 1] | select -ExpandProperty buyout_price
                    }
                    #Write-Host "$rivenUri&negative_stats=$($_.url_name)"
                }
            }
            $rivenStats | ConvertTo-Json
        })
    }
}

if(-not (Test-Path (Split-Path $statsPath))){
    New-Item -Path (Split-Path $statsPath) -ItemType Directory
}
$stats | ConvertTo-Json | Out-File $statsPath -Encoding utf8 | Out-Null

return $stats
