trap on_exit INT QUIT TERM

# Color print functions
print_red() { printf '\033[0;31;31m%s\033[0m' "$1"; }
print_green() { printf '\033[0;31;32m%s\033[0m' "$1"; }
print_yellow() { printf '\033[0;31;33m%s\033[0m' "$1"; }
print_blue() { printf '\033[0;31;36m%s\033[0m' "$1"; }

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Cleanup function
on_exit() {
    print_red "\nScript terminated. Cleaning up...\n"
    rm -fr speedtest.tgz speedtest-cli benchtest_*
    exit 1
}

# Get OS information
get_os_info() {
    [ -f /etc/redhat-release ] && cat /etc/redhat-release && return
    [ -f /etc/os-release ] && awk -F'[= "]' '/PRETTY_NAME/{print $3,$4,$5}' /etc/os-release && return
    [ -f /etc/lsb-release ] && awk -F'[="]+' '/DESCRIPTION/{print $2}' /etc/lsb-release && return
}

# Draw a separator line
draw_line() {
    printf "%-70s\n" "-" | tr ' ' '-'
}

# Run speed test
run_speed_test() {
    local nodeName="$2"
    local server_id="$1"
    local cmd="./speedtest-cli/speedtest --progress=no --accept-license --accept-gdpr"
    [ -n "$server_id" ] && cmd+=" --server-id=$server_id"
    $cmd >./speedtest-cli/speedtest.log 2>&1
    
    if [ $? -eq 0 ]; then
        local dl_speed up_speed latency
        dl_speed=$(awk '/Download/{print $3" "$4}' ./speedtest-cli/speedtest.log)
        up_speed=$(awk '/Upload/{print $3" "$4}' ./speedtest-cli/speedtest.log)
        latency=$(awk '/Latency/{print $3" "$4}' ./speedtest-cli/speedtest.log)
        [ -n "$dl_speed" ] && [ -n "$up_speed" ] && [ -n "$latency" ] && \
        printf "\033[0;33m%-18s\033[0;32m%-18s\033[0;31m%-20s\033[0;36m%-12s\033[0m\n" \
        "$nodeName" "$up_speed" "$dl_speed" "$latency"
    fi
}

# Run all speed tests
run_all_speed_tests() {
    run_speed_test '' 'Speedtest.net'
    run_speed_test '21541' 'Los Angeles, US'
    run_speed_test '43860' 'Dallas, US'
    run_speed_test '40879' 'Montreal, CA'
    run_speed_test '24215' 'Paris, FR'
    run_speed_test '28922' 'Amsterdam, NL'
    run_speed_test '24447' 'Shanghai, CN'
    run_speed_test '5530' 'Chongqing, CN'
    run_speed_test '60572' 'Guangzhou, CN'
    run_speed_test '32155' 'Hongkong, CN'
    run_speed_test '23647' 'Mumbai, IN'
    run_speed_test '13623' 'Singapore, SG'
    run_speed_test '21569' 'Tokyo, JP'
}

# I/O test
io_test() {
    (dd if=/dev/zero of=benchtest_$$ bs=512k count="$1" conv=fdatasync && rm -f benchtest_$$) 2>&1 | awk -F '[,，]' '{io=$NF} END {print io}'
}

# Convert to human-readable size
convert_size() {
    local size="$1"
    local unit="KB"
    local factor=1

    if [ "$size" -ge 1073741824 ]; then
        unit="TB"; factor=1073741824
    elif [ "$size" -ge 1048576 ]; then
        unit="GB"; factor=1048576
    elif [ "$size" -ge 1024 ]; then
        unit="MB"; factor=1024
    fi

    printf "%.1f %s\n" "$(awk "BEGIN {print $size / $factor}")" "$unit"
}

# Sum an array
sum_array() {
    local total=0
    for num in "$@"; do
        total=$((total + num))
    done
    echo "$total"
}

# Check virtualization
check_virtualization() {
    local virtualx sys_manu sys_product sys_ver
    command_exists "dmesg" && virtualx="$(dmesg 2>/dev/null)"
    command_exists "dmidecode" && {
        sys_manu=$(dmidecode -s system-manufacturer 2>/dev/null)
        sys_product=$(dmidecode -s system-product-name 2>/dev/null)
        sys_ver=$(dmidecode -s system-version 2>/dev/null)
    }

    if grep -qa docker /proc/1/cgroup; then
        virt="Docker"
    elif grep -qa lxc /proc/1/cgroup; then
        virt="LXC"
    elif grep -qa container=lxc /proc/1/environ; then
        virt="LXC"
    elif [[ -f /proc/user_beancounters ]]; then
        virt="OpenVZ"
    elif [[ "$virtualx" == *kvm-clock* ]] || [[ "$sys_product" == *KVM* ]] || [[ "$sys_manu" == *QEMU* ]]; then
        virt="KVM"
    elif [[ "$virtualx" == *"VMware Virtual Platform"* ]] || [[ "$sys_product" == *"VMware Virtual Platform"* ]]; then
        virt="VMware"
    elif [[ "$virtualx" == *"Parallels"* ]]; then
        virt="Parallels"
    elif [[ "$virtualx" == *VirtualBox* ]]; then
        virt="VirtualBox"
    elif [ -e /proc/xen ]; then
        virt="Xen"
    elif [[ "$sys_manu" == *"Microsoft Corporation"* && "$sys_product" == *"Virtual Machine"* ]]; then
        virt="Hyper-V"
    else
        virt="Dedicated"
    fi
}

# Get IPv4 info
get_ipv4_info() {
    local org city country region
    org=$(wget -q -T10 -O- ipinfo.io/org)
    city=$(wget -q -T10 -O- ipinfo.io/city)
    country=$(wget -q -T10 -O- ipinfo.io/country)
    region=$(wget -q -T10 -O- ipinfo.io/region)

    [ -n "$org" ] && echo " Organization: $(print_blue "$org")"
    [ -n "$city" ] && [ -n "$country" ] && echo " Location: $(print_blue "$city / $country")"
    [ -n "$region" ] && echo " Region: $(print_yellow "$region")"
    [ -z "$org" ] && echo " Region: $(print_red "No ISP detected")"
}

# Install speedtest-cli
install_speedtest() {
    if [ ! -e "./speedtest-cli/speedtest" ]; then
        local sysarch
        sysarch=$(uname -m)

        case "$sysarch" in
            x86_64) arch="x86_64" ;;
            i386|i686) arch="i386" ;;
            armv8|aarch64) arch="aarch64" ;;
            armv7|armv7l) arch="armhf" ;;
            armv6) arch="armel" ;;
            *) print_red "Unsupported architecture: $sysarch\n"; exit 1 ;;
        esac

        url="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-${arch}.tgz"
        wget --no-check-certificate -q -T10 -O speedtest.tgz "$url" || {
            print_red "Failed to download speedtest-cli.\n"
            exit 1
        }
        
        mkdir -p speedtest-cli && tar zxf speedtest.tgz -C speedtest-cli && chmod +x speedtest-cli/speedtest
        rm -f speedtest.tgz
    fi

    printf "%-18s%-18s%-20s%-12s\n" "Node Name" "Upload Speed" "Download Speed" "Latency"
}

# Print script intro
print_intro() {
    echo "---------------- benchmark.sh Script by Syauqqii ----------------"
    echo " Version: $(print_green "v2024-09-07")"
    echo " Usage: $(print_red "wget -qO- https://github.com/bench/benchmark.sh | bash")"
}
