#!/usr/bin/env bash
# Pi-MobiSec: A security layer for using public hotspots
# (c) 2017 Patrick W. Fraley (https://pi-mobisec.net)
# Secure your computer on unsecure networks.
#
# Installs Pi-MobiSec
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

set -e

###### global variables ######
tmpLog=/tmp/pi-mobisec.log
skipSpaceCheck=false

APP_REPO=""
APP_SETTINGS=/etc/pimobisec
LOCAL_REPO=${APP_SETTINGS}/.pimobisec

INTERNAL_NETWORK_DEVICE="usb0"
INTERNAL_IPV4_ADDRESS="10.235.58.1"
INTERNAL_IPV4_NETMASK="255.255.255.0"

DHCP_RANGE_START="10.235.58.100"
DHCP_RANGE_END="10.235.58.110"
DHCP_LEASE_TIME="12h"

EXTERNAL_NETWORK_DEVICE="wlan0"

IPTABLES=$(which iptables)

# Find the rows and columns will default to 80x24 is it can not be detected
screen_size=$(stty size 2>/dev/null || echo 24 80)
rows=$(echo "${screen_size}" | awk '{print $1}')
columns=$(echo "${screen_size}" | awk '{print $2}')

# Divide by two so the dialogs take up half of the screen, which looks nice.
r=$(( rows / 2 ))
c=$(( columns / 2 ))
# Unless the screen is tiny
r=$(( r < 20 ? 20 : r ))
c=$(( c < 70 ? 70 : c ))

check_distro() {
    if command -v apt-get &> /dev/null; then
        ### Debian Based (Raspian, Armbian, Ubuntu)
        PKG_MANAGER="apt-get"
        UPDATE_PKG_CACHE="${PKG_MANAGER} update"
        INSTALLER_DEPS=(apt-utils debconf git iproute2 whiptail)
        APP_DEPS=(dnsmasq sudo unzip)
    else
        ### Others are not yet supported (Fedora, Arch)
        echo "OS distribution not supported"
        exit
    fi
}

check_pi() {
    echo "::: Checking which pi we are on..."
    local pi_version=$(cat /proc/cpuinfo | grep -E '^[Rr]evision[[:space:]]*: ([[:alnum:]]*)' | awk '{print $4}')
    if [[ "${pi_version}" != "0x9000C1" ]]; then
        echo "::: Sorry only PiZero W supported for now. Others comming soon :)"
        exit 1
    fi
    echo "::: PiZero W detected."
}

verify_diskspace() {
    if [[ "${skipSpaceCheck}" == true ]]; then
        echo "::: --no_verify_disk_space passed to script, skipping free disk space verification!"
    else
        # 50MB is the minimum space needed (45MB install (includes web admin libraries etc) + 5MB one day of logs.)
        echo "::: Verifying free disk space..."
        local required_free_kilobytes=51200
        local existing_free_kilobytes=$(df -Pk | grep -m1 '\/$' | awk '{print $4}')

        # - Unknown free disk space , not a integer
        if ! [[ "${existing_free_kilobytes}" =~ ^([0-9])+$ ]]; then
            echo "::: Unknown free disk space!"
            echo "::: We were unable to determine available free disk space on this system."
            echo "::: You may override this check and force the installation, however, it is not recommended"
            echo "::: To do so, pass the argument '--no_verify_disk_space' to the install script"
            echo "::: eg. curl -L https://install.pi-mobisec.net | sudo bash /dev/stdin --no_verify_disk_space"
            exit 1
        # - Insufficient free disk space
        elif [[ ${existing_free_kilobytes} -lt ${required_free_kilobytes} ]]; then
            echo "::: Insufficient Disk Space!"
            echo "::: Your system appears to be low on disk space. Pi-MobiSec recommends a minimum of $required_free_kilobytes KiloBytes."
            echo "::: You only have ${existing_free_kilobytes} KiloBytes free."
            echo "::: If this is a new install you may need to expand your disk."
            echo "::: Try running 'sudo raspi-config', and choose the 'expand file system option'"
            echo "::: After rebooting, run this installation again. (curl -L https://install.pi-mobisec.net | bash)"
            echo "Insufficient free space, exiting..."
            exit 1
        fi
    fi
}

