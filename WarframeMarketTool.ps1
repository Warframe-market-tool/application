Param (
    [Switch]
    $test
)

# Function to know if the execution is script or exe
function isRunningExec {
    if ([System.Diagnostics.Process]::GetCurrentProcess().ProcessName -eq 'powershell' -or 
        [System.Diagnostics.Process]::GetCurrentProcess().ProcessName -eq 'pwsh') {
        # Running as a PowerShell script
        return 0
    } else {
        # Running as an EXE, use BaseDirectory for the location of the executable
        return 1
    }
}
# Function to detect if the script is running as an executable or a PowerShell script
function Get-RootPath {
    if ([System.Diagnostics.Process]::GetCurrentProcess().ProcessName -eq 'powershell' -or 
        [System.Diagnostics.Process]::GetCurrentProcess().ProcessName -eq 'pwsh') {
        # Running as a PowerShell script
        return $PSScriptRoot
    } else {
        # Running as an EXE, use BaseDirectory for the location of the executable
        return [System.AppDomain]::CurrentDomain.BaseDirectory
    }
}

# Constants
$RootPath        = Get-RootPath
$cookieJwtPath   = "$RootPath/jwt.txt"
$orderIgnorePath = "$RootPath/.orderignore"
$wmUri           = "https://api.warframe.market"

$MainXMLPath = "$RootPath/Views/Main.xaml"
$OMXMLPath   = "$RootPath/Views/OrderManagement.xaml"

# Load the XML files
Add-Type -AssemblyName PresentationFramework
[xml]$MainXML = Get-Content $MainXMLPath
[xml]$OMXML   = Get-Content $OMXMLPath

# Functions
function Update-Order( [string]$orderId, [Hashtable]$body, [string]$authorization )
{
    Invoke-RestMethod -Uri "$wmUri/v1/profile/orders/$orderId" -Method PUT -Headers @{
        "content-type"  = "application/json; utf-8"
        "accept"        = "application/json"
	    "Authorization" = $authorization
    } -Body ($body | ConvertTo-Json) -ContentType "application/json" | Out-Null
}

function Format-Info ($orderType, $name, $newPrice, $oldPrice, $bestPrice, $average)
{
    return "You $(switch($orderType) { "sell" {"WTS"} "buy" {"WTB"}}) $name for $newPrice PL (before $oldPrice) but someone sell it for $bestPrice PL - avg : $([Math]::Round($average, 2))"
}

function Test-OrderIgnore ($url_name)
{
    return $true -notin (Get-Content $orderIgnorePath | % {$url_name -like $_})
}

# Test JWT token
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
    }
}

#Test

if($test)
{
     Write-Host "[Test] Application is running."
     exit
}

## Begin Main UI
$MainFormXML = (New-Object System.Xml.XmlNodeReader $MainXML)
$Main = [Windows.Markup.XamlReader]::Load($MainFormXML)

### Login Modal
$LogInModal = $Main.FindName("LogInModal")
$EmailTextBox = $Main.FindName("EmailTextBox")
$PasswordBox = $Main.FindName("PasswordBox")
$LogInButton = $Main.FindName("LogInButton")

if($authorization -eq "")
{
    $LogInModal.Visibility = "Visible"
}

