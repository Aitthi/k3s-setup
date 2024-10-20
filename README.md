# My Favorite K3s Setup

It is just a shell script for remembering the steps to set up K3s. It is not a complete guide but a reminder for my personal use. The following script is tailored for setting up a K3s cluster on a fresh Debian installation using HAProxy as a load balancer, Cilium for networking, and Helm for managing Kubernetes packages.

---

## Load Balancer for control plane nodes (HAProxy)
```bash
apt install haproxy
```

### Add the following configuration to `/etc/haproxy/haproxy.cfg`
```cfg
frontend k3s-frontend
    bind *:6443
    mode tcp
    option tcplog
    default_backend k3s-backend

backend k3s-backend
    mode tcp
    option tcp-check
    balance roundrobin
    default-server inter 10s downinter 5s
    server server-1 10.130.0.3:6443 check
    # server server-2 10.10.10.51:6443 check
    # server server-3 10.10.10.52:6443 check
```

### Install necessary packages and Tuning the system
```bash
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
```