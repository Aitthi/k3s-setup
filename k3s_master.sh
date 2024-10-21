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
  - servicelb
disable-kube-proxy: true
disable-network-policy: true
kubelet-arg:
  - "max-pods=210"
EOT

# Install k3s
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.31.1+k3s1" INSTALL_K3S_EXEC="server" sh -s -

# Networking
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz

## Install
# cilium install --version 1.16.3 \
#    --set prometheus.enabled=true \
#    --set operator.prometheus.enabled=true \
#    --set hubble.enabled=true \
#    --set hubble.metrics.enableOpenMetrics=true \
#    --set hubble.metrics.enabled="{dns,drop,tcp,flow,port-distribution,icmp,httpV2:exemplars=true;labelsContext=source_ip\,source_namespace\,source_workload\,destination_ip\,destination_namespace\,destination_workload\,traffic_direction}"


## Install
cilium install --version 1.16.3  \
  --set prometheus.enabled=true \
  --set operator.prometheus.enabled=true \
  --set kubeProxyReplacement=true \
  --set ingressController.enabled=true \
  --set ingressController.loadbalancerMode=shared \
  --set loadBalancer.l7.backend=envoy \
  --set k8sServiceHost=10.130.0.3 \
  --set k8sServicePort=6443

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
$ helm repo add jetstack https://charts.jetstack.io --force-update

## Install the cert-manager helm chart
kubectl create namespace cert-manager
$ helm install cert-manager --namespace cert-manager --version v1.16.1 jetstack/cert-manager

# Force install
helm fetch rancher-latest/rancher --untar
# change kubernetes version in rancher/Chart.yaml
# bootstrapPassword just for a demo
helm install rancher ./rancher \
  --namespace cattle-system \
  --set hostname=k8s.assetsart.com \
  --set bootstrapPassword=admin \
  --set kubeVersionOverride=true
