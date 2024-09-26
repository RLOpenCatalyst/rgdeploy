# Redirect stdout and stderr to a log file and the console
$scriptPath = "C:\Users\Administrator\log\provision-windows.log"
Start-Transcript -Path $scriptPath -Append  

# Add mount script and set-user-token to startup folder
Write-Host "Moving mount-s3.bat and set-user-token.bat to startup folder"
if (Test-Path -Path "C:\Program Files\ResearchGateway\mount_s3.bat") {
	Copy-Item -Path "C:\Program Files\ResearchGateway\default.perm" -Destination "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\"
 -Force
} elseif (Test-Path -Path "C:\Users\Administrator\mount_s3.bat") {
	// This is only to support older pipelines which expect this location of the file
	Copy-Item -Path "C:\Users\Administrator\mount_s3.bat" -Destination "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\"
 -Force
}else {
	Write-Host "Error: Could not find mount_s3.bat. Study mounting might not work correctly."		
}
if (Test-Path -Path "C:\Program Files\ResearchGateway\set_user_token.bat") {
	Copy-Item -Path "C:\Program Files\ResearchGateway\set_user_token.bat" -Destination "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\"
 -Force
} elseif (Test-Path -Path "C:\Users\Administrator\set_user_token.bat") {
	// This is only to support older pipelines which expect this location of the file
	Copy-Item -Path "C:\Users\Administrator\set_user_token.bat" -Destination "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\"
 -Force
}else {
	Write-Host "Error: Could not find set_user_token.bat. Launch URL might not work correctly."		
}



# Set Administrator password
net user Administrator Admin@123

# Set environment variable
setx PARAMNAMEPREFIX /RL/RG/secure-desktop/auth-token/

# Download and install Microsoft Visual C++ Redistributable for Visual Studio 2017
Write-Host "Downloading Microsoft Visual C++ Redistributable for Visual Studio 2017..."
$downloadsuccesful = $false
Invoke-WebRequest -Uri "https://aka.ms/vs/15/release/vc_redist.x64.exe" -OutFile "$env:TEMP\vc_redist.x64.exe"
$downloadsuccesful = Test-Path -Path "$env:TEMP\vc_redist.x64.exe"

if ($downloadsuccesful) {
	Write-Host "Installing Microsoft Visual C++ Redistributable for Visual Studio 2017"
	Start-Process -FilePath "$env:TEMP\vc_redist.x64.exe" -ArgumentList "/install /quiet /norestart" -Wait
	Remove-Item -Path "$env:TEMP\vc_redist.x64.exe" -Force
} else {
	Write-Host "Failed to download Microsoft Visual C++ Redistributable for Visual Studio 2017"
	Exit 1
}

# AWS CLI Installer URL
$awsCliUrl = "https://awscli.amazonaws.com/AWSCLIV2.msi"

# Download AWS CLI MSI
Write-Host "Downloading AWS-CLI...$awsCliUrl"
$downloadsuccesful = $false
Invoke-WebRequest -Uri $awsCliUrl -OutFile "$env:TEMP\AWSCLIV2.msi"
$downloadsuccesful = Test-Path -Path "$env:TEMP\AWSCLIV2.msi"

