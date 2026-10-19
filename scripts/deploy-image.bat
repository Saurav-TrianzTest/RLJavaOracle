@echo off
setlocal enabledelayedexpansion

:: ============================================================
:: deploy-image.bat — Deploy ResortsLite to AWS EKS (Windows)
:: ============================================================

set "APP_NAME=resortslite"
set "NAMESPACE=resortslite"

echo ============================================
echo   ResortsLite - Deploy to AWS EKS
echo ============================================
echo.

:: ── AWS / EKS configuration ───────────────────────────────────
set /p "AWS_REGION=Enter AWS region (e.g. us-east-1): "
if "!AWS_REGION!"=="" (
    echo AWS region is required. Exiting.
    exit /b 1
)

set /p "CLUSTER_NAME=Enter EKS cluster name: "
if "!CLUSTER_NAME!"=="" (
    echo EKS cluster name is required. Exiting.
    exit /b 1
)

set /p "IMAGE_URI=Enter full Docker image URI (e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com/resortslite:latest): "
if "!IMAGE_URI!"=="" (
    echo Image URI is required. Exiting.
    exit /b 1
)

:: ── Application environment variables ────────────────────────
echo.
echo Configure application environment variables (press Enter to use defaults):

set /p "SPRING_DATASOURCE_URL=Enter SPRING_DATASOURCE_URL (default: jdbc:oracle:thin:@localhost:1521:ORCL): "
if "!SPRING_DATASOURCE_URL!"=="" set "SPRING_DATASOURCE_URL=jdbc:oracle:thin:@localhost:1521:ORCL"

set /p "SPRING_DATASOURCE_USERNAME=Enter SPRING_DATASOURCE_USERNAME (default: admin): "
if "!SPRING_DATASOURCE_USERNAME!"=="" set "SPRING_DATASOURCE_USERNAME=admin"

set /p "SPRING_DATASOURCE_PASSWORD=Enter SPRING_DATASOURCE_PASSWORD: "
if "!SPRING_DATASOURCE_PASSWORD!"=="" set "SPRING_DATASOURCE_PASSWORD=changeme"

set /p "REDIS_HOST=Enter REDIS_HOST (default: localhost): "
if "!REDIS_HOST!"=="" set "REDIS_HOST=localhost"

set /p "REDIS_PORT=Enter REDIS_PORT (default: 6379): "
if "!REDIS_PORT!"=="" set "REDIS_PORT=6379"

set /p "REDIS_PASSWORD=Enter REDIS_PASSWORD (press Enter if none): "

set /p "REDIS_SSL=Enable REDIS_SSL? [true/false] (default: false): "
if "!REDIS_SSL!"=="" set "REDIS_SSL=false"

set /p "REPORT_BASE_PATH=Enter REPORT_BASE_PATH (default: /var/reports): "
if "!REPORT_BASE_PATH!"=="" set "REPORT_BASE_PATH=/var/reports"

set /p "BACKUP_PATH=Enter BACKUP_PATH (default: /var/backups): "
if "!BACKUP_PATH!"=="" set "BACKUP_PATH=/var/backups"

set /p "APP_PAYMENT_ENDPOINT=Enter APP_PAYMENT_ENDPOINT (default: http://payment-svc:9090/charge): "
if "!APP_PAYMENT_ENDPOINT!"=="" set "APP_PAYMENT_ENDPOINT=http://payment-svc:9090/charge"

set /p "APP_INVENTORY_ENDPOINT=Enter APP_INVENTORY_ENDPOINT (default: http://inventory-svc:8081/rooms): "
if "!APP_INVENTORY_ENDPOINT!"=="" set "APP_INVENTORY_ENDPOINT=http://inventory-svc:8081/rooms"

set /p "APP_NOTIFICATION_ENDPOINT=Enter APP_NOTIFICATION_ENDPOINT (default: http://notify-svc:7070/send): "
if "!APP_NOTIFICATION_ENDPOINT!"=="" set "APP_NOTIFICATION_ENDPOINT=http://notify-svc:7070/send"

:: ── Configure kubectl ─────────────────────────────────────────
echo.
echo Configuring kubectl for EKS cluster: !CLUSTER_NAME! in !AWS_REGION! ...
aws eks update-kubeconfig --region !AWS_REGION! --name !CLUSTER_NAME!
if !ERRORLEVEL! neq 0 (
    echo Failed to configure kubectl. Exiting.
    exit /b 1
)

echo Verifying cluster connectivity...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
    echo Cannot connect to EKS cluster. Exiting.
    exit /b 1
)

:: ── Prepare temp manifests ────────────────────────────────────
set "DEPLOY_DIR=%TEMP%\resortslite-deploy"
if exist "!DEPLOY_DIR!" rmdir /s /q "!DEPLOY_DIR!"
mkdir "!DEPLOY_DIR!"

:: Determine project root (parent of scripts folder)
set "SCRIPT_DIR=%~dp0"
for %%i in ("!SCRIPT_DIR!..") do set "PROJECT_ROOT=%%~fi"

xcopy /e /i /q "!PROJECT_ROOT!\kubernetes" "!DEPLOY_DIR!" >nul

echo.
echo Substituting placeholders in Kubernetes manifests...

