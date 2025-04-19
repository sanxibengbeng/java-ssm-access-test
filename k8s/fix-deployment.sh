#!/bin/bash
set -e

# 配置变量
REGION="us-east-1"
ECR_REPO_NAME="kafka-client"
VERSION="fix-$(date +%Y%m%d%H%M%S)"

echo "===== 修复 Kafka 客户端部署 ====="

# 1. 更新 ConfigMap
echo "更新 ConfigMap..."
kubectl apply -f kafka-config.yaml

# 2. 构建 Java 应用
echo "构建 Java 应用..."
cd ..
mvn clean package

# 3. 获取 ECR 登录令牌
echo "登录到 ECR..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ECR_URI}

# 4. 构建并推送 Docker 镜像（使用正确的平台）
echo "构建并推送 Docker 镜像..."
# 确保在项目根目录
cd /Users/yulongzh/projects/architect-generation
docker build --platform linux/amd64 -t ${ECR_REPO_NAME}:${VERSION} .
docker tag ${ECR_REPO_NAME}:${VERSION} ${ECR_URI}/${ECR_REPO_NAME}:${VERSION}
docker push ${ECR_URI}/${ECR_REPO_NAME}:${VERSION}

# 5. 同时更新 latest 标签
docker tag ${ECR_REPO_NAME}:${VERSION} ${ECR_URI}/${ECR_REPO_NAME}:latest
docker push ${ECR_URI}/${ECR_REPO_NAME}:latest

# 6. 记录版本到历史文件
cd k8s  # 返回到 k8s 目录
echo "${VERSION}|${ECR_URI}/${ECR_REPO_NAME}:${VERSION}|$(date) - 修复架构问题" >> version_history

# 7. 获取服务账户角色 ARN
echo "获取服务账户角色 ARN..."
SERVICE_ACCOUNT_NAME="kafka-client-sa"
ROLE_ARN=$(kubectl get serviceaccount ${SERVICE_ACCOUNT_NAME} -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')
echo "服务账户角色 ARN: ${ROLE_ARN}"

# 8. 替换部署文件中的变量
echo "更新部署文件..."
IMAGE_URI="${ECR_URI}/${ECR_REPO_NAME}:${VERSION}"
cp deployment.yaml deployment-fix.yaml
sed -i.bak "s|\${ECR_IMAGE_URI}|${IMAGE_URI}|g" deployment-fix.yaml
sed -i.bak "s|\${SERVICE_ACCOUNT_ROLE_ARN}|${ROLE_ARN}|g" deployment-fix.yaml

# 9. 重新部署应用
echo "重新部署应用到 EKS..."
kubectl apply -f deployment-fix.yaml

# 10. 等待部署完成
echo "等待部署完成..."
kubectl rollout status deployment/kafka-client

echo "===== 修复部署完成 ====="
echo "已部署版本: ${VERSION}"
echo "您可以使用以下命令查看 Pod 日志："
echo "kubectl logs -f deployment/kafka-client"
