# Determine the path of the running executable or script
$ExePath = [System.AppDomain]::CurrentDomain.BaseDirectory

# Construct paths to the XML files
$MainXMLPath = Join-Path $ExePath 'Views\Main.xaml'
$OMXMLPath = Join-Path $ExePath 'Views\OrderManagement.xaml'
$ConfigPath = Join-Path $ExePath 'config.json'
$cookieJwtPath = Join-Path $ExePath 'jwt.txt'
$currentDate = (Get-Date).ToString("dd-MM-yyyy")
$statsPath = Join-Path $ExePath "csv\stats_$currentDate.csv"
$csvPath = Join-Path $ExePath 'csv'
# Load the XML files
Add-Type -AssemblyName PresentationFramework
[xml]$MainXML  = Get-Content $MainXMLPath
[xml]$OMXML    = Get-Content $OMXMLPath

# Load and parse the configuration file
$config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($config.email) -or [string]::IsNullOrWhiteSpace($config.password)) {
    [System.Windows.MessageBox]::Show("Please provide both email and password in the config file.", "Missing Information", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
    exit
}

$wmUri         = $config.wmUri
$email         = $config.email
$password      = $config.password

$authorization = ""

if(Test-Path $cookieJwtPath)
{
    $cookieJwt = Get-Content $cookieJwtPath
    $user = (Invoke-restmethod -Uri "$wmUri/v1/profile" -Method GET -Headers @{
	    "Authorization" = $cookieJwt
    }).profile
    if($user.id -ne "None")
    {
        $authorization = $cookieJwt
        $authorization | Out-File $cookieJwtPath
        Write-Output "Login success with the token to the market api."
    }
}
if($authorization -eq "")
{
    $loginResp = Invoke-WebRequest -Uri "$wmUri/v1/auth/signin" -Method Post -Headers @{
        "content-type"  = "application/json; utf-8"
        "accept"        = "application/json"
	    "Authorization" = ""
    } -Body (@{
        "email"     = $email
        "password"  = $password
        "auth_type" = "header"
    } | ConvertTo-Json) -ContentType "application/json"

    if($loginResp.StatusCode -ne 200)
    {
        [System.Windows.MessageBox]::Show("Login status : Email /Password are incorrect.Please correct it in the config file.", "Login failed", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        exit "failed login $($loginResp.StatusCode) $($loginResp.StatusDescription)"
    }

    $authorization = $loginResp.Headers.Authorization
    $authorization | Out-File $cookieJwtPath
    $user          = ($loginResp.Content | ConvertFrom-Json).payload.user
    Write-Output "Login success to the market api."
}

$items = (Invoke-RestMethod -Uri "$wmUri/v1/items" -Method Get).payload.items


function Update-Order( [string]$orderId, [Hashtable]$body, [string]$authorization )
{
    Invoke-RestMethod -Uri "$wmUri/v1/profile/orders/$orderId" -Method PUT -Headers @{
        "content-type"  = "application/json; utf-8"
        "accept"        = "application/json"
	    "Authorization" = $authorization
    } -Body ($body | ConvertTo-Json) -ContentType "application/json" | Out-Null
}

if ($args -notcontains "-no-gui"){

    $MainFormXML = (New-Object System.Xml.XmlNodeReader $MainXML)
    $Main = [Windows.Markup.XamlReader]::Load($MainFormXML)

    $SearchTextBox = $Main.FindName("SearchTextBox")
    $SearchListBox = $Main.FindName("SearchListBox")
    $StatsDataGrid = $Main.FindName("StatsDataGrid")
    $SearchTextBox.Add_TextChanged({
        if($SearchTextBox.Text.Length -gt 2)
        {
            if($SearchTextBox.Text -notin $items.item_name)
            {
                $SearchListBox.ItemsSource = $items.item_name -match $SearchTextBox.Text
            }
            else
            {
                $profileOrders = Invoke-RestMethod -Uri "$wmUri/v1/profile/$($user.ingame_name)/orders" -Method Get -Headers @{
                    "content-type"  = "application/json; utf-8"
                    "accept"        = "application/json"
                    "Authorization" = $authorization
                }
                $url_name = $items | ? item_name -eq $SearchTextBox.Text | select -ExpandProperty url_name
                $StatsDataGrid.ItemsSource = foreach($item_in_set in (Invoke-RestMethod -Uri "$wmUri/v1/items/$url_name" -Method Get).payload.item.items_in_set) { 
                    Start-Sleep -Milliseconds 250
                    $pieceStats = (Invoke-RestMethod -Uri "$wmUri/v1/items/$($item_in_set.url_name)/statistics" -Method Get).payload.statistics_closed."48hours"
                    [PSCustomObject]@{
                        name = $item_in_set.en.item_name
                        avg  = [math]::Round(($pieceStats | measure avg_price -Average).Average * $item_in_set.quantity_for_set)
                        vol  = ($pieceStats | measure volume -Sum).Sum
                        sell = ($profileOrders.payload.sell_orders | ? {$_.item.url_name -eq $item_in_set.url_name} | select -ExpandProperty platinum) -join '-'
                        buy  = ($profileOrders.payload.buy_orders  | ? {$_.item.url_name -eq $item_in_set.url_name} | select -ExpandProperty platinum) -join '-'
                    }
                }
                
            }
        }
        else
        {
            $SearchListBox.ItemsSource = $null
        }
        if($SearchListBox.items.Count -gt 0)
        {
            $SearchListBox.Visibility = "visible"
        }
        else
        {
            $SearchListBox.Visibility = "hidden"
        }
    })
    $SearchTextBox.Add_LostFocus({
        $SearchListBox.Visibility = "hidden"
    })
    $SearchListBox.Add_SelectionChanged({
        $SearchTextBox.Text = $SearchListBox.SelectedItem
        $SearchListBox.Visibility = "hidden"
    })

    $StateTextBlock = $Main.FindName("StateTextBlock")

    $StartButton = $Main.FindName("Start")
    $StartButton.Add_Click({
        $StateTextBlock.Text = "Unavailable"
        $StateTextBlock.Foreground = "red"
        [System.Windows.Forms.Application]::DoEvents()
        $profileOrders = Invoke-RestMethod -Uri "$wmUri/v1/profile/$($user.ingame_name)/orders" -Method Get -Headers @{
            "content-type"  = "application/json; utf-8"
            "accept"        = "application/json"
            "Authorization" = $authorization
        }
        foreach ($order in ($profileOrders.payload.sell_orders + $profileOrders.payload.buy_orders | ? visible -eq $true)) {
            $body = @{
                "order_id" = $order.id
                "platinum" = $order.platinum
                "visible"  = $order.visible
            }

            $topUri   = "$wmUri/v2/orders/item/$($order.item.url_name)/top"
            $stats = (Invoke-RestMethod -Uri "$wmUri/v1/items/$($order.item.url_name)/statistics" -Method Get).payload.statistics_closed."48hours"
            if($order.mod_rank)
            {
                $stats = $stats | ? mod_rank -eq $order.mod_rank
                if($order.mod_rank -eq $order.item.mod_max_rank)
                {
                    $topUri   += "/?maxRank=true"
                }
            }

            $topOrders = Invoke-RestMethod -Uri $topUri -Method Get -Headers @{
                "platform" = $order.platform
                "language" = $order.region
            }
            
            $bestSellOrder = $topOrders.data.sell | ? {$_.user.ingamename -ne $user.ingame_name} | select -First 1
            $bestBuyOrder  = $topOrders.data.buy  | ? {$_.user.ingamename -ne $user.ingame_name} | select -First 1
            
            $sumVolume = ($stats | measure volume    -Sum    ).Sum
            $avgPrice  = ($stats | measure avg_price -Average).Average            

            $minPercent = 0.05
            $maxPercent = 0.25
            $info = switch($order.order_type)
            {
                "sell" {
                    $newPrice = $bestSellOrder.platinum - 1
                    if($newPrice -gt $avgPrice * (1 + $maxPercent)) {
                        #"You WTS $($order.item.en.item_name) for $newPrice PL (before $($order.platinum)) but the average price is $([int]$avgPrice)"
                        $newPrice = [math]::Round($avgPrice * (1 + $maxPercent))
                    }
                    if($newPrice -lt $avgPrice * (1 + $minPercent)) {
                        #"You WTS $($order.item.en.item_name) for $newPrice PL (before $($order.platinum)) but the average price is $([int]$avgPrice)"
                        $newPrice = [math]::Round($avgPrice * (1 + $minPercent))
                    }
                    if($newPrice -le $bestBuyOrder.platinum) {
                        "You WTS $($order.item.en.item_name) for $newPrice PL (before $($order.platinum)) but someone buy it for $($bestBuyOrder.platinum) PL"
                    }
                }
                "buy" {
                    $newPrice = $bestBuyOrder.platinum + 1
                    if($newPrice -lt $avgPrice * (1 - $maxPercent)) {
                        #"You WTB $($order.item.en.item_name) for $newPrice PL (before $($order.platinum)) but the average price is $([int]$avgPrice)"
                        $newPrice = [math]::Round($avgPrice * (1 - $maxPercent))
                    }
                    if($newPrice -gt $avgPrice * (1 - $minPercent)) {
                        #"You WTB $($order.item.en.item_name) for $newPrice PL (before $($order.platinum)) but the average price is $([int]$avgPrice)"
                        $newPrice = [math]::Round($avgPrice * (1 - $minPercent))
                    }
                    if($newPrice -ge $bestSellOrder.platinum) {
                        "You WTB $($order.item.en.item_name) for $newPrice PL (before $($order.platinum)) but someone sell it for $($bestSellOrder.platinum) PL"
                    }
                }
            }
            if($info)
            {
                ### UI
                $OMFormXML = (New-Object System.Xml.XmlNodeReader $OMXML)
                $OrderManagement = [Windows.Markup.XamlReader]::Load($OMFormXML)
                
                $ModalMessageBorder = $OrderManagement.FindName("ModalMessageBorder")

                $TopSellGrid = $OrderManagement.FindName("TopSell")
                $TopSellGrid.ItemsSource = @($topOrders.data.sell | select @{l="name";e={$_.user.inGameName}}, platinum, quantity, @{l="status";e={$_.user.status}})
                $TopSellGrid.Add_SelectionChanged({
                    Param(
                        [object]$sender,
                        [System.Windows.Controls.SelectionChangedEventArgs]$e
                    )
                    $row = ([System.Windows.Controls.DataGrid]$sender).SelectedCells[0].Item
                    Write-Host $row
                    Set-Clipboard "/w $($row.name) Hi, WTB $($order.item.en.item_name) for $($row.platinum)"
                    $sender.UnselectAll()
                    
                    $ModalMessageBorder.Visibility = "Hidden"
                    $ModalMessageBorder.Visibility = "Visible"

                })

                $TopBuyGrid = $OrderManagement.FindName("TopBuy")
                $TopBuyGrid.ItemsSource = @($topOrders.data.buy | select @{l="name";e={$_.user.inGameName}}, platinum, quantity, @{l="status";e={$_.user.status}})
                $TopBuyGrid.Add_SelectionChanged({
                    Param(
                        [object]$sender,
                        [System.Windows.Controls.SelectionChangedEventArgs]$e
                    )
                    $row = ([System.Windows.Controls.DataGrid]$sender).SelectedCells[0].Item
                    Write-Host $row
                    Set-Clipboard "/w $($row.name) Hi, WTS $($order.item.en.item_name) for $($row.platinum)"
                    $sender.UnselectAll()
                    
                    $ModalMessageBorder.Visibility = "Hidden"
                    $ModalMessageBorder.Visibility = "Visible"
                })
                
                $InfoTextBlock = $OrderManagement.FindName("InfoTextBlock")
                $InfoTextBlock.Text = $info

                $AcceptButton = $OrderManagement.FindName("AcceptButton")
                $AcceptButton.Add_Click({
                    $body.platinum = $newPrice
                    if($body.platinum -ne $order.platinum)
                    {
                        Update-Order -orderId $order.id -body $body -Authorization $Authorization
                    }
                    $OrderManagement.Close()
                })

                $InvisibleButton = $OrderManagement.FindName("InvisibleButton")
                $InvisibleButton.Add_Click({
                    $body.visible = $false
                    Update-Order -orderId $order.id -body $body -Authorization $Authorization
                    $OrderManagement.Close()
                })

                $SkipButton = $OrderManagement.FindName("SkipButton")
                $SkipButton.Add_Click({
                    $OrderManagement.Close()
                })

                $OrderManagement.ShowDialog() | Out-Null
                ###
            }
            else
            {
                $body.platinum = $newPrice
                Update-Order -orderId $order.id -body $body -Authorization $Authorization
            }
            Start-Sleep -Milliseconds 500
        }
        $StateTextBlock.Text = "Available"
        $StateTextBlock.Foreground = "green"
    })


}

function Export-Stats([bool] $RunGui) {
    if ($RunGui) {
        $StateTextBlock.Text = "Unavailable"
        $StateTextBlock.Foreground = "red"
        [System.Windows.Forms.Application]::DoEvents()
    }
    if((Test-Path $statsPath) -and (dir $statsPath).CreationTime.Date -eq (Get-Date).Date -and $RunGui)
    {
        Get-Content $statsPath | ConvertFrom-Csv | Out-GridView
    }
    else
    {
        $stats = foreach($item in ($items | ? item_name -like "* Set"))
        {
            $setStats = (Invoke-RestMethod -Uri "$wmUri/v1/items/$($item.url_name)/statistics" -Method Get).payload.statistics_closed."48hours"
            $setData  = (Invoke-RestMethod -Uri "$wmUri/v1/items/$($item.url_name)"            -Method Get).payload.item.items_in_set
            $piecesStats = $setData | ? quantity_for_set -gt 0 | % { 
                Start-Sleep -Milliseconds 250
                $pieceStats = (Invoke-RestMethod -Uri "$wmUri/v1/items/$($_.url_name)/statistics" -Method Get).payload.statistics_closed."48hours"
                [PSCustomObject]@{
                    name = $_.en.item_name
                    avg  = ($pieceStats | measure avg_price -Average).Average * $_.quantity_for_set
                    sum  = ($pieceStats | measure volume    -Sum    ).Sum
                }
            }
            $set_avg_price  = [math]::Round(($setStats | measure avg_price -Average).Average)
            $set_pieces_avg = [math]::Round(($piecesStats | measure avg   -Sum    ).sum)
            [PSCustomObject]@{
                name              = $item.item_name
                set_avg_price     = $set_avg_price
                set_sum_volume    = ($setStats | measure volume -Sum).sum
                set_pieces_avg    = $set_pieces_avg
                set_pieces_volume = ($piecesStats | measure sum -Sum).sum
                avg_benef         = $set_avg_price - $set_pieces_avg
            }
            Start-Sleep -Milliseconds 500
        }
        #Test if the csv file exist
        if (-not (Test-Path -Path $csvPath)) {
            New-Item -ItemType Directory -Path $csvPath
        }
        $stats | ConvertTo-Csv | Out-File $statsPath
        if ($RunGui){
            $stats | Out-GridView
        }
        
    }
    if ($RunGui) {
        $StateTextBlock.Text = "Available"
        $StateTextBlock.Foreground = "green"
    }
}

if ($args -notcontains "-no-gui"){

    $SetStatsButton = $Main.FindName("SetStats")
    $SetStatsButton.Add_Click({
        Export-Stats -RunGui 1
    })
}



################## Arg pass to the program ##########################

if ($args -notcontains "-no-gui"){
    $Main.ShowDialog() | Out-Null
    Exit
}

if($args.contains(("-export-csv"))){
    Export-Stats -RunGui 0
    Exit
}