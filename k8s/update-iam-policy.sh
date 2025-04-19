#!/bin/bash
set -e

# 配置变量
REGION="us-east-1"
CLUSTER_NAME="kafka-client-cluster"
SERVICE_ACCOUNT_NAME="kafka-client-sa"

echo "===== 更新 IAM 策略 ====="

# 1. 获取服务账户角色 ARN
echo "获取服务账户角色 ARN..."
ROLE_ARN=$(kubectl get serviceaccount ${SERVICE_ACCOUNT_NAME} -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')
echo "服务账户角色 ARN: ${ROLE_ARN}"

# 2. 从角色 ARN 中提取角色名称
ROLE_NAME=$(echo $ROLE_ARN | cut -d'/' -f2)
echo "角色名称: ${ROLE_NAME}"

# 3. 创建策略文档
echo "创建策略文档..."
cat > secretsmanager-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret"
            ],
            "Resource": "arn:aws:secretsmanager:${REGION}:*:secret:MSK-SCRAM-User-Secret*"
        }
    ]
}
EOF

# 4. 创建 IAM 策略
echo "创建 IAM 策略..."
POLICY_ARN=$(aws iam create-policy --policy-name MSKSecretAccessPolicy --policy-document file://secretsmanager-policy.json --query 'Policy.Arn' --output text)
echo "策略 ARN: ${POLICY_ARN}"

# 5. 将策略附加到角色
echo "将策略附加到角色..."
aws iam attach-role-policy --role-name ${ROLE_NAME} --policy-arn ${POLICY_ARN}

echo "===== IAM 策略更新完成 ====="