:: Use PowerShell for sed-like substitution on Windows
powershell -Command "(Get-Content '!DEPLOY_DIR!\deployment.yaml') -replace '\{\{IMAGE_URI\}\}', '!IMAGE_URI!' | Set-Content '!DEPLOY_DIR!\deployment.yaml'"
powershell -Command "(Get-Content '!DEPLOY_DIR!\deployment.yaml') -replace '\{\{SPRING_DATASOURCE_URL\}\}', '!SPRING_DATASOURCE_URL!' | Set-Content '!DEPLOY_DIR!\deployment.yaml'"
powershell -Command "(Get-Content '!DEPLOY_DIR!\deployment.yaml') -replace '\{\{SPRING_DATASOURCE_USERNAME\}\}', '!SPRING_DATASOURCE_USERNAME!' | Set-Content '!DEPLOY_DIR!\deployment.yaml'"
powershell -Command "(Get-Content '!DEPLOY_DIR!\deployment.yaml') -replace '\{\{SPRING_DATASOURCE_PASSWORD\}\}', '!SPRING_DATASOURCE_PASSWORD!' | Set-Content '!DEPLOY_DIR!\deployment.yaml'"
powershell -Command "(Get-Content '!DEPLOY_DIR!\deployment.yaml') -replace '\{\{REDIS_HOST\}\}', '!REDIS_HOST!' | Set-Content '!DEPLOY_DIR!\deployment.yaml'"
powershell -Command "(Get-Content '!DEPLOY_DIR!\deployment.yaml') -replace '\{\{REDIS_PORT\}\}', '!REDIS_PORT!' | Set-Content '!DEPLOY_DIR!\deployment.yaml'"
powershell -Command "(Get-Content '!DEPLOY_DIR!\deployment.yaml') -replace '\{\{REDIS_PASSWORD\}\}', '!REDIS_PASSWORD!' | Set-Content '!DEPLOY_DIR!\deployment.yaml'"
powershell -Command "(Get-Content '!DEPLOY_DIR!\deployment.yaml') -replace '\{\{REDIS_SSL\}\}', '!REDIS_SSL!' | Set-Content '!DEPLOY_DIR!\deployment.yaml'"
powershell -Command "(Get-Content '!DEPLOY_DIR!\deployment.yaml') -replace '\{\{REPORT_BASE_PATH\}\}', '!REPORT_BASE_PATH!' | Set-Content '!DEPLOY_DIR!\deployment.yaml'"
powershell -Command "(Get-Content '!DEPLOY_DIR!\deployment.yaml') -replace '\{\{BACKUP_PATH\}\}', '!BACKUP_PATH!' | Set-Content '!DEPLOY_DIR!\deployment.yaml'"
powershell -Command "(Get-Content '!DEPLOY_DIR!\deployment.yaml') -replace '\{\{APP_PAYMENT_ENDPOINT\}\}', '!APP_PAYMENT_ENDPOINT!' | Set-Content '!DEPLOY_DIR!\deployment.yaml'"
powershell -Command "(Get-Content '!DEPLOY_DIR!\deployment.yaml') -replace '\{\{APP_INVENTORY_ENDPOINT\}\}', '!APP_INVENTORY_ENDPOINT!' | Set-Content '!DEPLOY_DIR!\deployment.yaml'"
powershell -Command "(Get-Content '!DEPLOY_DIR!\deployment.yaml') -replace '\{\{APP_NOTIFICATION_ENDPOINT\}\}', '!APP_NOTIFICATION_ENDPOINT!' | Set-Content '!DEPLOY_DIR!\deployment.yaml'"

:: ── Apply manifests ───────────────────────────────────────────
echo.
echo Applying Kubernetes manifests...

echo   [1/4] Applying namespace...
kubectl apply -f "!DEPLOY_DIR!\namespace.yaml"
if !ERRORLEVEL! neq 0 ( echo Failed to apply namespace. & exit /b 1 )

echo   [2/4] Applying deployment...
kubectl apply -f "!DEPLOY_DIR!\deployment.yaml"
if !ERRORLEVEL! neq 0 ( echo Failed to apply deployment. & exit /b 1 )

echo   [3/4] Applying service...
kubectl apply -f "!DEPLOY_DIR!\service.yaml"
if !ERRORLEVEL! neq 0 ( echo Failed to apply service. & exit /b 1 )

echo   [4/4] Applying ingress...
kubectl apply -f "!DEPLOY_DIR!\ingress.yaml"
if !ERRORLEVEL! neq 0 ( echo Failed to apply ingress. & exit /b 1 )

:: ── Wait for rollout ──────────────────────────────────────────
echo.
echo Waiting for deployment rollout...
kubectl rollout status deployment/!APP_NAME! -n !NAMESPACE! --timeout=300s
if !ERRORLEVEL! neq 0 (
    echo Deployment rollout failed. Check pod logs:
    echo   kubectl logs -l app=!APP_NAME! -n !NAMESPACE!
    exit /b 1
)

:: ── Verify ────────────────────────────────────────────────────
echo.
echo Verifying deployed resources...
kubectl get pods,svc,ingress -n !NAMESPACE!

echo.
echo ============================================
echo   Deployment complete!
echo   Check ingress for the application URL.
echo   Health check: /actuator/health
echo ============================================
echo.
echo Rollback command (if needed):
echo   kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!

:: ── Cleanup ───────────────────────────────────────────────────
rmdir /s /q "!DEPLOY_DIR!"

endlocal
