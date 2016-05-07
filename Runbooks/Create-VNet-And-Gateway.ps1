param (        
        [parameter(Mandatory=$false)]
        [String]$resourceGroupName,
        
        [parameter(Mandatory=$false)]
        [String]$location,

        [parameter(Mandatory=$false)]
        [String]$randomName,

        [parameter(Mandatory=$false)]
        [PSCredential]$CredentialAsset,

        [parameter(Mandatory=$false)]
        [System.Collections.ArrayList]$Tags
)

#Random Name that is not too long and starts with a letter that we use to name all our cattle (no pets!)
if(!$randomName) {
do { $randomName = [System.Guid]::NewGuid().toString().substring(0,15) -ireplace '-' }
until ($randomName -match "(^[a-z])")
}
Write-Output "Random Name: $randomName"
$Environment = Get-AutomationVariable -Name 'Environment'

if(!$Tags) {
$Tags = New-Object System.Collections.ArrayList;
$Tags.Add(@{ Name="created-by"; Value="Create-VNet-AndGateway Runbook"})
$Tags.Add(@{ Name="environment"; Value=$Environment })
$Tags.Add(@{ Name="application"; Value="Cloudy Application"})
$Tags.Add(@{ Name="application-version"; Value="1.0"})
$Tags.Add(@{ Name="auto-name"; Value=$randomName })
}

if(!$location) { $location = Get-AutomationVariable -Name 'Location' }
if($CredentialAsset -eq $null) { $CredentialAsset = Get-AutomationPSCredential -Name 'CloudyDemosCredential' }
$subscriptionId = Get-AutomationVariable -Name 'SubscriptionId'

# Log In to the Azure Subscription we want to add resources to
Login-AzureRmAccount -Credential $CredentialAsset -SubscriptionId $subscriptionId 

if(!$resourceGroupName) { $resourceGroupName = $randomName }
Try {
$resourceGroup = Get-AzureRmResourceGroup -Name $resourceGroupName -Location $location -ErrorAction Stop
Write-Output "Using Existing Resource Group."
} catch {
Write-Output "Creating New Resource Group."
New-AzureRmResourceGroup -Name $resourceGroupName -Location $location -Tag $Tags
} 

# Virtual Network Params
$vnetName = $resourceGroupName + "-Network"
$vnetAddressRange = Get-AutomationVariable -Name 'VNetAddressRange'
$FrontEndAddressPrefix = Get-AutomationVariable -Name 'VNetFrontEndAddressRange'
$MiddleTierAddressPrefix = Get-AutomationVariable -Name 'VNetMiddleAddressRange'
$BackEndAddressPrefix = Get-AutomationVariable -Name 'VNetBackEndAddressRange'
$GatewaySubnetAddressPrefix = Get-AutomationVariable -Name 'VNetGatewayAddressRange'

$GWName = $vnetName + "-Gateway"
$GWIPName = "GatewayIP"
$GWIPconfName = "GatewayIPCOnfig"
$P2SRootCertName = "VPNCertificate.cer"
$GWDNSName = $randomName
$DiagnosticsStorageAccountName = $GWDNSName + "diags"
$GWPublicIpAddressName = $GWName + "-PublicIP"

#Create Some Rules...
$FrontEnd_HTTP_rule = New-AzureRmNetworkSecurityRuleConfig -Name frontend-rule -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix $VPNClientAddressPool -SourcePortRange * -DestinationAddressPrefix $FrontEndAddressPrefix -DestinationPortRange 80  -ErrorAction Stop
$MiddleTier_HTTP_rule = New-AzureRmNetworkSecurityRuleConfig -Name middletier-rule -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix $FrontEndAddressPrefix -SourcePortRange * -DestinationAddressPrefix $MiddleTierAddressPrefix -DestinationPortRange 80 -ErrorAction Stop
$Backend_DB_Rule = New-AzureRmNetworkSecurityRuleConfig -Name backtier-rule -Access Allow -Protocol Tcp -Direction Inbound -Priority 103 -SourceAddressPrefix $MiddleTierAddressPrefix -SourcePortRange * -DestinationAddressPrefix $BackEndAddressPrefix -DestinationPortRange 1433 -ErrorAction Stop
$RDPFromVPNClientsRule = New-AzureRmNetworkSecurityRuleConfig -Name rdp-rule -Access Allow -Protocol Tcp -Direction Inbound -Priority 200 -SourceAddressPrefix $VPNClientAddressPool -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389 -ErrorAction Stop
$BlockVnetInBound = New-AzureRmNetworkSecurityRuleConfig -Name blockVnets-rule -Access Deny -Protocol * -Direction Inbound -Priority 1000 -SourceAddressPrefix "VirtualNetwork" -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange * -ErrorAction Stop