# Install AWS CLI silently
if ($downloadsuccesful) {
	Write-Host "Installing AWS-CLI" 
	Start-Process -FilePath msiexec.exe -ArgumentList "/i `"$env:TEMP\AWSCLIV2.msi`" /quiet /qn /norestart" -Wait	
	Remove-Item -Path "$env:TEMP\AWSCLIV2.msi" -Force
} else {
	Write-Host "AWS CLI download failed"
	Exit 1
}

# Download Nice-Dcv Server
Write-Host "Downloading Nice-Dcv"
$downloadsuccesful = $false
$niceDcvServerURL = "https://d1uj6qtbmh3dt5.cloudfront.net/2023.1/Servers/nice-dcv-server-x64-Release-2023.1-16388.msi"
Invoke-WebRequest -Uri $niceDcvServerURL -OutFile "$env:TEMP\nice-dcv-server-x64-Release-2023.1-16388.msi"
$downloadsuccesful = Test-Path -Path "$env:TEMP\nice-dcv-server-x64-Release-2023.1-16388.msi"
$restartdcv = $false
if (!$downloadsuccesful){
	Write-Host "Failed to download NICE DCV Server"
	Exit 1
}	
# Install Nice-Dcv Server
Write-Host "Installing Nice-Dcv Server"
Start-Process msiexec.exe -ArgumentList "/i `"$env:TEMP\nice-dcv-server-x64-Release-2023.1-16388.msi`" ADDLOCAL=ALL /quiet /norestart /l*v 	dcv_install_msi.log" -Wait
Remove-Item -Path "$env:TEMP\nice-dcv-server-x64-Release-2023.1-16388.msi" -Force
Write-Host "Moving default.perm to location C:\Program Files\NICE\DCV\Server\conf\default.perm"
if (Test-Path -Path "C:\Program Files\ResearchGateway\default.perm") {
	Copy-Item -Path "C:\Program Files\ResearchGateway\default.perm" -Destination "C:\Program Files\NICE\DCV\Server\conf\default.perm" -Force
	$restartdcv = $true
} elseif (Test-Path -Path "C:\Users\Administrator\default.perm") {
	// This is only to support older pipelines which expect this location of the file
	Copy-Item -Path "C:\Users\Administrator\default.perm" -Destination "C:\Program Files\NICE\DCV\Server\conf\default.perm" -Force
	$restartdcv = $true
}else {
	Write-Host "Error: Could not find default.perm. NICE DCV might not be configured correctly."		
}

if ($restartdcv) {
	Write-Host "Restarting DCV server"
	Restart-Service "dcvserver"
	$svcstatus= ((Get-Service -Name 'dcvserver').Status )
	Write-Host "DCV service status:  $svcstatus"
}
# Download and install rclone
Write-Host "Downloading rclone..."
mkdir C:\rclone
$rcloneURL = "https://downloads.rclone.org/v1.65.2/rclone-v1.65.2-windows-amd64.zip"
$downloadsuccesful = $false
Invoke-WebRequest -Uri $rcloneURL -OutFile "$env:TEMP\rclone-v1.65.2-windows-amd64.zip"
$downloadsuccesful = Test-Path -Path "$env:TEMP\rclone-v1.65.2-windows-amd64.zip"
if (!$downloadsuccesful) {
	Write-Host "Failed to download rclone. Mounting studies may not work."
	Exit 1
}
Write-Host "Installing rclone..."
Expand-Archive -Path "$env:TEMP\rclone-v1.65.2-windows-amd64.zip" -DestinationPath "C:\rclone\"
Remove-Item -Path "$env:TEMP\rclone-v1.65.2-windows-amd64.zip" -Force
# Download and install RStudio
Write-Host "Downloading RStudio..."
$RVersion = "R-4.4.1-win.exe"
$rstudioURL = "https://cran.rstudio.com/bin/windows/base/$RVersion"
$downloadsuccesful = $false
Invoke-WebRequest -Uri $rstudioURL -OutFile "$env:TEMP\$RVersion"
$downloadsuccesful = Test-Path -Path "$env:TEMP\$RVersion"

if ($downloadsuccesful) {
	Write-Host "Installing RStudio..."
	Start-Process -FilePath "$env:TEMP\$RVersion" -ArgumentList "/VERYSILENT /NORESTART" -Wait
	Remove-Item -Path "$env:TEMP\$RVersion" -Force
} else {
	Write-Host "Failed to download RStudio"
}

# Install Chocolatey and winfsp
Write-Host "Installing Chocolatey..."
Set-ExecutionPolicy Bypass -Scope Process -Force
iex ((New-Object System.Net.WebClient).DownloadString("https://chocolatey.org/install.ps1"))
choco install winfsp -y

# Install cx_Freeze
Write-Host "Installing cx_Freeze..."
cmd /c start powershell -ExecutionPolicy RemoteSigned {
    pip install cx_Freeze
}

# Install Node.js
Write-Host "Downloading Node.js..."
$nodeURL = "https://nodejs.org/dist/v18.20.2/node-v18.20.2-x64.msi"
$downloadsuccesful = $false
Invoke-WebRequest -Uri $nodeURL -OutFile "$env:TEMP\node-v18.20.2-x64.msi"
$downloadsuccesful = Test-Path -Path "$env:TEMP\node-v18.20.2-x64.msi"
if ($downloadsuccesful) {
	Write-Host "Installing node.js"
	Start-Process -FilePath msiexec.exe -ArgumentList "/i `"$env:TEMP\node-v18.20.2-x64.msi`" /qn"
	Remove-Item -Path "$env:TEMP\node-v18.20.2-x64.msi" -Force
} else {
	Write-Host "Failed to download Node.js."
}

# Edit registry entry for auth-token-verifier
New-ItemProperty -Force -Path "Microsoft.PowerShell.Core\Registry::\HKEY_USERS\S-1-5-18\Software\GSettings\com\nicesoftware\dcv\security" -Name "auth-token-verifier" -PropertyType "String" -Value "http://127.0.0.1:8445"
Stop-Transcript
