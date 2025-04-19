#!/bin/bash
set -e

# 配置变量
CLUSTER_NAME="kafka-client-cluster"
REGION="us-east-1"
SERVICE_ACCOUNT_NAME="kafka-client-sa"
ECR_REPO_NAME="kafka-client"

echo "===== 初始化 EKS 环境 ====="

# 1. 检查 EKS 集群是否存在，如果不存在则创建
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

# 2. 更新 kubeconfig
echo "更新 kubeconfig..."
aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${REGION}

# 3. 创建 OIDC 提供商
echo "创建 OIDC 提供商..."
eksctl utils associate-iam-oidc-provider --cluster ${CLUSTER_NAME} --approve --region ${REGION}

# 4. 创建服务账户和 IAM 角色
echo "创建服务账户和 IAM 角色..."
eksctl create iamserviceaccount \
  --name ${SERVICE_ACCOUNT_NAME} \
  --namespace default \
  --cluster ${CLUSTER_NAME} \
  --attach-policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore \
  --attach-policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite \
  --approve \
  --region ${REGION}

# 5. 创建 ECR 仓库（如果不存在）
echo "创建 ECR 仓库..."
if ! aws ecr describe-repositories --repository-names ${ECR_REPO_NAME} --region ${REGION} 2>/dev/null; then
  echo "ECR 仓库不存在，正在创建..."
  aws ecr create-repository --repository-name ${ECR_REPO_NAME} --region ${REGION}
fi

echo "===== EKS 环境初始化完成 ====="
