#!/bin/bash

set -e

printtag() {
    # GitHub Actions tag format
    echo "::$1::${2-}"
}

begingroup() {
    printtag "group" "$1"
}

endgroup() {
    printtag "endgroup"
}

MACPORTS_VERSION=2.10.3

OS_MAJOR=$(uname -r | cut -f 1 -d .)
OS_ARCH=$(uname -m)
case "$OS_ARCH" in
    i586|i686|x86_64)
        OS_ARCH=i386
        ;;
    arm64)
        OS_ARCH=arm
        ;;
esac

MACPORTS_FILENAME=MacPorts-${MACPORTS_VERSION}-${OS_MAJOR}.tar.bz2


begingroup "Fetching MacPorts..."
/usr/bin/curl -fsSLO "https://github.com/macports/macports-ci-files/releases/download/v${MACPORTS_VERSION}/${MACPORTS_FILENAME}" &
curl_mpbase_pid=$!
endgroup


begingroup "Info"
echo "macOS version: $(sw_vers -productVersion)"
echo "IP address: $(/usr/bin/curl -fsS https://www-origin.macports.org/ip.php)"
/usr/bin/curl -fsSIo /dev/null https://packages-private.macports.org/.org.macports.packages-private.healthcheck.txt && private_packages_available=yes || private_packages_available=no
echo "Can reach private packages server: $private_packages_available"
endgroup


begingroup "Disabling Spotlight"
# Disable Spotlight indexing. We don't need it, and it might cost performance
sudo mdutil -a -i off
endgroup


begingroup "Uninstalling Homebrew"
# Move directories to /opt/off
echo "Moving directories..."
sudo mkdir /opt/off
/usr/bin/sudo /usr/bin/find /opt/homebrew -mindepth 1 -maxdepth 1 -type d -print -exec /bin/mv {} /opt/off/ \;

# Unlink files
echo "Removing files..."
/usr/bin/sudo /usr/bin/find /opt/homebrew -mindepth 1 -maxdepth 1 -type f -print -delete

# Rehash to forget about the deleted files
hash -r
endgroup


begingroup "Installing MacPorts"
# Install MacPorts built by https://github.com/macports/macports-base/tree/master/.github
wait $curl_mpbase_pid
echo "Extracting..."
sudo tar -xpf "${MACPORTS_FILENAME}" -C /
rm -f "${MACPORTS_FILENAME}"
endgroup


begingroup "Configuring MacPorts"
# Set PATH for portindex
source /opt/local/share/macports/setupenv.bash
# CI is not interactive
echo "ui_interactive no" | sudo tee -a /opt/local/etc/macports/macports.conf >/dev/null
# Only download from the CDN, not the mirrors
echo "host_blacklist *.distfiles.macports.org *.packages.macports.org" | sudo tee -a /opt/local/etc/macports/macports.conf >/dev/null
# Also try downloading archives from the private server
echo "archive_site_local https://packages-private.macports.org/:tbz2" | sudo tee -a /opt/local/etc/macports/macports.conf >/dev/null
# Only install for target x86_64
echo "build_arch x86_64" | sudo tee -a /opt/local/etc/macports/macports.conf >/dev/null
# Prefer to get archives from the public server instead of the private server
# preferred_hosts has no effect on archive_site_local
# See https://trac.macports.org/ticket/57720
#echo "preferred_hosts packages.macports.org" | sudo tee -a /opt/local/etc/macports/macports.conf >/dev/null
# Modify soruces.conf so macports-wine is first
echo "file:///opt/macports-wine" | sudo tee /opt/local/etc/macports/sources.conf >/dev/null
echo "rsync://rsync.macports.org/macports/release/tarballs/ports.tar [default]" | sudo tee -a /opt/local/etc/macports/sources.conf >/dev/null
endgroup


begingroup "Running postflight"
# Create macports user
sudo /opt/local/libexec/macports/postflight/postflight
endgroup


begingroup "Cloning macports-wine"
cd /opt
sudo git clone https://github.com/Gcenx/macports-wine.git
endgroup


begingroup "Updating PortIndex"
sudo port sync >/dev/null
sudo port sync -v
endgroup
