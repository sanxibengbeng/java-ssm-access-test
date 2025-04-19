#!/bin/bash
set -e

# 配置变量
CLUSTER_NAME="kafka-client-cluster"
REGION="us-east-1"
SERVICE_ACCOUNT_NAME="kafka-client-sa"
VERSION_HISTORY_FILE="version_history"

echo "===== 部署应用到 EKS ====="

# 1. 检查版本历史文件是否存在
if [ ! -f "${VERSION_HISTORY_FILE}" ]; then
  echo "错误: 版本历史文件 ${VERSION_HISTORY_FILE} 不存在"
  exit 1
fi

# 2. 显示可用版本
echo "可用版本列表:"
cat "${VERSION_HISTORY_FILE}" | nl

# 3. 选择要部署的版本
echo "请输入要部署的版本编号:"
read VERSION_NUMBER

# 4. 获取选择的版本信息
SELECTED_VERSION=$(sed -n "${VERSION_NUMBER}p" "${VERSION_HISTORY_FILE}")
if [ -z "${SELECTED_VERSION}" ]; then
  echo "错误: 无效的版本编号"
  exit 1
fi

# 5. 解析版本信息
IMAGE_URI=$(echo "${SELECTED_VERSION}" | cut -d'|' -f2)
VERSION=$(echo "${SELECTED_VERSION}" | cut -d'|' -f1)
echo "选择的版本: ${VERSION}"
echo "镜像 URI: ${IMAGE_URI}"

# 6. 更新 kubeconfig
echo "更新 kubeconfig..."
aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${REGION}

# 7. 获取服务账户角色 ARN
echo "获取服务账户角色 ARN..."
ROLE_ARN=$(kubectl get serviceaccount ${SERVICE_ACCOUNT_NAME} -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')
if [ -z "${ROLE_ARN}" ]; then
  echo "错误: 无法获取服务账户角色 ARN，请确保已运行 init_eks.sh"
  exit 1
fi
echo "服务账户角色 ARN: ${ROLE_ARN}"

# 8. 替换部署文件中的变量
echo "更新部署文件..."
cp deployment.yaml deployment.yaml.bak
sed -i.bak "s|\${ECR_IMAGE_URI}|${IMAGE_URI}|g" deployment.yaml
sed -i.bak "s|\${SERVICE_ACCOUNT_ROLE_ARN}|${ROLE_ARN}|g" deployment.yaml

# 9. 部署应用
echo "部署应用到 EKS..."
kubectl apply -f deployment.yaml

# 10. 等待部署完成
echo "等待部署完成..."
kubectl rollout status deployment/kafka-client

echo "===== 部署完成 ====="
echo "已部署版本: ${VERSION}"
echo "您可以使用以下命令查看 Pod 日志："
echo "kubectl logs -f deployment/kafka-client"