$LoginEvent = {
    $loginResp = Invoke-WebRequest -Uri "$wmUri/v1/auth/signin" -Method Post -Headers @{
        "content-type"  = "application/json; utf-8"
        "accept"        = "application/json"
	    "Authorization" = ""
    } -Body (@{
        "email"     = $EmailTextBox.Text
        "password"  = $PasswordBox.Password
        "auth_type" = "header"
    } | ConvertTo-Json) -ContentType "application/json"

    if($loginResp -ne $null -and $loginResp.StatusCode -eq 200)
    {
        $authorization = $loginResp.Headers.Authorization
        $authorization | Out-File $cookieJwtPath
        $user          = ($loginResp.Content | ConvertFrom-Json).payload.user
        $LogInModal.Visibility = "Hidden"
    }
    else
    {
        [System.Windows.MessageBox]::Show("Email / Password are incorrect.", "Login failed", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        #exit "failed login $($loginResp.StatusCode) $($loginResp.StatusDescription)"
    }
}

$LoginEnterPressed = {
    Param ([object] $sender, [System.Windows.Input.KeyEventArgs] $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Enter)
    {
        Invoke-Command $LoginEvent
    }
}

$EmailTextBox.Add_KeyDown($LoginEnterPressed)
$PasswordBox.Add_KeyDown($LoginEnterPressed)
$LogInButton.Add_Click($LoginEvent)

### Search Bar
$items = (Invoke-RestMethod -Uri "$wmUri/v1/items" -Method Get).payload.items
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
            $itemData = (Invoke-RestMethod -Uri "$wmUri/v1/items/$url_name" -Method Get).payload.item
            if($itemData.mod_max_rank -ne $null)
            {
                $pieceStats = (Invoke-RestMethod -Uri "$wmUri/v1/items/$url_name/statistics" -Method Get).payload.statistics_closed."48hours"
                $StatsDataGrid.ItemsSource = @(
                    [PSCustomObject]@{
                        name = "$($itemData.en.item_name) rank 0"
                        avg  = [math]::Round(($pieceStats | ? mod_rank -eq 0 | measure median -Average).Average)
                        vol  = ($pieceStats | ? mod_rank -eq 0 | measure volume -Sum).Sum
                        sell = ($profileOrders.payload.sell_orders | ? {$_.item.url_name -eq $itemData.url_name} | ? mod_rank -eq 0 | select -ExpandProperty platinum) -join '-'
                        buy  = ($profileOrders.payload.buy_orders  | ? {$_.item.url_name -eq $itemData.url_name} | ? mod_rank -eq 0 | select -ExpandProperty platinum) -join '-'
                    },
                    [PSCustomObject]@{
                        name = "$($itemData.en.item_name) rank $($pieceStats.mod_max_rank)"
                        avg  = [math]::Round(($pieceStats | ? mod_rank -eq $itemData.mod_max_rank | measure median -Average).Average)
                        vol  = ($pieceStats | ? mod_rank -eq $itemData.mod_max_rank | measure volume -Sum).Sum
                        sell = ($profileOrders.payload.sell_orders | ? {$_.item.url_name -eq $itemData.url_name} | ? mod_rank -eq $itemData.mod_max_rank | select -ExpandProperty platinum) -join '-'
                        buy  = ($profileOrders.payload.buy_orders  | ? {$_.item.url_name -eq $itemData.url_name} | ? mod_rank -eq $itemData.mod_max_rank | select -ExpandProperty platinum) -join '-'
                    }
                )
            }
            else
            {
                $StatsDataGrid.ItemsSource = @(foreach($item_in_set in $itemData.items_in_set) { 
                    Start-Sleep -Milliseconds 250
                    $pieceStats = (Invoke-RestMethod -Uri "$wmUri/v1/items/$($item_in_set.url_name)/statistics" -Method Get).payload.statistics_closed."48hours"
                    [PSCustomObject]@{
                        name = $item_in_set.en.item_name
                        avg  = [math]::Round(($pieceStats | measure median -Average).Average * [math]::Max(1, $item_in_set.quantity_for_set))
                        vol  = ($pieceStats | measure volume -Sum).Sum
                        sell = ($profileOrders.payload.sell_orders | ? {$_.item.url_name -eq $item_in_set.url_name} | select -ExpandProperty platinum) -join '-'
                        buy  = ($profileOrders.payload.buy_orders  | ? {$_.item.url_name -eq $item_in_set.url_name} | select -ExpandProperty platinum) -join '-'
                    }
                })
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

### Reprice
$RepriceButton = $Main.FindName("RepriceButton")
$RepriceButton.Add_Click({
    $StateTextBlock.Text = "Unavailable"
    $StateTextBlock.Foreground = "red"
    [System.Windows.Forms.Application]::DoEvents()
    $profileOrders = Invoke-RestMethod -Uri "$wmUri/v1/profile/$($user.ingame_name)/orders" -Method Get -Headers @{
        "content-type"  = "application/json; utf-8"
        "accept"        = "application/json"
	    "Authorization" = $authorization
    }
    foreach ($order in ($profileOrders.payload.sell_orders + $profileOrders.payload.buy_orders | ? {$_.visible -eq $true -and (Test-OrderIgnore -url_name $_.item.url_name)})) {
        $body = @{
            "order_id" = $order.id
            "platinum" = $order.platinum
            "visible"  = $order.visible
        }

        $stats = (Invoke-RestMethod -Uri "$wmUri/v1/items/$($order.item.url_name)/statistics" -Method Get).payload.statistics_closed."90days"

        $topUri = "$wmUri/v2/orders/item/$($order.item.url_name)/top"
        if($order.mod_rank -ne $null)
        {
            $stats = $stats | ? mod_rank -eq $order.mod_rank
            if($order.mod_rank -eq $order.item.mod_max_rank)
            {
                $topUri += "/?maxRank=true"
            }
        }

        $topOrders = Invoke-RestMethod -Uri $topUri -Method Get -Headers @{
            "platform" = $order.platform
            "language" = $order.region
        }
        $minPercent = 0.05
        $maxPercent = 0.25
        
        $topSellOrders = $topOrders.data.sell | ? {$_.user.ingamename -ne $user.ingame_name}
        $topBuyOrders  = $topOrders.data.buy  | ? {$_.user.ingamename -ne $user.ingame_name}
        
        $medianPrice = ($stats | select -Last 1).median 
        $sumVolume   = ($stats | select -Last 1).volume  

        $bestSellPrice = $topSellOrders.platinum -gt ($medianPrice * (1 + $minPercent)) | select -First 1
        $bestBuyPrice  = $topBuyOrders.platinum  -lt ($medianPrice * (1 - $minPercent)) | select -First 1
        
        #Write-Host "a. $($order.item.en.item_name) - $bestSellPrice - $newPrice - $($bestSellOrder.platinum) $([int]$medianPrice)"
        $info = switch($order.order_type)
        {
            "sell" {
                $newPrice = $bestSellPrice - 1
                if($newPrice -gt $medianPrice * (1 + $maxPercent)) {
                    #"You WTS $($order.item.en.item_name) for $newPrice PL (before $($order.platinum)) but the average price is $([int]$medianPrice)"
                    $newPrice = [math]::Round($medianPrice * (1 + $maxPercent))
                }
                if($bestSellPrice -eq $null -or $newPrice -lt $medianPrice * (1 + $minPercent)) {
                    #"You WTS $($order.item.en.item_name) for $newPrice PL (before $($order.platinum)) but the average price is $([int]$medianPrice)"
                    $newPrice = [math]::Round($medianPrice * (1 + $minPercent))
                }
                if($newPrice -le ($topBuyOrders | select -ExpandProperty platinum -First 1)) {
                    Format-Info -orderType $_ -name $order.item.en.item_name -newPrice $newPrice -oldPrice $order.platinum -bestPrice ($topBuyOrders | select -ExpandProperty platinum -First 1) -average $medianPrice
                }
            }
            "buy" {
                $newPrice = $bestBuyPrice + 1
                if($newPrice -lt $medianPrice * (1 - $maxPercent)) {
                    #"You WTB $($order.item.en.item_name) for $newPrice PL (before $($order.platinum)) but the average price is $([int]$medianPrice)"
                    $newPrice = [math]::Round($medianPrice * (1 - $maxPercent))
                }
                if($bestBuyPrice -eq $null -or $newPrice -gt $medianPrice * (1 - $minPercent)) {
                    #"You WTS $($order.item.en.item_name) for $newPrice PL (before $($order.platinum)) but the average price is $([int]$medianPrice)"
                    $newPrice = [math]::Round($medianPrice * (1 - $minPercent))
                }
                if($newPrice -ge ($topSellOrders | select -ExpandProperty platinum -First 1)) {
                    Format-Info -orderType $_ -name $order.item.en.item_name -newPrice $newPrice -oldPrice $order.platinum -bestPrice ($topSellOrders | select -ExpandProperty platinum -First 1) -average $medianPrice
                }
            }
        }
        #Write-Host "b. $($order.item.en.item_name) - $bestSellPrice - $newPrice - $($bestSellOrder.platinum) $([int]$medianPrice)"
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
                #Write-Host $row
                Set-Clipboard "/w $($row.name) Hi, WTB $($order.item.en.item_name) for $($row.platinum) PL"
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
                #Write-Host $row
                Set-Clipboard "/w $($row.name) Hi, WTS $($order.item.en.item_name) for $($row.platinum) PL"
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

### Set Statistics
$SetStatsButton = $Main.FindName("SetStatsButton")
$SetStatsButton.Add_Click({
    $StateTextBlock.Text = "Unavailable"
    $StateTextBlock.Foreground = "red"
    [System.Windows.Forms.Application]::DoEvents()
    if ([System.Windows.Forms.MessageBox]::Show(
            "This button will show you statistics on all sets and parts in those sets.`r`nIt can take some time. Are you sure you want to continue?", 
            "Status", 
            [System.Windows.Forms.MessageBoxButtons]::YesNo, 
            [System.Windows.Forms.MessageBoxIcon]::Information) -eq [System.Windows.Forms.DialogResult]::Yes
        ) 
    {
        if (isRunningExec -eq 1) {
            # Running as an Executable
            & "$RootPath\SetsStatistics.exe" -wmUri $wmUri -RootPath $RootPath | Out-GridView
        } else {
            # Running as script
            & "$RootPath\SetsStatistics.ps1" -wmUri $wmUri -RootPath $RootPath | Out-GridView
        }
        
    }
    $StateTextBlock.Text = "Available"
    $StateTextBlock.Foreground = "green"
})

### Clipboard Buttons
$DucatsButton = $Main.FindName("OrderIgnoreButton")
$DucatsButton.Add_Click({
    if(-not (Test-Path $orderIgnorePath))
    {
        New-Item $orderIgnorePath -ItemType File
    }
    start $orderIgnorePath
})

### Set Statistics
$ThanksButton = $Main.FindName("ThanksButton")
$ThanksButton.Add_Click({
    Set-Clipboard "Thanks for the trade. If you have time, can you please leave a good comment."
})


$Main.ShowDialog() | Out-Null