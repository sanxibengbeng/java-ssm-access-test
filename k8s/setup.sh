#!/bin/bash
set -e

# 配置变量
CLUSTER_NAME="kafka-client-cluster"
REGION="us-east-1"  # 修改为 us-east-1
ECR_REPO_NAME="kafka-client"
SERVICE_ACCOUNT_NAME="kafka-client-sa"

echo "===== 开始部署 Kafka 客户端到 EKS ====="

# 1. 构建 Java 应用
echo "构建 Java 应用..."
cd ..
mvn clean package

# 2. 创建 ECR 仓库（如果不存在）
echo "创建 ECR 仓库..."
if ! aws ecr describe-repositories --repository-names ${ECR_REPO_NAME} --region ${REGION} 2>/dev/null; then
  echo "ECR 仓库不存在，正在创建..."
  aws ecr create-repository --repository-name ${ECR_REPO_NAME} --region ${REGION}
fi

# 3. 获取 ECR 登录令牌
echo "登录到 ECR..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ECR_URI}

# 4. 构建并推送 Docker 镜像
echo "构建并推送 Docker 镜像..."
# 确保在项目根目录
cd /Users/yulongzh/projects/architect-generation
docker build -t ${ECR_REPO_NAME}:latest .
docker tag ${ECR_REPO_NAME}:latest ${ECR_URI}/${ECR_REPO_NAME}:latest
docker push ${ECR_URI}/${ECR_REPO_NAME}:latest
cd k8s  # 返回到 k8s 目录

# 5. 检查 EKS 集群是否存在，如果不存在则创建
echo "检查 EKS 集群..."
if ! aws eks describe-cluster --name ${CLUSTER_NAME} --region ${REGION} > /dev/null 2>&1; then
  echo "创建 EKS 集群 ${CLUSTER_NAME}..."
  eksctl create cluster \
    --name ${CLUSTER_NAME} \
    --region ${REGION} \
    --nodegroup-name standard-workers \
    --node-type t3.medium \
    --nodes 2 \
    --nodes-min 1 \
    --nodes-max 3
else
  echo "EKS 集群 ${CLUSTER_NAME} 已存在"
fi

# 6. 更新 kubeconfig
echo "更新 kubeconfig..."
aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${REGION}

# 7. 创建 OIDC 提供商
echo "创建 OIDC 提供商..."
eksctl utils associate-iam-oidc-provider --cluster ${CLUSTER_NAME} --approve --region ${REGION}

# 8. 创建服务账户和 IAM 角色
echo "创建服务账户和 IAM 角色..."
eksctl create iamserviceaccount \
  --name ${SERVICE_ACCOUNT_NAME} \
  --namespace default \
  --cluster ${CLUSTER_NAME} \
  --attach-policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore \
  --attach-policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite \
  --approve \
  --region ${REGION}

# 9. 获取服务账户角色 ARN
echo "获取服务账户角色 ARN..."
ROLE_ARN=$(kubectl get serviceaccount ${SERVICE_ACCOUNT_NAME} -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')
echo "服务账户角色 ARN: ${ROLE_ARN}"

# 10. 替换部署文件中的变量
echo "更新部署文件..."
IMAGE_URI="${ECR_URI}/${ECR_REPO_NAME}:latest"
sed -i.bak "s|\${ECR_IMAGE_URI}|${IMAGE_URI}|g" deployment.yaml
sed -i.bak "s|\${SERVICE_ACCOUNT_ROLE_ARN}|${ROLE_ARN}|g" deployment.yaml

# 11. 部署应用
echo "部署应用到 EKS..."
kubectl apply -f deployment.yaml

# 12. 等待部署完成
echo "等待部署完成..."
kubectl rollout status deployment/kafka-client

echo "===== 部署完成 ====="
echo "您可以使用以下命令查看 Pod 日志："
echo "kubectl logs -f deployment/kafka-client"
