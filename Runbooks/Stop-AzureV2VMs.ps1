<#
.SYNOPSIS
  Connects to Azure and stops of all VMs in the specified Azure subscription or resource group

.DESCRIPTION
  This runbook connects to Azure and stops all VMs in an Azure subscription or resource group.  
  You can attach a schedule to this runbook to run it at a specific time. Note that this runbook does not stop
  Azure classic VMs. Use https://gallery.technet.microsoft.com/scriptcenter/Stop-Azure-Classic-VMs-7a4ae43e for that.

  REQUIRED AUTOMATION ASSETS
  1. An Automation variable asset called "SubscriptionId" that contains the GUID for this Azure subscription.  
     To use an asset with a different name you can pass the asset name as a runbook input parameter or change the default value for the input parameter.
  2. An Automation Connection asset called "AzureRunAsConnection" to use to connect to a subscription. This is created automatically when a Automation Account is created and this option is checked. 
  
.PARAMETER AzureCredentialAssetName
   Optional with default of "AzureCredential".
   The name of an Automation credential asset that contains the Azure AD user credential with authorization for this subscription. 
   To use an asset with a different name you can pass the asset name as a runbook input parameter or change the default value for the input parameter.

.PARAMETER AzureSubscriptionIdAssetName
   Optional with default of "SubscriptionId".
   The name of An Automation variable asset that contains the GUID for this Azure subscription.
   To use an asset with a different name you can pass the asset name as a runbook input parameter or change the default value for the input parameter.

.PARAMETER ResourceGroupName
   Optional
   Allows you to specify the resource group containing the VMs to stop.  
   If this parameter is included, only VMs in the specified resource group will be stopped, otherwise all VMs in the subscription will be stopped.  

.NOTES
   AUTHOR: Adam Hems 
   LASTEDIT: May 25, 2016
#>

param (
        
    [Parameter(Mandatory=$false)]
    [String] $AzureSubscriptionIdAssetName = 'SubscriptionId',

    [Parameter(Mandatory=$false)] 
    [String] $ResourceGroupName
)

# Returns strings with status messages
[OutputType([String])]

# Connect to Azure and select the subscription to work against
#$Cred = Get-AutomationPSCredential -Name $AzureCredentialAssetName -ErrorAction Stop
#$null = Add-AzureRmAccount -Credential $Cred -ErrorAction Stop -ErrorVariable err

$SubId = Get-AutomationVariable -Name $AzureSubscriptionIdAssetName -ErrorAction Stop

# Log in using Service Account
$Conn = Get-AutomationConnection -Name "AzureRunAsConnection" -ErrorAction Stop -ErrorVariable err
Add-AzureRMAccount -ServicePrincipal -Tenant $Conn.TenantID -ApplicationId $Conn.ApplicationID -CertificateThumbprint $Conn.CertificateThumbprint -ErrorAction Stop -ErrorVariable err
Select-AzureRmSubscription -SubscriptionId $SubId -ErrorAction Stop -ErrorVariable err
 
if($err) {
	throw $err
}

# If there is a specific resource group, then get all VMs in the resource group,
# otherwise get all VMs in the subscription.
if ($ResourceGroupName) 
{ 
	$VMs = Get-AzureRmVM -ResourceGroupName $ResourceGroupName
}
else 
{ 
	$VMs = Get-AzureRmVM
}

# Stop each of the VMs
foreach ($VM in $VMs)
{
	$StopRtn = $VM | Stop-AzureRmVM -Force -ErrorAction Continue

	if ($StopRtn.Status -ne 'Succeeded')
	{
		# The VM failed to stop, so send notice
        Write-Output ($VM.Name + " failed to stop")
        Write-Error ($VM.Name + " failed to stop. Error was:") -ErrorAction Continue
		Write-Error (ConvertTo-Json $StopRtn.Error) -ErrorAction Continue
	}
	else
	{
		# The VM stopped, so send notice
		Write-Output ($VM.Name + " has been stopped")
	}
}