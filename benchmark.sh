trap cleanup_script INT QUIT TERM

print_red() { printf '\033[0;31;31m%b\033[0m' "$1" }
print_green() { printf '\033[0;31;32m%b\033[0m' "$1" }
print_yellow() { printf '\033[0;31;33m%b\033[0m' "$1" }
print_cyan() { printf '\033[0;31;36m%b\033[0m' "$1" }

check_command() {
    local command_name="$1"
    if eval type type >/dev/null 2>&1; then
        eval type "$command_name" >/dev/null 2>&1
    elif command >/dev/null 2>&1; then
        command -v "$command_name" >/dev/null 2>&1
    else
        which "$command_name" >/dev/null 2>&1
    fi
    return $?
}

cleanup_script() {
    print_red "\nScript dihentikan. Membersihkan file sementara...\n"
    rm -fr speedtest.tgz speedtest-cli benchmark_*
    exit 1
}

get_os_info() {
    [ -f /etc/redhat-release ] && awk '{print $0}' /etc/redhat-release && return
    [ -f /etc/os-release ] && awk -F'[= "]' '/PRETTY_NAME/{print $3,$4,$5}' /etc/os-release && return
    [ -f /etc/lsb-release ] && awk -F'[="]+' '/DESCRIPTION/{print $2}' /etc/lsb-release && return
}

draw_line() {
    printf "%-70s\n" "-" | sed 's/\s/-/g'
}

run_speedtest() {
    local test_server="$2"
    if [ -z "$1" ]; then
        ./speedtest-cli/speedtest --progress=no --accept-license --accept-gdpr >./speedtest-cli/speedtest.log 2>&1
    else
        ./speedtest-cli/speedtest --progress=no --server-id="$1" --accept-license --accept-gdpr >./speedtest-cli/speedtest.log 2>&1
    fi
    if [ $? -eq 0 ]; then
        local download_rate upload_rate ping
        download_rate=$(awk '/Download/{print $3" "$4}' ./speedtest-cli/speedtest.log)
        upload_rate=$(awk '/Upload/{print $3" "$4}' ./speedtest-cli/speedtest.log)
        ping=$(awk '/Latency/{print $3" "$4}' ./speedtest-cli/speedtest.log)
        if [[ -n "${download_rate}" && -n "${upload_rate}" && -n "${ping}" ]]; then
            printf "\033[0;33m%-18s\033[0;32m%-18s\033[0;31m%-20s\033[0;36m%-12s\033[0m\n" " ${test_server}" "${upload_rate}" "${download_rate}" "${ping}"
        fi
    fi
}

test_speed() {
    run_speedtest '' 'Speedtest.net'
    run_speedtest '21541' 'Los Angeles, US'
    run_speedtest '43860' 'Dallas, US'
    run_speedtest '40879' 'Montreal, CA'
    run_speedtest '24215' 'Paris, FR'
    run_speedtest '28922' 'Amsterdam, NL'
    run_speedtest '24447' 'Shanghai, CN'
    run_speedtest '5530' 'Chongqing, CN'
    run_speedtest '60572' 'Guangzhou, CN'
    run_speedtest '32155' 'Hongkong, CN'
    run_speedtest '23647' 'Mumbai, IN'
    run_speedtest '13623' 'Singapore, SG'
    run_speedtest '21569' 'Tokyo, JP'
}

disk_io_test() {
    (LANG=C dd if=/dev/zero of=benchmark_$$ bs=512k count="$1" conv=fdatasync && rm -f benchmark_$$) 2>&1 | awk -F '[,，]' '{io=$NF} END { print io}' | sed 's/^[ \t]*//;s/[ \t]*$//'
}

calculate_size() {
    local raw_value=$1
    local result=0
    local factor=1
    local unit="KB"
    if ! [[ ${raw_value} =~ ^[0-9]+$ ]]; then
        echo ""
        return
    fi
    if [ "${raw_value}" -ge 1073741824 ]; then
        factor=1073741824
        unit="TB"
    elif [ "${raw_value}" -ge 1048576 ]; then
        factor=1048576
        unit="GB"
    elif [ "${raw_value}" -ge 1024 ]; then
        factor=1024
        unit="MB"
    elif [ "${raw_value}" -eq 0 ]; then
        echo "${result}"
        return
    fi
    result=$(awk 'BEGIN{printf "%.1f", '"$raw_value"' / '$factor'}')
    echo "${result} ${unit}"
}

