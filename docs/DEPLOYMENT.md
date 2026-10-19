# ResortsLite — Deployment Guide (AWS EKS)

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Project Structure](#project-structure)
4. [Local Development with Docker Compose](#local-development-with-docker-compose)
5. [Build and Push Docker Image](#build-and-push-docker-image)
6. [AWS EKS Deployment](#aws-eks-deployment)
7. [Kubernetes Manifest Reference](#kubernetes-manifest-reference)
8. [Configuration Management](#configuration-management)
9. [Scaling and Management](#scaling-and-management)
10. [Troubleshooting](#troubleshooting)
11. [Security Considerations](#security-considerations)

---

## Overview

**Application**: ResortsLite  
**Framework**: Spring Boot 2.7.x  
**Java Version**: Java 8  
**Build Tool**: Maven  
**Target Platform**: AWS EKS (Elastic Kubernetes Service)  
**Application Port**: 8080  
**Health Endpoint**: `/actuator/health`

ResortsLite is a legacy resort booking application modernised for cloud-native deployment on AWS EKS. It uses Spring Session backed by Amazon ElastiCache for Redis to enable stateless horizontal scaling across multiple pod replicas.

---

## Prerequisites

### Local Development
| Tool | Version | Purpose |
|------|---------|---------|
| Docker | 20.10+ | Container build and run |
| Docker Compose | 2.x | Local multi-container orchestration |
| Java | 8+ | Local development (optional) |
| Maven | 3.8+ | Local build (optional) |

### AWS EKS Deployment
| Tool | Version | Purpose |
|------|---------|---------|
| AWS CLI | 2.x | AWS authentication and ECR access |
| kubectl | 1.27+ | Kubernetes cluster management |
| eksctl | 0.150+ | EKS cluster creation (optional) |

### AWS IAM Permissions Required
```
ecr:GetAuthorizationToken
ecr:BatchCheckLayerAvailability
ecr:GetDownloadUrlForLayer
ecr:BatchGetImage
ecr:CreateRepository
ecr:PutImage
ecr:InitiateLayerUpload
ecr:UploadLayerPart
ecr:CompleteLayerUpload
eks:DescribeCluster
eks:ListClusters
```

---

## Project Structure

```
.
├── Dockerfile                    # Multi-stage Docker build
├── .dockerignore                 # Files excluded from Docker context
├── docker-compose.yml            # Local development compose file
├── pom.xml                       # Maven build descriptor
├── src/
│   └── main/
│       ├── java/com/demo/resortslite/
│       │   ├── ResortsLiteApplication.java
│       │   ├── BookingController.java
│       │   ├── BookingService.java
│       │   ├── ReportService.java
│       │   └── entity/Doctor.java
│       └── resources/
│           └── application.properties
├── kubernetes/
│   ├── namespace.yaml            # Kubernetes namespace
│   ├── deployment.yaml           # Application deployment
│   ├── service.yaml              # ClusterIP service
│   └── ingress.yaml              # AWS ALB ingress
├── scripts/
│   ├── build-push.sh             # Linux/macOS build & push
│   ├── build-push.bat            # Windows build & push
│   ├── deploy-image.sh           # Linux/macOS EKS deploy
│   └── deploy-image.bat          # Windows EKS deploy
└── docs/
    └── DEPLOYMENT.md             # This file
```

---

## Local Development with Docker Compose

### 1. Configure Environment Variables

Create a `.env` file in the project root (never commit this file):

```bash
# Database
SPRING_DATASOURCE_URL=jdbc:oracle:thin:@localhost:1521:ORCL
SPRING_DATASOURCE_USERNAME=admin
SPRING_DATASOURCE_PASSWORD=your_password

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=
REDIS_SSL=false

# Application paths
REPORT_BASE_PATH=/var/reports
BACKUP_PATH=/var/backups

# Internal service endpoints
APP_PAYMENT_ENDPOINT=http://payment-svc:9090/charge
APP_INVENTORY_ENDPOINT=http://inventory-svc:8081/rooms
APP_NOTIFICATION_ENDPOINT=http://notify-svc:7070/send
```

### 2. Build and Start

```bash
# Build the image and start the application
docker compose up --build

# Run in background
docker compose up --build -d

# View logs
docker compose logs -f resortslite

# Stop
docker compose down
```

### 3. Verify the Application

```bash
# Health check
curl http://localhost:8080/actuator/health

# Test booking endpoint
curl -X POST "http://localhost:8080/api/bookings/create" \
  -d "guestName=John&roomType=Suite&checkIn=2024-01-01&checkOut=2024-01-05"
```

---

## Build and Push Docker Image

### Linux / macOS

```bash
chmod +x scripts/build-push.sh
./scripts/build-push.sh
```

The script will prompt you to:
1. Select registry type (AWS ECR or Docker Hub)
2. Enter registry credentials and details
3. Specify an image tag (defaults to `latest`)

### Windows

```cmd
scripts\build-push.bat
```

### Manual Build (AWS ECR)

```bash
# Set variables
AWS_REGION=us-east-1
AWS_ACCOUNT_ID=123456789012
IMAGE_TAG=1.0.0

# Authenticate to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Create repository (first time only)
aws ecr create-repository --repository-name resortslite --region $AWS_REGION

# Build and push
docker build -t ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/resortslite:${IMAGE_TAG} .
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/resortslite:${IMAGE_TAG}
```

---

## AWS EKS Deployment

### Step 1: Configure AWS CLI

```bash
aws configure
# Enter: AWS Access Key ID, Secret Access Key, Region, Output format
```

### Step 2: Create or Connect to EKS Cluster

**Create a new cluster (if needed):**
```bash
eksctl create cluster \
  --name resortslite-cluster \
  --region us-east-1 \
  --nodegroup-name standard-workers \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 4 \
  --managed
```

**Connect to existing cluster:**
```bash
aws eks update-kubeconfig --region us-east-1 --name resortslite-cluster
kubectl cluster-info
```

### Step 3: Install AWS Load Balancer Controller (for Ingress)

```bash
# Add the EKS chart repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install the controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=resortslite-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

### Step 4: Run the Deployment Script

**Linux / macOS:**
```bash
chmod +x scripts/deploy-image.sh
./scripts/deploy-image.sh
```

**Windows:**
```cmd
scripts\deploy-image.bat
```

The script will prompt for:
- AWS region and EKS cluster name
- Full Docker image URI
- All required environment variables (database, Redis, service endpoints)

### Step 5: Verify Deployment

```bash
# Check all resources
kubectl get all -n resortslite

# Check pod logs
kubectl logs -l app=resortslite -n resortslite --tail=100

# Check ingress and get URL
kubectl get ingress -n resortslite

# Test health endpoint
INGRESS_HOST=$(kubectl get ingress resortslite-ingress -n resortslite \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl http://${INGRESS_HOST}/actuator/health
```

---

## Kubernetes Manifest Reference

### namespace.yaml
Creates the `resortslite` namespace to isolate all application resources.

### deployment.yaml
- **Replicas**: 2 (for high availability)
- **Image**: Pulled from `{{IMAGE_URI}}` placeholder (replaced at deploy time)
- **Resources**: 250m CPU / 512Mi memory (requests); 500m CPU / 1Gi memory (limits)
- **Liveness Probe**: `GET /actuator/health` — initial delay 60s, period 30s
- **Readiness Probe**: `GET /actuator/health` — initial delay 30s, period 15s
- **JVM Flags**: `-Xms256m -Xmx512m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0`

### service.yaml
- **Type**: ClusterIP (internal access only; ALB Ingress handles external traffic)
- **Port**: 80 → 8080 (container port)

### ingress.yaml
- **Class**: AWS ALB (Application Load Balancer)
- **Scheme**: internet-facing
- **Health check path**: `/actuator/health`
- **Host**: `resortslite.example.com` (update to your actual domain)

---

## Configuration Management

### Environment Variables Reference

| Variable | Description | Default |
|----------|-------------|---------|
| `SPRING_DATASOURCE_URL` | Oracle JDBC connection URL | `jdbc:oracle:thin:@localhost:1521:ORCL` |
| `SPRING_DATASOURCE_USERNAME` | Database username | `admin` |
| `SPRING_DATASOURCE_PASSWORD` | Database password | — |
| `REDIS_HOST` | ElastiCache Redis endpoint | `localhost` |
| `REDIS_PORT` | Redis port | `6379` |
| `REDIS_PASSWORD` | Redis auth token | — |
| `REDIS_SSL` | Enable TLS for Redis | `false` |
| `REPORT_BASE_PATH` | Base path for report files | `/var/reports` |
| `BACKUP_PATH` | Base path for backup files | `/var/backups` |
| `APP_PAYMENT_ENDPOINT` | Payment service URL | `http://payment-svc:9090/charge` |
| `APP_INVENTORY_ENDPOINT` | Inventory service URL | `http://inventory-svc:8081/rooms` |
| `APP_NOTIFICATION_ENDPOINT` | Notification service URL | `http://notify-svc:7070/send` |
| `SPRING_PROFILES_ACTIVE` | Spring profile | `docker` |
| `JAVA_OPTS` | JVM options | See Dockerfile |

### Using AWS Secrets Manager for Sensitive Values

```bash
# Store database password
aws secretsmanager create-secret \
  --name resortslite/db-password \
  --secret-string "your_db_password"

# Store Redis auth token
aws secretsmanager create-secret \
  --name resortslite/redis-password \
  --secret-string "your_redis_token"
```

Use the [AWS Secrets Store CSI Driver](https://docs.aws.amazon.com/secretsmanager/latest/userguide/integrating_csi_driver.html) to mount secrets as environment variables in your pods.

---

## Scaling and Management

### Manual Scaling

```bash
# Scale to 4 replicas
kubectl scale deployment resortslite --replicas=4 -n resortslite

# Check rollout status
kubectl rollout status deployment/resortslite -n resortslite
```

### Horizontal Pod Autoscaler (HPA)

```bash
kubectl autoscale deployment resortslite \
  --cpu-percent=70 \
  --min=2 \
  --max=10 \
  -n resortslite

kubectl get hpa -n resortslite
```

### Rolling Update

```bash
# Update image
kubectl set image deployment/resortslite \
  resortslite=<NEW_IMAGE_URI> \
  -n resortslite

# Monitor rollout
kubectl rollout status deployment/resortslite -n resortslite
```

### Rollback

```bash
# Rollback to previous version
kubectl rollout undo deployment/resortslite -n resortslite

# Rollback to specific revision
kubectl rollout history deployment/resortslite -n resortslite
kubectl rollout undo deployment/resortslite --to-revision=2 -n resortslite
```

---

## Troubleshooting

### Pod Not Starting

```bash
# Check pod status
kubectl get pods -n resortslite

# Describe pod for events
kubectl describe pod <pod-name> -n resortslite

# Check logs
kubectl logs <pod-name> -n resortslite
kubectl logs <pod-name> -n resortslite --previous  # crashed pod
```

### Common Issues

**ImagePullBackOff**
```bash
# Verify ECR credentials
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <account>.dkr.ecr.us-east-1.amazonaws.com

# Check image exists
aws ecr describe-images --repository-name resortslite --region us-east-1
```

**CrashLoopBackOff (JVM / Database)**
```bash
# Check application logs for stack traces
kubectl logs -l app=resortslite -n resortslite --tail=200

# Verify database connectivity from within the pod
kubectl exec -it <pod-name> -n resortslite -- sh
```

**Redis Connection Failure**
```bash
# Verify REDIS_HOST and REDIS_PORT environment variables
kubectl exec -it <pod-name> -n resortslite -- env | grep REDIS

# Check ElastiCache security group allows traffic from EKS node security group
```

**Ingress Not Getting External IP**
```bash
# Check AWS Load Balancer Controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Verify IAM permissions for the controller service account
```

**Health Check Failing**
```bash
# Test health endpoint directly from pod
kubectl exec -it <pod-name> -n resortslite -- \
  wget -qO- http://localhost:8080/actuator/health

# Check management endpoint configuration
kubectl exec -it <pod-name> -n resortslite -- env | grep MANAGEMENT
```

---

## Security Considerations

1. **Never commit secrets** — Use AWS Secrets Manager or Kubernetes Secrets for sensitive values
2. **Non-root container** — The application runs as `appuser` (non-root) inside the container
3. **Network policies** — Consider adding Kubernetes NetworkPolicy to restrict pod-to-pod traffic
4. **Image scanning** — Enable ECR image scanning to detect vulnerabilities
5. **HTTPS** — Configure ACM certificate on the ALB for TLS termination:
   ```yaml
   alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-east-1:123456789:certificate/xxx
   alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS": 443}]'
   ```
6. **Redis TLS** — Set `REDIS_SSL=true` and use the TLS endpoint for ElastiCache in production
7. **Resource limits** — CPU and memory limits are set to prevent noisy-neighbour issues
8. **Log4j** — The pom.xml includes log4j-core 2.14.1 which has CVE-2021-44228 (Log4Shell). **Upgrade to 2.17.1+ immediately** before production deployment.
9. **commons-collections** — Version 3.2.1 has CVE-2015-6420 (RCE). **Upgrade to 3.2.2+** before production deployment.

---

## Java-Specific Notes

- **JVM Container Support**: `-XX:+UseContainerSupport` ensures the JVM respects container memory limits (Java 8u191+)
- **MaxRAMPercentage**: Set to 75% to leave headroom for the OS and non-heap memory
- **Startup Time**: Spring Boot on Java 8 typically takes 20–40 seconds; liveness probe `initialDelaySeconds` is set to 60s accordingly
- **Graceful Shutdown**: `terminationGracePeriodSeconds: 30` allows in-flight requests to complete
- **Spring Session / Redis**: Sessions are stored in ElastiCache, enabling true stateless horizontal scaling — no sticky sessions required on the ALB
- **Actuator**: `/actuator/health` is exposed for both liveness and readiness probes; `show-details=always` is enabled for detailed health information
