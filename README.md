# Enterprise deployment of RLCatalyst Research Gateway

## Introduction

Welcome to the RLCatalyst Research Gateway deployment manual. This guide is designed to provide documentation for users who will be installing and administering the Research Gateway product.

## What is Research Gateway

RLCatalyst Research Gateway is a solution built on AWS, and provides a self-service portal with cost and budget management that helps consume AWS resources for Scientific Research. It can be easily integrated into existing AWS customer accounts. It provides 1-Click AWS Service Catalog assets. budget management and data access with secure governance. Universities and Research Institutions can adopt this solution with minimal upfront investments. It is available in both SaaS and Enterprise models.

This is a cost-effective pre-built solution and packaged service offerings built on AWS.
It supports both self hosting(Enterprise) and managed hosting(SaaS) options
It is easy to deploy, consume, manage and extend.
It provides easy budget and cost governance.
It provides in-built security, based on AWS Best Practices
It provides a pre-built catalog of products which are ready to use out of the box.

## Planning for deployment

### Research Gateway Architecture

![image](https://user-images.githubusercontent.com/73109773/141417964-3738d959-99a2-471d-bf34-15f15637eac8.png)

#### 1. Hardware Requirements

| Virtual Machine Purpose            | Virtual Machine Spec                  |
| ---------------------------------- | ------------------------------------- |
| Role: Portal                       | t3.large 2CPU, 8GB RAM, 100GB Disk    |
| Role: DB AWS DocumentDB            | db.t3.large (dev) db.r5.large+ (prod) |

#### 2. ACM or External Certificates for SSL 

*Create a certificate for your domain*

To make the Research Gateway application available securely over SSL, you need a certificate issued by a public Certificate Authority (CA). 
If you already have a certificate for your domain issued by a third-party CA, you can import it into ACM. [See how](https://docs.aws.amazon.com/acm/latest/userguide/import-certificate.html).

Use one certificate for both the portal and the workspaces. The portal is served at the subdomain (for example `sub.mydomain.com`). Workspaces are served at hostnames under that subdomain (for example `workspace1.sub.mydomain.com`). A wildcard alone (`*.sub.mydomain.com`) does not cover the portal hostname, so the certificate must include both names. The same certificate is attached to the ALB listener, which routes `sub.mydomain.com` to the portal and `workspace1.sub.mydomain.com`-style hostnames to the workspaces.

If you already have a certificate for these names issued by AWS in ACM, you can pass CertificateArn with launch stack ( #7 - #9) and skip the following step.

     aws acm request-certificate --domain-name sub.mydomain.com --subject-alternative-names "*.sub.mydomain.com" --validation-method DNS --idempotency-token 1234 --options CertificateTransparencyLoggingPreference=DISABLED

`--domain-name` is the portal hostname. `--subject-alternative-names` adds the wildcard that covers the workspace hostnames. Quote the wildcard so the shell does not expand `*`. Replace `sub.mydomain.com` with your subdomain.

You will need to validate your ownership of the domain either via DNS (recommended) or via email. ACM returns DNS validation records for both names; add those CNAME records before the certificate is issued. Pass the issued certificate ARN as CertificateArn when you create the ALB listener (#7 - #9).

Fore more details on requesting a certificate, follow this [link](https://docs.aws.amazon.com/acm/latest/userguide/gs-acm-request-public.html)

#### 3. Network Requirements

 1. VPC  
 2. 3 Public Subnets  
 3. 3 Private Subnets  
 4. IGW  
 5. NAT Instance / NAT Gateway  
 6. Bastion Hosts  (Optional)
 7. Application Load Balancer  
 8. Listener  
 9. Target Group
10. Route 53  

<!-- trunk-ignore(markdownlint/MD036) -->
*Create #1 - #5 above using the following quick-start*


[![Launch Stack](https://cdn.rawgit.com/buildkite/cloudformation-launch-stack-button-svg/master/launch-stack.svg)](https://us-west-2.console.aws.amazon.com/cloudformation/home?region=us-west-2#/stacks/create/review?templateURL=https://aws-quickstart.s3.amazonaws.com/quickstart-aws-vpc/templates/aws-vpc.template.yaml&param_NumberOfAZs=3)


<!-- trunk-ignore(markdownlint/MD036) -->

<!-- trunk-ignore(markdownlint/MD036) -->
*Create #7 - #9 above using the following quick-start*


[![Launch Stack](https://cdn.rawgit.com/buildkite/cloudformation-launch-stack-button-svg/master/launch-stack.svg)](https://us-west-2.console.aws.amazon.com/cloudformation/home?region=us-west-2#/stacks/create/review?templateURL=https://rglaunch-stack.s3.us-east-2.amazonaws.com/rg-alb-route53.yml)


<!-- trunk-ignore(markdownlint/MD036) -->

*Note* - Create #7 - #9 above using AWS CLI commands also .For that you refer to the rg_alb-tg-creation.md file from repo

*10.Set up Route 53 for your domain/sub-domain*

From the AWS Console, select Route 53 service. [Create a hosted zone for your domain](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/CreatingNewSubdomain.html). If you are using an existing domain you can add a CNAME record and select the public DNS name of the ALB as the value. It is also possible to create a separate hosted zone for the sub-domain used for Research Gateway.

*Note* - It is possible to use Research Gateway without a domain-name but we do not recommend that for product workloads. To do so, use the public DNS name of the ALB as the URL of the Research Gateway in the setup scripts.

#### 4. Software Requirements

| Virtual Machine Purpose     | Software pre-requisites |
| --------------------------- | ----------------------- |
| Role: Portal                | Python, Docker 20.04+   |
| Role: DB (Option 1) MongoDB | MongoDB 3.6.23          |
                                                   

The application software for Research Gateway will be made available to you as a docker image shared from Relevance Lab's Elastic Container Registry instance to your AWS account.
As a part of this deployment, you will create an AMI for the portal EC2 instance which will have these softwares pre-deployed. Alternately, you can request the AMI to be shared with you by Relevance Lab and the software above will be available pre-deployed on the AMI shared with you.

#### 5. AWS Services required

- AWS Cognito
- Amazon S3
- AWS CloudFormation
- AWS DocumentDB
- AWS ImageBuilder
- AWS EC2
- AWS IAM
- AWS service catalog
- Elastic container Registery

## Installing the required 3rd party software

The following sofware needs to be installed on the Portal EC2 instance
| Software  | Version |
|-----------|---------|
| MongoDB   | 3.6.23  |
| Docker    | 20.10.9 |
| AWS CLI   | latest  |
| jq        | latest  |
| zip       | latest  |

For your convenience we have created packer scripts which allow you to create the AMI in your account For that you refer to the rg_AMI-creation.md file from repo

If an AMI with the pre-requisites has been shared with you, you can skip this section

### Installing Research Gateway

Clone this repo on a machine that has AWS CLI configured with Default output format as JSON.
Run deploy.sh with the following parameters.

 *Note* : Check aws configure before running script
  - $aws configure
      - AWS Access Key ID:"your_Access_Key"
      - AWS Secret Access Key :"your_Secret_Key"
      - Default region name:"Your_Region"
      - Default output format : json


| Parameter# | Purpose                                                                                    |
| ---------- | ------------------------------------------------------------------------------------------ |
| Param 1    | The AMI from which the EC2 instance that runs Research Gateway should be created           |
| Param 2    | Name of the S3 bucket to create which holds the CFT templates used in the Standard Catalog |
| Param 3    | VPC Id of the VPC in which to launch the Research Gateway EC2 instance                     |
| Param 4    | The Private Subnet1 in which to launch the Research Gateway DocumentDB                             |
| Param 5    | The Private Subnet2 in which to launch the Research Gateway DocumentDB                             |
| Param 6    | The Private Subnet3 in which to launch the Research Gateway DocumentDB                             |
| Param 7    | The Key Pair to use for launching the EC2 Instance                                         |
| Param 8    | Choose the environment - one of PROD, STAGE, QA, DEV                                       |
| Param 9    | The URL at which the Research Gateway will be accessed. e.g. https://myrg.example.com      |
| Param 10   | The Target Group ARN to which the Portal EC2 instance should be added                      |

*Note:* If you run into errors and only some stacks are created, you can retry the same deployment by running deploy.sh as follows.
    
    ./deploy.sh -f runid.json

runid.json is created in the rgdeploy folder when you first run deploy.sh with parameters. Example jwzx.json. All the original parameters passed to deploy.sh are stored in this file and enable the process to be picked up from where it was interrupted.

### Updating the AMI list for AMI based products

Download CFT template (dcvpipeline.yml) from rgrepo and update Master-AMI id with deployed region AMI-ID and RUN CFT by passing bucket name as deployed S3 RG template bucket. 

The deployment creates EC2 Image Builder pipelines for building the RStudio PCluster  Nextflow and DCV based AMIs that are used within Research Gateway. By default, these pipelines are set up to be manually triggered. You can change that in the AWS console if you wish to  trigger them on a schedule.

steps to run pipelines: AWS Console - EC2Imagebuilder – select image pipelines (Rstudio Nextflow PCluster NICE-DCV)-click on Actions- Run pipeline

Once a build is completed, the AMIs are automatically distributed to the regions supported by Research Gateway in your account. The AMI Ids need to be updated into your database before creating any projects. 

- Note down the names of the four pipelines created for RStudio Nextflow_Advanced PCluster NICE-DCV. They will be of the format:
RG-PortalStack-ImageBuilder-$runid-Pipeline_RStudio
RG-PortalStack-ImageBuilder-$runid-Pipeline_Nextflow_Advanced.
RG-PortalStack-ImageBuilder-$runid-Pipeline_PCluster
RL_RG_Nicedcv
The runid will be the random 4-character string generated for your instance during deployment. All the stacks created in your deployment should have that as a suffix.
- In the rgdeploy folder, cd to products folder. You will find an img-builder-config.json file there. Edit it and set the pipeline names according to the ones deployed in your account. Save the file.
- Run the script make-amilist.sh. You may have to run chmod +x make-amilist.sh if execute permissions are not set on the file.

- Note: we need to wait untill ec2image builder pipeline distribution complete,without builds complete by running below command shows Error

      ./make-amilist.sh > new-ami-list.json
- Next run the following command to update your DB.

      curl -X POST -H "Content-Type: application/json" -d @new-ami-list.json http://<RG-URL>/notificationsink/updateScAmiId
- Note that these AMI-Ids will be picked up by any projects created after this update. For projects already created prior to the update, you have to update the SSM Parameter Store paths (as mentioned in img-builder-config.json) for the project account with the ami-id of the corresponding region and product.

- Store the AMI Ids in the AWS SSM Parameter store of the base account (where Research Gateway runs) by running the following commands.

      ./products/make-ami-list-json.sh <region> > ./products/ami-list.json
      ./scripts/updatessmpaths.sh

### Creating the first user

- Connect to the EC2 instance using SSH or the SSM Session Manager from the AWS Console
- Run the following command
  - create_rg_admin_user.sh
- Enter the details prompted
  - First Name
  - Last Name
  - Email Id
- Ensure you get a success message.
- Check your email for an email with a verification link. You may need to check your spam folder for an email from
  no-reply@verificationemail.com
- Click on the verification link in the email and change your password.
- You can now access the Research Gateway at the URL (Param 9 above) with the email id and password.
- Refer to the [help pages](https://researchgateway.readthedocs.io/en/latest/) for more details on using Research Gateway
