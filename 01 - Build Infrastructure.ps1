$subscr="Visual Studio Enterprise"
$labName="exhybridlab1"
$locName="EastUS"
$adVMSize="Standard_D1_v2"
$exVMSize="Standard_D3_v2"

Login-AzureRMAccount

If (Test-AzureRmDnsAvailability -DomainQualifiedName $labName -Location $locName) {

    $cred=Get-Credential -Message "Type the username and password of the local administrator account for the VMs."

    Get-AzureRmSubscription -SubscriptionName $subscr | Select-AzureRmSubscription

    Register-AzureRmResourceProvider -ProviderNamespace Microsoft.Storage
    Register-AzureRmResourceProvider -ProviderNamespace Microsoft.Network
    Register-AzureRmResourceProvider -ProviderNamespace Microsoft.Compute

    New-AzureRMResourceGroup -Name $labName -Location $locName
    New-AzureRMStorageAccount -Name $labName -ResourceGroupName $labName -Type Standard_LRS -Location $locName

    ## BUILD NETWORK
    $exSubnet=New-AzureRMVirtualNetworkSubnetConfig -Name EX2016Subnet -AddressPrefix 10.0.0.0/24
    New-AzureRMVirtualNetwork -Name EX2016Vnet -ResourceGroupName $labName -Location $locName -AddressPrefix 10.0.0.0/16 -Subnet $exSubnet -DNSServer 10.0.0.4
    $rule1 = New-AzureRMNetworkSecurityRuleConfig -Name "RDPTraffic" -Description "Allow RDP to all VMs on the subnet" -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389
    $rule2 = New-AzureRMNetworkSecurityRuleConfig -Name "ExchangeSecureWebTraffic" -Description "Allow HTTPS to the Exchange server" -Access Allow -Protocol Tcp -Direction Inbound -Priority 101 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix "10.0.0.5/32" -DestinationPortRange 443
    New-AzureRMNetworkSecurityGroup -Name EX2016Subnet -ResourceGroupName $labName -Location $locName -SecurityRules $rule1, $rule2
    $vnet=Get-AzureRMVirtualNetwork -ResourceGroupName $labName -Name EX2016Vnet
    $nsg=Get-AzureRMNetworkSecurityGroup -Name EX2016Subnet -ResourceGroupName $labName
    Set-AzureRMVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name EX2016Subnet -AddressPrefix "10.0.0.0/24" -NetworkSecurityGroup $nsg

    # Validate current list of EOP IPs at: https://technet.microsoft.com/en-us/library/dn163583(v=exchg.150).aspx
    $EOP = @("23.103.132.0/22","23.103.136.0/21","23.103.144.0/20","23.103.191.0/24","23.103.198.0/23","23.103.200.0/22","23.103.212.0/22","40.92.0.0/14","40.107.0.0/17","40.107.128.0/18","52.100.0.0/14","65.55.88.0/24","65.55.169.0/24","94.245.120.64/26","104.47.0.0/17","104.212.58.0/23","134.170.132.0/24","134.170.140.0/24","157.55.234.0/24","157.56.110.0/23","157.56.112.0/24","207.46.51.64/26","207.46.100.0/24","207.46.163.0/24","213.199.154.0/24","213.199.180.128/26","216.32.180.0/23")
    $ruleN = 102
    foreach ($IP in $EOP)
    {
        $ruleName = $IP.Replace("/","_")
        Add-AzureRmNetworkSecurityRuleConfig -NetworkSecurityGroup $nsg -Name "EOP-$ruleName" -Direction Inbound -Priority $ruleN -Access Allow -SourceAddressPrefix $IP -SourcePortRange "*" -DestinationAddressPrefix "10.0.0.5/32" -DestinationPortRange "25" -Protocol "Tcp"
        Set-AzureRmNetworkSecurityGroup -NetworkSecurityGroup $nsg
        $ruleN++
    }


    ## BUILD DOMAIN CONTROLLER VM
    New-AzureRMAvailabilitySet -Name "adAvailabilitySet" -ResourceGroupName $labName -Location $locName
    $vnet=Get-AzureRMVirtualNetwork -Name "EX2016Vnet" -ResourceGroupName $labName
    $pip = New-AzureRMPublicIpAddress -Name "adVM-PublicIP" -ResourceGroupName $labName -Location $locName -AllocationMethod "Dynamic"
    $nic = New-AzureRMNetworkInterface -Name "adVM-NIC" -ResourceGroupName $labName -Location $locName -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id -PrivateIpAddress "10.0.0.4"
    $avSet=Get-AzureRMAvailabilitySet -Name "adAvailabilitySet" -ResourceGroupName $labName 
    $vm=New-AzureRMVMConfig -VMName "adVM" -VMSize $adVMSize -AvailabilitySetId $avSet.Id
    $storageAcc=Get-AzureRMStorageAccount -ResourceGroupName $labName -Name $labName
    $vm=Set-AzureRMVMOperatingSystem -VM $vm -Windows -ComputerName "adVM" -Credential $cred -ProvisionVMAgent -EnableAutoUpdate
    $vm=Set-AzureRMVMSourceImage -VM $vm -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2012-R2-Datacenter" -Version "latest"
    $vm=Add-AzureRMVMNetworkInterface -VM $vm -Id $nic.Id
    $osDiskUri=$storageAcc.PrimaryEndpoints.Blob.ToString() + "vhds/adVM-EX2016Vnet-OSDisk.vhd"
    $vm=Set-AzureRMVMOSDisk -VM $vm -Name "adVM-EX2016Vnet-OSDisk" -VhdUri $osDiskUri -CreateOption "fromImage"
    New-AzureRMVM -ResourceGroupName $labName -Location $locName -VM $vm


    ## BUILD EXCHANGE 2016 VM
    New-AzureRMAvailabilitySet -Name "exAvailabilitySet" -ResourceGroupName $labName -Location $locName
    $vnet=Get-AzureRMVirtualNetwork -Name "EX2016Vnet" -ResourceGroupName $labName
    $pip=New-AzureRMPublicIpAddress -Name "exVM-PublicIP" -ResourceGroupName $labName -DomainNameLabel $labName -Location $locName -AllocationMethod "Dynamic"
    $nic=New-AzureRMNetworkInterface -Name "exVM-NIC" -ResourceGroupName $labName -Location $locName -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id -PrivateIpAddress "10.0.0.5"
    $avSet=Get-AzureRMAvailabilitySet -Name "exAvailabilitySet" -ResourceGroupName $labName 
    $vm=New-AzureRMVMConfig -VMName "exVM" -VMSize $exVMSize -AvailabilitySetId $avSet.Id
    $storageAcc=Get-AzureRMStorageAccount -ResourceGroupName $labName -Name $labName
    $vm=Set-AzureRMVMOperatingSystem -VM $vm -Windows -ComputerName "exVM" -Credential $cred -ProvisionVMAgent -EnableAutoUpdate
    $vm=Set-AzureRMVMSourceImage -VM $vm -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2012-R2-Datacenter" -Version "latest"
    $vm=Add-AzureRMVMNetworkInterface -VM $vm -Id $nic.Id
    $osDiskUri=$storageAcc.PrimaryEndpoints.Blob.ToString() + "vhds/exVM-EX2016Vnet-OSDisk.vhd"
    $vm=Set-AzureRMVMOSDisk -VM $vm -Name "exVM-EX2016Vnet-OSDisk" -VhdUri $osDiskUri -CreateOption "fromImage"
    New-AzureRMVM -ResourceGroupName $labName -Location $locName -VM $vm


    ## OUTPUT
    Write-Host "adVM:" (Get-AzureRMPublicIpaddress -Name "adVM-PublicIP" -ResourceGroup $labName).IpAddress
    Write-Host "exVM:" (Get-AzureRMPublicIpaddress -Name "exVM-PublicIP" -ResourceGroup $labName).IpAddress
} Else {
    Write-Host "The name $labName is not unique to Azure, please select a different name."
}