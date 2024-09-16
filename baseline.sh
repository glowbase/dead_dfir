#!/bin/bash

# Define log colour 
RED='\033[31m'
GREEN='\033[32m'
BLUE='\033[34m'
CYAN='\033[35m'
RESET='\033[0m'
BOLD='\033[1m'
BOLD_PINK='\033[1;35m'
DIV="=============================="

log_header() {
  local heading=$1
  local sub_heading=$2

  # No subheading
  if [ -z "$sub_heading" ]; then
    echo  -e "${BLUE}${DIV}|${BOLD}${GREEN} ${heading} ${RESET}${BLUE}|${DIV}${RESET}"
  else
    echo  -e "${BLUE}${DIV}|${BOLD}${GREEN} ${heading} - ${sub_heading} ${RESET}${BLUE}|${DIV}${RESET}"
  fi
}

log_value() {
  local title=$1
  local val=$2

  echo -e "${RED}${BOLD}[+] ${BLUE}${title}: ${RESET}${val}"
}

get_file_property() {
  local key=$1
  local file=$2
  
  echo $(cat $file | grep $key | cut -d '"' -f 2)
}

# Set timezone to UTC
export TZ="UTC"

# Use the provided mount point
MOUNT_POINT="$1"

# Check if the mount point exists
if [ ! -d "$MOUNT_POINT" ]; then
  echo "Error: Mount point $MOUNT_POINT does not exist."
  exit 1
fi

echo $(log_header "DEVICE SETTINGS")

# -----------------------------------------------------------
# OS VERSION
# -----------------------------------------------------------
if [ -f "$MOUNT_POINT/etc/os-release" ]; then
  os_version=$(get_file_property "PRETTY_NAME" $MOUNT_POINT/etc/os-release)
elif [ -f "$MOUNT_POINT/etc/lsb-release" ]; then
  os_version=$(get_file_property "PRETTY_NAME" $MOUNT_POINT/etc/lsb-release)
elif [ -f "$MOUNT_POINT/etc/redhat-release" ]; then
  os_version=$(get_file_property "PRETTY_NAME" $MOUNT_POINT/etc/redhat-release)
elif [ -f "$MOUNT_POINT/etc/debian_version" ]; then
  os_version=$(get_file_property "PRETTY_NAME" $MOUNT_POINT/etc/debian_version)
else
  os_version="Not Found"
fi

echo $(log_value "OS Version" "${os_version}")

# -----------------------------------------------------------
# KERNEL VERSION
# -----------------------------------------------------------
kernel_ver=$(ls $MOUNT_POINT/lib/modules | cut -d "." -f 1-4)
echo $(log_value "Kernel Version" "${kernel_ver}")

# -----------------------------------------------------------
# PROCESSOR ARCHITECTURE
# -----------------------------------------------------------
proc_arch=$(ls $MOUNT_POINT/lib/modules | cut -d "." -f 5 )
echo $(log_value "Processor Architecture" "${proc_arch}")

# -----------------------------------------------------------
# TIME ZONE
# -----------------------------------------------------------
# https://forums.ni.com/t5/NI-Linux-Real-Time-Discussions/Timezones/td-p/3693784

timezone="$(realpath $MOUNT_POINT/etc/localtime | sed 's/.*zoneinfo\///')"
echo $(log_value "Time Zone" "${timezone}")

# -----------------------------------------------------------
# LAST SHUTDOWN
# -----------------------------------------------------------
last_shutdown=$( last -x -f $MOUNT_POINT/var/log/wtmp | grep shutdown | head -n 1 | cut -d " " -f 7,9-10)
echo $(log_value "Last Shutdown" "${last_shutdown}")

# -----------------------------------------------------------
# USERS
# -----------------------------------------------------------
echo $(log_header "USERS")

users=$(grep "/home" $MOUNT_POINT/etc/passwd | cut -d ":" -f 1,3)

for userid in $users; do
  id=$(echo "${userid}" | cut -d ":" -f 2)
  user=$(echo "${userid}" | cut -d ":" -f 1)

  groups=$(cat $MOUNT_POINT/etc/group | grep $user | cut -d ":" -f 1 | sed ':a;N;$!ba;s/\n/, /g')

  echo -e "${CYAN}${BOLD}$user${RESET} ($id): $groups"
