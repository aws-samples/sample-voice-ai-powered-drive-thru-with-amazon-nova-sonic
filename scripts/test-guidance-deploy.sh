#!/bin/bash
set -e

# ============================================
# Guidance for Drive Thru Voice AI using Amazon Bedrock
# Internal CodeBuild Test Deploy Script
# Target: aws/codebuild/amazonlinux-x86_64-standard:5.0
# ============================================

# ============================================
# CONFIGURATION
# ============================================
AWS_REGION="us-east-1"
ENVIRONMENT="dev"
TIMESTAMP=$(date +%s)
INFRA_STACK_NAME="nova-sonic-infra-test-${TIMESTAMP}"
APP_STACK_NAME="nova-sonic-app-test-${TIMESTAMP}"
EMAIL_ADDRESS="wwso-guidance-deployments-ignore@amazon.com"

# ============================================
# ENVIRONMENT SETUP
# ============================================
export AWS_REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "============================================"
echo "Test Deployment — Drive Thru Voice AI"
echo "============================================"
echo "Account ID: $ACCOUNT_ID"
echo "Region: $AWS_REGION"
echo "Infrastructure Stack: $INFRA_STACK_NAME"
echo "Application Stack: $APP_STACK_NAME"
echo "Timestamp: $TIMESTAMP"
echo "============================================"

# ============================================
# INSTALL DEPENDENCIES
# ============================================
echo ""
echo "Step 1: Installing dependencies..."
echo "--------------------------------------------"
# Python 3 and AWS CLI are pre-installed in CodeBuild AL2023
echo "  Python: $(python3 --version)"
echo "  AWS CLI: $(aws --version 2>&1 | head -1)"

# ============================================
# CREATE DEPLOYMENT BUCKET
# ============================================
echo ""
echo "Step 2: Creating deployment S3 bucket..."
echo "--------------------------------------------"
DEPLOY_BUCKET="cfn-test-deploy-${ACCOUNT_ID}-${TIMESTAMP}"
aws s3 mb "s3://${DEPLOY_BUCKET}" --region "$AWS_REGION"
echo "  ✓ Bucket created: $DEPLOY_BUCKET"

# ============================================
# DEPLOY INFRASTRUCTURE STACK
# ============================================
echo ""
echo "Step 3: Deploying infrastructure stack..."
echo "--------------------------------------------"

aws s3 cp nova-sonic-infrastructure-drivethru.yaml "s3://${DEPLOY_BUCKET}/nova-sonic-infrastructure-drivethru.yaml" --region "$AWS_REGION"
echo "  ✓ Template uploaded to S3"

aws cloudformation create-stack \
    --stack-name "$INFRA_STACK_NAME" \
    --template-url "https://${DEPLOY_BUCKET}.s3.${AWS_REGION}.amazonaws.com/nova-sonic-infrastructure-drivethru.yaml" \
    --parameters \
        ParameterKey=Environment,ParameterValue="$ENVIRONMENT" \
        ParameterKey=UserEmail,ParameterValue="$EMAIL_ADDRESS" \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --region "$AWS_REGION"
echo "  ✓ Stack creation initiated"

echo "  Waiting for infrastructure stack (5-10 minutes)..."
aws cloudformation wait stack-create-complete \
    --stack-name "$INFRA_STACK_NAME" \
    --region "$AWS_REGION"
echo "  ✓ Infrastructure stack deployed"

# Capture outputs
echo "  Capturing stack outputs..."
aws cloudformation describe-stacks \
    --stack-name "$INFRA_STACK_NAME" \
    --query "Stacks[0].Outputs" \
    --output table \
    --region "$AWS_REGION"

# ============================================
# DEPLOY APPLICATION STACK
# ============================================
echo ""
echo "Step 4: Deploying application stack..."
echo "--------------------------------------------"

aws s3 cp nova-sonic-application-drivethru.yaml "s3://${DEPLOY_BUCKET}/nova-sonic-application-drivethru.yaml" --region "$AWS_REGION"
echo "  ✓ Template uploaded to S3"

aws cloudformation create-stack \
    --stack-name "$APP_STACK_NAME" \
    --template-url "https://${DEPLOY_BUCKET}.s3.${AWS_REGION}.amazonaws.com/nova-sonic-application-drivethru.yaml" \
    --parameters \
        ParameterKey=InfrastructureStackName,ParameterValue="$INFRA_STACK_NAME" \
    --capabilities CAPABILITY_IAM \
    --region "$AWS_REGION"
echo "  ✓ Stack creation initiated"

echo "  Waiting for application stack (10-15 minutes for AI image generation)..."
aws cloudformation wait stack-create-complete \
    --stack-name "$APP_STACK_NAME" \
    --region "$AWS_REGION"
echo "  ✓ Application stack deployed"

# ============================================
# VALIDATION
# ============================================
echo ""
echo "Step 5: Validating deployment..."
echo "--------------------------------------------"

INFRA_STATUS=$(aws cloudformation describe-stacks \
    --stack-name "$INFRA_STACK_NAME" \
    --query "Stacks[0].StackStatus" \
    --output text \
    --region "$AWS_REGION")
echo "  Infrastructure stack: $INFRA_STATUS"

APP_STATUS=$(aws cloudformation describe-stacks \
    --stack-name "$APP_STACK_NAME" \
    --query "Stacks[0].StackStatus" \
    --output text \
    --region "$AWS_REGION")
echo "  Application stack: $APP_STATUS"

# Verify DynamoDB menu items
MENU_TABLE=$(aws cloudformation describe-stacks \
    --stack-name "$INFRA_STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='MenuTable'].OutputValue" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

if [[ -n "$MENU_TABLE" && "$MENU_TABLE" != "None" ]]; then
    MENU_COUNT=$(aws dynamodb scan \
        --table-name "$MENU_TABLE" \
        --select COUNT \
        --query "Count" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "0")
    echo "  Menu items in DynamoDB: $MENU_COUNT"
fi

if [[ "$INFRA_STATUS" == "CREATE_COMPLETE" && "$APP_STATUS" == "CREATE_COMPLETE" ]]; then
    echo "  ✓ Deployment validation PASSED"
else
    echo "  ✗ Deployment validation FAILED"
    # Continue to cleanup even on failure
fi

# ============================================
# CLEANUP
# ============================================
echo ""
echo "Step 6: Cleaning up resources..."
echo "--------------------------------------------"

echo "  Deleting application stack..."
aws cloudformation delete-stack --stack-name "$APP_STACK_NAME" --region "$AWS_REGION"
aws cloudformation wait stack-delete-complete --stack-name "$APP_STACK_NAME" --region "$AWS_REGION"
echo "  ✓ Application stack deleted"

echo "  Deleting infrastructure stack..."
aws cloudformation delete-stack --stack-name "$INFRA_STACK_NAME" --region "$AWS_REGION"
aws cloudformation wait stack-delete-complete --stack-name "$INFRA_STACK_NAME" --region "$AWS_REGION"
echo "  ✓ Infrastructure stack deleted"

echo "  Deleting deployment bucket..."
aws s3 rb "s3://${DEPLOY_BUCKET}" --force --region "$AWS_REGION"
echo "  ✓ Deployment bucket deleted"

echo ""
echo "============================================"
echo "Test deployment completed successfully!"
echo "============================================"
