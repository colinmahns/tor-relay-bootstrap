#!/bin/bash

# check for root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

PWD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# add official Tor repository
if ! grep -q "http://deb.torproject.org/torproject.org" /etc/apt/sources.list; then
    echo "== Adding the official Tor repository"
    echo "deb http://deb.torproject.org/torproject.org `lsb_release -cs` main" >> /etc/apt/sources.list
    gpg --keyserver keys.gnupg.net --recv 886DDD89
    gpg --export A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89 | apt-key add -
fi

# update software
echo "== Updating software"
apt-get update
apt-get full-upgrade -y

# install tor and related packages
echo "== Installing Tor and related packages"
apt-get install -y deb.torproject.org-keyring tor tor-arm tor-geoipdb
service tor stop

# configure tor
cp $PWD/etc/tor/torrc /etc/tor/torrc

# configure firewall rules
echo "== Configuring firewall rules"
apt-get install -y debconf-utils
echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections
echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
apt-get install -y iptables iptables-persistent
cp $PWD/etc/iptables/rules.v4 /etc/iptables/rules.v4
cp $PWD/etc/iptables/rules.v6 /etc/iptables/rules.v6
chmod 600 /etc/iptables/rules.v4
chmod 600 /etc/iptables/rules.v6
iptables-restore < /etc/iptables/rules.v4
ip6tables-restore < /etc/iptables/rules.v6

# configure automatic updates
echo "== Configuring unattended upgrades"
apt-get install -y unattended-upgrades apt-listchanges
cp $PWD/etc/apt/apt.conf.d/20auto-upgrades /etc/apt/apt.conf.d/20auto-upgrades
service unattended-upgrades restart

# final instructions
echo ""
echo "== Try SSHing into this server again in a new window, to confirm the firewall isn't broken"
echo ""
echo "== If you haven't already, you should use SSH key authentication"
echo ""
echo "== Edit /etc/tor/torrc"
echo "  - Set Address, Nickname, Contact Info, and MyFamily for your Tor relay"
echo "  - Then run: service tor restart"
echo ""
echo "== Register your new Tor relay at Tor Weather (https://weather.torproject.org/)"
echo "   to get automatic emails about its status"

