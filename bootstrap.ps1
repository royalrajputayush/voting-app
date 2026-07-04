$ErrorActionPreference = "Stop"

$ClusterName = "voting-app-cluster"

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "      Bootstrapping Local Kubernetes Cluster        " -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

# Check dependencies
foreach ($cmd in @("kind", "kubectl", "helm", "docker")) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Error "Error: $cmd is not installed. Please install it first."
    }
}

# Check if Docker is running
& docker info >$null 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Error: Docker daemon is not running. Please start Docker Desktop/daemon."
}

# Create kind cluster configuration inline
Write-Host "Creating kind cluster configuration..."
$kindConfig = @"
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
"@

$kindConfig | Out-File -FilePath "kind-config.yaml" -Encoding utf8

# Check if cluster exists
$clusters = & kind get clusters
if ($clusters -contains $ClusterName) {
    Write-Host "Cluster '$ClusterName' already exists. Recreating it to ensure clean state..."
    & kind delete cluster --name $ClusterName
}

Write-Host "Creating kind cluster..."
& kind create cluster --config kind-config.yaml --name $ClusterName
Remove-Item -Path "kind-config.yaml" -Force

# Apply NGINX Ingress Controller
Write-Host "Deploying NGINX Ingress Controller..."
& kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# Wait for Ingress Controller to be ready
Write-Host "Waiting for NGINX Ingress Controller to become ready (this may take a minute)..."
& kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s

# Build Docker Images
Write-Host "Building application container images..."
& docker build -t example-voting-app-vote:latest ./vote
& docker build -t example-voting-app-result:latest ./result
& docker build -t example-voting-app-worker:latest ./worker

# Load Docker Images into kind cluster
Write-Host "Loading images into kind cluster..."
& kind load docker-image example-voting-app-vote:latest --name $ClusterName
& kind load docker-image example-voting-app-result:latest --name $ClusterName
& kind load docker-image example-voting-app-worker:latest --name $ClusterName

# Deploy using Helm
Write-Host "Deploying voting-app Helm chart..."
& helm upgrade --install voting-app ./charts/voting-app -f ./charts/voting-app/values-dev.yaml

# Wait for database schema bootstrap job to run
Write-Host "Waiting for Postgres and bootstrap job to complete..."
try {
    & kubectl wait --for=condition=complete job/db-bootstrap --timeout=90s
} catch {
    # Ignore errors here if it already completed
}

# Wait for application pods to be ready
Write-Host "Waiting for application pods to become ready..."
& kubectl wait --for=condition=ready pod --selector=app=vote --timeout=90s
& kubectl wait --for=condition=ready pod --selector=app=result --timeout=90s
& kubectl wait --for=condition=ready pod --selector=app=worker --timeout=90s

Write-Host "====================================================" -ForegroundColor Green
Write-Host "          Voting App Deployment Complete!           " -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
Write-Host "You can access the services at:"
Write-Host "  - Vote Web App:    http://vote.127.0.0.1.nip.io" -ForegroundColor Yellow
Write-Host "  - Results App:     http://result.127.0.0.1.nip.io" -ForegroundColor Yellow
Write-Host "====================================================" -ForegroundColor Green
