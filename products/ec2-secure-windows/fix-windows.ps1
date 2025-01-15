$scriptPath = "C:\Users\Administrator\log\provision-windows.log"
Start-Transcript -Path $scriptPath -Append

# Add mount script and set-user-token to startup folder
Write-Host "Moving mount-s3.bat and set-user-token.bat to startup folder"
if ((Test-Path -Path "C:\Users\Administrator\mount_s3.bat") -and !(Test-Path -Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\mount_s3.bat")) {
    Move-Item -Path "C:\Users\Administrator\mount_s3.bat" -Destination "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\"
}
if ((Test-Path -Path "C:\Users\Administrator\set_user_token.bat") -and !(Test-Path -Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\set_user_token.bat")) {
    Move-Item -Path "C:\Users\Administrator\set_user_token.bat" -Destination "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\"
}
$serviceName ='win-nice-dcv-auth-svc'
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($service) {
    Write-Host "Service '$serviceName' is installed."
    $svcstatus= ($service.Status )
    if (!($svcstatus -eq 'Running')) {
        Write-Host "Starting Service '$serviceName'"
        Start-Service -Name 'win-nice-dcv-auth-svc'
    } else {
        Write-Host "Service '$serviceName' is $svcstatus."
    }
    Write-Host "Testing Service '$serviceName'."
    $output=Start-Process -FilePath "cmd.exe" -ArgumentList "/c curl -i -X POST `"http://localhost:8445`" -H `"Content-Type: application/x-www-form-urlencoded`" -H `"Accept: application/xml`" -d `"sessionId=console&authenticationToken=xxxxx&clientAddress=127.0.0.1`""
    Write-Host $output
} else {
    Write-Host "Service '$serviceName' is not installed. Attempting to install"
    if (Test-Path -Path "C:\\Program Files\\win-nice-dcv-auth-svc\\requirements.txt") {
        echo "Step 1/3 Installing pre-requisites..."
        pip install -r "C:\\Program Files\\win-nice-dcv-auth-svc\\requirements.txt"
    }
    if (Test-Path -Path "C:\\Program Files\\win-nice-dcv-auth-svc\\win-nice-dcv-auth-svc.py") {
        echo "Step 2/3 Installing service ..."
        python "C:\\Program Files\\win-nice-dcv-auth-svc\\win-nice-dcv-auth-svc.py" --startup auto install
        echo "Step 3/3 Starting service...."
        python "C:\\Program Files\\win-nice-dcv-auth-svc\\win-nice-dcv-auth-svc.py" start        
    }
    $svcstatus = ((Get-Service -Name $serviceName).Status)
    Write-Host "Service '$serviceName' is $svcstatus."    
}

$serviceName ='AmazonSSMAgent'
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($service) {
    Write-Host "Service '$serviceName' is installed."
    $svcstatus= ($service.Status )
    if (!($svcstatus -eq 'Running')) {
        Write-Host "Starting Service '$serviceName'"
        Start-Service -Name 'win-nice-dcv-auth-svc'
    } else {
        Write-Host "Service '$serviceName' is $svcstatus."
    }
} else {
    Write-Host "Service '$serviceName' is not installed."
}
