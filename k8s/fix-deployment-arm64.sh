#!/bin/bash
set -e

# 配置变量
REGION="us-east-1"
ECR_REPO_NAME="kafka-client"
VERSION="fix-arm64-$(date +%Y%m%d%H%M%S)"

echo "===== 修复 Kafka 客户端部署（ARM64 版本）====="

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

# 4. 构建并推送 Docker 镜像（使用 ARM64 架构）
echo "构建并推送 Docker 镜像（ARM64 架构）..."
# 确保在项目根目录
cd /Users/yulongzh/projects/architect-generation
docker build -t ${ECR_REPO_NAME}:${VERSION} .
docker tag ${ECR_REPO_NAME}:${VERSION} ${ECR_URI}/${ECR_REPO_NAME}:${VERSION}
docker push ${ECR_URI}/${ECR_REPO_NAME}:${VERSION}

# 5. 同时更新 latest 标签
docker tag ${ECR_REPO_NAME}:${VERSION} ${ECR_URI}/${ECR_REPO_NAME}:latest
docker push ${ECR_URI}/${ECR_REPO_NAME}:latest

# 6. 记录版本到历史文件
cd k8s  # 返回到 k8s 目录
echo "${VERSION}|${ECR_URI}/${ECR_REPO_NAME}:${VERSION}|$(date) - ARM64 架构" >> version_history

# 7. 获取服务账户角色 ARN
echo "获取服务账户角色 ARN..."
SERVICE_ACCOUNT_NAME="kafka-client-sa"
ROLE_ARN=$(kubectl get serviceaccount ${SERVICE_ACCOUNT_NAME} -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || echo "")

if [ -z "$ROLE_ARN" ]; then
  echo "创建服务账户..."
  kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kafka-client-sa
  namespace: default
EOF

  echo "创建 OIDC 提供商..."
  CLUSTER_NAME="kafka-client-cluster"
  eksctl utils associate-iam-oidc-provider --cluster ${CLUSTER_NAME} --approve --region ${REGION}

  echo "创建 IAM 角色..."
  eksctl create iamserviceaccount \
    --name ${SERVICE_ACCOUNT_NAME} \
    --namespace default \
    --cluster ${CLUSTER_NAME} \
    --attach-policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore \
    --attach-policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite \
    --approve \
    --region ${REGION}
    
  ROLE_ARN=$(kubectl get serviceaccount ${SERVICE_ACCOUNT_NAME} -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')
fi

echo "服务账户角色 ARN: ${ROLE_ARN}"

# 8. 创建修复后的部署文件
echo "创建修复后的部署文件..."
IMAGE_URI="${ECR_URI}/${ECR_REPO_NAME}:${VERSION}"
cat > deployment-arm64.yaml <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kafka-client-sa
  namespace: default
  annotations:
    eks.amazonaws.com/role-arn: ${ROLE_ARN}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-client
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: kafka-client
  template:
    metadata:
      labels:
        app: kafka-client
    spec:
      serviceAccountName: kafka-client-sa
      containers:
      - name: kafka-client
        image: ${IMAGE_URI}
        env:
        - name: BOOTSTRAP_SERVERS
          valueFrom:
            configMapKeyRef:
              name: kafka-config
              key: bootstrap.servers
        - name: GROUP_ID
          valueFrom:
            configMapKeyRef:
              name: kafka-config
              key: group.id
        - name: AWS_REGION
          valueFrom:
            configMapKeyRef:
              name: kafka-config
              key: region
        - name: SECRET_NAME
          valueFrom:
            configMapKeyRef:
              name: kafka-config
              key: secret.name
        resources:
          limits:
            cpu: "500m"
            memory: "512Mi"
          requests:
            cpu: "250m"
            memory: "256Mi"
EOF

# 9. 重新部署应用
echo "重新部署应用到 EKS..."
kubectl apply -f deployment-arm64.yaml

# 10. 等待部署完成
echo "等待部署完成..."
kubectl rollout status deployment/kafka-client --timeout=60s || true

echo "===== 修复部署完成 ====="
echo "已部署版本: ${VERSION}"
echo "您可以使用以下命令查看 Pod 日志："
echo "kubectl logs -f deployment/kafka-client"
