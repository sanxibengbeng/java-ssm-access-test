#!/bin/bash
set -e

# 配置变量
REGION="us-east-1"
ECR_REPO_NAME="kafka-client"
VERSION_HISTORY_FILE="version_history"

echo "===== 构建镜像并推送到 ECR ====="

# 1. 构建 Java 应用
echo "构建 Java 应用..."
cd ..
mvn clean package

# 2. 获取 ECR 登录令牌
echo "登录到 ECR..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ECR_URI}

# 3. 生成版本号（使用时间戳）
TIMESTAMP=$(date +%Y%m%d%H%M%S)
VERSION="v${TIMESTAMP}"
echo "使用版本号: ${VERSION}"

# 4. 构建并推送 Docker 镜像（指定平台为 linux/amd64）
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
echo "${VERSION}|${ECR_URI}/${ECR_REPO_NAME}:${VERSION}|$(date)" >> ${VERSION_HISTORY_FILE}
echo "版本 ${VERSION} 已添加到 ${VERSION_HISTORY_FILE}"

echo "===== 镜像构建和推送完成 ====="
echo "镜像: ${ECR_URI}/${ECR_REPO_NAME}:${VERSION}"
