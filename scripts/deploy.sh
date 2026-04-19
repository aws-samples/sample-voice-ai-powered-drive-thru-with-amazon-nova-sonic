#!/bin/bash
set -e

# ============================================
# Guidance for Drive Thru Voice AI using Amazon Bedrock
# User-Facing Deploy Script
# ============================================

# ============================================
# CONFIGURATION
# ============================================
AWS_REGION="${AWS_REGION:-us-east-1}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
INFRA_STACK_NAME="nova-sonic-infra-${ENVIRONMENT}-$(date +%s)"
APP_STACK_NAME="nova-sonic-app-${ENVIRONMENT}-$(date +%s)"

# ============================================
# PLATFORM DETECTION
# ============================================
detect_platform() {
    case "$(uname -s)" in
        Darwin*)  PLATFORM="macos" ;;
        Linux*)   PLATFORM="linux" ;;
        MINGW*|MSYS*|CYGWIN*) PLATFORM="windows" ;;
        *)        PLATFORM="unknown" ;;
    esac
    echo "Detected platform: $PLATFORM"
}

# ============================================
# PREREQUISITE CHECKS
# ============================================
check_prerequisites() {
    echo "============================================"
    echo "Checking prerequisites..."
    echo "============================================"

    command -v aws >/dev/null 2>&1 || { echo "ERROR: AWS CLI is required. Install: https://aws.amazon.com/cli/"; exit 1; }
    echo "  ✓ AWS CLI found: $(aws --version 2>&1 | head -1)"

    # Verify AWS credentials
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || {
        echo "ERROR: AWS credentials not configured. Run 'aws configure' or set environment variables."
        exit 1
    }
    echo "  ✓ AWS credentials valid (Account: $ACCOUNT_ID)"
    echo "  ✓ Region: $AWS_REGION"
}

