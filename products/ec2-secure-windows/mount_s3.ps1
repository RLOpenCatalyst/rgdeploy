<powershell>
cd C:\rclone\
$studyMount = Get-Content -Raw C:\Users\Administrator\s3_mount.txt | ConvertFrom-Json

# Iterate through each bucket configuration and mount it using rclone
$driveLetter = 70
$mountPoint = [char]($driveLetter)+":"

function MountStudy {
    param (
        [array]$mountArray,
        [int]$driveLetter,
        [string]$pointToMount
    )
    foreach ($config in $mountArray) {    
    $bucketName = $config.bucket
    $prefix = $config.prefix
    $remoteName = $config.id
    $region = $config.region
    $roleArn = $config.roleArn
    $mountString = "${bucketName}:$bucketName/$prefix"
    echo "$mountString"
    echo "$mountPoint"
    if($roleArn) {
    $assumeRole = aws sts assume-role --role-arn $roleArn --role-session-name s3-bucket-access --duration-seconds 43200
    $assumeRole = $assumeRole | ConvertFrom-Json
    $accessKey = $assumeRole.Credentials.AccessKeyId
    $secretKey = $assumeRole.Credentials.SecretAccessKey
    $sessionToken = $assumeRole.Credentials.SessionToken
    .\rclone config create $bucketName s3 provider AWS env_auth true access_key_id $accessKey secret_access_key $secretKey session_token $sessionToken region $region location_constraint $region
    } else {
    .\rclone config create $bucketName s3 provider AWS env_auth true region $region location_constraint $region
    }
    # Construct the rclone mount command
    #$rcloneMountCommand = ".\rclone mount study:$bucketName/$prefix S: --vfs-cache-mode full --log-file C:\Users\Administrator\log\rcloneNewlogs.txt"
    $rcloneMountCommand = "cmd /c start powershell -executionpolicy remotesigned -WindowStyle hidden -Command .\rclone mount $mountString $pointToMount --vfs-cache-mode full --ignore-checksum --log-file C:\Users\Administrator\log\rclone.txt"
    # Execute the rclone mount command
    Invoke-Expression $rcloneMountCommand
    $driveLetter += 1
    $pointToMount = [char]($driveLetter)+":"
    
    }
}

while ($true) {

# Your command goes here
Write-Host "Executing the command every twelve hours"

# unmount the mouted files
taskkill /im rclone.exe /f

# Call the function every twelve hour
MountStudy -mountArray $studyMount -driveLetter $driveLetter -pointToMount $mountPoint

Start-Sleep -Seconds 43200  # Sleep for twelve hour

Write-Host "Executing the mounting command after every twelve hours"

}

</powershell>
