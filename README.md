> [!NOTE]
> The content presented here serves as an example intended solely for educational objectives and should not be implemented in a live production environment without proper modifications and rigorous testing. 

# Voice AI-Powered Drive-Thru with Amazon Nova Sonic

[Artificial Intelligence](https://aws.amazon.com/ai/) (AI) is transforming the quick-service restaurant industry, particularly in drive-thru operations where efficiency and customer satisfaction intersect. Traditional systems create significant obstacles in service delivery, from staffing limitations and order accuracy issues to inconsistent customer experiences across locations. These challenges, combined with rising labor costs and demand fluctuations, have pushed the industry to seek innovative solutions.

In this post, we'll demonstrate how to implement a Quick Service Restaurants (QSRs) drive-thru solution using [Amazon Nova Sonic](https://aws.amazon.com/ai/generative-ai/nova/speech/) and AWS services. We'll walk through building an intelligent system that combines voice AI with interactive menu displays, providing technical insights and implementation guidance to help restaurants modernize their drive-thru operations.

For QSRs, the stakes are particularly high during peak hours, when long wait times and miscommunication between customers and staff can significantly impact business performance. Common pain points include order accuracy issues, service quality variations across different shifts, and limited ability to handle sudden spikes in customer demand. Modern consumers expect the same seamless, efficient service they experience with digital ordering systems, creating an unprecedented opportunity for voice AI technology to support 24/7 availability and consistent service quality.

Amazon Nova Sonic is a [foundation model (FM)](https://aws.amazon.com/what-is/foundation-models/) within the [Amazon Nova](https://aws.amazon.com/ai/generative-ai/nova/) family, designed specifically for voice-enabled applications. Available through [Amazon Bedrock](https://aws.amazon.com/bedrock/), developers can use Nova Sonic to create applications that understand spoken language, process complex conversational interactions, and generate appropriate responses for real-time customer engagement. This innovative speech-to-speech model addresses traditional voice application challenges through:

- Accurately recognizes streaming speech across accents with robustness to background noise
- Adapts speech response to user's tone and sentiment
- Bidirectional streaming speech I/O with low user perceived latency
- Graceful interruption handling and natural turn-taking in conversations
- Industry-leading price-performance

When integrated with AWS serverless services, Nova Sonic delivers natural, human-like voice interactions that helps improve the drive-thru experience. The architecture creates a cost-effective system that enhances both service consistency and operational efficiency through intelligent automation.

## Solution overview

Our voice AI drive-thru solution creates an intelligent ordering system that combines real-time voice interaction with a robust backend infrastructure, delivering a natural customer experience. The system processes speech in real-time, understanding various accents, speaking styles, and handling background noise common in drive-thru environments. Integrating voice commands with interactive menu displays enhances user feedback while streamlining the ordering process by reducing verbal interactions.

The system is built on AWS serverless architecture, integrating key components including [Amazon Cognito](https://aws.amazon.com/cognito/) for authentication with [role-based access control](https://docs.aws.amazon.com/cognito/latest/developerguide/role-based-access-control.html), [AWS Amplify](https://aws.amazon.com/amplify/) for the digital menu board, [Amazon API Gateway](https://aws.amazon.com/api-gateway/) to facilitate access to [Amazon DynamoDB](https://aws.amazon.com/dynamodb/) tables, [AWS Lambda](https://aws.amazon.com/lambda/) functions with [Amazon Nova Canvas](https://aws.amazon.com/ai/generative-ai/nova/creative/) for menu image generation, and [Amazon Simple Storage Service](https://aws.amazon.com/s3/) (Amazon S3) with [Amazon CloudFront](https://aws.amazon.com/cloudfront/) for image storage and delivery.

The following architecture diagram illustrates how these services interconnect to for natural conversations between customers and the digital menu board, orchestrating the entire customer journey from drive-thru entry to order completion.

<img width="1450" height="841" alt="1 NovaSonic-DriveThru-Architecture-Diagram" src="https://github.com/user-attachments/assets/248ec923-69ab-46cc-8186-370398c9c65f" />

Let's examine how each component works together to power this intelligent ordering system.

## Prerequisites

You must have the following in place to complete the solution in this post:

- An [AWS account](https://signin.aws.amazon.com/signin?redirect_uri=https%3A%2F%2Fportal.aws.amazon.com%2Fbilling%2Fsignup%2Fresume&client_id=signup)
- FM access in Amazon Bedrock for Amazon Nova Sonic and Amazon Nova Canvas in the same AWS Region where you will deploy this solution
- The accompanying AWS CloudFormation templates downloaded from the [aws-samples GitHub repo](https://github.com/aws-samples/sample-voice-ai-powered-drive-thru-with-amazon-nova-sonic)

## Deploy solution resources using AWS CloudFormation

Deploy the CloudFormation templates in an AWS Region where Amazon Bedrock is [available](https://docs.aws.amazon.com/bedrock/latest/userguide/models-regions.html) and has support for the following models: Amazon Nova Sonic and Amazon Nova Canvas.

This solution consists of two CloudFormation templates that work together to create a complete restaurant drive-thru ordering system. The `nova-sonic-infrastructure-drivethru.yaml` template establishes the foundational AWS infrastructure including Cognito user authentication, S3 storage with CloudFront CDN for menu images, DynamoDB tables for menu items and customer data, and API Gateway endpoints with proper CORS configuration. The `nova-sonic-application-drivethru.yaml` template builds upon this foundation by deploying a Lambda function that populates the system with a complete embedded drive-thru menu featuring burgers, wings, fries, drinks, sauces, and combo meals, while using the Amazon Nova Canvas AI model to automatically generate professional food photography for each menu item and storing them in the S3 bucket for delivery through CloudFront.

During the deployment of the first CloudFormation template `nova-sonic-infrastructure-drivethru.yaml`, you will need to specify the following parameters:

- Stack name
- Environment - Deployment environment: dev, staging, or prod (defaults to dev)
- UserEmail - Valid email address for the user account (required)

**Important:** You must enable access to the selected Amazon Nova Sonic model and Amazon Nova Canvas model in the Amazon Bedrock console before deployment.

AWS resource usage will incur costs. When deployment is complete, the following resources will be deployed:

- Amazon Cognito resources:
  - [User pool](https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-pools.html) – `CognitoUserPool`
  - [App client](https://docs.aws.amazon.com/cognito/latest/developerguide/user-pool-settings-client-apps.html) – `AppClient`
  - [Identity pool](https://docs.aws.amazon.com/cognito/latest/developerguide/identity-pools.html) – `CognitoIdentityPool`
  - [Groups](https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-pools-user-groups.html) – `AppUserGroup`
  - [User](https://docs.aws.amazon.com/cognito/latest/developerguide/managing-users.html) – `AppUser`

- [AWS Identity and Access Management](https://aws.amazon.com/iam/) (IAM) resources:
  - [IAM roles](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles.html):
    - `AuthenticatedRole`
    - `DefaultAuthenticatedRole`
    - `ApiGatewayDynamoDBRole`
    - `LambdaExecutionRole`
    - `S3BucketCleanupRole`

- Amazon DynamoDB tables:
  - `MenuTable` – Stores menu items, pricing, and customization options
  - `LoyaltyTable` – Stores customer loyalty information and points
  - `CartTable` – Stores shopping cart data for active sessions
  - `OrderTable` – Stores completed and pending orders
  - `ChatTable` – Stores completed chat details

- Amazon S3, CloudFront and AWS WAF resources:
  - `MenuImagesBucket` – S3 bucket for storing menu item images
  - `MenuImageCloudFrontDistribution` - CloudFront distribution for global content delivery
  - `CloudFrontOriginAccessIdentity` – Secure access between CloudFront and S3
  - `CloudFrontWebACL` – WAF protection for CloudFront distribution with security rules

- Amazon API Gateway resources:
  - REST API – `app-api` with Cognito authorization
  - API resources and methods:
    - `/menu` (GET, OPTIONS)
    - `/loyalty` (GET, OPTIONS)
    - `/cart` (POST, DELETE, OPTIONS)
    - `/order` (POST, OPTIONS)
    - `/chat` (POST, OPTIONS)
  - API deployment to specified environment stage

- AWS Lambda function:
  - `S3BucketCleanupLambda` – Cleans up S3 bucket on stack deletion

- CloudFormation Custom Resource:
  - `S3BucketCleanup` – Triggers `S3BucketCleanupLambda`

After you deploy the CloudFormation template, copy the following from the Outputs tab on the AWS CloudFormation console to use during the configuration of your frontend application:

- `cartApiUrl`
- `loyaltyApiUrl`
- `menuApiUrl`
- `orderApiUrl`
- `chatApiUrl`
- `UserPoolClientId`
- `UserPoolId`
- `IdentityPoolId`

The following screenshot shows you what the **Outputs** tab will look like.

![2 CFN-Output](https://github.com/user-attachments/assets/ef8fab56-8089-43ee-b261-5f3df19ebacb)

These output values are essential for configuring your frontend application (deployed via AWS Amplify) to connect with the backend services. The API URLs will be used for making REST API calls, while the Cognito IDs will be used for user authentication and authorization.

During the deployment of the second CloudFormation template `nova-sonic-application-drivethru.yaml` you will need to specify the following parameters:

- Stack name
- InfrastructureStackName – This stack name matches the one you previously deployed using `nova-sonic-infrastructure-drivethru.yaml`

When deployment is complete, the following resources will be deployed:

- AWS Lambda function:
  - `DriveThruMenuLambda` – Populates menu data and generates AI images

- CloudFormation Custom Resource:
  - `DriveThruMenuPopulation` – Triggers `DriveThruMenuLambda`

Once both CloudFormation templates are successfully deployed, you'll have a fully functional restaurant drive-thru ordering system with AI-generated menu images, complete authentication, and ready-to-use API endpoints for your Amplify frontend deployment.

## Deploy the Amplify application

You need to manually deploy the Amplify application using the frontend code found on GitHub. Complete the following steps:

1. Download the frontend code `NovaSonic-FrontEnd.zip` from [GitHub](https://github.com/aws-samples/sample-voice-ai-powered-drive-thru-with-amazon-nova-sonic).
2. Use the .zip file to manually [deploy](https://docs.aws.amazon.com/amplify/latest/userguide/manual-deploys.html) the application in Amplify.
3. Return to the Amplify page and use the domain it automatically generated to access the application.

## User authentication

The solution uses Amazon Cognito user pools and identity pools to implement secure, role-based access control for restaurant's digital menu board. User pools handle authentication and group management through the `AppUserGroup`, and identity pools provide temporary AWS credentials mapped to specific IAM roles including `AuthenticatedRole`. The system makes sure that only verified digital menu board users can access the application and interact with the menu APIs, cart management, order processing, and loyalty services, while also providing secure access to Amazon Bedrock. This combines robust security with an intuitive ordering experience for both customers and restaurant operations.

## Serverless data management

The solution implements a serverless API architecture using Amazon API Gateway to create a single REST API `(app-api)` that facilitates communication between the frontend interface and backend services. The API includes five resource endpoints `(/menu, /loyalty, /cart, /chat,/order)` with Cognito-based authentication and direct DynamoDB integration for data operations. The backend utilizes five DynamoDB tables: `MenuTable` for menu items and pricing, `LoyaltyTable` for customer profiles and loyalty points, `CartTable` for active shopping sessions, `ChatTable` for capturing chat history and `OrderTable` for order tracking and history. This architecture provides fast, consistent performance at scale with Global Secondary Indexes enabling efficient queries by customer ID and order status for optimal drive-thru operations.

## Menu and image generation and distribution

The solution uses Amazon S3 and CloudFront for secure, global content delivery of menu item images. The CloudFormation template creates a `MenuImagesBucket` with restricted access through a CloudFront Origin Access Identity, making sure images are served securely using the CloudFront distribution for fast loading times worldwide. AWS Lambda powers the AI-driven content generation through the `DriveThruMenuLambda` function, which automatically populates sample menu data and generates high-quality menu item images using Amazon Nova Canvas. This serverless function executes during stack deployment to create professional food photography for the menu items, from classic burgers to specialty wings, facilitating consistent visual presentation across the entire menu. The Lambda function integrates with DynamoDB to store generated image URLs and uses S3 for persistent storage, creating a complete automated workflow that scales based on demand while optimizing costs through pay-per-use pricing.

## Voice AI processing

The solution uses Amazon Nova Sonic as the core voice AI engine. The digital menu board establishes direct integration with Amazon Nova Sonic through secure WebSocket connections, for immediate processing of customer speech input and conversion to structured ordering data. The CloudFormation template configures IAM permissions for the `AuthenticatedRole` to access the amazon.nova-sonic-v1:0 foundation model, allowing authenticated users to interact with the voice AI service. Nova Sonic handles complex natural language understanding and intent recognition, processing customer requests like menu inquiries, order modifications, and item customizations while maintaining conversation context throughout the ordering process. This direct integration minimizes latency concerns and provides customers with a natural, conversational ordering experience that rivals human interaction while maintaining reliable service across drive-thru locations.

## Hosting the digital menu board

AWS Amplify hosts and delivers the digital menu board interface as a scalable frontend application. The interface displays AI-generated menu images through CloudFront, with real-time pricing from DynamoDB, optimized for drive-thru environments. The React-based application automatically scales during peak hours, using the global content delivery network available in CloudFront for fast loading times. It integrates with Amazon Cognito for authentication, establishes WebSocket connections to Amazon Nova Sonic for voice processing, and uses API Gateway endpoints for menu and order management. This serverless solution maintains high availability while providing real-time visual updates as customers interact through voice commands.

## WebSocket connection flow

The following sequence diagram illustrates the WebSocket connection setup enabling direct browser-to-Nova Sonic communication. This architecture leverages the AWS SDK [update](https://github.com/aws/aws-sdk-js-v3/releases/tag/v3.842.0) (client-bedrock-runtime v3.842.0), which introduces WebSocketHandler support in browsers, avoiding the need for a server.

<img width="1257" height="953" alt="3 WebSocketConnectionSetup Configuration" src="https://github.com/user-attachments/assets/1ba35d0a-fcf1-4767-bba9-12c51d6801f5" />

This advancement allows frontend applications to establish direct WebSocket connections to Nova Sonic, reducing latency and complexity while enabling real-time conversational AI in the browser. The initialization process includes credential validation, Bedrock client establishment, AI assistant configuration, and [audio input](https://docs.aws.amazon.com/nova/latest/userguide/input-events.html) setup (16kHz PCM). This direct client-to-service communication represents a shift from traditional architectures, offering more efficient and scalable conversational AI applications.

## Voice interaction and dynamic menu

The following sequence diagram illustrates the flow of a customer's burger query, demonstrating how natural language requests are processed to deliver synchronized audio responses and visual updates.

<img width="1769" height="1025" alt="4 DynamicMenuContext Real-TimeUpdates" src="https://github.com/user-attachments/assets/bc107fe5-7635-43e0-b4ae-266e72497938" />

This diagram shows how a query `("Can you show me what burgers you have?")` is handled. Nova Sonic calls `getMenuItems` `({category: "burgers"})` to retrieve menu data, while Frontend App components fetch and structure burger items and prices. Nova Sonic generates a contextual response and triggers `showCategory` `({category: "burgers"})` to highlight the burger section in the UI. This process facilitates real-time synchronization between audio responses and visual menu updates, creating a seamless customer experience throughout the conversation.

## Drive-thru solution walkthrough

After deploying your application in AWS Amplify, open the generated URL in your browser. You'll see two setup options: `Choose Sample` and `Manual Setup`. Select `Choose Sample` then pick `AI Drive-Thru Experience` from the sample list, and then select `Load Sample`. This will automatically import the system prompt, tools, and tool configurations for the drive-thru solution. We will configure these settings in the following steps.

![5 LoadSampleConfiguration-compressed](https://github.com/user-attachments/assets/08227d31-9263-4993-8be8-f32496744b4b)

After selecting `Load Sample`, you'll be prompted to configure the connection settings. You'll need to use the Amazon Cognito and API Gateway information from your CloudFormation stack outputs. These values are required because they connect your digital menu board to backend services.

Enter the configuration values you copied from the CloudFormation outputs `(nova-sonic-infrastructure-drivethru.yaml)`. These are organized into two sections, as demonstrated in the following videos. After you enter the configuration details in each section, select `Save` button at the top of the screen.

Amazon Cognito configuration:
- `UserPoolId`
- `UserPoolClientId`
- `IdentityPoolId`

![6 AmazonCongitoConfiguration-compressed](https://github.com/user-attachments/assets/f28ce41a-db6e-4bd8-9c35-7f86a01204b0)

Agent configuration:
- Auto-Initiate Conversation - Nova Sonic is initially set to wait for you to start the conversation. However, you can enable automatic conversation initiation by checking the 'Enable auto-initiate' box. There is a pre-recorded 'Hello' that you can use that's stored locally.

![7 AutoInitiate-compressed](https://github.com/user-attachments/assets/940ce553-c4d8-4c40-b3c9-c4a56941791a)

- Tools global parameters:
  - `menuAPIURL`
  - `cartAPIURL`
  - `orderAPIUR`
  - `loyaltyAPIURL`
  - `chatAPIURL`

![8 AgentConfiguration-compressed](https://github.com/user-attachments/assets/ee0c2930-9184-4e8e-9873-6cd2fd357e57)

After completing the configuration, click the `Save and Exit` button located at the top of the page. This action will redirect you to a sign-in screen. To access the system, use the username `appuser` and the password automatically generated and emailed to you to the email that was provided during the CloudFormation deployment.

After entering the temporary password, you'll be asked to verify your account through a temporary code sent to your email.

Upon your initial login attempt, you'll be required to create a new password to replace the temporary one, as demonstrated in the following video.

![9 SignInDigitalMenuBoard-compressed](https://github.com/user-attachments/assets/e084593f-3af1-4166-a947-7e4aefd9d3ca)

Begin your drive-thru experience by clicking the microphone icon. The AI assistant welcomes you and guides you through placing your order while dynamically updating the digital menu board to highlight relevant items. The system intelligently suggests complementary items and adapts its communication style to enhance your ordering experience.

https://github.com/user-attachments/assets/1a7aa7a0-88e6-4849-9dea-6fcce6c4141c

## Clean up

If you decide to discontinue using the solution, you can follow these steps to remove it, its associated resources deployed using AWS CloudFormation, and the Amplify deployment:

1. Delete the CloudFormation stack:
   - On the AWS CloudFormation console, choose Stacks in the navigation pane.
   - Locate the stack you created during the deployment process of `nova-sonic-application-drivethru.yaml` (you assigned a name to it).
   - Select the stack and choose Delete.
   - Repeat this for `nova-sonic-infrastructure-drivethru.yaml`

2. Delete the Amplify application and its resources. For instructions, refer to [Clean Up Resources](https://aws.amazon.com/getting-started/hands-on/build-web-app-s3-lambda-api-gateway-dynamodb/module-six/).

## Conclusion

The voice AI-powered drive-thru ordering system using Amazon Nova Sonic provides restaurants with a practical solution to common operational challenges including staffing constraints, order accuracy issues, and peak-hour bottlenecks. The serverless architecture built on AWS services—Amazon Cognito for authentication, API Gateway for data communication, DynamoDB for storage, and AWS Amplify for hosting, creates a scalable system that handles varying demand while maintaining consistent performance. The system supports essential restaurant operations including menu management, cart functionality, loyalty programs, and order processing through direct API Gateway and DynamoDB integration. For restaurants looking to modernize their drive-thru operations, this solution offers measurable benefits including reduced wait times, improved order accuracy, and operational efficiency gains. The pay-per-use pricing model and automated scaling help control costs while supporting business growth. As customer expectations shift toward more efficient service experiences, implementing voice AI technology provides restaurants with a competitive advantage and positions them well for future technological developments in the food service industry.

## Additional resources

To learn more about Amazon Nova Sonic and additional solutions, refer to the following resources:

- [Introducing Amazon Nova Sonic: Human-like voice conversations for generative AI applications](https://aws.amazon.com/blogs/aws/introducing-amazon-nova-sonic-human-like-voice-conversations-for-generative-ai-applications/)
- Frontend application source code used in this blog is available on [GitHub](https://github.com/aws-samples/sample-voice-ai-powered-contextual-menu-board-with-amazon-nova-sonic)
- [Voice AI-Powered Hotel In-Room Service with Amazon Nova Sonic](https://github.com/aws-samples/sample-voice-ai-powered-in-room-service-with-amazon-nova-sonic/tree/main)

---
