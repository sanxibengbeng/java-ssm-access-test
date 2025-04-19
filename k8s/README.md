# Kafka Client EKS 部署指南

本指南介绍如何将 Kafka 客户端应用程序部署到 Amazon EKS 集群，并配置 Pod 角色以授予 SSM 和 Secrets Manager 权限。

## 前提条件

- AWS CLI 已配置
- kubectl 已安装
- Docker 已安装
- Maven 已安装（用于构建 Java 应用）

## 部署流程

项目提供了一系列脚本来自动化部署流程：

### 1. 初始化 EKS 环境

使用 `init_eks.sh` 脚本创建和配置 EKS 环境：

```bash
./init_eks.sh
```

此脚本将：
- 检查并创建 EKS 集群（如果不存在）
- 更新 kubeconfig
- 创建 OIDC 提供商
- 创建服务账户和 IAM 角色（具有 SSM 和 Secrets Manager 权限）
- 创建 ECR 仓库（如果不存在）

### 2. 构建和推送 Docker 镜像

使用 `build_push.sh` 脚本构建应用并推送到 ECR：

```bash
./build_push.sh
```

此脚本将：
- 构建 Java 应用（使用 Maven）
- 登录到 ECR
- 生成版本号（基于时间戳）
- 构建 Docker 镜像（针对 linux/amd64 平台）
- 推送镜像到 ECR（同时更新 latest 标签）
- 记录版本信息到 `version_history` 文件

### 3. 部署应用到 EKS

使用 `deploy.sh` 脚本部署应用：

```bash
./deploy.sh
```

此脚本将：
- 显示可用版本列表
- 让您选择要部署的版本
- 更新 kubeconfig
- 获取服务账户角色 ARN
- 从模板创建部署文件并替换变量
- 部署应用到 EKS
- 等待部署完成

## 配置说明

在 `deployment.tpl.yaml` 中：

1. **ServiceAccount**: 配置了与 IAM 角色的关联
2. **ConfigMap**: 包含 Kafka 连接配置和 AWS 区域信息
3. **Deployment**: 定义了应用程序部署，包括:
   - 使用服务账户
   - 环境变量配置
   - 资源限制

## 其他脚本说明

- `update-iam-policy.sh`: 更新 IAM 策略
- `update-node-role.sh`: 更新节点角色
- `setup.sh`: 初始化设置脚本

## 验证部署

```bash
# 检查 Pod 状态
kubectl get pods

# 查看 Pod 日志
kubectl logs -f deployment/kafka-client
```

## 故障排除

- 如果 Pod 无法启动，检查日志: `kubectl logs <pod-name>`
- 验证服务账户权限: `kubectl describe serviceaccount kafka-client-sa`
- 检查 IAM 角色: `aws iam get-role --role-name <role-name>`
- 查看部署状态: `kubectl describe deployment kafka-client`
- 检查 ConfigMap 配置: `kubectl describe configmap kafka-config`
