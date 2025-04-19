# Kafka Client EKS 部署指南

本指南介绍如何将 Kafka 客户端应用程序部署到 Amazon EKS 集群，并配置 Pod 角色以授予 SSM 和 Secrets Manager 权限。

## 前提条件

- AWS CLI 已配置
- kubectl 已安装
- Docker 已安装
- 已有 EKS 集群或准备创建新集群
- Maven 已安装（用于构建 Java 应用）

## 部署步骤

### 1. 构建 Docker 镜像并推送到 ECR

```bash
# 创建 ECR 仓库
aws ecr create-repository --repository-name kafka-client

# 获取登录命令
aws ecr get-login-password | docker login --username AWS --password-stdin $(aws sts get-caller-identity --query Account --output text).dkr.ecr.$(aws configure get region).amazonaws.com

# 构建 Docker 镜像
docker build -t kafka-client .

# 标记镜像
docker tag kafka-client:latest $(aws sts get-caller-identity --query Account --output text).dkr.ecr.$(aws configure get region).amazonaws.com/kafka-client:latest

# 推送镜像到 ECR
docker push $(aws sts get-caller-identity --query Account --output text).dkr.ecr.$(aws configure get region).amazonaws.com/kafka-client:latest
```

### 2. 创建 EKS 集群（如果尚未创建）

```bash
eksctl create cluster --name kafka-client-cluster --region us-west-2 --nodegroup-name standard-workers --node-type t3.medium --nodes 2 --nodes-min 1 --nodes-max 3
```

### 3. 创建 IAM 角色和服务账户

```bash
# 创建 OIDC 提供商
eksctl utils associate-iam-oidc-provider --cluster kafka-client-cluster --approve

# 创建服务账户和 IAM 角色
eksctl create iamserviceaccount \
  --name kafka-client-sa \
  --namespace default \
  --cluster kafka-client-cluster \
  --attach-policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore \
  --attach-policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite \
  --approve
```

### 4. 更新部署文件

编辑 `deployment.yaml` 文件，替换以下变量：
- `${ECR_IMAGE_URI}`: 替换为您的 ECR 镜像 URI
- `${SERVICE_ACCOUNT_ROLE_ARN}`: 替换为服务账户角色 ARN

### 5. 部署应用

```bash
kubectl apply -f deployment.yaml
```

### 6. 验证部署

```bash
# 检查 Pod 状态
kubectl get pods

# 查看 Pod 日志
kubectl logs -f deployment/kafka-client
```

## 配置说明

在 `deployment.yaml` 中：

1. **ServiceAccount**: 配置了与 IAM 角色的关联
2. **ConfigMap**: 包含 Kafka 连接配置和 AWS 区域信息
3. **Deployment**: 定义了应用程序部署，包括:
   - 使用服务账户
   - 环境变量配置
   - 资源限制

## 故障排除

- 如果 Pod 无法启动，检查日志: `kubectl logs <pod-name>`
- 验证服务账户权限: `kubectl describe serviceaccount kafka-client-sa`
- 检查 IAM 角色: `aws iam get-role --role-name <role-name>`