convert_to_kb() {
    local byte_value=$1
    awk 'BEGIN{printf "%.0f", '"$byte_value"' / 1024}'
}

sum_values() {
    local values=("$@")
    local total
    total=0
    for value in "${values[@]}"; do
        total=$((total + value))
    done
    echo ${total}
}

detect_virtualization() {
    check_command "dmesg" && virt_log="$(dmesg 2>/dev/null)"
    if check_command "dmidecode"; then
        system_maker="$(dmidecode -s system-manufacturer 2>/dev/null)"
        system_product="$(dmidecode -s system-product-name 2>/dev/null)"
        system_version="$(dmidecode -s system-version 2>/dev/null)"
    else
        system_maker=""
        system_product=""
        system_version=""
    fi
    if grep -qa docker /proc/1/cgroup; then
        virt_type="Docker"
    elif grep -qa lxc /proc/1/cgroup; then
        virt_type="LXC"
    elif grep -qa container=lxc /proc/1/environ; then
        virt_type="LXC"
    elif [[ -f /proc/user_beancounters ]]; then
        virt_type="OpenVZ"
    elif [[ "${virt_log}" == *kvm-clock* ]]; then
        virt_type="KVM"
    elif [[ "${system_product}" == *KVM* ]]; then
        virt_type="KVM"
    elif [[ "${system_maker}" == *QEMU* ]]; then
        virt_type="KVM"
    elif [[ "${virt_log}" == *"VMware Virtual Platform"* ]]; then
        virt_type="VMware"
    elif [[ "${system_product}" == *"VMware Virtual Platform"* ]]; then
        virt_type="VMware"
    elif [[ "${virt_log}" == *"Parallels Software International"* ]]; then
        virt_type="Parallels"
    elif [[ "${virt_log}" == *VirtualBox* ]]; then
        virt_type="VirtualBox"
    elif [[ -e /proc/xen ]]; then
        if grep -q "control_d" "/proc/xen/capabilities" 2>/dev/null; then
            virt_type="Xen-Dom0"
        else
            virt_type="Xen-DomU"
        fi
    elif [ -f "/sys/hypervisor/type" ] && grep -q "xen" "/sys/hypervisor/type"; then
        virt_type="Xen"
    elif [[ "${system_maker}" == *"Microsoft Corporation"* ]]; then
        if [[ "${system_product}" == *"Virtual Machine"* ]]; then
            if [[ "${system_version}" == *"7.0"* || "${system_version}" == *"Hyper-V"* ]]; then
                virt_type="Hyper-V"
            else
                virt_type="Microsoft Virtual Machine"
            fi
        fi
    else
        virt_type="Dedicated"
    fi
}

get_ipv4_info() {
    local isp city_name country_name region_name
    isp="$(wget -q -T10 -O- ipinfo.io/org)"
    city_name="$(wget -q -T10 -O- ipinfo.io/city)"
    country_name="$(wget -q -T10 -O- ipinfo.io/country)"
    region_name="$(wget -q -T10 -O- ipinfo.io/region)"
    if [[ -n "${isp}" ]]; then
        echo " ISP                : $(print_cyan "${isp}")"
    fi
    if [[ -n "${city_name}" && -n "${country_name}" ]]; then
        echo " Lokasi             : $(print_cyan "${city_name}, ${region_name}, ${country_name}")"
    fi
    local current_ip
    current_ip="$(wget -q -T10 -O- ipinfo.io/ip)"
    if [[ -n "${current_ip}" ]]; then
        echo " Alamat IPv4 Publik : $(print_cyan "${current_ip}")"
    fi
}

get_ipv6_info() {
    local isp city_name country_name region_name
    isp="$(wget -q -T10 -O- ipinfo.io/org?token=${token}&lang=en)"
    city_name="$(wget -q -T10 -O- ipinfo.io/city)"
    country_name="$(wget -q -T10 -O- ipinfo.io/country)"
    region_name="$(wget -q -T10 -O- ipinfo.io/region)"
    if [[ -n "${isp}" ]]; then
        echo " ISP                : $(print_cyan "${isp}")"
    fi
    if [[ -n "${city_name}" && -n "${country_name}" ]]; then
        echo " Lokasi             : $(print_cyan "${city_name}, ${region_name}, ${country_name}")"
    fi
    local current_ip
    current_ip="$(wget -q -T10 -O- ipinfo.io/ip)"
    if [[ -n "${current_ip}" ]]; then
        echo " Alamat IPv6 Publik : $(print_cyan "${current_ip}")"
    fi
}

test_speed
disk_io_test
