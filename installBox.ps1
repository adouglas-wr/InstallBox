$ErrorActionPreference = "Stop"
# Boxstarter options
# $Boxstarter.RebootOk=$true # Allow reboots?
# $Boxstarter.NoPassword=$false # Is this a machine with no login password?
# $Boxstarter.AutoLogin=$true # Save my password securely and auto-login after a reboot

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
            Write-Host "Package $($package.name) already installed"
        }else{
            $expandedArgs = Expand-String $package.args
            $expandedPath = Expand-String $package.path
            Install-From-Process $package.name $expandedArgs $expandedPath $package.validExitCodes
        }
    }
}

function Install-Choco-Packages ($packages){
    foreach ($package in $packages) {
        cinst $package
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
            Copy-Item $source $destination -Recurse
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

function Restore-Folder-Structure ($path){
    if(!(Test-Path $path)){
        New-Item -ItemType Directory -Path $path
    }
}

function New-Directory-Symlink ($source,$destination){
    cmd /c mklink /D $destination $source
}

function Expand-String($source){
    return $ExecutionContext.InvokeCommand.ExpandString($source)
}

#just for test
[environment]::SetEnvironmentVariable("BoxstarterConfig","E:\\Tomek\\Programowanie\\Github\\Boxstarter\\config.json","Machine")

$installedPrograms = Get-Package -ProviderName Programs | select -Property Name
$config = Get-Content ([environment]::GetEnvironmentVariable("BoxstarterConfig","Machine")) -Raw  | ConvertFrom-Json

Write-Host "Config file loaded $($config)"

Write-Host "About to install choco packages"
Install-Choco-Packages $config.chocolateyPackages
Write-Host "Choco packages installed"

Write-Host "About to install local packages"
Install-Local-Packages $config.localPackages $installedPrograms
Write-Host "Local packages installed"

Write-Host "About to install windows features"
Install-Windows-Features $config.features
Write-Host "Windows features installed"

Write-Host "About to copy configs"
Copy-Configs $config.configs
Write-Host "Configs copied"

Write-Host "About to pin taskbar items"
New-TaskBar-Items $config.taskBarItems
Write-Host "Taskbar items pinned"

Write-Host "About to install windows updates"
Install-WindowsUpdate -Full -SuppressReboots
Write-Host "Windows updates installed"