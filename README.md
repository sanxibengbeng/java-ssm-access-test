## 部署方案概述
我创建了以下文件：

1. Dockerfile - 用于构建 Java 应用的容器镜像
2. k8s/deployment.yaml - Kubernetes 部署清单，包含 ServiceAccount、ConfigMap 和 Deployment
3. k8s/setup.sh - 自动化部署脚本
4. k8s/README.md - 详细的部署指南

## 关键功能

1. Pod IAM 角色集成
   • 使用 IAM Roles for Service Accounts (IRSA) 为 Pod 提供 AWS 权限
   • 配置了 SSM 和 Secrets Manager 权限

2. 环境变量配置
   • 通过 ConfigMap 提供配置参数
   • 支持从环境变量读取配置

3. Java 代码优化
   • 更新了 Java 代码以从环境变量读取配置
   • 添加了长时间运行的循环以保持容器运行

4. Maven 构建优化
   • 添加了 maven-shade-plugin 以创建可执行 JAR

## 执行部署

要部署应用程序，请按照以下步骤操作：

1. 确保您已安装必要的工具
   • AWS CLI
   • kubectl
   • eksctl
   • Docker
   • Maven

2. 执行部署脚本
  bash
   cd /Users/yulongzh/projects/architect-generation/k8s
   ./setup.sh
   

这个脚本会自动执行以下操作：
• 构建 Java 应用
• 创建 ECR 仓库并推送 Docker 镜像
• 创建或使用现有的 EKS 集群
• 配置 IAM 角色和服务账户
• 部署应用到 EKS

## 验证部署

部署完成后，您可以使用以下命令验证部署：

bash
# 查看 Pod 状态
kubectl get pods

# 查看 Pod 日志
kubectl logs -f deployment/kafka-client


## 注意事项

1. 配置更新
   • 如需更改 MSK 连接信息，请更新 k8s/deployment.yaml 中的 ConfigMap

2. 安全最佳实践
   • 在生产环境中，应限制 IAM 策略范围，仅允许访问特定资源
   • 考虑使用 AWS Secrets Manager 存储敏感配置

3. 资源管理
   • 根据实际需求调整 Pod 的资源限制

这个解决方案遵循了 AWS 最佳实践，特别是使用 IRSA 来安全地授予 Pod 访问 AWS 服务的权限，而不是在容器中存储凭证。

您可以立即执行 ./setup.sh 脚本开始部署，或者根据您的具体需求修改配置参数。