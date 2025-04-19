import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as eks from 'aws-cdk-lib/aws-eks';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import * as ecr_assets from 'aws-cdk-lib/aws-ecr-assets';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as path from 'path';

export class ArchitectGenerationEksStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Create a VPC for our EKS cluster
    const vpc = new ec2.Vpc(this, 'ArchitectGenerationVpc', {
      maxAzs: 2,
      natGateways: 1,
    });

    // Create an IAM role for the EKS cluster
    const clusterRole = new iam.Role(this, 'ClusterRole', {
      assumedBy: new iam.ServicePrincipal('eks.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEKSClusterPolicy'),
      ],
    });

    // Create the EKS cluster
    const cluster = new eks.Cluster(this, 'ArchitectGenerationCluster', {
      version: eks.KubernetesVersion.V1_26,
      vpc,
      defaultCapacity: 2,
      defaultCapacityInstance: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MEDIUM),
      clusterLogging: [
        eks.ClusterLoggingTypes.API,
        eks.ClusterLoggingTypes.AUDIT,
        eks.ClusterLoggingTypes.AUTHENTICATOR,
        eks.ClusterLoggingTypes.CONTROLLER_MANAGER,
        eks.ClusterLoggingTypes.SCHEDULER,
      ],
    });

    // Create a service account with SSM permissions
    const serviceAccount = cluster.addServiceAccount('architect-generation-sa', {
      name: 'architect-generation-sa',
      namespace: 'default',
    });

    // Add SSM permissions to the service account
    serviceAccount.role.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore')
    );
    
    // Add Secrets Manager permissions to the service account
    const secretsPolicy = new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'secretsmanager:GetSecretValue',
        'secretsmanager:DescribeSecret'
      ],
      resources: ['*'] // In production, restrict to specific secrets
    });
    
    serviceAccount.role.attachInlinePolicy(new iam.Policy(this, 'secrets-policy', {
      statements: [secretsPolicy]
    }));

    // Build Docker image from local directory
    const dockerAsset = new ecr_assets.DockerImageAsset(this, 'ArchitectGenerationImage', {
      directory: path.join(__dirname, '../../'), // Path to the project root
      file: 'Dockerfile', // Assuming Dockerfile is in the project root
    });

    // Create ConfigMap for application configuration
    const configMap = cluster.addManifest('KafkaConfigMap', {
      apiVersion: 'v1',
      kind: 'ConfigMap',
      metadata: {
        name: 'kafka-config',
        namespace: 'default'
      },
      data: {
        'bootstrap.servers': 'your-msk-bootstrap-broker-endpoints',
        'group.id': 'kafka-msk-client-group',
        'region': 'us-west-2',
        'secret.name': 'MSK-SCRAM-User-Secret'
      }
    });

    // Deploy the application to EKS
    const appLabel = { app: 'architect-generation' };
    
    const deployment = cluster.addManifest('ArchitectGenerationDeployment', {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: {
        name: 'architect-generation',
      },
      spec: {
        replicas: 2,
        selector: { matchLabels: appLabel },
        template: {
          metadata: { labels: appLabel },
          spec: {
            serviceAccountName: serviceAccount.serviceAccountName,
            containers: [
              {
                name: 'architect-generation',
                image: dockerAsset.imageUri,
                ports: [{ containerPort: 8080 }],
                env: [
                  {
                    name: 'BOOTSTRAP_SERVERS',
                    valueFrom: {
                      configMapKeyRef: {
                        name: 'kafka-config',
                        key: 'bootstrap.servers'
                      }
                    }
                  },
                  {
                    name: 'GROUP_ID',
                    valueFrom: {
                      configMapKeyRef: {
                        name: 'kafka-config',
                        key: 'group.id'
                      }
                    }
                  },
                  {
                    name: 'AWS_REGION',
                    valueFrom: {
                      configMapKeyRef: {
                        name: 'kafka-config',
                        key: 'region'
                      }
                    }
                  },
                  {
                    name: 'SECRET_NAME',
                    valueFrom: {
                      configMapKeyRef: {
                        name: 'kafka-config',
                        key: 'secret.name'
                      }
                    }
                  }
                ],
                resources: {
                  limits: {
                    cpu: '500m',
                    memory: '512Mi',
                  },
                  requests: {
                    cpu: '250m',
                    memory: '256Mi',
                  },
                },
              },
            ],
          },
        },
      },
    });

    // Create a service to expose the application
    const service = cluster.addManifest('ArchitectGenerationService', {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: {
        name: 'architect-generation-service',
      },
      spec: {
        selector: appLabel,
        ports: [
          {
            port: 80,
            targetPort: 8080,
          },
        ],
        type: 'LoadBalancer',
      },
    });

    // Make sure the service is deployed after the deployment
    service.node.addDependency(deployment);

    // Output the EKS cluster name
    new cdk.CfnOutput(this, 'ClusterName', {
      value: cluster.clusterName,
    });

    // Output the service account role ARN
    new cdk.CfnOutput(this, 'ServiceAccountRoleArn', {
      value: serviceAccount.role.roleArn,
    });
  }
}