done

# -----------------------------------------------------------
# SUDOERS
# -----------------------------------------------------------
echo $(log_header "SUDOERS")

if [ -f "$MOUNT_POINT/etc/sudoers" ]; then
  sudoers="$(grep -v "#" $MOUNT_POINT/etc/sudoers | egrep -v "^$|Defaults")"

  echo "$sudoers" | sed -e 's/^[%@]*\([a-zA-Z0-9_-]*\)[ \t]*\(.*\)/\x1b[1;35m\1\x1b[0m \2/'
else
  echo $(log_value "'/etc/sudoers' file not found..." "")
fi

# -----------------------------------------------------------
# INSTALLED SOFTWARE
# -----------------------------------------------------------
echo $(log_header "INSTALLED SOFTWARE")

if [ -f "$MOUNT_POINT/var/log/dpkg.log" ]; then
 echo
elif [ -f "$MOUNT_POINT/var/log/yum.log" ]; then
  packages=$(grep -i installed $MOUNT_POINT/var/log/yum.log)
  highlighted=$(echo "${packages}" | cut -d " " -f 1-3,5 | sed -e 's/^\(.*\) \([^-]*\)-\(.*\)/\1 \x1b[1;35m\2\x1b[0m-\3/')

  echo "$highlighted"
else
  echo $(log_value "Could't find Installed Software..." "")
fi

# -----------------------------------------------------------
# CRON JOBS
# -----------------------------------------------------------
echo $(log_header "CRON JOBS")

suspicious_patterns=(
    "wget"
    "curl"
    "nc"
    "bash"
    "sh"
    "base64"
    "eval"
    "exec"
    "/tmp/"
    "/dev/"
    "perl"
    "python"
    "ruby"
    "nmap"
    "tftp"
    "nc"
)

cron_files=(
    "$MOUNT_POINT/etc/crontab"
    "$MOUNT_POINT/etc/cron.d"
    "$MOUNT_POINT/etc/cron.hourly"
    "$MOUNT_POINT/etc/cron.daily"
    "$MOUNT_POINT/etc/cron.weekly"
    "$MOUNT_POINT/etc/cron.monthly"
)

user_cron_directories=(
    "$MOUNT_POINT/var/spool/cron/crontabs" # Debian/Ubuntu
    "$MOUNT_POINT/var/spool/cron"          # Red Hat/CentOS
)

escape_sed_delimiters() {
    local string="$1"
    echo "$string" | sed 's/[.[\*^$]/\\&/g'
}

is_suspicious() {
    local line="$1"

	for pattern in "${suspicious_patterns[@]}"; do
		if echo "$line" | grep -q "$pattern"; then
			return 0
		fi
	done

    return 1
}

scan_cron_jobs() {
    local path="$1"

    if [ -f "$path" ]; then
        echo -e $(log_value "$file" "")

        while IFS= read -r line; do
            if is_suspicious "$line"; then
				echo "$line"
			fi
        done < "$path"
    elif [ -d "$path" ]; then
        for file in "$path"/*; do
            if [ -f "$file" ]; then
                echo -e $(log_value "$file" "")

                while IFS= read -r line; do
                    if is_suspicious "$line"; then
                        echo "$line"
                    fi
                done < "$file"
            fi
        done
    fi
}

found_suspicious=false
for file in "${cron_files[@]}"; do
    if [ -e "$file" ]; then
        scan_cron_jobs "$file"
        found_suspicious=true
    fi
done

for dir in "${user_cron_directories[@]}"; do
    if [ -d "$dir" ]; then
        for user_cron in "$dir"/*; do
            if [ -f "$user_cron" ]; then
                scan_cron_jobs "$user_cron"
                found_suspicious=true
            fi
        done
    fi
done

if [ "$found_suspicious" = false ]; then
    echo "No Suspicious Crons Found..."
fi
# -----------------------------------------------------------
# NETWORK
# -----------------------------------------------------------
echo $(log_header "NETWORK")



echo -e "${RED}${DIV}| FINISHED |${DIV}${RESET}"
