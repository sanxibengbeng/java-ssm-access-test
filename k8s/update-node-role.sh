#!/bin/bash
set -e

# 配置变量
REGION="us-east-1"
CLUSTER_NAME="kafka-client-cluster"

echo "===== 更新节点角色策略 ====="

# 1. 获取节点角色名称
echo "获取节点角色名称..."
NODE_ROLE_NAME=$(aws eks describe-nodegroup --cluster-name ${CLUSTER_NAME} --nodegroup-name standard-workers --region ${REGION} --query 'nodegroup.nodeRole' --output text | cut -d'/' -f2)
echo "节点角色名称: ${NODE_ROLE_NAME}"

# 2. 创建策略文档
echo "创建策略文档..."
cat > node-secretsmanager-policy.json <<EOF
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

# 3. 创建 IAM 策略
echo "创建 IAM 策略..."
POLICY_ARN=$(aws iam create-policy --policy-name NodeMSKSecretAccessPolicy --policy-document file://node-secretsmanager-policy.json --query 'Policy.Arn' --output text)
echo "策略 ARN: ${POLICY_ARN}"

# 4. 将策略附加到节点角色
echo "将策略附加到节点角色..."
aws iam attach-role-policy --role-name ${NODE_ROLE_NAME} --policy-arn ${POLICY_ARN}

echo "===== 节点角色策略更新完成 ====="
