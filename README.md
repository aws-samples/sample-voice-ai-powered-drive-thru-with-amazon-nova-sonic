# Guidance for Drive Thru Voice AI using Amazon Bedrock

> **Note:** If you are following the step-by-step walkthrough from the [AWS Blog Post](https://aws.amazon.com/blogs/machine-learning/voice-ai-powered-drive-thru-ordering-with-amazon-nova-sonic-and-dynamic-menu-displays/), the blog guides you through deploying each CloudFormation template individually via the console. This README provides both an automated deployment script and equivalent manual steps for Guidance submission. The underlying infrastructure and application are the same.

## Table of Contents

1. [Overview](#overview)
    - [Cost](#cost)
2. [Prerequisites](#prerequisites)
    - [Operating System](#operating-system)
    - [AWS Account Requirements](#aws-account-requirements)
    - [Supported Regions](#supported-regions)
3. [Automated Deployment](#automated-deployment)
4. [Manual Deployment](#manual-deployment)
5. [Deployment Validation](#deployment-validation)
6. [Running the Guidance](#running-the-guidance)
7. [Next Steps](#next-steps)
8. [Cleanup](#cleanup)
9. [FAQ, Known Issues, Additional Considerations, and Limitations](#faq-known-issues-additional-considerations-and-limitations)
10. [Notices](#notices)
11. [Authors](#authors)

## Overview

This Guidance demonstrates how to build an intelligent drive-thru ordering system for quick-service restaurants (QSRs) using **Amazon Nova 2 Sonic** and AWS serverless services. The system combines real-time voice AI with an interactive digital menu board to deliver natural, human-like ordering experiences that address common operational challenges including staffing constraints, order accuracy issues, and peak-hour bottlenecks.

**Amazon Nova 2 Sonic** is a foundation model (FM) within the **Amazon Nova** family, available through **Amazon Bedrock**. It processes streaming speech with robustness to background noise, adapts responses to user tone and sentiment, and supports bidirectional streaming with low perceived latency. The system establishes direct WebSocket connections from the browser to Nova 2 Sonic using the AWS SDK (`client-bedrock-runtime` v3.842.0), eliminating the need for a backend relay server.

The architecture integrates the following AWS services:

- **Amazon Cognito** — User authentication with role-based access control
- **AWS Amplify** — Hosts the React-based digital menu board frontend
- **Amazon API Gateway** — REST API with Cognito authorization and direct **Amazon DynamoDB** integration
- **Amazon DynamoDB** — Stores menu items, loyalty data, cart sessions, orders, and chat history across five tables
- **AWS Lambda** — Populates menu data and generates AI images using **Stability AI Stable Image Core** model via Amazon Bedrock
- **Amazon Simple Storage Service (Amazon S3)** — Stores AI-generated menu item images
- **Amazon CloudFront** — Global content delivery for menu images with **AWS WAF** protection
- **AWS Key Management Service (AWS KMS)** — Encrypts DynamoDB tables and Lambda environment variables
- **Amazon Simple Queue Service (Amazon SQS)** — Dead letter queue for Lambda error handling
- **AWS Identity and Access Management (IAM)** — Least-privilege roles for all service interactions

The following architecture diagram illustrates how these services interconnect to enable natural conversations between customers and the digital menu board, orchestrating the entire customer journey from drive-thru entry to order completion.

![Architecture Diagram](assets/images/architecture-diagram.png)

1. The customer approaches the drive-thru and the digital menu board loads via **AWS Amplify**, authenticating through **Amazon Cognito**.
2. **Amazon Cognito** issues temporary AWS credentials mapped to an **IAM** role, granting access to **Amazon Bedrock** and **Amazon API Gateway** endpoints.
3. The frontend establishes a direct WebSocket connection to **Amazon Nova 2 Sonic** through **Amazon Bedrock** for real-time speech-to-speech processing.
4. Nova 2 Sonic processes the customer's voice input, recognizes intent, and calls tool functions (e.g., `getMenuItems`, `showCategory`) to retrieve menu data.
5. **Amazon API Gateway** routes tool function requests to **Amazon DynamoDB** tables (Menu, Cart, Order, Loyalty, Chat) using direct service integration.
6. **Amazon CloudFront** delivers AI-generated menu images from **Amazon S3**, protected by **AWS WAF** rules.
7. Nova 2 Sonic generates a contextual audio response and triggers UI updates on the digital menu board to highlight relevant items.
8. The ordering flow continues through cart management, order placement, and loyalty point tracking until the customer completes the transaction.

### Cost

You are responsible for the cost of the AWS services used while running this Guidance. As of April 2026, the cost for running this Guidance with the default settings in the US East (N. Virginia) Region is approximately **$131.00 per month** for processing approximately 10,000 drive-thru orders.

The following table provides a sample cost breakdown for deploying this Guidance with the default parameters in the US East (N. Virginia) Region for one month.

| AWS Service | Dimensions | Cost [USD] |
| --- | --- | --- |
| Amazon Cognito | 1,000 active users per month (no advanced security) | $0.00 |
| Amazon API Gateway | 50,000 REST API calls per month | $0.18 |
| Amazon DynamoDB | 5 tables, on-demand capacity, 10 GB storage, 50,000 read/write units | $7.50 |
| AWS Lambda | 10,000 invocations, 1024 MB memory, 30s avg duration (menu population) | $5.01 |
| Amazon S3 | 1 GB storage, 50,000 GET requests | $0.03 |
| Amazon CloudFront | 50 GB data transfer, 100,000 requests | $5.85 |
| AWS WAF | 1 Web ACL, 3 rules, 100,000 requests | $7.00 |
| Amazon Bedrock — Nova 2 Sonic | 10,000 voice sessions, ~30s avg (input + output audio) | $83.00 |
| Amazon Bedrock — Image Generation | 25 images generated during initial deployment | $2.50 |
| AWS KMS | 1 customer-managed key, 50,000 requests | $1.03 |
| Amazon SQS | 1,000 messages (dead letter queue) | $0.00 |
| AWS Amplify Hosting | 1 app, 15 GB served | $18.90 |
| **Total estimated cost** | | **~$131.00/month** |

We recommend creating a [Budget](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html) through [AWS Cost Explorer](https://aws.amazon.com/aws-cost-management/aws-cost-explorer/) to help manage costs. Prices are subject to change. For full details, refer to the pricing webpage for each AWS service used in this Guidance.

## Prerequisites

### Operating System

These deployment instructions are optimized to best work on **Amazon Linux 2023**. Deployment on macOS, Windows, or other Linux distributions may require additional steps.

- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) v2.x — configured with appropriate credentials
- [AWS account](https://signin.aws.amazon.com/signin) with administrator access or sufficient permissions to create the resources listed in this Guidance

### AWS Account Requirements

Before deploying this Guidance, verify the following:

1. **Amazon Bedrock model access** — Enable access to the following foundation models in the Amazon Bedrock console in the same Region where you deploy this Guidance:
   - Amazon Nova 2 Sonic (`amazon.nova-2-sonic-v1:0`)
   - Stability AI Stable Image Core (`stability.stable-image-core-v1:1`)

2. **Service quotas** — Verify your account has sufficient quotas for:
   - AWS Lambda concurrent executions (default: 1,000)
   - Amazon DynamoDB tables (default: 2,500)
   - Amazon CloudFront distributions (default: 200)

3. **AWS WAF** — The deployment creates a WAF Web ACL with `CLOUDFRONT` scope. This requires the CloudFormation stack to be deployed in `us-east-1` or in a Region that supports CloudFront-scoped WAF resources.

### Supported Regions

Deploy this Guidance in an AWS Region where Amazon Bedrock supports both Amazon Nova 2 Sonic and the Stability AI image generation model. As of April 2026, supported Regions include:

- US East (N. Virginia) — `us-east-1`
- US West (Oregon) — `us-west-2`

Verify current Region availability in the [Amazon Bedrock supported Regions documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/models-regions.html).

## Automated Deployment

For automated deployment, a cross-platform deploy script (`scripts/deploy.sh`) is available. This script automates all deployment steps including resource creation, configuration, and validation.

```bash
# Clone the repository
git clone https://github.com/aws-samples/sample-voice-ai-powered-drive-thru-with-amazon-nova-sonic.git
cd sample-voice-ai-powered-drive-thru-with-amazon-nova-sonic

# Make the script executable and run it
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

**What the script does:**
- Detects your operating system (macOS, Linux, Windows WSL)
- Verifies AWS CLI is installed and credentials are configured
- Prompts for your email address and preferred AWS Region
- Uploads CloudFormation templates to S3 and deploys both stacks
- Validates the deployment and displays stack outputs
- Provides cleanup commands at the end

**Environment:**
- Designed for macOS, Linux, and Windows (WSL/Git Bash)
- Requires AWS CLI v2.x configured with appropriate credentials
- Amazon Bedrock model access must be enabled before running

**Note:** The deploy script automates the two CloudFormation stack deployments. After the script completes, deploy the Amplify frontend manually — see [Step 5 in Manual Deployment](#step-5-deploy-the-amplify-frontend). For a detailed understanding of each deployment step, see the [Manual Deployment](#manual-deployment) section below.

## Manual Deployment

### Step 1: Clone the repository

```bash
git clone https://github.com/aws-samples/sample-voice-ai-powered-drive-thru-with-amazon-nova-sonic.git
cd sample-voice-ai-powered-drive-thru-with-amazon-nova-sonic
```

### Step 2: Deploy the infrastructure stack

1. Open the [AWS CloudFormation console](https://console.aws.amazon.com/cloudformation/).
2. Choose **Create stack** > **With new resources (standard)**.
3. Under **Specify template**, choose **Upload a template file** and upload `nova-sonic-infrastructure-drivethru.yaml`.
4. Choose **Next** and provide the following parameters:
   - **Stack name** — Enter a name (e.g., `nova-sonic-infra-dev`)
   - **Environment** — Select `dev`, `staging`, or `prod` (default: `dev`)
   - **UserEmail** — Enter a valid email address to receive the initial login credentials
5. Choose **Next**, acknowledge the IAM capabilities checkbox, and choose **Submit**.
6. Wait for the stack status to reach `CREATE_COMPLETE` (approximately 5–10 minutes).

### Step 3: Record infrastructure outputs

1. In the CloudFormation console, select the infrastructure stack.
2. Choose the **Outputs** tab.
3. Copy and save the following values — you need them to configure the frontend application:
   - `UserPoolId`
   - `UserPoolClientId`
   - `IdentityPoolId`
   - `menuApiUrl`
   - `cartApiUrl`
   - `orderApiUrl`
   - `loyaltyApiUrl`
   - `chatApiUrl`

### Step 4: Deploy the application stack

1. In the CloudFormation console, choose **Create stack** > **With new resources (standard)**.
2. Upload `nova-sonic-application-drivethru.yaml`.
3. Provide the following parameter:
   - **InfrastructureStackName** — Enter the exact stack name from Step 2 (e.g., `nova-sonic-infra-dev`)
4. Choose **Next**, acknowledge the IAM capabilities checkbox, and choose **Submit**.
5. Wait for the stack status to reach `CREATE_COMPLETE` (approximately 10–15 minutes). This stack generates AI images for all menu items using Amazon Bedrock.

### Step 5: Deploy the Amplify frontend

1. Download the frontend code `NovaSonic-FrontEnd.zip` from the [GitHub repository](https://github.com/aws-samples/sample-voice-ai-powered-drive-thru-with-amazon-nova-sonic).
2. Open the [AWS Amplify console](https://console.aws.amazon.com/amplify/).
3. Choose **Create new app** > **Deploy without Git provider**.
4. Upload the `NovaSonic-FrontEnd.zip` file and choose **Save and deploy**.
5. Wait for the deployment to complete and note the generated application URL.

## Deployment Validation

1. Open the [AWS CloudFormation console](https://console.aws.amazon.com/cloudformation/) and verify both stacks show status `CREATE_COMPLETE`:
   - Infrastructure stack (e.g., `nova-sonic-infra-dev`)
   - Application stack (e.g., `nova-sonic-app-dev`)

2. Verify DynamoDB tables are populated:

   ```bash
   aws dynamodb scan --table-name <MenuTableName> --select COUNT
   ```

   Expected output: `"Count": 22` (22 menu items including burgers, wings, fries, drinks, sauces, desserts, and combos).

3. Verify AI-generated images exist in S3:

   ```bash
   aws s3 ls s3://<MenuImagesBucketName>/ --recursive | wc -l
   ```

   Expected output: approximately 22 image files across category folders.

4. Open the Amplify application URL in a browser and verify the sign-in page loads.

## Running the Guidance

### Step 1: Configure the application

1. Open the Amplify application URL in your browser.
2. Select **Choose Sample**, then pick **AI Drive-Thru Experience** from the sample list, and select **Load Sample**. This imports the system prompt, tools, and tool configurations.
3. Enter the Amazon Cognito configuration values from the CloudFormation outputs:
   - `UserPoolId`
   - `UserPoolClientId`
   - `IdentityPoolId`
4. Enter the API endpoint URLs under **Tools global parameters**:
   - `menuAPIURL`
   - `cartAPIURL`
   - `orderAPIURL`
   - `loyaltyAPIURL`
   - `chatAPIURL`
5. (Optional) Enable **Auto-Initiate Conversation** to have Nova 2 Sonic greet the customer automatically.
6. Select **Save and Exit**.

### Step 2: Sign in

1. On the sign-in screen, enter username `appuser` and the temporary password sent to the email address you provided during CloudFormation deployment.
2. Complete the account verification using the code sent to your email.
3. Create a new permanent password when prompted.

### Step 3: Start a voice interaction

1. Select the microphone icon on the digital menu board.
2. Speak a request, for example: *"Can you show me what burgers you have?"*
3. Observe the following:
   - Nova 2 Sonic responds with a natural audio description of available burgers.
   - The digital menu board highlights the burger category and displays AI-generated images with pricing.
4. Continue the conversation to add items to your cart, customize orders, and complete the transaction.

**Sample interaction flow:**
- *"I'd like a Cheese Burger with extra bacon"* — adds a customized item to the cart
- *"Add a Cola and Regular Fries"* — adds additional items
- *"What combos do you have?"* — displays combo meal options
- *"Place my order"* — finalizes the order and provides a summary

## Next Steps

Consider the following enhancements to customize this Guidance for your environment:

- **Custom menu data** — Replace the sample menu items in the Lambda function with your restaurant's actual menu, pricing, and customization options.
- **Multi-language support** — Configure Nova 2 Sonic with additional language prompts to serve customers in multiple languages.
- **Payment integration** — Integrate a payment gateway (e.g., Stripe, Square) with the order processing flow through additional API Gateway endpoints.
- **Analytics dashboard** — Use **Amazon QuickSight** with DynamoDB data exports to visualize order trends, peak hours, and popular items.
- **Loyalty program expansion** — Extend the loyalty table schema and Nova 2 Sonic tool functions to support tiered rewards, promotions, and personalized recommendations.
- **Multi-location deployment** — Parameterize the CloudFormation templates for multi-Region or multi-account deployment to support restaurant chains.

## Cleanup

Follow these steps to remove all resources created by this Guidance:

1. **Delete the application CloudFormation stack:**
   - Open the [AWS CloudFormation console](https://console.aws.amazon.com/cloudformation/).
   - Select the application stack (deployed from `nova-sonic-application-drivethru.yaml`).
   - Choose **Delete** and confirm.
   - Wait for the stack deletion to complete.

2. **Delete the infrastructure CloudFormation stack:**
   - Select the infrastructure stack (deployed from `nova-sonic-infrastructure-drivethru.yaml`).
   - Choose **Delete** and confirm.
   - Wait for the stack deletion to complete.

   > **Note:** The S3 bucket cleanup Lambda function automatically empties the `MenuImagesBucket` and `AccessLogsBucket` during stack deletion. If deletion fails due to non-empty buckets, manually empty them first:
   >
   > ```bash
   > aws s3 rm s3://<MenuImagesBucketName> --recursive
   > aws s3 rm s3://<AccessLogsBucketName> --recursive
   > ```

3. **Delete the Amplify application:**
   - Open the [AWS Amplify console](https://console.aws.amazon.com/amplify/).
   - Select the deployed application.
   - Choose **Actions** > **Delete app** and confirm.

4. **Verify cleanup:**
   - Confirm no remaining resources in the CloudFormation, DynamoDB, S3, and Amplify consoles.
   - Check for any orphaned CloudWatch log groups under `/aws/lambda/` and delete them manually if present.

## FAQ, Known Issues, Additional Considerations, and Limitations

**Known issues:**

- The AI image generation step during the application stack deployment can take 10–15 minutes due to sequential image generation for all menu items. If the Lambda function times out, re-deploy the application stack.
- WebSocket connections to Nova 2 Sonic may disconnect after extended idle periods. The frontend automatically reconnects when the user initiates a new voice interaction.

**Additional considerations:**

- This Guidance creates a CloudFront distribution with a default domain name. For production use, configure a custom domain with an ACM certificate.
- The API Gateway endpoints use Cognito authorization. Unauthenticated access is not permitted.
- The S3 buckets have Object Lock enabled in GOVERNANCE mode with a 30-day retention period. Factor this into your data lifecycle management.
- Amazon Bedrock usage incurs per-request charges for both Nova 2 Sonic voice sessions and image generation. Monitor usage through AWS Cost Explorer.
- The sample menu data and customer records are synthetic and intended for demonstration purposes only.

For any feedback, questions, or suggestions, use the [Issues tab](https://github.com/aws-samples/sample-voice-ai-powered-drive-thru-with-amazon-nova-sonic/issues) in the GitHub repository.

## Notices

*Customers are responsible for making their own independent assessment of the information in this Guidance. This Guidance: (a) is for informational purposes only, (b) represents AWS current product offerings and practices, which are subject to change without notice, and (c) does not create any commitments or assurances from AWS and its affiliates, suppliers or licensors. AWS products or services are provided "as is" without warranties, representations, or conditions of any kind, whether express or implied. AWS responsibilities and liabilities to its customers are controlled by AWS agreements, and this Guidance is not part of, nor does it modify, any agreement between AWS and its customers.*

## Authors

- Salman Ahmed, Senior TAM
- Sergio Barraza, Senior TAM
- Ravi Kumar, Senior TAM
- Ankush Goyal, ESL TAM
