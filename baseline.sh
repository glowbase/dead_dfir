#!/bin/bash

clear
export GREP_COLORS="01;35"

RED='\033[31m'
GREEN='\033[32m'
BLUE='\033[34m'
CYAN='\033[35m'
RESET='\033[0m'
BOLD='\033[1m'
BOLD_PINK='\033[1;35m'
DIV="=============================="

BANNER="
██████╗ ███████╗ █████╗ ██████╗     ██████╗ ███████╗██╗██████╗ 
██╔══██╗██╔════╝██╔══██╗██╔══██╗    ██╔══██╗██╔════╝██║██╔══██╗
██║  ██║█████╗  ███████║██║  ██║    ██║  ██║█████╗  ██║██████╔╝
██║  ██║██╔══╝  ██╔══██║██║  ██║    ██║  ██║██╔══╝  ██║██╔══██╗
██████╔╝███████╗██║  ██║██████╔╝    ██████╔╝██║     ██║██║  ██║
╚═════╝ ╚══════╝╚═╝  ╚═╝╚═════╝     ╚═════╝ ╚═╝     ╚═╝╚═╝  ╚═╝

Perform post-mortem analysis on 'dead' Linux machines.
"

OPTIONS=("MOUNT_POINT" "TIME_ZONE")
SWITCHES=("-m")
OPTION_IDX=0
NEXT_ARG_VARIABLE=""
MOUNT_REQUIRED=0

for arg in "$@"; do
	if [ ! -z "$NEXT_ARG_VARIABLE" ]; then
		eval "${NEXT_ARG_VARIABLE}=\"$arg\""
		NEXT_ARG_VARIABLE=""
		continue
	fi

	if [[ ${SWITCHES[@]} =~ $arg ]]; then
		case $arg in
		"-m")
			MOUNT_REQUIRED=1
			NEXT_ARG_VARIABLE="DISK_IMAGE"
			;;
		esac
		continue
	else

		case $OPTION_IDX in
			0)
				MOUNT_POINT="$arg"
				;;
			1)
				TIME_ZONE="$arg"
				;;
		esac
	
		((OPTION_IDX++))
	fi

done

# echo "Mount Point: $MOUNT_POINT"
# echo "Time Zone: $TIME_ZONE"
# if [ ! -z "$DISK_IMAGE" ]; then
# 	echo "Disk Image: $DISK_IMAGE"
# fi
# echo "Mount Required: $MOUNT_REQUIRED"

log_header() {
	local heading=$1
	local sub_heading=$2

	if [ -z "$sub_heading" ]; then
		echo -e "${BLUE}${DIV}|${BOLD}${GREEN} ${heading} ${RESET}${BLUE}|${DIV}${RESET}"
	else
		echo -e "${BLUE}${DIV}|${BOLD}${GREEN} ${heading} - ${sub_heading} ${RESET}${BLUE}|${DIV}${RESET}"
	fi
}

log_value() {
	local title=$1
	local val=$2

	echo -e "${RED}${BOLD}[+] ${BLUE}${title}: ${RESET}${val}"
}

get_property() {
	local key=$1
	local file=$2
	
	echo $(cat $file | grep $key | cut -d '"' -f 2)
}

get_birth() {
	local path=$1

	stat "$MOUNT_POINT$home" | grep "Birth" | cut -d " " -f 3,4 | cut -d "." -f 1
}

get_timezone() {
	if [ -f "$MOUNT_POINT/etc/timezone" ]; then
		echo "$(cat $MOUNT_POINT/etc/timezone)"
	else
		echo "$(realpath $MOUNT_POINT/etc/localtime | sed 's/.*zoneinfo\///')"
	fi
}

initial_checks(){
	# Check if the mount point exists
	if [ ! -d "$MOUNT_POINT" ]; then
		echo "Error: Mount point $MOUNT_POINT does not exist."
		exit 1
	fi

	# Change timezone based on user input and target
	timezone="$(get_timezone)"

	if [ ! "$TIME_ZONE" ]; then
		export TZ="$timezone"
	else 
		export TZ="$TIME_ZONE"
	fi
}

convert_timestamp() {
	local timestamp="$1"
	# Convert timestamp to the target timezone
	# Assumes the format of timestamp is YYYY-MM-DD HH:MM:SS for conversion
	date -d "$timestamp $from_tz" +"%Y-%m-%d %H:%M:%S" -u | TZ="$to_tz" date +"%Y-%m-%d %H:%M:%S"
}

