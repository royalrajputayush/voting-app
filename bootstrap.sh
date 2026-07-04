#!/bin/bash
set -e

CLUSTER_NAME="voting-app-cluster"

echo "===================================================="
echo "      Bootstrapping Local Kubernetes Cluster        "
echo "===================================================="

# Check dependencies
for cmd in kind kubectl helm docker; do
  if ! command -v $cmd &> /dev/null; then
    echo "Error: $cmd is not installed. Please install it first."
    exit 1
  fi
done

# Check if Docker is running
if ! docker info &> /dev/null; then
  echo "Error: Docker daemon is not running. Please start Docker Desktop/daemon."
  exit 1
fi

# Create kind cluster configuration inline
echo "Creating kind cluster configuration..."
cat <<EOF > kind-config.yaml
apiVersion: kind.x-k8s.io/v1alpha4
kind: Cluster
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    apiVersion: kubeadm.k8s.io/v1beta3
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

# Create cluster if it doesn't exist
if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
  echo "Cluster '${CLUSTER_NAME}' already exists. Recreating it to ensure clean state..."
  kind delete cluster --name "$CLUSTER_NAME"
fi

echo "Creating kind cluster..."
kind create cluster --config kind-config.yaml --name "$CLUSTER_NAME"
rm -f kind-config.yaml

# Apply NGINX Ingress Controller
echo "Deploying NGINX Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# Wait for Ingress Controller to be ready
echo "Waiting for NGINX Ingress Controller to become ready (this may take a minute)..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

# Build Docker Images
echo "Building application container images..."
docker build -t example-voting-app-vote:latest ./vote
docker build -t example-voting-app-result:latest ./result
docker build -t example-voting-app-worker:latest ./worker

# Load Docker Images into kind cluster
echo "Loading images into kind cluster..."
kind load docker-image example-voting-app-vote:latest --name "$CLUSTER_NAME"
kind load docker-image example-voting-app-result:latest --name "$CLUSTER_NAME"
kind load docker-image example-voting-app-worker:latest --name "$CLUSTER_NAME"

# Deploy using Helm
echo "Deploying voting-app Helm chart..."
helm upgrade --install voting-app ./charts/voting-app -f ./charts/voting-app/values-dev.yaml

# Wait for database schema bootstrap job to run
echo "Waiting for Postgres and bootstrap job to complete..."
kubectl wait --for=condition=complete job/db-bootstrap --timeout=90s || true

# Wait for application pods to be ready
echo "Waiting for application pods to become ready..."
kubectl wait --for=condition=ready pod --selector=app=vote --timeout=90s
kubectl wait --for=condition=ready pod --selector=app=result --timeout=90s
kubectl wait --for=condition=ready pod --selector=app=worker --timeout=90s

echo "===================================================="
echo "          Voting App Deployment Complete!           "
echo "===================================================="
echo "You can access the services at:"
echo "  - Vote Web App:    http://vote.127.0.0.1.nip.io"
echo "  - Results App:     http://result.127.0.0.1.nip.io"
echo "===================================================="
