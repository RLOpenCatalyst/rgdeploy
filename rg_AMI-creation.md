# Creating the AMI with Pre-Requisites

Follow these steps to create an AMI with pre-requisites:

## 1. Install Packer

- Refer to the [Packer Installation Guide](https://learn.hashicorp.com/tutorials/packer/get-started-install-cli).
- For Amazon Linux 2023 (AWS CloudShell):
  ```bash
  sudo yum install -y yum-utils
  sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
  sudo yum -y install packer
  ```

## 2. Install the Amazon Plugin for Packer

1. **Create a Packer Configuration File:**
   Create a file named `packer-config.pkr.hcl` with the following content:
   ```hcl
   packer {
     required_plugins {
       amazon = {
         version = ">= 1.3.3"
         source  = "github.com/hashicorp/amazon"
       }
     }
   }
   ```

2. **Run Packer Initialization:**
   Use the following command to download and install the Amazon plugin:
   ```bash
   packer init packer-config.pkr.hcl
   ```

## 3. Export AWS Credentials

Set your AWS credentials and region as environment variables:
```bash
export AWS_ACCESS_KEY_ID="your_Access_Key"
export AWS_SECRET_ACCESS_KEY="your_Secret_Key"
export AWS_DEFAULT_REGION="Your_Region"
```

## 4. Clone the Repository

Clone the required repository to your local machine or AWS CloudShell.

## 5. Grant Permissions for Target Account

- Ensure the target account number is added in the Admin Account-ECR with permissions to access image builds.

## 6. Create an IAM Role for ECR and EC2 Actions

1. **Create a Role:**
   - Create a role and attach a policy permitting ECR and EC2 actions.

2. **Update the `packer-rg.json` File:**
   - Replace the placeholder `<your_rolename>` in the `"iam_instance_profile"` field under the builders section with your role name.

## 7. Build the AMI

Run the following command to build the AMI:
```bash
packer build -var 'awsRegion=your_region' -var 'vpcId=your_VPCID' -var 'subnetId=your_SubnetID' packer-rg.json
```

### Runtime Variables:
- Pass the following variables at runtime:
  - `VPCID`
  - `SubnetID`
  - `AWSRegion`

## 8. Retrieve the AMI ID

After the build completes successfully, note the AMI ID from the output.

---

### Notes

- Ensure all variables and IAM roles are correctly configured before running the build.
- For further details, refer to the repository documentation or Packer's [official documentation](https://www.packer.io/docs).

