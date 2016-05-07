	param (        
        [parameter(Mandatory=$false)]
        [String]$resourceGroupName,
        [parameter(Mandatory=$false)]
        [String]$VnetResourceGroupName,
        [parameter(Mandatory=$false)]
        [String]$VnetName,
        [parameter(Mandatory=$false)]
        [String]$location,
		[parameter(Mandatory=$false)]
        [String]$AutomationAccountName,
		[parameter(Mandatory=$false)]
        [String]$AutomationResourceGroup,
		[parameter(Mandatory=$false)]
        [String]$DSCConfigurationName = "CloudyApplication.WebServer",
		[parameter(Mandatory=$false)]
        [String]$randomName,
    	[parameter(Mandatory=$false)]
		[PSCredential]$CredentialAsset,
		[parameter(Mandatory=$false)]
		[bool]$ShutDownVMsAfterCreation = $true
    )

    #Random Name that is not too long and starts with a letter that we use to name all our cattle (no pets!)
	if(!$randomName) {
		do { $randomName = [System.Guid]::NewGuid().toString().substring(0,15) -ireplace '-' }
		until ($randomName -match "(^[a-z])")
	}
	Write-Output "Random Name: $randomName"
	
	if(!$location) { $location = Get-AutomationVariable -Name 'Location' }
	if($CredentialAsset -eq $null) { $CredentialAsset = Get-AutomationPSCredential -Name 'CloudyDemosCredential' }
	$tenantId = Get-AutomationVariable -Name 'TenantId'
	$subscriptionId = Get-AutomationVariable -Name 'SubscriptionId'
	if(!$AutomationAccountName) { $AutomationAccountName = Get-AutomationVariable -Name 'AutomationAccountName' }
	if(!$AutomationResourceGroup) { $AutomationResourceGroup = Get-AutomationVariable -Name 'Automation-ResourceGroup' }
	
	# Log In to the Azure Subscription we want to add resources to
	Login-AzureRmAccount -Credential $CredentialAsset -TenantId $tenantId -SubscriptionId $subscriptionId 

	if(!$resourceGroupName) { $resourceGroupName = $randomName }
	Try {
		$resourceGroup = Get-AzureRmResourceGroup -Name $resourceGroupName -Location $location -ErrorAction Stop
		Write-Output "Using Existing Resource Group."
	} catch {
		Write-Output "Creating New Resource Group."
		New-AzureRmResourceGroup -Name $resourceGroupName -Location $location
	} 
		
	if(!$VnetResourceGroupName) { $VnetResourceGroupName = $randomName }	
	if(!$VnetName) { $VnetName = $VnetResourceGroupName + "-Network" }
	$vmSize = Get-AutomationVariable -Name 'VM-Size'
	$VMCredential = Get-AutomationPSCredential -Name 'VMAdmin'
	$HowManyVMs = Get-AutomationVariable -Name 'VMCount'
	$AvailabilitySetName = $randomName+ "-AvailabilitySet"
	$frontEndIPConfigName = $randomName+ "-Frontend"
	$LBName = $randomName + "-LoadBalancer"
	$backEndIpConfigName = $randomName+ "-Backend"
	$VMDiskStorageAccountName = $randomName + "vhds"
	$DiagnosticsStorageAccountName = $randomName + "diags"
	$pubName = "MicrosoftWindowsServer"
	$offerName = "WindowsServer"
	$skuName = "2012-R2-Datacenter"

	# Build up Tags to apply
	$Tags = New-Object System.Collections.ArrayList;
	$Tags.Add(@{ Name="created-by"; Value="Create-LoadBlanced-VMs Runbook"})
	$Tags.Add(@{ Name="environment"; Value="demo"})
	$Tags.Add(@{ Name="application"; Value="Cloudy Application"})
	$Tags.Add(@{ Name="application-version"; Value="1.0"})
	$Tags.Add(@{ Name="auto-name"; Value=$randomName })

	$ResourceGroup = Get-AzureRmResourceGroup -Name $resourceGroupName -Location $location 
	    if(!$ResourceGroup) {
			New-AzureRmResourceGroup -Name $resourceGroupName -Location $location -Tag $Tags
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
	
	Try {
		$VMDiskStorageAccount = Get-AzureRmStorageAccount  -Name $VMDiskStorageAccountName -ResourceGroupName $resourceGroupName -ErrorAction Stop
		Write-Output "Using Existing Storage Account for Disks."
	} catch {
		Write-Output "Creating New Disk  Storage Account."
		New-AzureRmStorageAccount -Name $VMDiskStorageAccountName -Location $location -Type "Standard_LRS" -ResourceGroupName $resourceGroupName -Tag $Tags -ErrorAction Stop
		$VMDiskStorageAccount = Get-AzureRmStorageAccount -Name $DiagnosticsStorageAccountName -ResourceGroupName $resourceGroupName -ErrorAction Stop
	}
	Try {
		$vnet = Get-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $VnetResourceGroupName -ErrorAction Stop
		Write-Output "Using Existing Network."
	} catch {
 		Write-Output "Creating New VNet."
		.\Create-VNet-And-Gateway.ps1 -Location $location -ResourceGroupName $VnetResourceGroupName -CredentialAsset $CredentialAsset -randomName $randomName -Tags $Tags
		$vnet = Get-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $VnetResourceGroupName -ErrorAction Stop
	}
	$VMSubnet = Get-AzureRmVirtualNetworkSubnetConfig -Name "Frontend" -VirtualNetwork $vnet -ErrorAction Stop

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
	
	Try {
		$AvailabilitySet = Get-AzureRmAvailabilitySet –Name $AvailabilitySetName –ResourceGroupName $resourceGroupName -ErrorAction Stop
		Write-Output "Using Existing Availability Set."
	} catch { 
		Write-Output "Creating New Availability Set."
		#Create Front Tier Availability Set
		$AvailabilitySet = New-AzureRmAvailabilitySet –Name $AvailabilitySetName –ResourceGroupName $resourceGroupName -Location $location -Tag $Tags -ErrorAction Stop
	}

	#Set Up Disk Encryption of VM's	
	$KeyVaultName = $randomName + "-Vault"
	Try {
		$KeyVault = Get-AzureRmKeyVault -vaultname $KeyVaultName -resourcegroup $resourceGroupName -ErrorAction Stop
		Write-Output "Using Existing KeyVault."
		
		$ADApplicationDisplayName = $randomName + "-Application"
		$ADApplicationHomePage = "http://" + $randomName
		$now = [System.DateTime]::Now
		$oneYearFromNow = $now.AddYears(1)
		$aadClientSecret = [Guid]::NewGuid()
		Try {
			$ADApplication = Get-AzureRmADApplication -IdentifierUri $ADApplicationHomePage -ErrorAction Stop
			Write-Output "Using Existing AAD Application."
		} Catch {
			Write-Output "Creating new AAD Application."
			$ADApplication = New-AzureRMADApplication -DisplayName $ADApplicationDisplayName -homepage $ADApplicationHomePage  -IdentifierUris $ADApplicationHomePage -StartDate $now -EndDate $oneYearFromNow -Password $aadClientSecret -ErrorAction Stop
			New-AzureRmADServicePrincipal -ApplicationId $ADApplication.applicationid
		}
		$aadClientID = $ADApplication.applicationid
		
		Set-AzureRmKeyVaultaccesspolicy -vaultname $KeyVaultName -resourcegroup $resourceGroupName -serviceprincipalname $aadClientID -PermissionsToSecrets all -PermissionsToKeys all 
        Set-AzureRmKeyVaultaccesspolicy -vaultname $KeyVaultName -resourcegroup $resourceGroupName -enabledfordiskencryption

		$DiskEncryptionVaultUrl = $KeyVault.vaulturi
		$KeyVaultResourceId = $KeyVault.resourceid
	
	} Catch {
		Write-Output "No  KeyVault Found - not encrypting any disks."
	}
	
	# Build VM's
	$backend= Get-AzureRmLoadBalancerBackendAddressPoolConfig -name $backEndIpConfigName -LoadBalancer $nrplb -ErrorAction Stop
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
	    New-AzureRmVM -ResourceGroupName $resourceGroupName -Location $location -VM $vm -Tag $Tags
	
	    # Kick of Encryption of the VM's. Requires a reboot - takes 15 mins or so
	    if($DiskEncryptionVaultUrl) {
			Set-AzureRmVMDiskEncryptionExtension -ResourceGroupName $resourceGroupName -VMName $vm.Name -AadClientID $aadClientID -AadClientSecret $aadClientSecret -DiskEncryptionKeyVaultUrl $DiskEncryptionVaultUrl -DiskEncryptionKeyVaultId $keyVaultResourceId -Force	
		} 
	    
	    # Register with DSC
	    Register-AzureRmAutomationDscNode -ResourceGroupName $AutomationResourceGroup -AutomationAccountName $AutomationAccountName -AzureVMName $vm.Name -AzureVMResourceGroup $resourceGroupName -AzureVMLocation $location -ConfigurationMode ApplyAndAutocorrect -RebootNodeIfNeeded $true -ActionAfterReboot ContinueConfiguration -NodeConfigurationName $DSCConfigurationName
	    
		# Shut it down
	    if($ShutDownVMsAfterCreation) { Stop-AzureRmVM -Name $vm.Name -ResourceGroupName $resourceGroupName -force }
	}
	Write-Output "Done!"