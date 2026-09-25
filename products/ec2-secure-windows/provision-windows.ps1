  
# Redirect stdout and stderr to a log file and the console
# $scriptPath = "C:\Users\Administrator\log\provision-windows.log"
# Start-Transcript -Path $scriptPath -Append  

# Set env variable
setx PARAMNAMEPREFIX /RL/RG/secure-desktop/auth-token/
 
# AWS CLI Installer URL
$awsCliUrl = "https://awscli.amazonaws.com/AWSCLIV2.msi"

echo "downloading AWS-CLI..." 
# Download AWS CLI MSI
Invoke-WebRequest -Uri $awsCliUrl -OutFile "$env:TEMP\AWSCLIV2.msi"

# Download and install Microsoft Visual C++ Redistributable for Visual Studio 2017
echo "downloading Microsoft Visual C++ Redistributable for Visual Studio 2017..." 
Invoke-WebRequest -Uri "https://aka.ms/vs/15/release/vc_redist.x64.exe" -OutFile "$env:TEMP\vc_redist.x64.exe"
Start-Process -FilePath "$env:TEMP\vc_redist.x64.exe" -ArgumentList "/install /quiet /norestart" -Wait

# Install AWS CLI silently
echo "Installing AWS-CLI" 
Start-Process -FilePath msiexec.exe -ArgumentList "/i `"$env:TEMP\AWSCLIV2.msi`" /quiet /qn /norestart" -Wait

# Remove temporary files
echo "Removing AWSCLIV2.msi, vc_redist.x64.exe" 
Remove-Item "$env:TEMP\AWSCLIV2.msi" -Force
Remove-Item "$env:TEMP\vc_redist.x64.exe" -Force

# Download nice-dcv-server
echo "Downloading Nice-Dcv" 
$niceDcvServerURL = "https://d1uj6qtbmh3dt5.cloudfront.net/2023.1/Servers/nice-dcv-server-x64-Release-2023.1-16388.msi"
Invoke-WebRequest -Uri $niceDcvServerURL -OutFile "C:\Users\Administrator\nice-dcv-server-x64-Release-2023.1-16388.msi"

# install nice-dcv-server
echo "Installing nice-dcv-server"
Start-process msiexec.exe -wait -ArgumentList '/i nice-dcv-server-x64-Release-2023.1-16388.msi ADDLOCAL=ALL /quiet /norestart /l*v dcv_install_msi.log'

# Install Rstudio
echo "Downloading Rstudio..."
$rstudioURL = "https://cran.rstudio.com/bin/windows/base/R-4.4.1-win.exe"
Invoke-WebRequest -Uri $rstudioURL -OutFile "C:\Users\Administrator\R-4.4.1-win.exe"
echo "Installing Rstudio..."
.\R-4.4.1-win.exe /VERYSILENT /NORESTART

# Install rclone
echo "Downloading rclone..."
mkdir c:\rclone
$rcloneURL = "https://downloads.rclone.org/v1.65.2/rclone-v1.65.2-windows-amd64.zip"
Invoke-WebRequest -Uri $rcloneURL -OutFile "C:\Users\Administrator\rclone-v1.65.2-windows-amd64.zip"

echo "Installing Rclone"
Expand-Archive -path 'C:\Users\Administrator\rclone-v1.65.2-windows-amd64.zip' -destinationpath '.\'
cp C:\Users\Administrator\rclone-v1.65.2-windows-amd64\*.* C:\rclone\

echo "Installing chocollaty and Google-Chrome..."
Set-ExecutionPolicy Bypass -Scope Process -Force; `iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
choco install winfsp -y
choco install googlechrome -y

# Install cx_Freeze
echo "Instaling cx_Freeze"
cmd /c start powershell -executionpolicy remotesigned {
pip install cx_Freeze
}

#Compile custom auth svc
echo "compiling custom auth service"
C:\Users\Administrator\win-nice-dcv-auth-svc\install_custom_auth.bat


#install node.js
echo "Installing Node"
$nodeURL = "https://nodejs.org/dist/v18.20.2/node-v18.20.2-x64.msi"
Invoke-WebRequest -Uri $nodeURL -OutFile "C:\Users\Administrator\node-v18.20.2-x64.msi"
msiexec.exe  /i C:\Users\Administrator\node-v18.20.2-x64.msi /qn

# Edit registry entry
New-ItemProperty -Path "Microsoft.PowerShell.Core\Registry::\HKEY_USERS\S-1-5-18\Software\GSettings\com\nicesoftware\dcv\security" -Name "auth-token-verifier" -PropertyType "String" -Value "http://127.0.0.1:8445" -Force

echo "Copying default.perm to location C:\Program Files\NICE\DCV\Server\conf\default.perm"
cp "C:\Users\Administrator\default.perm" "C:\Program Files\NICE\DCV\Server\conf\default.perm"
# Add mount script and set-user-token to startup folder
echo "copying mount_s3.bat, set_user_token.bat to startup folder"
cp C:\Users\Administrator\mount_s3.bat "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\"
cp C:\Users\Administrator\set_user_token.bat "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\"

# Set Admin password
net user Administrator Admin@123

# End the transcript (stop logging)
# Stop-Transcript
