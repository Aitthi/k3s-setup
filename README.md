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

### Master Node
```bash
# Create the k3s master node
mkdir -p /etc/rancher/k3s
cat <<EOT >> /etc/rancher/k3s/config.yaml
cluster-init: true
tls-san: 10.130.0.3 # LB IP
node-label:
  - "name=master-1"
  - "role=master"
flannel-backend: none
node-ip: 10.130.0.4
cluster-cidr: 20.42.0.0/16
service-cidr: 20.43.0.0/16
cluster-dns: 20.43.0.10
disable:
  - traefik
disable-kube-proxy: true
disable-network-policy: true
kubelet-arg:
  - "max-pods=210"
EOT

# Install k3s
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.31.1+k3s1" INSTALL_K3S_EXEC="server" sh -s -

kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_gatewayclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_gateways.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_httproutes.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_referencegrants.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_grpcroutes.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/experimental/gateway.networking.k8s.io_tlsroutes.yaml


# Networking
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz

## Install
cilium install --version 1.16.3  \
  --set prometheus.enabled=true \
  --set operator.prometheus.enabled=true \
  --set kubeProxyReplacement=true \
  --set ingressController.enabled=true \
  --set ingressController.loadbalancerMode=shared \
  --set loadBalancer.l7.backend=envoy \
  --set k8sServiceHost=10.130.0.3 \
  --set k8sServicePort=6443 \
  --set ipam.mode=kubernetes \
  --set k8s.requireIPv4PodCIDR=true \
  --set k8s.requireIPv6PodCIDR=false \
  --set hubble.metrics.enableOpenMetrics=true \
  --set gatewayAPI.enabled=true \
  --set egressGateway.enabled=true \
  --set bpf.masquerade=true \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true \
  --set hubble.metrics.enabled="{dns,drop,tcp,flow,port-distribution,icmp,httpV2:exemplars=true;labelsContext=source_ip\,source_namespace\,source_workload\,destination_ip\,destination_namespace\,destination_workload\,traffic_direction}"

# ถ้า cilium gateway ไม่สร้าง
# [install/kubernetes/cilium/templates/cilium-gateway-api-class.yaml](https://github.com/cilium/cilium/blob/main/install/kubernetes/cilium/templates/cilium-gateway-api-class.yaml)

# Note: k8sServiceHost ควรใช้ LoadBalancer
# 10.130.0.3 -> 10.130.0.4
#           -> 10.130.0.5

# helm
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | tee /usr/share/keyrings/helm.gpg > /dev/null
apt-get install apt-transport-https --yes
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | tee /etc/apt/sources.list.d/helm-stable-debian.list
apt-get update
apt-get install helm


# Install cert-manager
# https://artifacthub.io/packages/helm/cert-manager/cert-manager#configuration
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.1/cert-manager.crds.yaml
## Add the Jetstack Helm repository
helm repo add jetstack https://charts.jetstack.io --force-update

## Install the cert-manager helm chart
kubectl create namespace cert-manager
helm install cert-manager --namespace cert-manager --version v1.16.1 jetstack/cert-manager

# Force install
helm fetch rancher-latest/rancher --untar
# change kubernetes version in rancher/Chart.yaml
# bootstrapPassword just for a demo
helm install rancher ./rancher \
  --namespace cattle-system \
  --set hostname=k8s.assetsart.com \
  --set bootstrapPassword=admin \
  --set kubeVersionOverride=true
```
