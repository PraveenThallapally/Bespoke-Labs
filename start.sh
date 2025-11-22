#!/bin/bash
set -e

echo "=== Starting Docker daemon ==="
dockerd &

# Wait for Docker to be ready
sleep 15
until docker info >/dev/null 2>&1; do
    echo "Waiting for Docker daemon..."
    sleep 2
done
echo "Docker daemon is ready!"

echo "=== Building FastAPI image ==="
cd /app/wiki-service
docker build -t wiki-fastapi:v1 .

echo "=== Creating k3d cluster ==="
k3d cluster create wiki \
    --api-port 6550 \
    --port 8080:80@loadbalancer \
    --wait

echo "=== Loading FastAPI image into k3d ==="
k3d image import wiki-fastapi:v1 --cluster wiki

echo "=== Waiting for cluster to be ready ==="
kubectl wait --for=condition=Ready nodes --all --timeout=120s

echo "=== Deploying Helm chart ==="
cd /app/wiki-chart
helm install wiki-release . --wait --timeout 5m

echo "=== Deployment complete! ==="
echo "Access the application at http://localhost:8080"
echo "FastAPI: http://localhost:8080/users"
echo "Grafana: http://localhost:8080/grafana"

# Keep container running
tail -f /dev/null
