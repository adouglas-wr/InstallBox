$ErrorActionPreference = "Stop"
Import-Module (Join-Path $Boxstarter.BaseDir Boxstarter.Bootstrapper\Get-PendingReboot.ps1) -global -DisableNameChecking
# # Boxstarter options
$Boxstarter.RebootOk=$true
$Boxstarter.NoPassword=$false
$Boxstarter.AutoLogin=$true


$knownPendingFileRenames = @( ("\??\" + (Join-Path $env:USERPROFILE "AppData\Local\Temp\Microsoft.PackageManagement" )))

function Clear-Known-Pending-Renames($pendingRenames, $configPendingRenames){
    $pendingRenames = $pendingRenames + $configPendingRenames
    $regKey = "HKLM:SYSTEM\CurrentControlSet\Control\Session Manager\"
    $regProperty = "PendingFileRenameOperations"
    $pendingReboot = Get-PendingReboot

    Write-Host "Current pending reboot $($pendingReboot | Out-String)"
    
    if($pendingReboot."PendFileRename"){
        $output = @();
        # TODO LINQ equivalent SelectMany etc, make more efficient as this is uglllly
        foreach($fileName in $pendingReboot.PendFileRenVal){
            foreach($split in $fileName.Split([Environment]::NewLine)){
                $exclude = $false;
                foreach($rename in $pendingRenames){
                    if($split.StartsWith($rename)){
                       $exclude = $true
                       break;
                    }
                }

                if(($exclude -eq $false) -and ![string]::IsNullOrWhiteSpace($split) -and ($output -notcontains $split)){
                    $output += $split
                }
            }
        }

        Set-ItemProperty -Path $regKey -Name $regProperty -Value ([string]::Join([Environment]::NewLine, $output))
        Write-Host "Updated pending reboot $(Get-PendingReboot | Out-String)"
    }
}

function Install-From-Process ($packageName, $silentArgs, $filePath, $validExitCodes = @( 0)){
    Write-Host "Installing $($packageName)"
    $expandedFilePath = Expand-String $filePath
    $expandedSilentArgs = Expand-String $silentArgs;

    $process = Start-Process $expandedFilePath $expandedSilentArgs -NoNewWindow -Wait -PassThru
    if($validExitCodes -notcontains $process.ExitCode){
        Write-Error "Process $($filePath) returned invalid exit code $($process.ExitCode)"
        Write-Error "Package $($packageName) was not installed correctly"   
    }else{
        Write-Host "Package $($packageName) was successfully installed"
    }
}

function Install-Local-Packages ($packages, $installedPackages){
    foreach ($package in $packages) {
        if($installedPackages -like "*$($package.name)*"){
            Write-Warning "Package $($package.name) already installed"
        }else{
            $expandedArgs = Expand-String $package.args
            $expandedPath = Expand-String $package.path
            Install-From-Process $package.name $expandedArgs $expandedPath $package.validExitCodes
        }
    }
}

function Install-Choco-Packages ($packages, $ignorechecksums){
    foreach ($package in $packages) {
        cinst $package --ignorechecksums:$ignorechecksums
    }
}

function Install-Windows-Features ($packages){
    foreach ($package in $packages) {
        cinst $package -Source windowsfeatures
    }
}

function Copy-Configs ($packages){
    foreach ($package in $packages) {
        $source = Expand-String $package.source
        $destination = Expand-String $package.destination

        Write-Host "Copying configs for $($package.name)"
        
        Restore-Folder-Structure $destination
        if($package.deleteIfExists -and (Test-Path $destination)) {
            cmd /c rmdir /s /q $destination
        }

        if($package.symlink){
            New-Directory-Symlink $source $destination
        }else{
            Copy-Item $source $destination -Recurse -Force
        }

        Write-Host "Config copied"
    }
}

function New-TaskBar-Items ($packages){
    foreach ($package in $packages) {
        $path = Expand-String $package.path
        Write-Host "Pinning $($package.name)"
        Install-ChocolateyPinnedTaskBarItem $path
        Write-Host "Item pinned"
    }
}

function Invoke-Custom-Scripts ($scripts) {
    foreach ($script in $scripts) {
        Write-Host "Abount to run custom script $($script.name)"
        Invoke-Expression $script.value
        Write-Host "Finished running $($script.name) script"        
    }
}

function Restore-Folder-Structure ($path){
    if(!(Test-Path $path)){
        New-Item -ItemType Directory -Path $path
    }
}

function Disable-Power-Saving() {
    powercfg -change -standby-timeout-ac 0
    powercfg -change -standby-timeout-dc 0
    powercfg -hibernate off
}

function New-Directory-Symlink ($source,$destination){
    cmd /c mklink /D $destination $source
}

function Expand-String($source){
    return $ExecutionContext.InvokeCommand.ExpandString($source)
}

function Write-Step($message) {
    Write-Host $message -ForegroundColor Green
}

#[environment]::SetEnvironmentVariable("BoxstarterConfig","E:\\OneDrive\\Configs\\Boxstarter\\config.json", "Machine")

$installedPrograms = Get-Package -ProviderName Programs | select -Property Name
$config = Get-Content ([environment]::GetEnvironmentVariable("BoxstarterConfig","Machine")) -Raw  | ConvertFrom-Json
if($config -eq $null){
    throw "Unable to load config file"
}

$ErrorActionPreference = "Continue"

Write-Step "Config file loaded $($config | Out-String)"

Write-Step "Abount to clean known pending renames"
Clear-Known-Pending-Renames $knownPendingFileRenames $config.pendingFileRenames
Write-Step "Pending renames cleared"

Write-Step "Abount to disable power saving mode"
Disable-Power-Saving
Write-Step "Power saving mode disabled"

Write-Step "About to install choco packages"
Install-Choco-Packages $config.chocolateyPackages $config.ignoreChecksums
Write-Step "Choco packages installed"

refreshenv

Write-Step "About to install windows features"
Install-Windows-Features $config.windowsFeatures
Write-Step "Windows features installed"

Write-Step "About to install local packages"
Install-Local-Packages $config.localPackages $installedPrograms
Write-Step "Local packages installed"

Write-Step "About to run custom scripts"
Invoke-Custom-Scripts $config.customScripts
Write-Step "Custom scripts run";

Write-Step "About to copy configs"
Copy-Configs $config.configs
Write-Step "Configs copied"

Write-Step "About to pin taskbar items"
New-TaskBar-Items $config.taskBarItems
Write-Step "Taskbar items pinned"

if($config.installWindowsUpdates){
    Write-Step "About to install windows updates"
    Install-WindowsUpdate -Full -SuppressReboots
    Write-Step "Windows updates installed"
}

