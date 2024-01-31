# RHACM DR - Prepare storage AWS non-STS
## Create AWS S3 bucket and access to it
### Set the BUCKET variable:
```bash
BUCKET=rhacm-dr-test-mmw
# Specify same name in dpa.yaml
```
### Set the REGION variable:
```bash
REGION=us-east-2
# Specify same region in dpa.yaml
```
### Create an AWS S3 bucket:
```bash
aws s3api create-bucket --bucket $BUCKET --region $REGION --create-bucket-configuration LocationConstraint=$REGION
# Verify
aws s3api list-buckets
```
### Create IAM user:
```bash
aws iam create-user --user-name velero
```
### Create a velero-policy.json file:
```bash
cat > velero-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeVolumes",
                "ec2:DescribeSnapshots",
                "ec2:CreateTags",
                "ec2:CreateVolume",
                "ec2:CreateSnapshot",
                "ec2:DeleteSnapshot"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:DeleteObject",
                "s3:PutObject",
                "s3:AbortMultipartUpload",
                "s3:ListMultipartUploadParts"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket",
                "s3:GetBucketLocation",
                "s3:ListBucketMultipartUploads"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET}"
            ]
        }
    ]
}
EOF
```

### Attach the policies to give the velero user the minimum necessary permissions
```bash
aws iam put-user-policy --user-name velero --policy-name velero --policy-document file://velero-policy.json
```
### Create an access key for the velero user
```bash
# NOTE. The first command creates the access key and stores the secret in the variable.
AWS_SECRET_ACCESS_KEY=$(aws iam create-access-key --user-name velero --output text | awk '{print $4}')
#AWS_ACCESS_KEY_ID=$(aws iam list-access-keys --user-name velero --output text | tail -1 | awk '{print $2}')
AWS_ACCESS_KEY_ID=$(aws iam list-access-keys --user-name velero --output json | jq -r .AccessKeyMetadata[].AccessKeyId)
echo $AWS_SECRET_ACCESS_KEY
echo $AWS_ACCESS_KEY_ID
```

### List access key value just created 
#### NOTE, you cannot get the SECRET_ACCESS_KEY after the initial creation
```bash
aws iam list-access-keys --user-name velero
```
#### If you have an issue, you can delete the access key and recreate showing the full output:
```bash
aws iam list-access-keys --user-name velero
aws iam delete-access-key --access-key-id <ACCESS KEY ID> --user-name velero
aws iam create-access-key --user-name velero
```
#### Example output
```
{
  "AccessKey": {
        "UserName": "velero",
        "Status": "Active",
        "CreateDate": "2017-07-31T22:24:41.576Z",
        "SecretAccessKey": <AWS_SECRET_ACCESS_KEY>,
        "AccessKeyId": <AWS_ACCESS_KEY_ID>
  }
}
```

### Create a credentials-velero file: 
```bash
cat << EOF > ./credentials-velero
[default]
aws_access_key_id=$AWS_ACCESS_KEY_ID
aws_secret_access_key=$AWS_SECRET_ACCESS_KEY
EOF
# Optional: backup credentials file in lab environment
cp credentials-velero credentials-velero.backup
```
