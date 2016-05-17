 param (        
        [parameter(Mandatory=$false)]
        [String]$resourceGroupName,
        [parameter(Mandatory=$false)]
        [String]$VnetResourceGroupName,
        [parameter(Mandatory=$false)]
        [String]$VnetName,
        [parameter(Mandatory=$false)]
        [String]$DSCConfigurationName = "CloudyApplication.WebServer",
        [parameter(Mandatory=$false)]
        [String]$SubnetName = "FrontEnd",
        [parameter(Mandatory=$false)]
        [bool]$ShutDownVMsAfterCreation = $false
    )

 if(!$resourceGroupName) { 
     #Random Name that is not too long and starts with a letter that we use to name all our cattle (no pets!)
     do { $randomName = [System.Guid]::NewGuid().toString().substring(0,15) -ireplace '-' }
     until ($randomName -match "(^[a-z])")
     Write-Output "Random Name: $randomName"
     $resourceGroupName = $randomName 
 } Else { 
     $randomName = $resourceGroupName
 }
 if(!$VnetResourceGroupName) { $VnetResourceGroupName = $resourceGroupName } 
 if(!$VnetName) { $VnetName = $VnetResourceGroupName + "-Network" }
 $location = Get-AutomationVariable -Name 'Location' -ErrorAction Stop
 $subscriptionId = Get-AutomationVariable -Name 'SubscriptionId' -ErrorAction Stop
 $AutomationAccountName = Get-AutomationVariable -Name 'AutomationAccountName' -ErrorAction Stop
 $AutomationResourceGroup = Get-AutomationVariable -Name 'Automation-ResourceGroup' -ErrorAction Stop
 $vmSize = Get-AutomationVariable -Name 'VM-Size' -ErrorAction Stop
 $VMCredential = Get-AutomationPSCredential -Name 'VMAdmin' -ErrorAction Stop
 $HowManyVMs = Get-AutomationVariable -Name 'VMCount' -ErrorAction Stop
 $Environment = Get-AutomationVariable -Name 'Environment' -ErrorAction Stop
 $AutomationConnection = Get-AutomationConnection -Name "AzureRunAsConnection" -ErrorAction Stop
 Try {
	 $OMSWorkspaceId= Get-AutomationVariable -Name 'OMSWorkspaceId' -ErrorAction Stop
	 $OMSWorkspaceKey= Get-AutomationVariable -Name 'OMSWorkspaceKey' -ErrorAction Stop
 } catch {}
 $AvailabilitySetName = $randomName+ "-AvailabilitySet"
 $frontEndIPConfigName = $randomName+ "-Frontend"
 $LBName = $randomName + "-LoadBalancer"
 $backEndIpConfigName = $randomName+ "-Backend"
 $VMDiskStorageAccountName = $randomName + "vhds"
 $DiagnosticsStorageAccountName = $randomName + "diags"
 $pubName = "MicrosoftWindowsServer" 
 $offerName = "WindowsServer"
 $skuName = "2012-R2-Datacenter"
 $KeyVaultName = $randomName + "-Vault"
 $ADApplicationDisplayName = $randomName + "-Application"
 $ADApplicationHomePage = "http://" + $randomName
 $AntimalwareSettingsString = '{ "AntimalwareEnabled": true,"RealtimeProtectionEnabled": true}';
 $OperationalInsightsWorkspaceName = $randomName + "-OpInsights"
 $EncryptionKeyName = $randomName + "-DiskEncryptionKey"
 $cert = Get-AutomationCertificate -Name "AzureRunAsCertificate" -ErrorAction Stop
 $thumbprint = $cert.thumbprint 
 Write-Output "Using Certificate Thumbprint: " $thumbprint 
 $certPwd = Get-AutomationVariable –Name "DiskEncryptionPassword" -ErrorAction Stop
 $kekname = $randomName + "-KeyEncryptionKey" 
  
 # Build Tags to label our resources
 $Tags = New-Object System.Collections.ArrayList;
 $Tags.Add(@{ Name="created-by"; Value="Create-LoadBlanced-VMs Runbook"})
 $Tags.Add(@{ Name="environment"; Value=$Environment})
 $Tags.Add(@{ Name="auto-name"; Value=$randomName })
 
 # Log in using Service Account
 $Conn = Get-AutomationConnection -Name "AzureRunAsConnection" -ErrorAction Stop
 Add-AzureRMAccount -ServicePrincipal -Tenant $Conn.TenantID -ApplicationId $Conn.ApplicationID -CertificateThumbprint $Conn.CertificateThumbprint -ErrorAction Stop
 Select-AzureRmSubscription -SubscriptionId $subscriptionId -ErrorAction Stop
 $aadClientID = $Conn.ApplicationID
 
 # setup anti-malware
 $allAntimalwareVersions = (Get-AzureRmVMExtensionImage -Location $location -PublisherName "Microsoft.Azure.Security" -Type "IaaSAntimalware").Version
 $AntimalwareTypeHandlerVersions = $allAntimalwareVersions[($allAntimalwareVersions.count)-1]
 $AntimalwareTypeHandlerMajorAndMinorVersions = $AntimalwareTypeHandlerVersions.split(".")
 $AntimalwareTypeHandlerMajorAndMinorVersions = $AntimalwareTypeHandlerMajorAndMinorVersions[0] + "." + $AntimalwareTypeHandlerMajorAndMinorVersions[1]
 
 Try {
  $resourceGroup = Get-AzureRmResourceGroup -Name $resourceGroupName -Location $location -ErrorAction Stop
  Write-Output "Using Existing Resource Group."
 } catch {
  Write-Output "Creating New Resource Group."
  New-AzureRmResourceGroup -Name $resourceGroupName -Location $location -ErrorAction Stop
 } 
  
 #Create Storage Accounts
 Try {
  $DiagnosticsStorageAccount = Get-AzureRmStorageAccount  -Name $DiagnosticsStorageAccountName -ResourceGroupName $resourceGroupName -ErrorAction Stop
  Write-Output "Using Existing Storage Account for Diagnostics."
 } catch {
  Write-Output "Creating New Diagnostics Storage Account."
  New-AzureRmStorageAccount -Name $DiagnosticsStorageAccountName -Location $location -Type "Standard_LRS" -ResourceGroupName $resourceGroupName  -Tag $Tags -ErrorAction Stop
  $DiagnosticsStorageAccount = Get-AzureRmStorageAccount -Name $DiagnosticsStorageAccountName -ResourceGroupName $resourceGroupName -ErrorAction Stop
 }
 
 # Try and get the Virtual Network we will use (create a new one if we can't find it)
 Try {
  $vnet = Get-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $VnetResourceGroupName -ErrorAction Stop
  Write-Output "Using Existing Network."
 } catch {
   Write-Output "Creating New VNet."
  .\Create-VNet-And-Gateway.ps1 -Location $location -ResourceGroupName $VnetResourceGroupName -randomName $randomName -Tags $Tags -CreateGateway $false
  $vnet = Get-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $VnetResourceGroupName -ErrorAction Stop
 }
 
 # Get the subnet where we will Deploy our VM's and load balancer.
 $VMSubnet = Get-AzureRmVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $vnet -ErrorAction Stop

 Try {
  $nrplb = Get-AzureRmLoadBalancer -ResourceGroupName $resourceGroupName -Name $LBName -ErrorAction Stop
  Write-Output "Using Existing LoadBalancer."
 } catch {
     # Create LB
     Write-Output "Creating New LoadBalancer."
	 $frontendIP = New-AzureRmLoadBalancerFrontendIpConfig -Name $frontEndIPConfigName -SubnetId $VMSubnet.Id
	 $LBaddresspool= New-AzureRmLoadBalancerBackendAddressPoolConfig -Name $backEndIpConfigName
	 $healthProbe = New-AzureRmLoadBalancerProbeConfig -Name "HealthProbe" -RequestPath "iisstart.htm" -Protocol http -Port 80 -IntervalInSeconds 60 -ProbeCount 2
	 $lbrule = New-AzureRmLoadBalancerRuleConfig -Name "Website" -FrontendIpConfiguration $frontendIP -BackendAddressPool $LBaddresspool -Probe $healthProbe -Protocol Tcp -FrontendPort 80 -BackendPort 80 -LoadDistribution Default
	 $nrplb = New-AzureRmLoadBalancer -ResourceGroupName $resourceGroupName -Name $LBName -Location $location -FrontendIpConfiguration $frontendIP -LoadBalancingRule $lbrule -BackendAddressPool $LBaddresspool -Probe $healthProbe -Tag $Tags -ErrorAction Stop
	 Set-AzureRmDiagnosticSetting -ResourceId $nrplb.Id -Enable $true -StorageAccountId $DiagnosticsStorageAccount.Id
 }
 $backend = Get-AzureRmLoadBalancerBackendAddressPoolConfig -name $backEndIpConfigName -LoadBalancer $nrplb -ErrorAction Stop
 
 Try {
  $AvailabilitySet = Get-AzureRmAvailabilitySet -Name $AvailabilitySetName -ResourceGroupName $resourceGroupName -ErrorAction Stop
  Write-Output "Using Existing Availability Set."
 } catch { 
  Write-Output "Creating New Availability Set."
  #Create Front Tier Availability Set
  $AvailabilitySet = New-AzureRmAvailabilitySet -Name $AvailabilitySetName -ResourceGroupName $resourceGroupName -Location $location -ErrorAction Stop
 }

 #Set Up Disk Encryption of VM's 
 try {
	$keyvault = get-azurermkeyvault -vaultname $keyvaultname -resourcegroup $resourceGroupName -ErrorAction Stop
} Catch {
	new-azurermkeyvault -vaultname $keyvaultname -location $location -ResourceGroupName $resourceGroupName
	$keyvault = get-azurermkeyvault -vaultname $keyvaultname -resourcegroup $resourceGroupName -ErrorAction Stop
	set-azurermkeyvaultaccesspolicy -vaultname $keyvaultname -resourcegroup $resourceGroupName -enabledfordiskencryption
	set-azurermkeyvaultaccesspolicy -vaultname $keyvaultname -resourcegroup $resourceGroupName -enabledfordeployment 
	set-azurermkeyvaultaccesspolicy -vaultname $keyvaultname -serviceprincipalname $aadclientid -permissionstokeys all -permissionstosecrets all -resourcegroupname $resourceGroupName
}

