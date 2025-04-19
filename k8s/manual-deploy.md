# 手动部署 Kafka 客户端到 EKS

如果自动化脚本遇到问题，您可以按照以下步骤手动部署应用程序。

## 1. 构建 Java 应用

```bash
cd /Users/yulongzh/projects/architect-generation
mvn clean package
```

## 2. 创建 ECR 仓库

```bash
# 设置变量
REGION="us-west-2"  # 根据需要修改
ECR_REPO_NAME="kafka-client"

# 创建 ECR 仓库
aws ecr create-repository --repository-name ${ECR_REPO_NAME} --region ${REGION}
```

## 3. 构建并推送 Docker 镜像

```bash
# 获取账户 ID 和 ECR URI
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

# 登录到 ECR
aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ECR_URI}

# 构建 Docker 镜像
docker build -t ${ECR_REPO_NAME}:latest .

# 标记镜像
docker tag ${ECR_REPO_NAME}:latest ${ECR_URI}/${ECR_REPO_NAME}:latest

# 推送镜像到 ECR
docker push ${ECR_URI}/${ECR_REPO_NAME}:latest
```

## 4. 创建 EKS 集群

```bash
CLUSTER_NAME="kafka-client-cluster"

# 创建 EKS 集群
eksctl create cluster \
  --name ${CLUSTER_NAME} \
  --region ${REGION} \
  --nodegroup-name standard-workers \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 3

# 更新 kubeconfig
aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${REGION}
```

## 5. 创建 IAM 角色和服务账户

```bash
SERVICE_ACCOUNT_NAME="kafka-client-sa"

# 创建 OIDC 提供商
eksctl utils associate-iam-oidc-provider --cluster ${CLUSTER_NAME} --approve --region ${REGION}

# 创建服务账户和 IAM 角色
eksctl create iamserviceaccount \
  --name ${SERVICE_ACCOUNT_NAME} \
  --namespace default \
  --cluster ${CLUSTER_NAME} \
  --attach-policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore \
  --attach-policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite \
  --approve \
  --region ${REGION}
```

## 6. 准备部署文件

```bash
cd /Users/yulongzh/projects/architect-generation/k8s

# 获取服务账户角色 ARN
ROLE_ARN=$(kubectl get serviceaccount ${SERVICE_ACCOUNT_NAME} -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')

# 更新部署文件
IMAGE_URI="${ECR_URI}/${ECR_REPO_NAME}:latest"
cp deployment.yaml deployment-updated.yaml
sed -i.bak "s|\${ECR_IMAGE_URI}|${IMAGE_URI}|g" deployment-updated.yaml
sed -i.bak "s|\${SERVICE_ACCOUNT_ROLE_ARN}|${ROLE_ARN}|g" deployment-updated.yaml
```

## 7. 部署应用

```bash
kubectl apply -f deployment-updated.yaml

# 等待部署完成
kubectl rollout status deployment/kafka-client
```

## 8. 验证部署

```bash
# 查看 Pod 状态
kubectl get pods

# 查看 Pod 日志
kubectl logs -f deployment/kafka-client
```

## 9. 清理资源（可选）

```bash
# 删除部署
kubectl delete -f deployment-updated.yaml

# 删除 EKS 集群
eksctl delete cluster --name ${CLUSTER_NAME} --region ${REGION}

# 删除 ECR 仓库
aws ecr delete-repository --repository-name ${ECR_REPO_NAME} --force --region ${REGION}
```
