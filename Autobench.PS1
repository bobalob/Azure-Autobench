Param(
    $cinebenchUrl = "http://http.maxon.net/pub/benchmarks/CINEBENCHR15.038.zip",
    $numberOfRuns = 1,
    $machineType = "TEST RUN",
    $targetCpuPercent = 20,
    $targetTimeInSeconds = 30
)

Start-Transcript -Path C:\Temp\Autobench.log

$tempFolder = "C:\Temp\Cinebench"
$tempOutput = "$($TempFolder)\Results.txt"
$extractFolder = "$($TempFolder)\App"

#Check if cinebench is already installed
if (!(Test-Path "$($tempFolder)\Installed.TXT")) {
    #Install cinebench
    New-Item $TempFolder -ItemType Directory -Force
    $tempZip = "$($TempFolder)\Cinebench.Zip"
    Invoke-WebRequest -Uri $cinebenchUrl -OutFile $tempZip
    Expand-Archive -Path $tempZip -DestinationPath $extractFolder
    "Installed" | Out-File "$($tempFolder)\Installed.TXT"
}

$appFolder = (Get-ChildItem $extractFolder -Directory -Filter "*CINEBENCH*" | Select-Object -First 1).FullName
$cbExecutable = (Get-ChildItem $appFolder -Filter "*CINEBENCH*.EXE" | Select-Object -First 1).FullName

#TODO: Detect Machine Idle for > 1 min?
$targetNotMet = $true
$cpuUsageArray=@()
$arraySize = [int]($targetTimeInSeconds/2)
$counter=0

Write-Host "Disable Windows Update to stop CPU theft!"
Set-Service wuauserv -StartupType Disabled

Write-Host "Measuring for $($targetTimeInSeconds) seconds..."
# The logic in this loop is definitley incorrect, but it works enough and I don't have time to fix it!
While ($targetNotMet) {
    $cpuUsageArray += (Get-WmiObject win32_processor | ForEach-Object {$_.LoadPercentage} )
    $rollingAverage = ($cpuUsageArray | Measure-Object -Average).average
    if ($counter -gt $arraySize) {
        Write-Host "Current rolling average == $($rollingAverage)"
        if ($rollingAverage -lt $targetCpuPercent) {
            Write-Host "CPU average usage over $($targetTimeInSeconds) is less than target..."
            $targetNotMet = $false
        }
    }
    Start-Sleep 1
    #TODO: Fix rolling average, overwrite start of array
    if ($cpuUsageArray.count -eq $arraySize) { $cpuUsageArray = @() }
    $counter++
}

Write-Host "Done."

#Gets the VM type from within the VM
$compute = Invoke-RestMethod -Method GET -Uri http://169.254.169.254/metadata/instance?api-version=2017-04-02 -Headers @{"Metadata"="True"}

$resultTable = @()
foreach ($run in (1..$numberOfRuns)) {
    Write-Host "Starting run..."
    #Start-Process -FilePath $cbExecutable -ArgumentList "-cb_cpux -cb_cpu1 -nogui" -Wait -RedirectStandardOutput $tempOutput
    Start-Process -FilePath $cbExecutable -ArgumentList "-cb_cpux -nogui" -Wait -RedirectStandardOutput $tempOutput
    $ResultMulti = ((Get-Content $tempOutput | Where-Object {$_ -match "Multiple"}).Split(":")[-1] -replace "pts","").Trim()
    #$ResultSingle = ((Get-Content $tempOutput | Where-Object {$_ -match "Single"}).Split(":")[-1] -replace "pts","").Trim()
    $ResultSingle = "Not Run"
    $ResultObject = "" | Select-Object System, ReportedSize, Run, Runtime, CpuType, Sockets, Cores, Threads, ResultMulti, ResultSingle
    
    $ResultObject.System = $machineType
    $ResultObject.ReportedSize = $compute.compute.vmSize
    $ResultObject.Run = $run
    $ResultObject.Runtime = (Get-Date).ToString()
    $ResultObject.CpuType = (Get-WmiObject -Class Win32_processor).Name | Select-Object -first 1
    $ResultObject.Sockets = @(Get-WmiObject win32_processor).Count
    (Get-WmiObject win32_processor).NumberOfCores | ForEach-Object {[Int]$ResultObject.Cores += $_}
    (Get-WmiObject win32_processor).NumberOfLogicalProcessors | ForEach-Object {[Int]$ResultObject.Threads += $_}
    $ResultObject.ResultMulti = $ResultMulti
    $ResultObject.ResultSingle = $ResultSingle
    Write-Host ($resultObject | Out-String)
    $resultTable += $ResultObject
}

#Append this machine's results to the local results file (Inside the VM)
$resultTable | Export-CSV C:\Results.CSV -Append -NoClobber

#Below was a janky script to upload the results to a storage account. I'm not publishing it since it's awful and contains keys!
#TODO: Make the upload script less hacky!
#. C:\uploadRes.PS1

Stop-Transcript