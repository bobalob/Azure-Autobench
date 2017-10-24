Param(
    [String]
    $resourceGroupName="your-resourcegroup",

    #Storage account to copy the script to
    [String]
    $storageAccountName="your-storage",

    #Container to copy script to
    [String]
    $containerName="scripts",

    [String]
    $location = "West Europe",
    
    [String]
    $scriptName = "Autobench.ps1",
    
    [String]
    $subscriptionName,
    
    #Your VM Name
    [Parameter(Mandatory=$True)]
    [String]
    $vmName = "CinebenchVM",

    [int]
    $runCount = 3
)
Set-Location $PSScriptRoot

# Ask user to Login to Account
if (!($Account)) {$Account = Login-AzureRmAccount}

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

$storageAccount = Get-AzureRmStorageAccount | Where-Object {$_.StorageAccountName -eq $storageAccountName}

#Get a storage context
$Keys = Get-AzureRmStorageAccountKey -ResourceGroupName $storageAccount.ResourceGroupName `
    -Name $storageAccountName
$storageContext = New-AzureStorageContext -StorageAccountName $storageAccountName `
    -StorageAccountKey $Keys[0].Value

# Publish the user defined PowerShell script
$blob = Set-AzureStorageBlobContent -Container $containerName `
    -File ".\$($ScriptName)" -Context $storageContext -Force
Write-Host "$($scriptName) uploaded to $($blob.ICloudBlob.Uri)"

# Generate a SAS token
$sasToken = New-AzureStorageBlobSASToken -Container $containerName `
    -Blob $scriptName -Permission r `
    -ExpiryTime (Get-Date).AddHours(2.0) -Context $storageContext
$fullFileUrl = "$($blob.ICloudBlob.Uri)$($sasToken)"

$vm = Get-AzureRmVm | Where-Object {$_.Name -eq $vmName}

# Deploy
Foreach ($run in (1..$runCount)) {
    #$Broken = $False
    $dateTime = Get-Date -Format "[dd-MM-yyyy--HH-mm]"
    Write-Host "$($dateTime) Execute Script... Run $($run)"

    Write-Host "$($scriptname) -machineType $($vm.HardwareProfile.VmSize)"

    Set-AzureRmVMCustomScriptExtension -ResourceGroupName $resourceGroupName `
        -VMName $vmName -Location $location -FileUri $fullFileUrl `
        -Run $scriptName -Name "$($scriptName.Split(".")[0])-Extension" `
        -Argument "-machineType $($vm.HardwareProfile.VmSize)"
    if (!($?)) {$Broken = $true}

    Start-Sleep 10

    Write-Host "Remove Extension..."
    Remove-AzureRmVMCustomScriptExtension -ResourceGroupName $resourceGroupName `
        -VMName $vmName -Force `
        -Name "$($scriptName.Split(".")[0])-Extension"

    $dateTime = Get-Date -Format "[dd-MM-yyyy--HH-mm]"
    Write-Host "$($dateTime) Run $($run) complete"
    
    #if ($Broken) {Break}
}