import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as eks from 'aws-cdk-lib/aws-eks';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as ecr_assets from 'aws-cdk-lib/aws-ecr-assets';
import * as path from 'path';

export class KafkaClientEksStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Create a VPC for our EKS cluster
    const vpc = new ec2.Vpc(this, 'KafkaClientVpc', {
      maxAzs: 2,
      natGateways: 1,
    });

    // Create the EKS cluster
    const cluster = new eks.Cluster(this, 'KafkaClientCluster', {
      version: eks.KubernetesVersion.V1_26,
      vpc,
      defaultCapacity: 2,
      defaultCapacityInstance: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MEDIUM),
    });

    // Create a service account with SSM permissions
    const serviceAccount = cluster.addServiceAccount('kafka-client-sa', {
      name: 'kafka-client-sa',
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
    const dockerAsset = new ecr_assets.DockerImageAsset(this, 'KafkaClientImage', {
      directory: path.join(__dirname, '../../'), // Path to the project root
      file: 'Dockerfile', // Dockerfile in the project root
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
    const appLabel = { app: 'kafka-client' };
    
    const deployment = cluster.addManifest('KafkaClientDeployment', {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: {
        name: 'kafka-client',
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
                name: 'kafka-client',
                image: dockerAsset.imageUri,
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
