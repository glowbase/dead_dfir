#!/bin/bash

clear
export GREP_COLOR="01;35"

MOUNT_POINT="$1"
TIME_ZONE="$2"

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

# Check if the mount point exists
if [ ! -d "$MOUNT_POINT" ]; then
  echo "Error: Mount point $MOUNT_POINT does not exist."
  exit 1
fi

get_timezone() {
  if [ -f "$MOUNT_POINT/etc/timezone" ]; then
    echo "$(cat $MOUNT_POINT/etc/timezone)"
  else
  echo "$(realpath $MOUNT_POINT/etc/localtime | sed 's/.*zoneinfo\///')"
  fi
}

# Change timezone based on user input and target
timezone="$(get_timezone)"

if [ ! "$TIME_ZONE" ]; then
	export TZ="$timezone"
else 
	export TZ="$TIME_ZONE"
fi

convert_timestamp() {
  local timestamp="$1"
  # Convert timestamp to the target timezone
  # Assumes the format of timestamp is YYYY-MM-DD HH:MM:SS for conversion
  date -d "$timestamp $from_tz" +"%Y-%m-%d %H:%M:%S" -u | TZ="$to_tz" date +"%Y-%m-%d %H:%M:%S"
}

# -----------------------------------------------------------
# MOUNT IMAGE
# -----------------------------------------------------------
mount_image() {
  echo 'eofijwoif'
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
    echo -e "  ${BOLD}Groups: ${RESET}$groups"
    echo -e "  ${BOLD}Home: ${RESET}$home"
    echo
  done
}

# -----------------------------------------------------------
# SUDOERS
# -----------------------------------------------------------
get_sudoers() {
  echo $(log_header "SUDOERS")
  echo

  if [ "$MOUNT_POINT/etc/sudoers" ]; then
    sudoers="$(grep -v "#" $MOUNT_POINT/etc/sudoers | egrep -v "^$|Defaults")"

    echo "$sudoers" | sed -e 's/^[%@]*\([a-zA-Z0-9_-]*\)[ \t]*\(.*\)/\x1b[1;35m\1\x1b[0m \2/'
  else
    echo "'/etc/sudoers' file not found..."
  fi

  if [ "$MOUNT_POINT/etc/group" ]; then

    local admins="$(egrep -i "^sudo|^admin|^wheel" "$MOUNT_POINT/etc/group")"
    
    for group in $admins; do
    groupname="${group%%:*}"

    echo
    echo $(log_value "$groupname" "")
    echo "${group##*:}" | tr ',' '\n'

    done
  fi
  echo
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
      echo "$(diff $file- $file)"
      echo
    elif [ -f "$file~" ]; then
      echo -e "$(log_value "$name" "")"
      echo "$(diff $file~ $file)"
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

  local software="wget|curl|php|mysql"

  if [ -f "$dpkg" ]; then
    echo "$(cat "$dpkg" | grep " installed " | egrep --color=always "$software|$" )"
  elif [ -f "$yum" ]; then
    echo "$(grep -i installed $yum | sed -e "s/Installed: //" | egrep --color=always "$software|$")"
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

  local patterns="wget|curl|nc|bash|sh|base64|eval|exec|/tmp/|/dev/|perl|python|ruby|nmap|tftp|nc|php"

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

    echo -e $(log_value "$file" "")
    echo "$(cat "$file" | grep -v "#" | egrep --color=always "$patterns" )"
    echo
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
  dns=$(cat $MOUNT_POINT/etc/resolv.conf | egrep -v "^#")
  echo "$dns"
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
    output="$(egrep "session opened|session closed" $MOUNT_POINT/var/log/auth.log | awk '{print "state:", $8,"\t|\t", "user:", $11,"\t|\t", "timestamp: ", $1, $2, $3}')"
  elif [ -e $MOUNT_POINT/var/log/secure ]; then
    output="$(egrep "session opened|session closed" $MOUNT_POINT/var/log/secure | awk '{print "state:", $8,"\t|\t", "user:", $11,"\t|\t", "timestamp: ", $1, $2, $3}')"
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

    echo -e "$(log_value "Possible Brute-Force Attempts" "")"
    awk '{print $1, $4}' "$log_file" | sed 's/\[//; s/\]//; s/:/ /; s/\// /g' | awk '{print $1, $2, $3, $4, $5}' | sort | uniq -c | sort -nr | head -n 10
    echo
  else
    echo "Apache logs do not exist..."
    echo
  fi
}

# -----------------------------------------------------------
# WORDPRESS
# -----------------------------------------------------------
get_wordpress_logs() {
  echo $(log_header "WORDPRESS")
  echo

  local log_file="$MOUNT_POINT/var/log/apache2/access.log"

  if [ -f "$log_file" ]; then
    # if cat $log_file | head -n 10 | egrep -q "wp-admin|wp-login|wp-content|wp"; then
      echo -e "$(log_value "Plugins" "")"
      query="$(cat $log_file | cut -d " " -f 1,4-7 | grep "POST" | grep "plugins" | head -n 10 )"
      echo "$query"
      echo

      echo -e "$(log_value "Themes" "")"
      query="$(cat $log_file | cut -d " " -f 1,4-7 | grep "POST" | grep "theme" | head -n 10 )"
      echo "$query"
      echo

      echo -e "$(log_value "Potential Shells" "")"
      query="$(cat $log_file | cut -d " " -f 1,4-7 | egrep --color=always "c99.php|shell.php|shell=|exec=|cmd=|act=|whoami|pwd|base64" | head -n 10 )"
      echo "$query"
      echo

      echo -e "$(log_value "Anomalous Extensions" "")"
      query="$(cat $log_file | cut -d " " -f 1,4-7 | egrep --color=always "\.(exe|sh|bin|zip|tar|gz|rar|pl|py|rb|log|bak)$" | head -n 10 )"
      echo "$query"
      echo

      echo -e "$(log_value "Uploaded Content" "")"
      query="$(cat $log_file | cut -d " " -f 1,4-7 | egrep "wp-content/uploads" | tail -n 10 )"
      echo "$query"
    # else
    #   echo "Does not appear to be a WordPress site..."
    # fi
  else
    echo "Apache logs do not exist..."
  fi

  echo
}

# -----------------------------------------------------------
# COMMAND HISTORY
# -----------------------------------------------------------
get_command_history() {
  echo $(log_header "COMMAND HISTORY")
  echo

  local users=$(egrep "bash|zsh" $MOUNT_POINT/etc/passwd)

  for line in $users; do
    local id=$(echo "${line}" | cut -d ":" -f 2)
    local user=$(echo "${line}" | cut -d ":" -f 1)
    local shell=$(echo "${line}" | cut -d ":" -f 7 | egrep "bash|zsh")
    local home="$(grep "^$user" $MOUNT_POINT/etc/passwd | cut -d ":" -f 6)"

    if [ $shell == "zsh" ]; then
      dir="$home/.zsh_history"
    else
      dir="$home/.bash_history"
    fi

    if [ -f "$dir" ]; then
      history="$(cat $MOUNT_POINT$dir)"
    else
      history="Cannot find history file..."
    fi

    echo -e "$(log_value "$user ($dir)" "")"
    echo "$history"
    echo
  done
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
  get_device_settings
  get_users
  get_sudoers
  get_backup_diff
  get_command_history
  get_installed_software
  get_cron_jobs
  get_network
  get_remote_sessions
  get_last_logins
  get_apache_config
  get_web_logs
  get_wordpress_logs

  echo -e "${RED}${DIV}| FINISHED |${DIV}${RESET}"
}

execute_all