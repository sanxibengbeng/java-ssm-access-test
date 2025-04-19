#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { ArchitectGenerationEksStack } from '../lib/architect-generation-eks-stack';

const app = new cdk.App();
new ArchitectGenerationEksStack(app, 'ArchitectGenerationEksStack', {
  env: { 
    account: process.env.CDK_DEFAULT_ACCOUNT, 
    region: process.env.CDK_DEFAULT_REGION 
  },
});
