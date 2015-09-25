tor-relay-bootstrap
===================

Simple bash script to bootstrap a Debian server to be a set-and-forget Tor relay, bridge, or exit. This script is meant for a Debian Jessie host.

This project is forked from @micahflee's excellent [tor-relay-bootstrap](https://github.com/micahflee/tor-relay-bootstrap) and merges in some changes that @NSAKEY made in his fork of tor-relay-bootstrap, [tor-bridge-bootstrap](https://github.com/nsakey/tor-bridge-bootstrap).
I've added the configuration for Tor exits and made the script multi-purpose.

Pull requests are welcome.

tor-relay-bootstrap does the following:

* Upgrades all the software on the system
* Adds the https://deb.torproject.org repository to apt along with apt-transport-https, so Tor updates will come directly from the Tor Project over HTTPS
* Installs and configures Tor to become a relay, bridge, or exit based off of the corresponding flag that is passed to the program. This still requires you to manually edit torrc to set Nickname, ContactInfo, etc. for this relay.
* Configures sane default firewall rules
* Configures automatic updates
* Installs tlsdate to ensure time is synced
* Installs monit and activate config to auto-restart all services
* Helps harden the ssh server
* Gives instructions on what the sysadmin needs to manually do at the end

To use it, set up a Debian server, SSH into it, switch to the root user, and:

```sh
git clone https://github.com/micahflee/tor-relay-bootstrap.git
cd tor-relay-bootstrap
./bootstrap.sh
```
Rationale for Port choices
--------------------------

I've decided to change the default ORPort and DirPort on the non-exit and exit relay values to 443 and 80 respectively, along with changing the firewall values to reflect this.
I've done this primarily to dodge Layer 3 filtering of ports that are common on some public networks. 
This helps a non-bridge user avoid this basic type of filtering if any of these relays are used as the Guard.
