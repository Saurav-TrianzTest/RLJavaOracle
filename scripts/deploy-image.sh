#!/bin/bash
set -e
set -o pipefail

# ============================================================
# deploy-image.sh — Deploy ResortsLite to AWS EKS
# ============================================================

APP_NAME="resortslite"
NAMESPACE="resortslite"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "============================================"
echo "  ResortsLite — Deploy to AWS EKS"
echo "============================================"
echo ""

# ── AWS / EKS configuration ───────────────────────────────────
read -rp "Enter AWS region (e.g. us-east-1): " AWS_REGION
if [ -z "$AWS_REGION" ]; then
  echo "AWS region is required. Exiting."
  exit 1
fi

read -rp "Enter EKS cluster name: " CLUSTER_NAME
if [ -z "$CLUSTER_NAME" ]; then
  echo "EKS cluster name is required. Exiting."
  exit 1
fi

read -rp "Enter full Docker image URI (e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com/resortslite:latest): " IMAGE_URI
if [ -z "$IMAGE_URI" ]; then
  echo "Image URI is required. Exiting."
  exit 1
fi

# ── Application environment variables ────────────────────────
echo ""
echo "Configure application environment variables (press Enter to skip optional values):"

read -rp "Enter SPRING_DATASOURCE_URL (e.g. jdbc:oracle:thin:@host:1521:SID): " SPRING_DATASOURCE_URL
SPRING_DATASOURCE_URL="${SPRING_DATASOURCE_URL:-jdbc:oracle:thin:@localhost:1521:ORCL}"

read -rp "Enter SPRING_DATASOURCE_USERNAME: " SPRING_DATASOURCE_USERNAME
SPRING_DATASOURCE_USERNAME="${SPRING_DATASOURCE_USERNAME:-admin}"

read -rsp "Enter SPRING_DATASOURCE_PASSWORD: " SPRING_DATASOURCE_PASSWORD
echo ""
SPRING_DATASOURCE_PASSWORD="${SPRING_DATASOURCE_PASSWORD:-changeme}"

read -rp "Enter REDIS_HOST (e.g. my-cluster.abc123.ng.0001.use1.cache.amazonaws.com): " REDIS_HOST
REDIS_HOST="${REDIS_HOST:-localhost}"

read -rp "Enter REDIS_PORT (default: 6379): " REDIS_PORT
REDIS_PORT="${REDIS_PORT:-6379}"

read -rsp "Enter REDIS_PASSWORD (press Enter if none): " REDIS_PASSWORD
echo ""

read -rp "Enable REDIS_SSL? [true/false] (default: false): " REDIS_SSL
REDIS_SSL="${REDIS_SSL:-false}"

read -rp "Enter REPORT_BASE_PATH (default: /var/reports): " REPORT_BASE_PATH
REPORT_BASE_PATH="${REPORT_BASE_PATH:-/var/reports}"

read -rp "Enter BACKUP_PATH (default: /var/backups): " BACKUP_PATH
BACKUP_PATH="${BACKUP_PATH:-/var/backups}"

read -rp "Enter APP_PAYMENT_ENDPOINT (default: http://payment-svc:9090/charge): " APP_PAYMENT_ENDPOINT
APP_PAYMENT_ENDPOINT="${APP_PAYMENT_ENDPOINT:-http://payment-svc:9090/charge}"

read -rp "Enter APP_INVENTORY_ENDPOINT (default: http://inventory-svc:8081/rooms): " APP_INVENTORY_ENDPOINT
APP_INVENTORY_ENDPOINT="${APP_INVENTORY_ENDPOINT:-http://inventory-svc:8081/rooms}"

read -rp "Enter APP_NOTIFICATION_ENDPOINT (default: http://notify-svc:7070/send): " APP_NOTIFICATION_ENDPOINT
APP_NOTIFICATION_ENDPOINT="${APP_NOTIFICATION_ENDPOINT:-http://notify-svc:7070/send}"

# ── Configure kubectl ─────────────────────────────────────────
echo ""
echo "Configuring kubectl for EKS cluster: $CLUSTER_NAME in $AWS_REGION ..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

