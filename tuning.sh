apt update && apt upgrade -y

# Kubernetes requires swap to be disabled for optimal performance.
swapoff -a

# Disable swap permanently
nano /etc/fstab

# Configure Kernel Parameters for eBPF and Cilium
# Load Required Kernel Modules:
modprobe ip_tables
modprobe ip6_tables
modprobe netlink_diag
modprobe xt_socket

# Ensure your kernel supports eBPF by checking for the presence of /sys/fs/bpf.
ls /sys/fs/bpf

# Set Kernel Parameters
tee /etc/sysctl.d/99-kubernetes-cilium.conf <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
fs.file-max = 52706963
fs.nr_open = 52706963
vm.max_map_count = 262144
vm.swappiness = 0
vm.overcommit_memory = 1
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
EOF

# Apply the new sysctl settings
sysctl --system

# Install Necessary Packages
apt install -y curl apt-transport-https gnupg2 software-properties-common ca-certificates lsb-release