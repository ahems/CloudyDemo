# Azure Automation with DSC Runbook examples

Here are some sample Azure Automation scripts. These two scripts will create and boot two clean Windows VM’s, a Load balancer to attach them to (and it will attach the VM’s to it), will configure infrastructure diagnostics, will create all the other virtual networking gear (if you haven’t created it already) from virtual NIC’s up to and including subnets and a VPN Gateway, it will put the VM’s in an “Availability Set” (for fault tolerance) and it will register the VM’s with your Automation Account once they have automatically booted. It will also encrypt the disks using BitLocker and enable Anti-virus.

The third script is used by the Automation Account to then automatically configure the two VM’s that register with it, and this example will automatically install IIS and start the default website on each VM (but obviously it can do a lot more than that). It all runs from an Azure Automation Account and most of it is configurable (you can have it build out 10 VM’s and put them behind the load balancer just by changing one variable for example). 

To try them yourself, create an Automation Account if you don’t have one already (the Free tier, the default, includes 500 minutes of script-running per month which is enough to run these scripts from beginning to end.) Make sure you do create a Service account as you will need that too log in with in these scripts.

Then, under “Assets” of your Automation Account, you need to add a “Credential” called “VMAdmin” and it’s the admin username and password for the new VM’s these scripts automatically provision.

Next, under “Variables” in your Automation Account there are these Variables that you need to create that these scripts refer to for default configuration. All are of type “String” except for “VMCount” (which is an integer). The names are hard-coded in the scripts but create them to these names and just set the values as appropriate.

1.	AutomationAccountName (The name of your Automation Account)
2.	Automation-ResourceGroup (The name of the Resource Group your Automation Account is in)
3.	Environment (this is just a label used to tag all the automatically-created resources e.g. demo, production, QA)
4.	Location (e.g. East US) – this is the Azure region to which all the Resources will get automatically deployed
5.	SubscriptionId – of the subscription you will deploy resources to
6.	VMCount – how many VM’s you want behind the Load-Balancer (e.g. 2 which is the minimum but can be 100 if you want!)
7.	VM-Size – what size VM’s would you like? E.g. “Standard_D1”
8.	VNetAddressRange – e.g. 192.168.0.0/16 (if you have not already created a VNET this example will create one using this Address Range)
9.	VNetFrontEndAddressRange – e.g. 192.168.1.0/24 (Example subnet if you have not created one already)
10.	VNetMiddleAddressRange – e.g. 192.168.2.0/24 (Example subnet if you have not created one already)
11.	VNetBackEndAddressRange – e.g. 192.168.3.0/24 (Example subnet if you have not created one already)
12.	VNetGatewayAddressRange – e.g. 192.168.4.0/24 (Example gateway subnet (and VPN Gateway) if you have not created one already)

The scripts reference a number of Azure Powershell Modules which are not installed in the Automation Accounts by default so you will need to add them under “Assets”, “Modules”, Browse Gallery” and add each of these [wish I knew a way to automate this as this step takes ages; also not all are really needed these are just all those required by the last one – AzureRm]:

•	AzureRM.Profile
•	Azure.Storage
•	AzureRM.ApiManagement
•	AzureRM.Automation
•	AzureRM.Backup
•	AzureRM.Batch
•	AzureRM.Compute
•	AzureRM.Cdn
•	AzureRM.DataFactories
•	AzureRM.DataLakeAnalytics
•	AzureRM.DataLakeStore
•	AzureRM.Dns
•	AzureRM.HDInsight
•	AzureRM.Insights
•	AzureRM.KeyVault
•	AzureRM.LogicApp
•	AzureRM.Network
•	AzureRM.NotificationHubs
•	AzureRM.OperationalInsights
•	AzureRM.RecoveryServices
•	AzureRM.RecoveryServices.Backup
•	AzureRM.RedisCache
•	AzureRM.Resources
•	AzureRM.SiteRecovery
•	AzureRM.Sql
•	AzureRM.Storage
•	AzureRM.StreamAnalytics
•	AzureRM.Tags
•	AzureRM.TrafficManager
•	AzureRM.UsageAggregates
•	AzureRM.Websites
•	AzureRM

Add the two scripts attached by selecting “Runbooks”, “Add a runbook”, “Import an existing Runbook” and import Create-VNet-And-Gateway.ps1 and Create-LoadBalanced-VMs.ps1. The latter calls the former if there is not A VNET created already. They should both appear as “New” – select each, edit, and publish to make them available to run.

Next, under “DSC Configurations”, import CloudyApplication.ps1 by selecting “Add a configuration”. Once it’s added and marked as “published”, select it from the “DSC Configurations” pane and select “Compile” which will make it available for VM’s checking in with that configuration. Once compiled you should get one example entry appear under the “DSC Node Configuration” section of your Automation Account. The scripts are configured such that all the VM’s they create will register themselves with this configuration by default.

You should then be able to select the “Runbooks” section of your Automation Account (which should have two in it now both marked as Published), select “Create-LoadBalanced-VMs” runbook and click “Start”. You will be presented with the following Parameters:

•	RESOUCEGROUPNAME – Name of the Resource Group Where you want your VM’s and Load Balancer deployed. If you leave this blank a random name will be automatically generated for you.
•	VNETRESOURCEGROUPNAME - Name of the Resource Group where you your VNET is. If you leave this blank or it doesn’t exist, one will be automatically created for you.
•	VNETNAME, Name of the VNET where you want your VM’s and load-balancer deployed to. If you leave this blank or it doesn’t exist, one will be automatically created for you.
•	DSCCONFIGURATIONNAME – this is the name of the configuration that these VM’s will all automatically configure themselves as. The default is the one in this example: “CloudyApplication.WebServer"
•	SUBNETNAME – the name of the Subnet on your VNet that you want to have your infrastructure deployed to. There is a default if you let I create the VNET for you that will work.
•	SHUTDOWNVMSAFTERCREATION – Would you like your VM’s shut own after they are created? This will save you money if you are just testing.

You can leave them all blank and just click Start in order to see it working – it will run for about an about or so and create a three-tier VNET and two VM’s in the VNET in a randomly generated Resource Group in the subscription you set the “SubscriptionID” variable of Your Automation Account to (assuming all your Variables are there and have valid values.)

Future improvements I can think of so far:
  
•	Enabling elastic auto-scaling of VMs by putting them in a Scale-Set
•	Using Choclatey to deploy some more interesting things
•	Deploying the content of a WebSite to the VM’s
•	Replacing the guts of Create-VNet-And-Gateway.ps1 and Create-LoadBalanced-VMs.ps1 with ARM template, if I can figure out a way of calling ARM templates on a private TFS repository from a Azure Automation PS Script not a public GitHub repos (as that’s easy but nobody is going to want to do that except for from Demos.)
•	Add nodes to an AD Domain

