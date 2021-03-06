#!/bin/sh

set -e # terminate script if any step fails
set -u # abort if any variables are unset

usage(){
    echo "bootstrap.sh [options]"
    echo "  -b          Set up a obsf4 Tor bridge"
    echo "  -r          Set up a (non-exit) Tor relay"
    echo "  -x          Set up a Tor exit relay (default is a reduced exit)"
    exit 255
}

# pretty colors
echo_green() { printf "\033[0;32m$1\033[0;39;49m\n"; }
echo_red() { printf "\033[0;31m$1\033[0;39;49m\n"; }

# Process options
while getopts "brx" option; do
  case $option in
    b ) TYPE="bridge" ;;
    r ) TYPE="relay" ;;
    x ) TYPE="exit" ;;
    * ) usage ;;
    esac
done

if [ -z ${TYPE:-} ]; then
   usage
fi

# check for root
if [ $(id -u) -ne 0 ]; then
    echo_red "This script must be run as root" 1>&2
    exit 1
fi

PWD="$(dirname "$0")"

# packages that we always install
TORPKGSCOMMON="deb.torproject.org-keyring tor tor-arm tor-geoipdb tlsdate fail2ban \
apparmor apparmor-profiles apparmor-utils unattended-upgrades apt-listchanges \
debconf-utils iptables iptables-persistent"

# packages that a bridge needs
TORBRIDGEPKG="git obfsproxy golang libcap2-bin"

# update software
echo_green "== Updating software"
apt-get --quiet update
apt-get --quiet --yes dist-upgrade

# apt-transport-https allows https debian mirrors. it's more fun that way.
# https://guardianproject.info/2014/10/16/reducing-metadata-leakage-from-software-updates/
# granted it doesn't fix *all* metadata problems
# see https://labs.riseup.net/code/issues/8143 for more on this discussion
#
# One reason not to use HTTPS is when using apt-cacher-ng which as of the
# version in Jessie does not support fetching via HTTPS. apt-cacher-ng listens
# on port 3142 by default. Since the apt config lines can span multiple lines
# we'll do a dumb check for '3142' in the config files. If it's found we'll
# add the HTTP repository.

# DO NOT TRY TO REDUCE THESE PACKAGES INTO $TORPKGSCOMMON
# THINGS WILL BREAK
# see https://github.com/colinmahns/tor-relay-bootstrap/commit/8cbfe26599232692c8c570405dba104e7548cf29
if ! grep -r ':3142\(\/\)\?"' /etc/apt/apt.conf* > /dev/null 2>&1 ; then
    apt-get --yes --quiet install lsb-release apt-transport-https
    DEBPROTO='https'
else
    apt-get --yes --quiet install lsb-release
    DEBPROTO='http'
fi

# add official Tor repository w/ http(s)
if ! grep -rq "https\?:\/\/deb\.torproject\.org\/torproject\.org" /etc/apt/sources.list*; then
    echo_green "== Adding the official Tor repository"
    if [ $DEBPROTO != 'https' ]; then
        echo_red 'Not using HTTPS for the Tor repository'
    fi
    echo "deb $DEBPROTO://deb.torproject.org/torproject.org `lsb_release -cs` main" >> /etc/apt/sources.list
    apt-key adv --keyserver keys.gnupg.net --recv A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89
    apt-get --quiet update
fi

# install tor and related packages
echo_green "== Installing Tor and related packages"
if [ "$TYPE" = "relay" ] ||  [ "$TYPE" = "exit" ] ; then
    apt-get --yes --quiet install $TORPKGSCOMMON
elif [ "$TYPE" = "bridge" ] ; then
    apt-get --quiet --yes install $TORPKGSCOMMON $TORBRIDGEPKG
    export OLDGOPATH="${GOPATH:-}"
    export GOPATH="$(mktemp -d)"
    go get git.torproject.org/pluggable-transports/obfs4.git/obfs4proxy
    mv -f "$GOPATH"/bin/obfs4proxy /usr/local/bin
    rm -rf "$GOPATH"
    export GOPATH="$OLDGOPATH"
fi
service tor stop

# configure tor
cp $PWD/etc/tor/${TYPE}torrc /etc/tor/torrc


# configure firewall rules
echo_green "== Configuring firewall rules"
echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections
echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
cp $PWD/etc/iptables/${TYPE}rules.v4 /etc/iptables/rules.v4
cp $PWD/etc/iptables/${TYPE}rules.v6 /etc/iptables/rules.v6
chmod 600 /etc/iptables/rules.v4
chmod 600 /etc/iptables/rules.v6
iptables-restore < /etc/iptables/rules.v4
ip6tables-restore < /etc/iptables/rules.v6

# configure automatic updates
echo_green "== Configuring unattended upgrades"
cp $PWD/etc/apt/apt.conf.d/20auto-upgrades /etc/apt/apt.conf.d/20auto-upgrades
service unattended-upgrades restart

# configure apparmor
if ! grep -q '^[^#].*apparmor=1' /etc/default/grub; then
    sed -i.bak 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 apparmor=1 security=apparmor"/' /etc/default/grub
    update-grub
fi

# configure sshd
ORIG_USER=$(logname)
if [ -n "$ORIG_USER" ]; then
    echo_green "== Configuring sshd"
    # Remove any existing AllowUsers lines
    if grep -q '^AllowUsers' /etc/ssh/sshd_config; then
        sed -i.bak '/^AllowUsers/d' /etc/ssh/sshd_config
    fi
    # only allow the current user to SSH in
    echo "AllowUsers $ORIG_USER" >> /etc/ssh/sshd_config
    echo_green "  - SSH login restricted to user: $ORIG_USER"
    if grep -q "Accepted publickey for $ORIG_USER" /var/log/auth.log; then
        # user has logged in with SSH keys so we can disable password authentication
        sed -i '/^#\?PasswordAuthentication/c\PasswordAuthentication no' /etc/ssh/sshd_config
        echo_green "  - SSH password authentication disabled"
        if [ $ORIG_USER = "root" ]; then
            # user logged in as root directly (rather than using su/sudo) so make sure root login is enabled
            sed -i '/^#\?PermitRootLogin/c\PermitRootLogin yes' /etc/ssh/sshd_config
        fi
    else
        # user logged in with a password rather than keys
        echo_red "  - You do not appear to be using SSH key authentication."
        echo_red "    You should set this up manually now."
    fi
    service ssh reload
else
    echo_red "== Could not configure sshd automatically."
    echo_red "   You will need to do this manually."
fi

# final instructions
echo_green "
== Try SSHing into this server again in a new window, to confirm the firewall
   isn't broken

== Edit /etc/tor/torrc
  - Set Address, Nickname, Contact Info, and MyFamily for your Tor relay
  - Optional: include a Bitcoin address in the 'ContactInfo' line
  - This will enable you to receive donations from OnionTip.com

== Register your new Tor relay at Tor Weather (https://weather.torproject.org/)
   to get automatic emails about its status

== Consider having /etc/apt/sources.list update over HTTPS and/or HTTPS+Tor
   see https://guardianproject.info/2014/10/16/reducing-metadata-leakage-from-software-updates/
   for more details

== REBOOT THIS SERVER
"
