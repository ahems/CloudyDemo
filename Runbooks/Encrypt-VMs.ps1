$resourceGroupName = "ea175790201b4"
$vmname = "ea175790201b4-0"
$keyvaultname = "ea175790201b4-KeyVault"

$location = Get-AutomationVariable -Name 'Location' -ErrorAction Stop
 $subscriptionId = Get-AutomationVariable -Name 'SubscriptionId' -ErrorAction Stop

 $Conn = Get-AutomationConnection -Name "AzureRunAsConnection" 
 Add-AzureRMAccount -ServicePrincipal -Tenant $Conn.TenantID -ApplicationId $Conn.ApplicationID -CertificateThumbprint $Conn.CertificateThumbprint
 Select-AzureRmSubscription -SubscriptionId $subscriptionId
$aadClientID = $Conn.ApplicationID
$cert = Get-AutomationCertificate -Name "DiskEncryption" -ErrorAction Stop
$thumbprint = $cert.thumbprint

try {
	$keyvault = get-azurermkeyvault -vaultname $keyvaultname -resourcegroup $resourceGroupName -ErrorAction Stop
} Catch {
	new-azurermkeyvault -vaultname $keyvaultname -location $location -ResourceGroupName $resourceGroupName
	$keyvault = get-azurermkeyvault -vaultname $keyvaultname -resourcegroup $resourceGroupName -ErrorAction Stop
}
set-azurermkeyvaultaccesspolicy -vaultname $keyvaultname -resourcegroup $resourceGroupName -enabledfordiskencryption
set-azurermkeyvaultaccesspolicy -vaultname $keyvaultname -resourcegroup $resourceGroupName -enabledfordeployment 
set-azurermkeyvaultaccesspolicy -vaultname $keyvaultname -serviceprincipalname $aadclientid -permissionstokeys all -permissionstosecrets all -resourcegroupname $resourceGroupName

$diskEncryptionKeyVaultUrl = $keyvault.vaulturi
$KeyVaultResourceId = $keyvault.resourceid

$kekname = 'keyencryptionkey'
$kek = add-azurekeyvaultkey -vaultname $keyvaultname -name $kekname -destination 'software'
$KeyEncryptionKeyUrl = $kek.key.kid

$bincert = $cert.getrawcertdata()
$credvalue = [system.convert]::ToBase64String($bincert)
$certPwd = Get-AutomationVariable –Name 'DiskEncryptionPassword'

$jsonObject = @"
{
"data": "$credvalue",
"dataType" :"pfx",
"password": "$plaintextPassword"
}
"@

$jsonObjectBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonObject)
$jsonEncoded = [System.Convert]::ToBase64String($jsonObjectBytes)

$secret = ConvertTo-SecureString -String $jsonEncoded -AsPlainText –Force
Set-AzureKeyVaultSecret -VaultName $keyVaultName -Name $vmname -SecretValue $secret 
$encryptionCertURI = (get-azurekeyvaultsecret -vaultname $keyVaultName -Name $vmname -ErrorAction Stop).Id

$vm = Get-AzureRmVm -Name $vmname -resourcegroup $resourceGroupName -ErrorAction Stop
add-azurermvmsecret -VM $vm -sourcevaultid $KeyVaultResourceId -certificateStore "My" -CertificateURL $encryptionCertURI -ErrorAction Stop
update-azurermvm -resourcegroupname $resourceGroupName -vm $vm -ErrorAction Stop

Set-AzureRmVMDiskEncryptionExtension -ResourceGroupName $resourceGroupName -VMName $vmname -AadClientID $aadClientID -AadClientCertThumbprint $thumbprint -DiskEncryptionKeyVaultUrl $diskEncryptionKeyVaultUrl -DiskEncryptionKeyVaultId $KeyVaultResourceId -KeyEncryptionKeyUrl $keyEncryptionKeyUrl -KeyEncryptionKeyVaultId $KeyVaultResourceId -Force -ErrorAction Stop