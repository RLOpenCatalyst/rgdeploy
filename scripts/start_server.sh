#!/bin/bash
version="0.1.11"
echo "Starting server....(start_server.sh v$version)"
if [ "$1" == "-h" ]; then
	echo "Usage: $(basename $0) <application_url> <target_group_arn>"
	echo '    Param 1: (optional) URL for SNS Callback'
	echo '             Will use public-host-name if not passed'
	echo '             e.g. https://myrg.example.com'
	echo '    Param 2: (optional) Target Group ARN to register with'
	exit 0
fi

[ -z "$RG_HOME" ] && RG_HOME='/opt/deploy/sp2'
echo "RG_HOME=$RG_HOME"

myurl=$1
tgarn=$2
port=80

echo 'Login to ECR'
aws ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin 045938549113.dkr.ecr.us-east-2.amazonaws.com

echo 'Pulling docker image for research portal'
docker pull $(cat "$RG_HOME/docker-compose.yml" | grep -i image | grep -i researchportal | awk '{print $2}' | uniq | tr -d '\r')
echo 'Pulling docker image for nginx'
docker pull $(cat "$RG_HOME/docker-compose.yml" | grep -i image | grep -i nginx | awk '{print $2}' | uniq | tr -d '\r')
echo 'Pulling docker image for notificationsink'
docker pull $(cat "$RG_HOME/docker-compose.yml" | grep -i image | grep -i notificationsink | awk '{print $2}' | uniq | tr -d '\r')

TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
ec2instanceid=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id)

if [ -z $myurl ]; then
	public_host_name="$(wget --header="X-aws-ec2-metadata-token: $TOKEN" -qO- http://169.254.169.254/latest/meta-data/public-hostname)"
	baseurl="$public_host_name"
else
	baseurl="$myurl"
fi
echo "BaseURL=$baseurl"
echo "TGARN=$tgarn"

if [ ! -z $tgarn ]; then
	echo "Registering instance $ec2instanceid with Target group: $tgarn"
	aws elbv2 register-targets --targets "Id=$ec2instanceid,Port=$port" --target-group-arn "$tgarn"
fi
echo "Calling swarm init will respond with error if this node is already part of a swarm"
/usr/local/sbin/swarm_init.sh

echo "Creating secrets"
mkdir -p "$RG_HOME"/{logs,slogs,notification_sink_logs}
if [ ! -f "$RG_HOME/nginx.conf" ]; then
	if [ -f "${RG_SRC:-/home/ec2-user/rgdeploy}/nginx.conf" ]; then
		cp "${RG_SRC:-/home/ec2-user/rgdeploy}/nginx.conf" "$RG_HOME/nginx.conf"
	elif [ -n "${S3_SOURCE:-}" ]; then
		aws s3 cp "s3://${S3_SOURCE}/nginx.conf" "$RG_HOME/nginx.conf" || true
	fi
fi
fixsecrets.sh

echo "Starting stack..."
docker stack deploy -c $RG_HOME/docker-compose.yml sp2

#Wait for 30 secs
sleep 5

#Check if stack is deployed
echo "Checking if stack is deployed"
service_count=$(docker service ls -q | wc -l)
if [ "${service_count}" -gt 0 ]; then
	echo "Service count deployed is $service_count"
else
	echo "Service not deployed successfully"
	exit 1
fi

sleep 30

function check_stack_status() {
	#Check if all the services are up
	state_replicated=0
	for i in $(docker service ls -q); do
		echo "$i"
		replicated=$(docker service inspect --pretty $i | grep -i "Service Mode" | awk '{print $3}')
		echo "Replicated service status: $replicated"
		if [ "${replicated}" == "Replicated" ]; then
			replicas=$(docker service inspect --pretty $i | grep -i replicas | awk '{print $2}')
			echo "Replicas count : $replicas"
			running_replicas=$(docker service ps $i | grep -i running | wc -l)
			echo "Running replicas count : $running_replicas"
			if [ ${replicas} -ne "${running_replicas}" ]; then
				let "state_replicated=state_replicated+1"
			fi
		fi
	done
	echo "Stack replication : $state_replicated"
	if [ "${state_replicated}" -gt 0 ]; then
		echo "CRITICAL - Not all services are replicated"
	else
		echo "OK - All services are replicated"
	fi
	return $state_replicated
}

for i in {0..3}; do
	echo "Checking stack status $i"
	check_stack_status
	res=$?
	echo "$res"
	if [ "${res}" == 0 ]; then
		echo "All services are up"
		break
	else
		sleep 30
	fi
done

#Check if web application is up and running
for i in {0..3}; do
	sleep 10
	echo "Checking if web application is up and running"
	status_code=$(curl -sL -w "%{http_code}\n" "$baseurl" -o /dev/null)
	if [ "$status_code" -ne 200 ]; then
		echo "Application is not up, responded with status $status_code"
	else
		echo "Application is up and running, status code response is $status_code"
		break
	fi
done

echo "Done"
