#!/bin/bash
version='0.1.1'
STACK_NAME="${STACK_NAME:-sp2}"
usage() {
	echo "Usage: $0 [-h] | -f <file-name> [-t]"
	echo "Version: $version"
	echo "  -h: Print help"
	echo "  -t: Run in test mode"
	echo "  -f: File in CSV format containing user records to import"
	echo "      First line in the file is a header line. Must contain"
	echo "      Number,EmailId,Role,FirstName,LastName,OU"
	echo "        Number    : Serial Number of the record"
	echo "        EmailId   : Required. EmailId of user to be invited"
	echo "        Role      : (Researcher|Principal|Admin). Assumed to be researcher if not passed"
	echo "        FirstName : Optional. First Name of the user"
	echo "        LastName  : Optional. Last Name of the user"
	echo "        OU        : Optional. Must correspond to an existing Organizational Unit if provided."
	echo "                    User will not be assigned to any Organizational Unit if not provided."
}

exit_abnormal() { # Function: Exit with error.
	usage
	exit 1
}

TEST=
while getopts "htf:" options; do
	# use silent error checking;
	# options f takes arguments.
	case "${options}" in #
	h)
		usage # print help and exit
		exit 0
		;;
	f)
		input_file=${OPTARG}            # Set $input to specified value.
		if [ ! -e "$input_file" ]; then # if $input is not a file that exists
			echo "Error: Please provide a file name"
			exit_abnormal
			exit 1 # Exit abnormally.
		fi
		;;
	t)
		TEST='yes'
		;;
	:) # If expected argument omitted:
		echo "Error: -${OPTARG} requires an argument."
		exit_abnormal # Exit abnormally.
		;;
	*)             # If unknown (any other) option:
		exit_abnormal # Exit abnormally.
		;;
	esac
done

if [ -z "$TEST" ]; then
    TOKEN=$(wget --method=PUT --header="X-aws-ec2-metadata-token-ttl-seconds: 21600" -qO- http://169.254.169.254/latest/api/token)
	instanceid=$(wget --header="X-aws-ec2-metadata-token: $TOKEN" -qO- http://169.254.169.254/latest/meta-data/instance-id)
else
	instanceid='i-1234509876'
fi
##############################################
## get_role
## Param 1: Role to translate to Level (0-Researcher, 1-Principal,2-Admin)
get_role() {
	if [ -z "$1" ]; then
		echo "0"
		return
	fi
	# trunk-ignore(shellcheck/SC2060)
	role=$(echo "$1" | tr [A-Z] [a-z])
	case "$1" in
	"researcher")
		echo "0"
		;;
	"principal")
		echo "1"
		;;
	"admin")
		echo "2"
		;;
	*)
		echo "0"
		;;
	esac
}
##############################################
## add_user
## Param 1: emailid
## Param 2: role
## Param 3: FirstName
## Param 4: LastName
add_user() {
	data="{\"username\":\"$1\",\"first_name\":\"$3\",\"last_name\":\"$4\",\"email\":\"$1\",\"password\":\"RgAdmin@$instanceid\",\"level\":\"$2\",\"org_id\":\"$5\"}"
	if [ -z "$TEST" ]; then
		message=$(curl --location --request POST "$baseurl/user/signup" --header "token: $token" --header "Content-Type: application/json" --data-raw "$data" | jq -r '.message')
		if [ "$message" == "success" ]; then
			echo "User created. You should receive an email to verify your email address. Please click on the link to change your password"
		else
			echo "Error: Could not create user ($message). Please contact support"
		fi
	else
		echo "$data" | jq -r
	fi
}

if [ -z "$TEST" ]; then
	[ -z "$RG_HOME" ] && RG_HOME="/opt/deploy/${STACK_NAME}"
	baseurl=$(jq -r '.baseURL' "$RG_HOME/config/config.json" | sed -e 's#/$##')
	token=$(jq -r '.tokenID[0]' "$RG_HOME/config/notification-config.json")

	if [ -z "$baseurl" ]; then
		echo " Base URL is not configured in config.json. Exiting"
		exit 1
	fi
	is_app_running='No'
	#Check if web application is up and running
	for i in {0..3}; do
		echo "Checking [$i] if app is running at $baseurl"
		status_code=$(curl -sL -w "%{http_code}\n" "$baseurl" -o /dev/null)
		if [ "$status_code" -ne 200 ]; then
			echo "Application is not up, responded with status $status_code"
		else
			echo "Application is up and running, status code response is $status_code"
			is_app_running='Yes'
			break
		fi
		sleep 5
	done

	if [ "$is_app_running" == 'No' ]; then
		echo "The Research Gateway application is not running. Use start_server.sh to start it"
		exit 1
	fi
fi
# Read all the lines starting from second line.
# Assumption is that first line is the header.
while IFS="," read -r serialno emailid role firstname lastname org_unit; do
	echo "Processing record $serialno"
	level=$(get_role "$role")
	add_user "$emailid" "$level" "$firstname" "$lastname" "$org_unit"
done < <(cut -d "," -f"1,2,3,4,5,6" "${input_file}" | tail -n +2)
