#!/bin/bash
set -e  # Exit on any error

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Canary Deployment Cluster Setup Script${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Function to print status
print_status() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check prerequisites
print_status "Checking prerequisites..."

if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed. Please install Docker first."
    exit 1
fi
print_success "Docker found"

if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed. Please install kubectl first."
    exit 1
fi
print_success "kubectl found"

if ! command -v helm &> /dev/null; then
    print_status "Helm not found. Installing Helm..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    print_success "Helm installed"
else
    print_success "Helm found"
fi

# Step 1: Install KIND
print_status "Installing KIND..."
# Remove old KIND if exists (in case it's corrupt)
sudo rm -f /usr/local/bin/kind
print_status "Downloading KIND from GitHub..."
curl -Lo ./kind https://github.com/kubernetes-sigs/kind/releases/download/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
print_success "KIND installed: $(kind version)"

# Step 2: Create KIND cluster
print_status "Creating KIND cluster..."

# Check if cluster already exists
if kind get clusters | grep -q "canary-cluster"; then
    print_status "Cluster 'canary-cluster' already exists. Deleting..."
    kind delete cluster --name canary-cluster
fi

cat <<EOF | kind create cluster --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: canary-cluster
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
EOF

print_success "KIND cluster created"

# Wait for cluster to be ready
print_status "Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s
print_success "Cluster is ready"

# Step 3: Install Istio
print_status "Installing Istio..."

# Download Istio if not present
if [ ! -d "istio-1.20.0" ]; then
    curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.20.0 sh -
fi

cd istio-1.20.0
export PATH=$PWD/bin:$PATH

# Install Istio
istioctl install --set profile=demo -y

cd ..
print_success "Istio installed"

# Wait for Istio to be ready
print_status "Waiting for Istio to be ready..."
kubectl wait --for=condition=Ready pods --all -n istio-system --timeout=300s
print_success "Istio is ready"

# Step 4: Install Argo Rollouts
print_status "Installing Argo Rollouts..."
kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
print_success "Argo Rollouts installed"

# Wait for Argo Rollouts to be ready
print_status "Waiting for Argo Rollouts to be ready..."
kubectl wait --for=condition=Ready pods --all -n argo-rollouts --timeout=300s
print_success "Argo Rollouts is ready"

# Install Argo Rollouts kubectl plugin
print_status "Installing Argo Rollouts kubectl plugin..."
if ! command -v kubectl-argo-rollouts &> /dev/null; then
    curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
    chmod +x kubectl-argo-rollouts-linux-amd64
    sudo mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts
    print_success "Argo Rollouts plugin installed"
else
    print_success "Argo Rollouts plugin already installed"
fi

# Step 5: Install Prometheus
print_status "Installing Prometheus..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --wait --timeout 10m
print_success "Prometheus installed"

# Step 6: Install ArgoCD
print_status "Installing ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
print_success "ArgoCD installed"

# Wait for ArgoCD to be ready
print_status "Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s
print_success "ArgoCD is ready"

# Install ArgoCD CLI (optional)
print_status "Installing ArgoCD CLI..."
if ! command -v argocd &> /dev/null; then
    curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
    chmod +x argocd-linux-amd64
    sudo mv argocd-linux-amd64 /usr/local/bin/argocd
    print_success "ArgoCD CLI installed"
else
    print_success "ArgoCD CLI already installed"
fi

# Step 7: Install NGINX Ingress Controller
print_status "Installing NGINX Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
print_success "NGINX Ingress Controller installed"

# Wait for NGINX Ingress to be ready
print_status "Waiting for NGINX Ingress to be ready..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s
print_success "NGINX Ingress is ready"

# Final verification
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

print_status "Cluster Summary:"
echo ""

print_status "Namespaces:"
kubectl get namespaces | grep -E "istio-system|argo-rollouts|monitoring|argocd|ingress-nginx"
echo ""

print_status "Pods in istio-system:"
kubectl get pods -n istio-system
echo ""

print_status "Pods in argo-rollouts:"
kubectl get pods -n argo-rollouts
echo ""

print_status "Pods in monitoring:"
kubectl get pods -n monitoring
echo ""

print_status "Pods in argocd:"
kubectl get pods -n argocd
echo ""

print_status "Pods in ingress-nginx:"
kubectl get pods -n ingress-nginx
echo ""

# Get ArgoCD initial password
print_status "ArgoCD Admin Password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Next Steps:${NC}"
echo -e "${GREEN}========================================${NC}"
echo "1. Access ArgoCD UI:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   Then visit: https://localhost:8080"
echo "   Username: admin"
echo "   Password: (shown above)"
echo ""
echo "2. Access Argo Rollouts Dashboard:"
echo "   kubectl argo rollouts dashboard"
echo "   Then visit: http://localhost:3100"
echo ""
echo "3. Access Prometheus:"
echo "   kubectl port-forward svc/prometheus-kube-prometheus-prometheus -n monitoring 9090:9090"
echo "   Then visit: http://localhost:9090"
echo ""
echo "4. Access Grafana:"
echo "   kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80"
echo "   Then visit: http://localhost:3000"
echo "   Username: admin"
echo "   Password: prom-operator"
echo ""
echo -e "${GREEN}Happy deploying! 🚀${NC}"