update_package_cache() {
    echo ":::"
    echo -n "::: Updating local cache of available packages..."
    if eval ${UPDATE_PKG_CACHE} &> /dev/null; then
        echo " done!"
    else
        echo -n "\n!!! ERROR - Unable to update package cache. Please try \"${UPDATE_PKG_CACHE}\""
    fi
}

notify_package_updates_available() {
  # Let user know if they have outdated packages on their system and
  # advise them to run a package update as soon as possible.
  echo ":::"
  echo -n "::: Checking ${PKG_MANAGER} for upgraded packages...."
  updatesToInstall=$(eval "${PKG_COUNT}")
  echo " done!"
  echo ":::"
  if [[ -d "/lib/modules/$(uname -r)" ]]; then
    if [[ ${updatesToInstall} -eq "0" ]]; then
      echo "::: Your system is up to date! Continuing with Pi-MobiSec installation..."
    else
      echo "::: There are ${updatesToInstall} updates available for your system!"
      echo "::: We recommend you update your OS after installing Pi-MobiSec! "
      echo ":::"
    fi
  else
    echo "::: Kernel update detected, please reboot your system and try again if your installation fails."
  fi
}

install_dependent_packages() {
    # Install packages passed in via argument array
    # No spinner - conflicts with set -e
    declare -a argArray1=("${!1}")
    declare -a installArray

    if command -v debconf-apt-progress &> /dev/null; then
        for i in "${argArray1[@]}"; do
            echo -n ":::    Checking for $i..."
            if dpkg-query -W -f='${Status}' "${i}" 2>/dev/null | grep "ok installed" &> /dev/null; then
                echo " installed!"
            else
                echo " added to install list!"
                installArray+=("${i}")
            fi
        done
        if [[ ${#installArray[@]} -gt 0 ]]; then
            debconf-apt-progress -- "${PKG_INSTALL[@]}" "${installArray[@]}"
            return
        fi
        return 0
    fi
}

stop_service() {
  # Stop service passed in as argument.
  # Can softfail, as process may not be installed when this is called
  echo ":::"
  echo -n "::: Stopping ${1} service..."
  if command -v systemctl &> /dev/null; then
    systemctl stop "${1}" &> /dev/null || true
  else
    service "${1}" stop &> /dev/null || true
  fi
  echo " done."
}

start_service() {
  # Start/Restart service passed in as argument
  # This should not fail, it's an error if it does
  echo ":::"
  echo -n "::: Starting ${1} service..."
  if command -v systemctl &> /dev/null; then
    systemctl restart "${1}" &> /dev/null
  else
    service "${1}" restart &> /dev/null
  fi
  echo " done."
}

enable_service() {
  # Enable service so that it will start with next reboot
  echo ":::"
  echo -n "::: Enabling ${1} service to start on reboot..."
  if command -v systemctl &> /dev/null; then
    systemctl enable "${1}" &> /dev/null
  else
    update-rc.d "${1}" defaults &> /dev/null
  fi
  echo " done."
}

setup_boot_config() {
    echo "::: Setting up config.txt"
    if grep -q "dtoverlay=dwc2" /boot/config.txt; then
        return
    fi
    echo "dtoverlay=dwc2" | tee -a /boot/config.txt >/dev/null
}

setup_boot_cmdline() {
    echo "::: Setting up cmdline.txt"
    if grep -q "modules-load=dwc2,g_ether" /boot/cmdline.txt; then
        return
    fi
    # TODO: Check if there is already a modules-load, loading other modules, if so append dwc2,g_ether
    echo -n " modules-load=dwc2,g_ether" | tee -a /boot/cmdline.txt >/dev/null
}

setup_usb_otg_ether() {
    setup_boot_config
    setup_boot_cmdline
}

setup_interface() {
    echo "::: Setting up interface ${INTERNAL_NETWORK_DEVICE} with ${INTERNAL_IPV4_ADDRESS}/${INTERNAL_IPV4_NETMASK}"
    if grep -q "iface ${INTERNAL_NETWORK_DEVICE} inet static" /etc/network/interfaces; then
        return
    fi
    echo "
allow-hotplug ${INTERNAL_NETWORK_DEVICE}
iface usb0 inet static
    address ${INTERNAL_IPV4_ADDRESS}
    netmask ${INTERNAL_IPV4_NETMASK}
post-up iptables-restore < /etc/network/iptables.v4" >> /etc/network/interfaces
}

setup_ip_forwarding() {
    echo "::: Setting up net.ipv4.ip_forward"
    if grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        return
    fi
    sed -i -- 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf
    sysctl -p /etc/sysctl.conf
}

setup_dnsmasq() {
    echo "interface=${INTERNAL_NETWORK_DEVICE}" > /etc/dnsmasq.d/pi-mobisec.conf
    echo "dhcp-range=${DHCP_RANGE_START},${DHCP_RANGE_END},${DHCP_LEASE_TIME}" >> /etc/dnsmasq.d/pi-mobisec.conf
}

setup_firewall() {
    echo "::: Setting up firewall rules and enabling them."
    if command -v iptables &> /dev/null; then
        # Flush all chains
        $IPTABLES -F INPUT DROP
        $IPTABLES -F FORWARD DROP
        $IPTABLES -F OUPUT DROP

        # Default drop everything
        $IPTABLES -P INPUT DROP
        $IPTABLES -P FORWARD DROP
        $IPTABLES -P OUPUT DROP

        # Accept all loopback traffic
        $IPTABLES -A INPUT -i lo -j ACCEPT
        $IPTABLES -A OUTPUT -o lo -j ACCEPT

        # Accept all internal traffic
        $IPTABLES -A INPUT -i ${INTERNAL_NETWORK_DEVICE} -j ACCEPT
        $IPTABLES -A OUTPUT -o ${INTERNAL_NETWORK_DEVICE} -j ACCEPT

        # Accept all established or related inbound connections
        $IPTABLES -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

        # Accept all established or related outbound connections
        $IPTABLES -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

        # Accept all inbound and outbound SSH connections
        # Don't delete this unless you have local access to the machine
        $IPTABLES -A INPUT -p tcp --dport 22 -j ACCEPT
        $IPTABLES -A OUTPUT -p tcp --dport 22 -j ACCEPT

        # Forwarding & Masquerading rules
        $IPTABLES -A FORWARD -i ${INTERNAL_NETWORK_DEVICE} -j ACCEPT
        $IPTABLES -A FORWARD -o ${INTERNAL_NETWORK_DEVICE} -j ACCEPT
        $IPTABLES -t nat -A POSTROUTING -o ${EXTERNAL_NETWORK_DEVICE} -j MASQUERADE
        echo "::: Saving firewall rules."
        iptables-save > /etc/network/iptables.v4
        return
    else
        echo "::: iptables command not found."
        return 0
    fi
}

valid_ip() {
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi

    return $stat
}

### dialogs
welcomeDialogs() {
    # Display the welcome dialog
    whiptail --msgbox --backtitle "Welcome" --title "Pi-MobiSec automated installer" "\nThis installer will transform your Pi Zero into a cloaking device while using public hotspots or unsecure wifi hotspots!  Instead of connecting your laptop to unsecure hotspots, you connect Pi-MobiSec to your laptop and let it connect to the wifi hotspot." ${r} ${c}

    # Support for a part-time dev
    whiptail --msgbox --backtitle "Donation" --title "Free and open source" "\nThe Pi-MobiSec is free, but powered by your donations:\n\nhttp://pi-mobisec.net/donate" ${r} ${c}
}

ipSettingsDialogs() {
    local ipAddressValid
    local netmaskValid
    # Ask for Ip Adress for usb0
    until [[ ${ipAddressValid} = True ]]; do
        INTERNAL_IPV4_ADDRESS=$(whiptail --inputbox --backtitle "IP-Address setup" --title "Settings for the private network" "\nPlease enter the ip-address for the private network." ${r} ${c} "${INTERNAL_IPV4_ADDRESS}" 3>&1 1>&2 2>&3) || \
        { ipAddressValid=False; echo "::: Cancel selected. Exiting..."; exit 1; }
        if valid_ip ${INTERNAL_IPV4_ADDRESS}; then
            ipAddressValid=True;
            echo "::: Your static IPv4 address:    ${INTERNAL_IPV4_ADDRESS}"
        fi
    done

    # Ask for Netmask for internal network
    until [[ ${netmaskValid} = True ]]; do
        INTERNAL_IPV4_NETMASK=$(whiptail --inputbox --backtitle "IP-Address setup" --title "Settings for the private network" "\nPlease enter the netmask for the private network." ${r} ${c} "${INTERNAL_IPV4_NETMASK}" 3>&1 1>&2 2>&3) || \
        { netmaskValid=False; echo "::: Cancel selected. Exiting..."; exit 1; }
        if valid_ip ${INTERNAL_IPV4_NETMASK}; then
            netmaskValid=True;
            echo "::: Your static IPv4 netmask:    ${INTERNAL_IPV4_NETMASK}"
        fi
    done
}

finishDialogs() {
    # Display the finish dialog
    if(whiptail --yesno --backtitle "Finish" --title "Pi-MobiSec automated installer" "\nThank you for installing Pi-MobiSec.  Your system is now ready to go.  Please reboot your pi to activate all settings.\n\nIf you like using this setup please donate to help in the development of Pi-MobiSec.\n\nInformation on how to donate can be found under:\nhttps://pi-mobisec.net/donate\n\nReboot now?" ${r} ${c}) then
        reboot
    fi
}

main() {
    ######## FIRST CHECK ########
    # Must be root to install
    echo ":::"
    if [[ ${EUID} -eq 0 ]]; then
        echo "::: Perfect, you are root."
    else
        echo "::: Please run this script as root."
        echo "::: If you are worried about security issues (which you should be) please review this script to see what it is doing and which changes it will introduce to your system."
        echo "::: eg. curl -L https://install.pi-mobisec.net | sudo bash"
        exit 1
    fi

    # Check for supported hardware
    check_pi

    # Make sure we are run on a Debian based distro (Raspian, Armbian, Ubuntu)
    check_distro

    # Check arguments for flags
    for var in "$@"; do
        case "$var" in
          "--no_verify_disk_space"   ) skipSpaceCheck=true;;
        esac
    done

    # Verify diskspace
    verify_diskspace

    update_package_cache

    notify_package_updates_available

    install_dependent_packages INSTALLER_DEPS[@]

    welcomeDialogs

    ### Ask user all required information
    # IP address for usb0
    # Netmask for usb0
    ipSettingsDialogs
    setup_interface

    install_dependent_packages APP_DEPS[@]

    ### Prepare system
    # Setup usb otg ether
    setup_usb_otg_ether
    # Setup ip forwarding (sysctl.conf)
    setup_ip_forwarding
    # Setup dnsmasq (Create config in dnsmasq.d/pi-mobisec.conf)
    setup_dnsmasq
    # Setup firewall (iptables, MASQ, Deny Access from Public interface, Allow all traffic from usb0)
    setup_firewall

    finishDialogs
}

if [[ "${PMS_TEST}" != true ]] ; then
    main "$@"
fi