$diskEncryptionKeyVaultUrl = $keyvault.vaulturi
$KeyVaultResourceId = $keyvault.resourceid

Try {
	$kek = get-azurekeyvaultkey -vaultname $keyvaultname -name $kekname -ErrorAction Stop
} Catch { 
	$kek = add-azurekeyvaultkey -vaultname $keyvaultname -name $kekname -destination 'software'
}
$KeyEncryptionKeyUrl = $kek.key.kid

$bincert = $cert.Export("PFX", $certPwd)
$credvalue = [system.convert]::ToBase64String($bincert)

$jsonObject = @"
{
"data": "$credvalue",
"dataType" :"pfx",
"password": "$certPwd"
}
"@

$jsonObjectBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonObject)
$jsonEncoded = [System.Convert]::ToBase64String($jsonObjectBytes)
$secret = ConvertTo-SecureString -String $jsonEncoded -AsPlainText –Force

 # Create Storage Account. Note: If disk Encryption desired - cannot use Premium Storage.
 Try {
  $VMDiskStorageAccount = Get-AzureRmStorageAccount  -Name $VMDiskStorageAccountName -ResourceGroupName $resourceGroupName -ErrorAction Stop
  Write-Output "Using Existing Storage Account for Disks."
 } catch {
  Write-Output "Creating New Disk Storage Account."
    # Use non-premium storage.
    New-AzureRmStorageAccount -Name $VMDiskStorageAccountName -Location $location -Type "Standard_LRS" -ResourceGroupName $resourceGroupName -Tag $Tags -ErrorAction Stop
    $VMDiskStorageAccount = Get-AzureRmStorageAccount -Name $DiagnosticsStorageAccountName -ResourceGroupName $resourceGroupName -ErrorAction Stop
 }
 
 # Create OMS Account if required
 if(!$OMSWorkspaceId -and !$OMSWorkspaceKey) {
    try {
        $OperationalInsightsWorkspace = Get-AzureRmOperationalInsightsWorkspace -ResourceGroupName $resourceGroupName -Name $OperationalInsightsWorkspaceName -ErrorAction Stop
        Write-Output "Using Existing OMS Account."
   } catch {
        Write-Output "Creating New OMS Account."
        $OperationalInsightsWorkspace = New-AzureRmOperationalInsightsWorkspace -Sku standard -ResourceGroupName $resourceGroupName -Name $OperationalInsightsWorkspaceName -Location $location
    }
    $OperationalInsightsWorkspaceSharedKeys = Get-AzureRmOperationalInsightsWorkspaceSharedKeys -ResourceGroupName $resourceGroupName -Name $OperationalInsightsWorkspaceName
    $OMSWorkspaceId = $OperationalInsightsWorkspace.CustomerId.Guid.ToString()
    $OMSWorkspaceKey = $OperationalInsightsWorkspaceSharedKeys.PrimarySharedKey
}

 # Build config of VM's and NIC's
 $counter = 0
 $ArrayOfVmConfigs = @()
 do { 
  Try {
      $NicName = $randomName + "-NIC" + $counter
   
   Try {
    Write-Output "Using Existing Network Interface."
       $nic = Get-AzureRmNetworkInterface -ResourceGroupName $resourceGroupName -Name $NicName -ErrorAction Stop
   } catch {
    Write-Output "Creating New Network Interface."
       $nic = New-AzureRmNetworkInterface -ResourceGroupName $resourceGroupName -Name $NicName -Location $location -Subnet $VMSubnet -LoadBalancerBackendAddressPool $nrplb.BackendAddressPools[0] -Force -Tag $myTags -ErrorAction Stop 
   }
      Set-AzureRmNetworkInterface -NetworkInterface $nic
  
      $vmName = $randomName + "-" + $counter
      $vmConfig = New-AzureRmVMConfig -VMName $vmName -VMSize $vmSize -AvailabilitySetId $AvailabilitySet.Id
      $vmConfig = Set-AzureRmVMOperatingSystem -VM $vmConfig -Windows -ComputerName $vmName -Credential $VMCredential -ProvisionVMAgent -EnableAutoUpdate
      $vmConfig = Set-AzureRmVMSourceImage -VM $vmConfig -PublisherName $pubName -Offer $offerName -Skus $skuName -Version "latest"
      $vmConfig = Add-AzureRmVMNetworkInterface -VM $vmConfig -Id $nic.Id
      $osDiskUri = "https://" + $VMDiskStorageAccountName + ".blob.core.windows.net/vhds/" + $vmName + ".vhd"
      $vmConfig = Set-AzureRmVMOSDisk -VM $vmConfig -Name $vmName -VhdUri $osDiskUri -CreateOption fromImage
      Set-AzureRmVMBootDiagnostics -Enable -ResourceGroupName $resourceGroupName -VM $vmConfig -StorageAccountName $DiagnosticsStorageAccountName
      
      $ArrayOfVmConfigs += $vmConfig
   
  } Finally {
      $counter++
  } 
 } until ($counter -eq $HowManyVMs)

 #Create VM's
 Foreach ($vm in $ArrayOfVmConfigs){

     # Create VM
     Write-Output "Creating VM " $vm.Name
     New-AzureRmVM -ResourceGroupName $resourceGroupName -Location $location -VM $vm -Tag $Tags
 
     Write-Output "Setting Secret" $vm.Name
	 Set-AzureKeyVaultSecret -VaultName $keyVaultName -Name $vm.Name -SecretValue $secret -ErrorAction Stop
	 $encryptionCertURI = (get-azurekeyvaultsecret -vaultname $keyVaultName -Name $vm.Name -ErrorAction Stop).Id

     Write-Output "Inserting Certificate from " $encryptionCertURI
	 $vm = Get-AzureRmVM -Name $vm.Name -ResourceGroupName $resourceGroupName -ErrorAction Stop
	 Add-AzureRmVMSecret -VM $vm -sourcevaultid $KeyVaultResourceId -certificateStore "My" -CertificateURL $encryptionCertURI -ErrorAction Stop 
	 Update-AzureRmVM -ResourceGroupName $resourceGroupName -VM $vm -ErrorAction Stop

     # Kick of Encryption of the VM's. Requires a reboot - takes 15 mins or so
     Write-Output "Starting Encryption"
  	 Set-AzureRmVMDiskEncryptionExtension -ResourceGroupName $resourceGroupName -VMName $vm.Name -AadClientID $aadClientID -AadClientCertThumbprint $thumbprint -DiskEncryptionKeyVaultUrl $diskEncryptionKeyVaultUrl -DiskEncryptionKeyVaultId $KeyVaultResourceId -KeyEncryptionKeyUrl    $keyEncryptionKeyUrl -KeyEncryptionKeyVaultId $KeyVaultResourceId -Force -ErrorAction Stop
          
     # Register with DSC
     Register-AzureRmAutomationDscNode -ResourceGroupName $AutomationResourceGroup -AutomationAccountName $AutomationAccountName -AzureVMName $vm.Name -AzureVMResourceGroup $resourceGroupName -AzureVMLocation $location -ConfigurationMode ApplyAndAutocorrect -RebootNodeIfNeeded $true -ActionAfterReboot ContinueConfiguration -NodeConfigurationName $DSCConfigurationName

     # Register with Operation Insights
     if($OMSWorkspaceId -and $OMSWorkspaceKey) { 
        Set-AzureRMVMExtension -ResourceGroupName $resourceGroupName -VMName $vm.Name -Name 'MicrosoftMonitoringAgent' -Publisher 'Microsoft.EnterpriseCloud.Monitoring' -ExtensionType 'MicrosoftMonitoringAgent' -TypeHandlerVersion '1.0' -Location $location -SettingString "{'workspaceId':  '$OMSWorkspaceId'}" -ProtectedSettingString "{'workspaceKey': '$OMSWorkspaceKey' }"
     }

     #Install anti-malware
     Set-AzureRmVMExtension -ResourceGroupName $resourceGroupName -VMName $vm.Name -Name "IaaSAntimalware" -Publisher "Microsoft.Azure.Security" -ExtensionType "IaaSAntimalware" -TypeHandlerVersion $AntimalwareTypeHandlerMajorAndMinorVersions -SettingString $AntimalwareSettingsString -Location $location
     
     # Shut it down
     if($ShutDownVMsAfterCreation) { Stop-AzureRmVM -Name $vm.Name -ResourceGroupName $resourceGroupName -force }
 }
 Write-Output "Done!"