to_lower() {
	echo "$1" | tr '[:upper:]' '[:lower:]'
}

to_upper() {
	echo "$1" | tr '[:lower:]' '[:upper:]'
}

determine_image_type() {
	# check mmls output for partition table
	local mmls_output=$(mmls "$1" 2>/dev/null)
	
	# if there is output, then it is a disk image
	if [ ! -z "$mmls_output" ]; then
		echo "disk"
	else
		# check if the output of the file command contains "filesystem"
		local file_output=$(file "$1")
		if [[ $file_output == *"filesystem"* ]]; then
			echo "filesystem"
		else
			echo "unknown"
		fi
	fi
}

mount_image_to_directory() {
	disk_image=$1
	mount_point=$2
	options=$3
	mount $options "$disk_image" $mount_point
	echo losetup -a | grep $disk_image | cut -d ":" -f 1
}

# -----------------------------------------------------------
# MOUNT IMAGE
# -----------------------------------------------------------
mount_image() {
	# check if the image exists
	if [ ! -f "$DISK_IMAGE" ]; then
		echo "Error: Image file $DISK_IMAGE does not exist."
		exit 1
	fi

	# check if the disk image is already mounted
	existing_loop=$(losetup -a | grep "$DISK_IMAGE" | cut -d ":" -f 1)
	if [ ! -z "$existing_loop" ]; then
		echo "EXISTING DEVICE FOUND"
		LOOP_DEVICE=$existing_loop
	fi

	# get the file extension
	extension="${DISK_IMAGE##*.}"
	lower_extension=$(to_lower $extension)

	case $lower_extension in
		"e01")
			if [ -z "$existing_loop" ]; then
				# in the mount directory create a ewf directory
				mkdir -p $MOUNT_POINT/ewf

				# mount the e01 via ewfmount
				ewfmount "$DISK_IMAGE" $MOUNT_POINT/ewf 1>/dev/null
				
				DISK_IMAGE=$MOUNT_POINT/ewf/ewf1
				
				# in the mount directory create a disk directory
				mkdir -p $MOUNT_POINT/disk
				MOUNT_POINT=$MOUNT_POINT/disk
			fi
			;;
	esac

	# check if the disk image is already mounted
	existing_loop=$(losetup -a | grep $DISK_IMAGE | cut -d ":" -f 1)
	if [ ! -z "$existing_loop" ]; then
		echo "EXISTING DEVICE FOUND"
		LOOP_DEVICE=$existing_loop
	fi

	# get the disk type
	image_type=$(determine_image_type "$DISK_IMAGE")
	case $image_type in
		"filesystem")
			if [ -z "$existing_loop" ]; then
				mount_image_to_directory "$LOOP_DEVICE" $MOUNT_POINT "ro"
			# mount the image to the mount point
			else
				LOOP_DEVICE=$(mount_image_to_directory "$DISK_IMAGE" $MOUNT_POINT "ro,loop")
			fi
			;;
		"disk")
			if [ -z "$existing_loop" ]; then
				# attach to disk to a loop device
				LOOP_DEVICE=$(losetup -f)
				losetup $LOOP_DEVICE "$DISK_IMAGE"
			fi

			# if the mmls output contains "Linx Logical Volume Manager" attach that to a loop device
			lvm_partition=$(mmls $LOOP_DEVICE 2>/dev/null | grep "Linux Logical Volume Manager" | awk '{print $3}')
			if [ ! -z "$lvm_partition" ]; then
				LVM_LOOP_DEVICE=$(losetup -f)
				lvm_partition=$(echo $((10#$lvm_partition)))
				# calculate the offset
				offset=$((lvm_partition * 512))
				losetup $LVM_LOOP_DEVICE -o $offset $LOOP_DEVICE
			
				vgchange -ay $pvs

				# determine if there are physical volumes on the device
				pvs=$(pvs 2>/dev/null | grep $LVM_LOOP_DEVICE | grep -i "lvm" | awk '{print $2}' | head -n 1)

				echo $pvs
				# if pvs is not empty, then there are physical lvm volumes
				if [ ! -z "$pvs" ]; then
				
					lv_name=$(lvs $pvs 2>/dev/null | grep $pvs | grep 'root' | awk '{print $1}')

					# mount the logical volume to the directory
					mount /dev/$pvs/$lv_name -o ro,noload $MOUNT_POINT

					# iterate through the lvs results
					for lv in $(lvs $pvs 2>/dev/null | grep $pvs | grep -E -v '(swap|root)' | awk '{print $1 $2}'); do
						# get the logical volume name
						lv_name=$(echo $lv | awk '{print $1}')

						# create a directory for the logical volume
						mkdir -p $MOUNT_POINT/$lv_name

						# mount the logical volume to the directory
						mount /dev/$pvs/$lv_name -o ro,noload $MOUNT_POINT/$lv_name 2>/dev/null
					done
				else
					echo "FAILED TO MOUNT LVM"
				fi
			else
				# get the partition table
				partition_table=$(mmls $LOOP_DEVICE 2>/dev/null)

				# if there is no partition table, mount the image to the mount point
				if [ -z "$partition_table" ]; then
					mount_image_to_directory $LOOP_DEVICE $MOUNT_POINT
				else
					# get the partition start sector
					partition_start=$(echo "$partition_table" | egrep "[0-9]{3}:  " | grep -v "GUID" | grep -v "Meta" | grep -v "\-\-\-\-" | grep -vi "swap" | head -n 1 | awk '{print $3}')

					partition_start=$(echo $((10#$partition_start)))
					# calculate the offset
					offset=$((partition_start * 512))

					# mount the image to the mount point with the offset
					mount_image_to_directory $LOOP_DEVICE $MOUNT_POINT "-o ro,loop,offset=$offset"
				fi
			fi
			;;
		"unknown")
			echo "Error: Unknown image type."
			exit 1
			;;
	esac
}

# -----------------------------------------------------------
# BANNER
# -----------------------------------------------------------

show_banner() {
	echo "$BANNER"
}

# -----------------------------------------------------------
# DEVICE SETTINGS
# -----------------------------------------------------------
get_device_settings() {
	echo $(log_header "DEVICE SETTINGS")
	echo

	# OS Version
	if [ -f "$MOUNT_POINT/etc/os-release" ]; then
		os_version=$(get_property "PRETTY_NAME" $MOUNT_POINT/etc/os-release)
	elif [ -f "$MOUNT_POINT/etc/lsb-release" ]; then
		os_version=$(get_property "PRETTY_NAME" $MOUNT_POINT/etc/lsb-release)
	elif [ -f "$MOUNT_POINT/etc/redhat-release" ]; then
		os_version=$(get_property "PRETTY_NAME" $MOUNT_POINT/etc/redhat-release)
	elif [ -f "$MOUNT_POINT/etc/debian_version" ]; then
		os_version=$(get_property "PRETTY_NAME" $MOUNT_POINT/etc/debian_version)
	else
		os_version="Not Found"
	fi

	echo $(log_value "OS Version" "$os_version")

	# Kernel Version
	kernel_ver=$(ls $MOUNT_POINT/lib/modules)
	echo $(log_value "Kernel Version" "$kernel_ver")

	# Processor Architecture
	proc_arch="$(ls $MOUNT_POINT/lib/modules | cut -d "." -f 5)"

	if [ ! $proc_arch ]; then
		proc_arch="$(ls $MOUNT_POINT/lib/modules | cut -d "-" -f 3)"
	fi

	echo $(log_value "Processor Architecture" "$proc_arch")

	# Time Zone
	echo $(log_value "Time Zone" "$timezone")

	# Last Shutdown
	shutdown=$(last -x -f $MOUNT_POINT/var/log/wtmp | egrep "shutdown|reboot" | head -n 1 | sed 's/  / /g' | cut -d " " -f 1,6-10)
	shutdown_time=$(echo $shutdown | cut -d " " -f 2-5)
	shutdown_type=$(echo $shutdown | cut -d " " -f 1)
	echo $(log_value "Last Shutdown" "$shutdown_time ($shutdown_type)")

	# Hostname
	hostname=$(cat $MOUNT_POINT/etc/hostname)
	echo $(log_value "Hostname" "$hostname")

	echo
}

# -----------------------------------------------------------
# USERS
# -----------------------------------------------------------
get_users() {
	echo $(log_header "USERS")
	echo

	users=$(egrep "bash|zsh" $MOUNT_POINT/etc/passwd | cut -d ":" -f 1,3)

	for userid in $users; do
		id=$(echo "${userid}" | cut -d ":" -f 2)
		user=$(echo "${userid}" | cut -d ":" -f 1)

		home="$(grep "^$user" $MOUNT_POINT/etc/passwd | cut -d ":" -f 6)"

		disabled="$(cat $MOUNT_POINT/etc/shadow | cut -d ":" -f 1-3 | egrep "^$user(:\$|::)")"
		dis_enabled="$([ "$disabled" ] && echo -e "${BOLD_PINK}True${RESET}" || echo "False")"

		password="$(egrep "^$user:[^!][^:]*:.*$" $MOUNT_POINT/etc/shadow)"
		pass_enabled="$([ "$password" ] && echo -e "${BOLD_PINK}True${RESET}" || echo "False")"

		groups=$(cat $MOUNT_POINT/etc/group | grep $user | cut -d ":" -f 1 | sed ':a;N;$!ba;s/\n/, /g')
		creation="$(get_birth $home)"

		echo -e "$(log_value "$user ($id)" "")"
		echo -e "  ${BOLD}Creation: ${RESET}$creation"
		echo -e "  ${BOLD}Password: ${RESET}$pass_enabled"
		echo -e "  ${BOLD}Disabled: ${RESET}${dis_enabled}"
		echo -e "  ${BOLD}Groups: ${RESET}$(echo $groups | egrep --color=always "sudo|admin|wheel")"
		echo -e "  ${BOLD}Home: ${RESET}$home"
		echo
	done
}

# -----------------------------------------------------------
# BACKUP DIFF
# -----------------------------------------------------------

get_backup_diff() {
	echo $(log_header "BACKUP DIFF")
	echo

	for name in "shadow" "passwd" "group"; do
		local file="$MOUNT_POINT/etc/$name"

		if [ -f "$file-" ]; then
			echo -e "$(log_value "$name" "")"
			echo "Modified: $(stat $file | grep Modify | cut -d " " -f 2-3 | cut -d "." -f 1)"
			echo
			echo "$(diff $file- $file | egrep "<|>|-" | egrep --color=always ">*|$")"
			echo
		elif [ -f "$file~" ]; then
			echo -e "$(log_value "$name" "")"
			echo "Modified: $(stat $file | grep Modify | cut -d " " -f 2-3 | cut -d "." -f 1)"
			echo
			echo "$(diff $file~ $file | egrep "<|>|-" | egrep --color=always ">*|$")"
			echo
		else
			echo -e "$(log_value "$name" "")"
			echo "No $name file backup found..."
			echo
		fi
	done
}

# -----------------------------------------------------------
# INSTALLED SOFTWARE
# -----------------------------------------------------------
get_installed_software() {
	echo $(log_header "INSTALLED SOFTWARE")
	echo

	local dpkg="$MOUNT_POINT/var/log/dpkg.log"
	local yum="$MOUNT_POINT/var/log/yum.log"

	local software="wget|curl|php|sql|apache|drupal"

	if [ -f "$dpkg" ]; then
		echo "$(cat "$dpkg" | grep " installed " | egrep --color=always "$software" )"
	elif [ -f "$yum" ]; then
		echo "$(grep -i installed $yum | sed -e "s/Installed: //" | egrep --color=always "$software")"
	else
		echo "$(log_value "Could't find Installed Software..." "")"
	fi

	echo
}

# -----------------------------------------------------------
# CRON JOBS
# -----------------------------------------------------------
get_cron_jobs() {
	echo $(log_header "CRON JOBS")
	echo

	local patterns="wget |curl |nc |bash |sh |base64|exec |/tmp/|perl|python|ruby|nmap |tftp|php"

	local cron_files=(
			"$MOUNT_POINT/etc/crontab"
			"$MOUNT_POINT/etc/cron.d"
			"$MOUNT_POINT/etc/cron.hourly"
			"$MOUNT_POINT/etc/cron.daily"
			"$MOUNT_POINT/etc/cron.weekly"
			"$MOUNT_POINT/etc/cron.monthly"
	)

	local user_cron_directories=(
			"$MOUNT_POINT/var/spool/cron/crontabs" # Debian/Ubuntu
			"$MOUNT_POINT/var/spool/cron"          # Red Hat/CentOS
	)

	print_crons() {
		local file=$1
		local result="$(cat "$file" | grep -v "#" | egrep --color=always "$patterns")"
		
		if [ ! -z "$result" ]; then
			echo -e $(log_value "$file" "")
			echo "$result"
			echo
		fi
	}

	scan_crons() {
		local path="$1"

		if [ -f "$path" ]; then
			print_crons "$path"
		elif [ -d "$path" ]; then
			for file in "$path"/*; do
				if [ -f "$file" ]; then
					print_crons "$file"
				fi
			done
		fi
	}

	for file in "${cron_files[@]}"; do
		if [ -e "$file" ]; then
			scan_crons "$file"
		fi
	done

	for dir in "${user_cron_directories[@]}"; do
		if [ -d "$dir" ]; then
			for user_cron in "$dir"/*; do
				if [ -f "$user_cron" ]; then
					scan_crons "$user_cron"
				fi
			done
		fi
	done
}

# -----------------------------------------------------------
# NETWORK
# -----------------------------------------------------------
get_network() {
	echo $(log_header "NETWORK")
	echo

	echo $(log_value "Hosts" "")
	hosts=$(cat $MOUNT_POINT/etc/hosts | egrep -v "^#")
	echo "$hosts"
	echo

	echo $(log_value "DNS" "")

	if [ -f "$MOUNT_POINT/etc/resolv.conf" ]; then
		dns=$(cat $MOUNT_POINT/etc/resolv.conf | egrep -v "^#")
		echo "$dns"
	else
		echo "/etc/resolv.conf file does not exist..."
	fi

	echo

	echo $(log_value "Interfaces" "")

	get_key() {
		local key=$1
		local file=$2

		echo "$(grep $key $file | tr -d '"' | cut -d "=" -f 2)"
	}

	debian="$MOUNT_POINT/etc/network/interfaces"
	rhel="$MOUNT_POINT/etc/sysconfig/network-scripts/ifcfg-*"

	if [ -f $debian ]; then
		interfaces="$(cat $debian | grep "iface")"

		while IFS= read -r line; do
			int="$(echo $line | cut -d " " -f 2)"
			type="$(echo $line | cut -d " " -f 4)"

			echo -e "${BOLD_PINK}$int:${RESET}"

			if [ "$type" == "dhcp" ]; then
				lease_config="$(cat $MOUNT_POINT/var/lib/dhcp/dhclient.$int.leases)"

				ip_address="$(echo "$lease_config" | grep -oP "fixed-address \K\d{1,3}(\.\d{1,3}){3}" | tail -n 1)"
				subnet_mask="$(echo "$lease_config" | grep -oP "subnet-mask \K\d{1,3}(\.\d{1,3}){3}" | tail -n 1)"
				default_gateway="$(echo "$lease_config" | grep -oP "routers \K\d{1,3}(\.\d{1,3}){3}" | tail -n 1)"
				renew_time="$(echo "$lease_config" | grep -oP 'renew \d+ \K\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}' | tail -n 1)"
				
				echo -e "  ${BOLD}Type:${RESET} $type"
				echo -e "  ${BOLD}IP:${RESET} $ip_address"
				echo -e "  ${BOLD}Mask:${RESET} $subnet_mask"
				echo -e "  ${BOLD}Gateway:${RESET} $default_gateway"
				echo -e "  ${BOLD}Set Time:${RESET} $renew_time"
			else
				echo -e "  ${BOLD}Type:${RESET} $type"
			fi

			echo
		done <<< "$interfaces"
	elif [ ! -z "$(cat $rhel)" ]; then
		for config in $(ls $rhel); do
			local uuid="$(get_key "UUID" "$config")"
			local int="$(get_key "DEVICE" "$config")"
			local type="$(get_key "BOOTPROTO" "$config")"

			echo -e "${BOLD_PINK}$int:${RESET}"

			if [ "$type" == "dhcp" ]; then
				lease_config="$(cat $MOUNT_POINT/var/lib/NetworkManager/dhclient-$uuid*)"

				ip_address="$(echo "$lease_config" | grep -oP "fixed-address \K\d{1,3}(\.\d{1,3}){3}" | tail -n 1)"
				subnet_mask="$(echo "$lease_config" | grep -oP "subnet-mask \K\d{1,3}(\.\d{1,3}){3}" | tail -n 1)"
				default_gateway="$(echo "$lease_config" | grep -oP "routers \K\d{1,3}(\.\d{1,3}){3}" | tail -n 1)"
				renew_time="$(echo "$lease_config" | grep -oP 'renew \d+ \K\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}' | tail -n 1)"
				
				echo -e "  ${BOLD}Type:${RESET} $type"
				echo -e "  ${BOLD}IP:${RESET} $ip_address"
				echo -e "  ${BOLD}Mask:${RESET} $subnet_mask"
				echo -e "  ${BOLD}Gateway:${RESET} $default_gateway"
				echo -e "  ${BOLD}Set Time:${RESET} $renew_time"
			else
				echo -e "  ${BOLD}Type:${RESET} static"
				echo -e "  ${BOLD}IP:${RESET} $(get_key "IPADDR" "$config")"
				echo -e "  ${BOLD}Mask:${RESET} $(get_key "NETMASK" "$config")"
			fi
			
			echo
		done
	else
		echo "Cannot find network configurations..."
		echo
	fi
}

# -----------------------------------------------------------
# LAST MODIFIED
# -----------------------------------------------------------
get_last_modified() {
	echo $(log_header "LAST MODIFIED")
	echo

	last_modified="$(find $MOUNT_POINT -type f -printf '%TY-%Tm-%Td %TH:%TM:%TS %p\n' 2>/dev/null | sort | tail -n 20)"
	echo "$last_modified"

	echo
}

# -----------------------------------------------------------
# SESSIONS
# -----------------------------------------------------------
get_remote_sessions() {
	
	echo $(log_header "REMOTE SESSIONS")
	echo

	if [ -e $MOUNT_POINT/var/log/auth.log ]; then
		output="$(egrep "session opened|session closed" $MOUNT_POINT/var/log/auth.log | awk '{print "state:", $8,"\t|\t", "user:", $11,"\t|\t", "timestamp: ", $1, $2, $3}' | tail)"
	elif [ -e $MOUNT_POINT/var/log/secure ]; then
		output="$(egrep "session opened|session closed" $MOUNT_POINT/var/log/secure | awk '{print "state:", $8,"\t|\t", "user:", $11,"\t|\t", "timestamp: ", $1, $2, $3}' | tail)"
	else
		output="Cannot find remote session information..."
	fi

	echo "$output"
	echo
}

# -----------------------------------------------------------
# LAST LOGINS
# -----------------------------------------------------------
get_last_logins() {
	echo $(log_header "LAST LOGINS")
	echo

	local output="$(lastlog -R $MOUNT_POINT | egrep -v "\*\*Never")"

	if [ "$MOUNT_POINT/var/log/lastlog" ]; then
		if [ "$output" ]; then
			while IFS= read -r line; do
				if [ "$(echo $line | egrep -v "Username|Port|From|Latest")" ]; then
					is_ip="$(echo $line | grep -oP '\b\d{1,3}(\.\d{1,3}){3}\b')"

					local user="$(echo $line | cut -d " " -f 1)"
					local type="$(echo $line | cut -d " " -f 2)"

						echo -e "${BOLD_PINK}$user${RESET}:"
						echo -e "  ${BOLD}Type: ${RESET}$type"
					if [ "$is_ip" ]; then
						local from="$(echo $line | cut -d " " -f 3)"
						local date_time="$(echo $line | cut -d " " -f 4-10)"

						echo -e "  ${BOLD}From: ${RESET}$from (Remote)"
						echo -e "  ${BOLD}Date/Time: ${RESET}$date_time"
						echo
					else
						local date_time="$(echo $line | cut -d " " -f 3-10)"

						echo -e "  ${BOLD}From: ${RESET}Local"
						echo -e "  ${BOLD}Date/Time: ${RESET}$date_time"
						echo
					fi
				fi
			done <<< "$output"
		else
			echo "/var/log/lastlog is empty..."
			echo
		fi
	else
		echo "/var/log/lastlog does not exist..."
		echo
	fi
}

# -----------------------------------------------------------
# WEB LOGS
# -----------------------------------------------------------
get_web_logs() {
	echo $(log_header "WEB LOGS")
	echo

	local log_file="$MOUNT_POINT/var/log/apache2/access.log"

	if [ -f "$log_file" ]; then
		echo -e "$(log_value "IP Addresses" "")"
		awk '{print $1}' "$log_file" | sort | uniq -c | sort -nr | head -n 10
		echo

		echo -e "$(log_value "User Agents" "")"
		local anomalous_useragents="wpscan"
		awk -F '"' '{print $6}' "$log_file" | sort | uniq -c | sort -nr | head -n 10 | egrep --color=always -i "$anomalous_useragents|$"
		echo

		query="$(cat $log_file | cut -d " " -f 1,4-7 | grep "POST" | grep "plugins" | head -n 10 )"
		if [ ! -z "$query" ]; then
			echo -e "$(log_value "Plugins" "")"
			echo "$query"
		fi
		echo

		query="$(cat $log_file | cut -d " " -f 1,4-7 | grep "POST" | grep "theme" | head -n 10 )"
		if [ ! -z "$query" ]; then
			echo -e "$(log_value "Themes" "")"
			echo "$query"
		fi
		echo

		query="$(cat $log_file | cut -d " " -f 1,4-7 | egrep --color=always "c99.php|shell.php|shell=|exec=|cmd=|act=|whoami|pwd|base64|eval" | head -n 10 )"
		if [ ! -z "$query" ]; then
			echo -e "$(log_value "Potential Shells" "")"
			echo "$query"
		fi
		echo

		query="$(cat $log_file | cut -d " " -f 1,4-7 | egrep --color=always "\.(exe|sh|bin|zip|tar|gz|rar|pl|py|rb|log|bak)$" | head -n 10 )"
		if [ ! -z "$query" ]; then
			echo -e "$(log_value "Anomalous Extensions" "")"
			echo "$query"
		fi
		echo

		query="$(cat $log_file | cut -d " " -f 1,4-7 | egrep "wp-content/uploads" | tail -n 10 )"
		if [ ! -z "$query"]; then
			echo -e "$(log_value "Uploaded Content" "")"
			echo "$query"
		fi
	else
		echo "Apache logs do not exist..."
		echo
	fi
}

# -----------------------------------------------------------
# COMMAND HISTORY
# -----------------------------------------------------------
get_command_history() {
	echo $(log_header "COMMAND HISTORY")
	echo

	local users=$(egrep "(bash|zsh)" $MOUNT_POINT/etc/passwd | tr -d ' ')
	local keywords="/tmp|/etc|whoami|id|passwd"

	for line in $users; do
		local user=$(echo "${line}" | cut -d ":" -f 1)
		local shell=$(echo "${line}" | cut -d ":" -f 7 | egrep "(bash|zsh)")
		local home="$(grep "^$user" $MOUNT_POINT/etc/passwd | cut -d ":" -f 6)"

		if [[ $shell =~ "zsh" ]]; then
			dir="$home/.zsh_history"
		else
			dir="$home/.bash_history"
		fi

		if [ -f "$dir" ]; then
			history="$(cat $MOUNT_POINT$dir | egrep --color=always "$keywords|$")"
		else
			history="Cannot find history file..."
		fi

		echo -e "$(log_value "$user ($dir)" "")"
		echo "$history"
		echo
	done
}

# -----------------------------------------------------------
# TEMPORARY FILES
# -----------------------------------------------------------
get_temp_files() {
	echo $(log_header "TMP FILES")
	echo

	echo "$(ls -lh $MOUNT_POINT/tmp)"

	echo
}

# -----------------------------------------------------------
# APACHE CONFIG
# -----------------------------------------------------------
get_apache_config() {
	echo $(log_header "APACHE CONFIG")
	echo

	local dir="$MOUNT_POINT/etc/apache2/sites-enabled"

	if [ -d "$dir" ]; then
		for file in "$dir"/*; do
			if [ -f "$file" ]; then
				local filename="$(basename "$file")"

				echo -e "$(log_value "$filename" "")"
				echo "$(cat $file | grep -v "#")"
				echo
			fi
		done
	else
		echo "Apache is not installed..."
		echo
	fi
}

execute_all() {
	show_banner

	# if MOUNT_REQUIRED is set, mount the image
	if [ $MOUNT_REQUIRED -eq 1 ]; then
		mount_image
	fi

	initial_checks
	get_device_settings
	get_users
	get_command_history
	get_temp_files
	get_backup_diff
	get_installed_software
	get_cron_jobs
	get_network
	get_remote_sessions
	get_last_logins
	get_apache_config
	get_web_logs
}

execute_all