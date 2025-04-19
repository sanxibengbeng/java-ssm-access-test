# Architect Generation EKS Deployment

This CDK project deploys the Architect Generation Java application to an Amazon EKS cluster with SSM permissions.

## Prerequisites

- AWS CLI configured with appropriate credentials
- Node.js and npm installed
- Docker installed and running
- Maven installed (for local testing)

## Project Structure

- `lib/architect-generation-eks-stack.ts`: Main CDK stack that creates the EKS cluster and deploys the application
- `bin/cdk-deployment.ts`: CDK app entry point
- `../Dockerfile`: Docker file to build the Java application container

## Deployment Steps

1. Install dependencies:
   ```
   npm install
   ```

2. Build the CDK project:
   ```
   npm run build
   ```

3. Deploy the stack:
   ```
   cdk deploy
   ```

4. To destroy the stack when no longer needed:
   ```
   cdk destroy
   ```

## Features

- Creates a new VPC for the EKS cluster
- Deploys an EKS cluster with appropriate IAM roles
- Creates a Kubernetes service account with SSM permissions
- Builds a Docker image from the Java application
- Deploys the application to the EKS cluster
- Exposes the application via a LoadBalancer service

## IAM Permissions

The application pods use IAM Roles for Service Accounts (IRSA) to securely access AWS SSM services without storing credentials in the container.