# ============================================
# USER INPUT
# ============================================
get_user_input() {
    echo ""
    echo "============================================"
    echo "Configuration"
    echo "============================================"

    # Prompt for email
    read -p "Enter a valid email address for the initial user account: " USER_EMAIL
    if [[ -z "$USER_EMAIL" ]]; then
        echo "ERROR: Email address is required."
        exit 1
    fi
    # Basic email validation
    if [[ ! "$USER_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        echo "ERROR: Invalid email address format."
        exit 1
    fi
    echo "  ✓ Email: $USER_EMAIL"

    # Confirm region
    read -p "Deploy to region $AWS_REGION? (y/n, default: y): " CONFIRM_REGION
    if [[ "$CONFIRM_REGION" == "n" || "$CONFIRM_REGION" == "N" ]]; then
        read -p "Enter AWS Region (e.g., us-east-1, us-west-2): " AWS_REGION
    fi
    echo "  ✓ Region: $AWS_REGION"
}

# ============================================
# DEPLOY INFRASTRUCTURE STACK
# ============================================
deploy_infrastructure() {
    echo ""
    echo "============================================"
    echo "Step 1: Deploying Infrastructure Stack"
    echo "============================================"
    echo "Stack name: $INFRA_STACK_NAME"

    # Upload template to S3 (CloudFormation requires S3 for large templates)
    DEPLOY_BUCKET="cfn-deploy-${ACCOUNT_ID}-${AWS_REGION}"
    echo "Creating deployment bucket: $DEPLOY_BUCKET"
    aws s3 mb "s3://${DEPLOY_BUCKET}" --region "$AWS_REGION" 2>/dev/null || true

    echo "Uploading infrastructure template..."
    aws s3 cp nova-sonic-infrastructure-drivethru.yaml "s3://${DEPLOY_BUCKET}/nova-sonic-infrastructure-drivethru.yaml" --region "$AWS_REGION"

    echo "Creating CloudFormation stack..."
    aws cloudformation create-stack \
        --stack-name "$INFRA_STACK_NAME" \
        --template-url "https://${DEPLOY_BUCKET}.s3.${AWS_REGION}.amazonaws.com/nova-sonic-infrastructure-drivethru.yaml" \
        --parameters \
            ParameterKey=Environment,ParameterValue="$ENVIRONMENT" \
            ParameterKey=UserEmail,ParameterValue="$USER_EMAIL" \
        --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
        --region "$AWS_REGION"

    echo "Waiting for infrastructure stack to complete (this may take 5-10 minutes)..."
    aws cloudformation wait stack-create-complete \
        --stack-name "$INFRA_STACK_NAME" \
        --region "$AWS_REGION"

    echo "  ✓ Infrastructure stack deployed successfully"

    # Capture outputs
    echo ""
    echo "Capturing stack outputs..."
    STACK_OUTPUTS=$(aws cloudformation describe-stacks \
        --stack-name "$INFRA_STACK_NAME" \
        --query "Stacks[0].Outputs" \
        --output json \
        --region "$AWS_REGION")

    echo "$STACK_OUTPUTS" | python3 -c "
import json, sys
outputs = json.load(sys.stdin)
for o in outputs:
    print(f\"  {o['OutputKey']}: {o['OutputValue']}\")
"
}

# ============================================
# DEPLOY APPLICATION STACK
# ============================================
deploy_application() {
    echo ""
    echo "============================================"
    echo "Step 2: Deploying Application Stack"
    echo "============================================"
    echo "Stack name: $APP_STACK_NAME"

    DEPLOY_BUCKET="cfn-deploy-${ACCOUNT_ID}-${AWS_REGION}"

    echo "Uploading application template..."
    aws s3 cp nova-sonic-application-drivethru.yaml "s3://${DEPLOY_BUCKET}/nova-sonic-application-drivethru.yaml" --region "$AWS_REGION"

    echo "Creating CloudFormation stack..."
    aws cloudformation create-stack \
        --stack-name "$APP_STACK_NAME" \
        --template-url "https://${DEPLOY_BUCKET}.s3.${AWS_REGION}.amazonaws.com/nova-sonic-application-drivethru.yaml" \
        --parameters \
            ParameterKey=InfrastructureStackName,ParameterValue="$INFRA_STACK_NAME" \
        --capabilities CAPABILITY_IAM \
        --region "$AWS_REGION"

    echo "Waiting for application stack to complete (this may take 10-15 minutes for AI image generation)..."
    aws cloudformation wait stack-create-complete \
        --stack-name "$APP_STACK_NAME" \
        --region "$AWS_REGION"

    echo "  ✓ Application stack deployed successfully"
}

# ============================================
# VALIDATION
# ============================================
validate_deployment() {
    echo ""
    echo "============================================"
    echo "Step 3: Validating Deployment"
    echo "============================================"

    # Check infrastructure stack
    INFRA_STATUS=$(aws cloudformation describe-stacks \
        --stack-name "$INFRA_STACK_NAME" \
        --query "Stacks[0].StackStatus" \
        --output text \
        --region "$AWS_REGION")
    echo "  Infrastructure stack status: $INFRA_STATUS"

    # Check application stack
    APP_STATUS=$(aws cloudformation describe-stacks \
        --stack-name "$APP_STACK_NAME" \
        --query "Stacks[0].StackStatus" \
        --output text \
        --region "$AWS_REGION")
    echo "  Application stack status: $APP_STATUS"

    if [[ "$INFRA_STATUS" == "CREATE_COMPLETE" && "$APP_STATUS" == "CREATE_COMPLETE" ]]; then
        echo "  ✓ Both stacks deployed successfully"
    else
        echo "  ✗ Deployment validation failed. Check the CloudFormation console for details."
        exit 1
    fi
}

# ============================================
# SUMMARY
# ============================================
print_summary() {
    echo ""
    echo "============================================"
    echo "Deployment Complete!"
    echo "============================================"
    echo ""
    echo "Infrastructure Stack: $INFRA_STACK_NAME"
    echo "Application Stack:    $APP_STACK_NAME"
    echo "Region:               $AWS_REGION"
    echo ""
    echo "Next steps:"
    echo "  1. Check your email ($USER_EMAIL) for the temporary password"
    echo "  2. Download NovaSonic-FrontEnd.zip from the GitHub repository"
    echo "  3. Deploy it to AWS Amplify (manual deploy)"
    echo "  4. Configure the Amplify app using the stack outputs below"
    echo "  5. Sign in with username 'appuser' and the temporary password"
    echo ""
    echo "Configuration values for Amplify:"
    echo "  UserPoolId:       $(aws cloudformation describe-stacks --stack-name $INFRA_STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue" --output text --region $AWS_REGION)"
    echo "  UserPoolClientId: $(aws cloudformation describe-stacks --stack-name $INFRA_STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='UserPoolClientId'].OutputValue" --output text --region $AWS_REGION)"
    echo "  IdentityPoolId:   $(aws cloudformation describe-stacks --stack-name $INFRA_STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='IdentityPoolId'].OutputValue" --output text --region $AWS_REGION)"
    echo "  menuApiUrl:       $(aws cloudformation describe-stacks --stack-name $INFRA_STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='menuApiUrl'].OutputValue" --output text --region $AWS_REGION)"
    echo "  cartApiUrl:       $(aws cloudformation describe-stacks --stack-name $INFRA_STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='cartApiUrl'].OutputValue" --output text --region $AWS_REGION)"
    echo "  orderApiUrl:      $(aws cloudformation describe-stacks --stack-name $INFRA_STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='orderApiUrl'].OutputValue" --output text --region $AWS_REGION)"
    echo "  loyaltyApiUrl:    $(aws cloudformation describe-stacks --stack-name $INFRA_STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='loyaltyApiUrl'].OutputValue" --output text --region $AWS_REGION)"
    echo "  chatApiUrl:       $(aws cloudformation describe-stacks --stack-name $INFRA_STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='chatApiUrl'].OutputValue" --output text --region $AWS_REGION)"
    echo ""
    echo "To view stack outputs:"
    echo "  aws cloudformation describe-stacks --stack-name $INFRA_STACK_NAME --query 'Stacks[0].Outputs' --output table --region $AWS_REGION"
    echo ""
    echo "============================================"
    echo "Cleanup commands:"
    echo "============================================"
    echo "  aws cloudformation delete-stack --stack-name $APP_STACK_NAME --region $AWS_REGION"
    echo "  aws cloudformation wait stack-delete-complete --stack-name $APP_STACK_NAME --region $AWS_REGION"
    echo "  aws cloudformation delete-stack --stack-name $INFRA_STACK_NAME --region $AWS_REGION"
    echo "  aws cloudformation wait stack-delete-complete --stack-name $INFRA_STACK_NAME --region $AWS_REGION"
    echo "  aws s3 rb s3://cfn-deploy-${ACCOUNT_ID}-${AWS_REGION} --force"
}

# ============================================
# MAIN
# ============================================
echo "============================================"
echo "Guidance for Drive Thru Voice AI"
echo "using Amazon Bedrock — Deployment Script"
echo "============================================"
echo ""

detect_platform
check_prerequisites
get_user_input
deploy_infrastructure
deploy_application
validate_deployment
print_summary
