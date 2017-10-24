Param(
    [String]
    $subscriptionName,
    
    [Parameter(Mandatory=$True)]
    [String]
    $vmName = "CinebenchVM"
)

# Ask user to Login to Account
if (!($Account)) {
    Write-Host "Find the login window! :)"
    $Account = Login-AzureRmAccount
}

if ($subscriptionName) {
    $Sub = Select-AzureRmSubscription -SubscriptionName $subscriptionName
    $SubscriptionId = $sub.Subscription.id
} else {
    # Ask user to Select the Subscription
    $Subs = Get-AzureRmSubscription
    Foreach ($Sub in $Subs) {
        $Sub
        $Answer = Read-Host "Use this subscription? [Y/N]"
        if ($Answer -eq "y") {
            $Sub = Select-AzureRmSubscription -SubscriptionId $Sub.Id
            $SubscriptionId = $sub.Subscription.id
            Break
        }
    }
}

if (!($SubscriptionId)) {
    Write-Warning "No Subscription was selected"
    Exit 1
}

$vm = Get-AzureRmVm | Where-Object {$_.Name -eq $vmName}

if (!($vm)) {Write-Warning "Invalid VM" ; Exit 1}

$vmSizes = Get-AzureRmVmSize -VMName $vmName -ResourceGroupName $vm.ResourceGroupName

$vmCores = ($vmSizes | Where-Object {$_.Name -eq $vm.HardwareProfile.VmSize}).NumberOfCores
$CoreInfo = Get-AzureRmVMUsage -Location $vm.location | Where-Object {$_.Name.Value -eq "cores"}

$maxCoresInRegion = $CoreInfo.Limit - $CoreInfo.CurrentValue + $vmCores

Write-Host "$($vm.Name) can scale to a maximum of $($maxCoresInRegion) core(s) based on it's current region and subscription"

$applicableSizes = ($vmSizes | Where-Object {$_.NumberOfCores -le $maxCoresInRegion}).Name
#$applicableSizes = Get-Content sizes.txt
Write-Host "Using the following applicable sizes:" -ForegroundColor Yellow
$applicableSizes
Write-Host "Continue?"
Pause

foreach ($vmSize in $applicableSizes) {
    $vm = Get-AzureRmVm -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name
    
    Write-Host "Resizing vm $($vm.name) from size $($vm.HardwareProfile.VmSize) to $($vmSize)" -ForegroundColor Cyan
    $vm.HardwareProfile.VmSize = $vmSize

    Write-Host "Update VM"

    Update-AzureRmVM -VM $vm -ResourceGroupName $vm.ResourceGroupName -ErrorAction SilentlyContinue
    if (!($?)) {
        Write-Host "Incompatible size, Stop VM..."
        Stop-AzureRmVM -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -Force
        Write-Host "Update VM"
        Update-AzureRmVM -VM $vm -ResourceGroupName $vm.ResourceGroupName
        if (!($?)) {
            Write-Warning "Can't change VM type to $($vmSize)"
            Continue
        }
    }
    #Detect if Running
    $VMState = $VM | Get-AzureRmVm -WarningAction SilentlyContinue -Status | 
            Select-Object Name, @{n="Status"; e={$_.Statuses[1].DisplayStatus}}
    if ($VMState.Status -ne "VM Running") {
        Write-Host "Start VM"
        Start-AzureRmVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name
    }

    Write-Host "Execute Script on VM"
    . .\Push-Autobench.PS1 -vmName $vm.Name `
        -subscriptionName $Sub.Subscription.Name `
        -resourceGroupName $vm.ResourceGroupName `
        -runCount 3

}

$vm = Get-AzureRmVm -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name
Stop-AzureRmVM -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -Force