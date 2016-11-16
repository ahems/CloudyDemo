# Three Tier IaaS Architecture Example Deployment

# Description
These template deploy a VNET with a web front end (for an Application Gateway), an Applicaiton Tier (Web servers in a scaleset, configured via DSC), a Security Tier (for a Primary and Secondary Domain Controller), a Middle Tier (for a Redis cache), a Data Tier (for a SQL Server Always-on cluster) and a Gateway subnet (for a VPN Gateway). 

## How to deploy these templates

1.	Create an Automation Account – make a note of the i) Primary Access Key and ii) URL (under “Properties”)
a.	Go to Assets, then Modules, do Browse gallery – add cChoco and xNetworking
b.	Download this file locally: 'https://github.com/ahems/CloudyDemo/blob/master/Templates/webServer.ps1
c.	Click DSC Configurations, Add – name it and add the file downloaded locally in the previous step 
d.	Once DSC Configuration has been added, select it and “Compile” it (you don’t need to wait for it)
2.	Create a new (or re-use an existing) KeyVault – make a note of it’s id from Properties (e.g. '"/subscriptions/1c3e5ae7-4995-4328-9d5d-85758464d44e/resourceGroups/myRg/providers/Microsoft.KeyVault/vaults/MyKeyVault"
a.	Create an access Policy to allow all access to Secrets for whomever you want to allow to deploy this template
b.	Create three secrets (upload options “manual”) with these names:
i.	AdministratorPassword – make this at least 12 characters, both upper and lower case and at least one special character. A GUID works well
ii.	AutomationAccountRegistrationKey – this is the Primary Access Key (i) you noted down above
iii.	AutomationAccountRegistrationUrl – this is the URL (ii) you noted down above

Once you have completed the above, you are ready to deploy the example from PowerShell ISE like so:

1.	'Login-AzureRmAccount
2.	'$resourceGroupName = "RandyRules"
3.	'New-AzureRmResourceGroup -Name $resourceGroupName -Location "East US"
4.	'$NewGUID = [system.guid]::newguid().guid
5.	'New-AzureRmResourceGroupDeployment -Verbose -Name $NewGUID -ResourceGroupName $resourceGroupName -TemplateFile "https://raw.githubusercontent.com/ahems/CloudyDemo/master/Templates/IaaSReferenceArchitecture-Parent.json" -ExistingKeyVaultId "/subscriptions/1c3e5ae7-4995-4328-9d5d-85758464d44e/resourceGroups/Randy/providers/Microsoft.KeyVault/vaults/RandysKeyVault"

It should take about 35 minutes or so. You should see the VM’s for your scaleset appear as Nodes in your Automation Account.
