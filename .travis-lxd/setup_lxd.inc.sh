#
# Set up LXD
#

set -u
set -e

echo "Updating package list..."
sudo apt-get -y update

echo "Removing old LXD..."
sudo apt-get -y remove lxd
sudo apt-get -y autoremove

echo "Installing Snap..."
sudo apt-get -y install snapd
echo "PATH=/snap/bin:$PATH" | sudo tee -a /etc/environment
export PATH=/snap/bin:$PATH

echo "Installing LXD from Snap (APT's version is too old)..."
sudo snap install lxd

echo "Waiting for LXD to start..."
sudo snap start lxd
sudo lxd waitready

if [ ! -f /var/lib/lxd/lxd.db ]; then
    echo "Initializing LXD..."
    sudo lxd init --auto --storage-backend=dir
fi

echo "Removing linuxcontainers.org repo..."
sudo lxc remote remove images || echo "Not here?"

LXD_BRIDGE_INTERFACE=testbr0
if [[ $(sudo lxc network list | grep $LXD_BRIDGE_INTERFACE | wc -l) -eq 0 ]]; then
    echo "Setting up LXD networking..."
    sudo lxc network create $LXD_BRIDGE_INTERFACE
    sudo lxc network attach-profile $LXD_BRIDGE_INTERFACE default eth0
fi

LXD_PROFILE=travis
if [[ $(sudo lxc profile list | grep $LXD_PROFILE | wc -l) -eq 0 ]]; then
    echo "Creating LXD profile..."
    sudo lxc profile copy default $LXD_PROFILE
    sudo lxc profile set $LXD_PROFILE security.privileged true
fi