echo "Verifying cluster connectivity..."
kubectl cluster-info || { echo "Cannot connect to EKS cluster. Exiting."; exit 1; }

# ── Prepare manifests (copy to temp dir to avoid modifying originals) ─────
DEPLOY_DIR="$(mktemp -d)"
cp -r "$PROJECT_ROOT/kubernetes/." "$DEPLOY_DIR/"

echo ""
echo "Substituting placeholders in Kubernetes manifests..."

# Replace IMAGE_URI
sed -i "s|{{IMAGE_URI}}|${IMAGE_URI}|g" "$DEPLOY_DIR/deployment.yaml"

# Replace environment variable placeholders
sed -i "s|{{SPRING_DATASOURCE_URL}}|${SPRING_DATASOURCE_URL}|g"         "$DEPLOY_DIR/deployment.yaml"
sed -i "s|{{SPRING_DATASOURCE_USERNAME}}|${SPRING_DATASOURCE_USERNAME}|g" "$DEPLOY_DIR/deployment.yaml"
sed -i "s|{{SPRING_DATASOURCE_PASSWORD}}|${SPRING_DATASOURCE_PASSWORD}|g" "$DEPLOY_DIR/deployment.yaml"
sed -i "s|{{REDIS_HOST}}|${REDIS_HOST}|g"                               "$DEPLOY_DIR/deployment.yaml"
sed -i "s|{{REDIS_PORT}}|${REDIS_PORT}|g"                               "$DEPLOY_DIR/deployment.yaml"
sed -i "s|{{REDIS_PASSWORD}}|${REDIS_PASSWORD}|g"                       "$DEPLOY_DIR/deployment.yaml"
sed -i "s|{{REDIS_SSL}}|${REDIS_SSL}|g"                                 "$DEPLOY_DIR/deployment.yaml"
sed -i "s|{{REPORT_BASE_PATH}}|${REPORT_BASE_PATH}|g"                   "$DEPLOY_DIR/deployment.yaml"
sed -i "s|{{BACKUP_PATH}}|${BACKUP_PATH}|g"                             "$DEPLOY_DIR/deployment.yaml"
sed -i "s|{{APP_PAYMENT_ENDPOINT}}|${APP_PAYMENT_ENDPOINT}|g"           "$DEPLOY_DIR/deployment.yaml"
sed -i "s|{{APP_INVENTORY_ENDPOINT}}|${APP_INVENTORY_ENDPOINT}|g"       "$DEPLOY_DIR/deployment.yaml"
sed -i "s|{{APP_NOTIFICATION_ENDPOINT}}|${APP_NOTIFICATION_ENDPOINT}|g" "$DEPLOY_DIR/deployment.yaml"

# ── Apply manifests ───────────────────────────────────────────
echo ""
echo "Applying Kubernetes manifests..."

echo "  [1/4] Applying namespace..."
kubectl apply -f "$DEPLOY_DIR/namespace.yaml"

echo "  [2/4] Applying deployment..."
kubectl apply -f "$DEPLOY_DIR/deployment.yaml"

echo "  [3/4] Applying service..."
kubectl apply -f "$DEPLOY_DIR/service.yaml"

echo "  [4/4] Applying ingress..."
kubectl apply -f "$DEPLOY_DIR/ingress.yaml"

# ── Wait for rollout ──────────────────────────────────────────
echo ""
echo "Waiting for deployment rollout..."
kubectl rollout status deployment/"$APP_NAME" -n "$NAMESPACE" --timeout=300s

# ── Verify ────────────────────────────────────────────────────
echo ""
echo "Verifying deployed resources..."
kubectl get pods,svc,ingress -n "$NAMESPACE"

# ── Display URL ───────────────────────────────────────────────
echo ""
INGRESS_HOST=$(kubectl get ingress resortslite-ingress -n "$NAMESPACE" \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
echo "============================================"
echo "  Deployment complete!"
echo "  Application URL: http://${INGRESS_HOST}"
echo "  Health check:    http://${INGRESS_HOST}/actuator/health"
echo "============================================"
echo ""
echo "Rollback command (if needed):"
echo "  kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"

# ── Cleanup temp dir ──────────────────────────────────────────
rm -rf "$DEPLOY_DIR"
