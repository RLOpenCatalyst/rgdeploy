@echo off
setlocal enabledelayedexpansion

rem Set PARAMNAMEPREFIX
setx PARAMNAMEPREFIX /RL/RG/secure-desktop/auth-token/

rem Get AWS region
for /f "delims=" %%i in ('curl -s "http://169.254.169.254/latest/meta-data/placement/region"') do set region=%%i

rem Get instance ID
for /f "delims=" %%i in ('curl -s "http://169.254.169.254/latest/meta-data/instance-id"') do set instance_id=%%i

rem Set session ID and generate auth token
set session_id=console
set auth_token=%random%-%random%-%random%-%random%-%random%
set parameter_name=/RL/RG/secure-desktop/auth-token/%instance_id%

rem Put parameter using AWS SSM
aws ssm put-parameter --name "!parameter_name!" --type "String" --value "{\"auth_token\":\"!auth_token!\",\"session_id\":\"!session_id!\"}" --region !region! --overwrite

echo User token set successfully
