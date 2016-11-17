# Three Tier IaaS Architecture Example Deployment

These template deploy a VNET with a web front end (for an Application Gateway), an Applicaiton Tier (Web servers in a scaleset, configured via DSC), a Security Tier (for a Primary and Secondary Domain Controller), a Middle Tier (for a Redis cache), a Data Tier (for a SQL Server Always-on cluster) and a Gateway subnet (for a VPN Gateway). 

## How to deploy these templates

0.	Create an Automation Account – make a note of the i) Primary Access Key and ii) URL (under “Properties”)
  00.	Go to Assets, then Modules, do Browse gallery – add cChoco and xNetworking
  00.	Download this file locally: https://github.com/ahems/CloudyDemo/blob/master/Templates/webServer.ps1
  00.	Click DSC Configurations, Add – name it and add the file downloaded locally in the previous step 
  00.	Once DSC Configuration has been added, select it and “Compile” it (you don’t need to wait for it)
0.	Create a new (or re-use an existing) KeyVault – make a note of it’s id from Properties (e.g. "/subscriptions/1c3e5ae7-4995-4328-9d5d-85758464d44e/resourceGroups/myRg/providers/Microsoft.KeyVault/vaults/MyKeyVault")
  00.	Create an access Policy to allow all access to Secrets for whomever you want to allow to deploy this template
  00.	Create three secrets (upload options “manual”) with these names:
    000.	AdministratorPassword – make this at least 12 characters, both upper and lower case and at least one special character. A GUID works well
    000.	AutomationAccountRegistrationKey – this is the Primary Access Key (i) you noted down above
    000.	AutomationAccountRegistrationUrl – this is the URL (ii) you noted down above

Once you have completed the above, you are ready to deploy the example from PowerShell ISE like so:

*	Login-AzureRmAccount
*	$resourceGroupName = "MyRg"
*	New-AzureRmResourceGroup -Name $resourceGroupName -Location "East US"
*	$NewGUID = [system.guid]::newguid().guid
*	New-AzureRmResourceGroupDeployment -Verbose -Name $NewGUID -ResourceGroupName $resourceGroupName -TemplateFile "https://raw.githubusercontent.com/ahems/CloudyDemo/master/Templates/IaaSReferenceArchitecture-Parent.json" -ExistingKeyVaultId "/subscriptions/1c3e5ae7-4995-4328-9d5d-85758464d44e/resourceGroups/MyRg/providers/Microsoft.KeyVault/vaults/RandysKeyVault"

It should take about 35 minutes or so. You should see the VM’s for your scaleset appear as Nodes in your Automation Account.

# Next Steps
* To Make the Web Servers install your own application, COnsider using Chocolatey: https://docs.microsoft.com/en-us/azure/automation/automation-dsc-cd-chocolatey