# Build the Network Security Groups...
$NSGFrontEnd = New-AzureRmNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $location -Name NSG-FrontEnd -SecurityRules $RDPFromVPNClientsRule,$FrontEnd_HTTP_rule, $BlockVnetInBound -Tag $Tags -ErrorAction Stop
$NSGMiddleTier = New-AzureRmNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $location -Name NSG-MiddleTier -SecurityRules $RDPFromVPNClientsRule,$MiddleTier_HTTP_rule, $BlockVnetInBound -Tag $Tags -ErrorAction Stop
$NSGBackEnd = New-AzureRmNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $location -Name NSG-Backnet -SecurityRules $RDPFromVPNClientsRule,$Backend_DB_Rule, $BlockVnetInBound -Tag $Tags -ErrorAction Stop
$NSGGateway = New-AzureRmNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $location -Name NSG-GW -ErrorAction Stop

# Add a Storage Account to Store Diagnostics from each NSG in
Try {
$DiagnosticsStorageAccount = Get-AzureRmStorageAccount  -Name $DiagnosticsStorageAccountName -ResourceGroupName $resourceGroupName -ErrorAction Stop
Write-Output "Using Existing Storage Account."
} catch {
Write-Output "Creating New Diagnostics Storage Account."
New-AzureRmStorageAccount -Name $DiagnosticsStorageAccountName -Location $location -Type "Standard_LRS" -ResourceGroupName $resourceGroupName -Tag $Tags -ErrorAction Stop
$DiagnosticsStorageAccount = Get-AzureRmStorageAccount  -Name $DiagnosticsStorageAccountName -ResourceGroupName $resourceGroupName -ErrorAction Stop
}

# Set Diagnotsics using storage account
Write-Output "Setting Diagnostics on NSG's."
Set-AzureRmDiagnosticSetting -ResourceId $NSGFrontEnd.Id -Enable $true -StorageAccountId $DiagnosticsStorageAccount.Id -ErrorAction Stop
Set-AzureRmDiagnosticSetting -ResourceId $NSGMiddleTier.Id -Enable $true -StorageAccountId $DiagnosticsStorageAccount.Id -ErrorAction Stop
Set-AzureRmDiagnosticSetting -ResourceId $NSGBackEnd.Id -Enable $true -StorageAccountId $DiagnosticsStorageAccount.Id -ErrorAction Stop
Set-AzureRmDiagnosticSetting -ResourceId $NSGGateway.Id -Enable $true -StorageAccountId $DiagnosticsStorageAccount.Id -ErrorAction Stop

Write-Output "Creating Subnets."
$FrontEndSubnet = New-AzureRmVirtualNetworkSubnetConfig -Name "FrontEnd" -AddressPrefix $FrontEndAddressPrefix -NetworkSecurityGroupId $NSGFrontEnd.Id -ErrorAction Stop
$MiddleTierSubnet = New-AzureRmVirtualNetworkSubnetConfig -Name "MiddleTier" -AddressPrefix $MiddleTierAddressPrefix -NetworkSecurityGroupId $NSGMiddleTier.Id -ErrorAction Stop
$BackendSubnet = New-AzureRmVirtualNetworkSubnetConfig -Name "BackEnd" -AddressPrefix $BackEndAddressPrefix -NetworkSecurityGroupId $NSGBackEnd.Id -ErrorAction Stop
$GatewaySubnet = New-AzureRmVirtualNetworkSubnetConfig -Name "GatewaySubnet" -AddressPrefix $GatewaySubnetAddressPrefix -NetworkSecurityGroupId $NSGGateway.Id -ErrorAction Stop

Write-Output "Creating VNET."
New-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $resourceGroupName -Location $location -AddressPrefix $vnetAddressRange -Subnet $FrontEndSubnet, $MiddleTierSubnet, $BackendSubnet, $GatewaySubnet -Tag $Tags -ErrorAction Stop
$vnet = Get-AzureRmVirtualNetwork -ResourceGroupName $resourceGroupName -Name $vnetName
$GatewaySubnet = Get-AzureRmVirtualNetworkSubnetConfig -Name "GatewaySubnet" -VirtualNetwork $vnet -ErrorAction Stop

#Create a point to site Gateway
Write-Output "Creating Gateway."
#Create Public IP Address for Gateway
$GatewayPiP = New-AzureRmPublicIpAddress -Name $GWPublicIpAddressName -ResourceGroupName $resourceGroupName -Location $location -AllocationMethod Dynamic -DomainNameLabel $GWDNSName -Tag $Tags 
$ipconf = New-AzureRmVirtualNetworkGatewayIpConfig -Name $GWIPconfName -Subnet $GatewaySubnet -PublicIpAddress $GatewayPiP -ErrorAction Stop

New-AzureRmVirtualNetworkGateway -Name $GWName -ResourceGroupName $resourceGroupName -Location $location -IpConfigurations $ipconf -GatewayType Vpn -VpnType RouteBased -EnableBgp $false -GatewaySku Basic -Tag $Tags -ErrorAction Stop

Write-Output "Create-VNet-And-Gateway Runbook has completed."
