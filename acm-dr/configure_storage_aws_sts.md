# RHACM DR - Prepare storage AWS non-STS
## Create AWS S3 bucket and access to it
### NOTE: this includes a configuration that works for CSI and non-CSI drivers. For CSI specific configuration, see the documentation.
#### Set variables
```bash
export ENV=prod # Substitute environment name - this is optional but is used for naming the S3 bucket and a few other resources below
echo $ENV
export CLUSTER_NAME=$(oc cluster-info | grep "running at" | awk -F. '{print $2}')
#export CLUSTER_NAME=$(rosa describe cluster -c ${CLUSTER_NAME} --output json | jq -r .name)
echo $CLUSTER_NAME
# ROSA_CLUSTER_ID is only required if you want to include in AWS tags
export ROSA_CLUSTER_ID=$(rosa describe cluster -c ${CLUSTER_NAME} --output json | jq -r .id)
echo $ROSA_CLUSTER_ID
export REGION=$(rosa describe cluster -c ${CLUSTER_NAME} --output json | jq -r .region.id)
echo $REGION
# Set S3_REGION to same as active hub. Passive hub will use the same value, not its own region.
#export S3_REGION=us-east-2
echo $S3_REGION


# The next command results in null if the ROSA cluster is not STS?
# Check if it is STS
oc get authentication.config.openshift.io cluster -o json | jq .spec.serviceAccountIssuer
# Sample output
# "https://rh-oidc.s3.us-east-1.amazonaws.com/256i475s1nnuaobmhd8hobotj7c6ufpb"

export OIDC_ENDPOINT=$(oc get authentication.config.openshift.io cluster -o jsonpath='{.spec.serviceAccountIssuer}' | sed 's|^https://||')
echo $OIDC_ENDPOINT
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo $AWS_ACCOUNT_ID
# CLUSTER_VERSION is only required if you want to include in AWS tags
export CLUSTER_VERSION=$(rosa describe cluster -c ${CLUSTER_NAME} -o json | jq -r .version.raw_id | cut -f -2 -d '.')
echo $CLUSTER_VERSION
export ROLE_NAME="${CLUSTER_NAME}-openshift-oadp-aws-cloud-credentials"
echo $ROLE_NAME
export SCRATCH="/tmp/${CLUSTER_NAME}/oadp"
echo $SCRATCH
mkdir -p ${SCRATCH}
echo "Cluster ID: ${ROSA_CLUSTER_ID}, Region: ${REGION}, S3 Region: ${S3_REGION}, OIDC Endpoint:
${OIDC_ENDPOINT}, AWS Account ID: ${AWS_ACCOUNT_ID}"

```

#### Prepare AWS IAM resources
```bash
# Create an IAM Policy to allow for S3 Access
POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='RosaOadpVer1'].{ARN:Arn}" --output text)
if [[ -z "${POLICY_ARN}" ]]; then
cat << EOF > ${SCRATCH}/policy.json
{
"Version": "2012-10-17",
"Statement": [
  {
    "Effect": "Allow",
    "Action": [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:PutBucketTagging",
      "s3:GetBucketTagging",
      "s3:PutEncryptionConfiguration",
      "s3:GetEncryptionConfiguration",
      "s3:PutLifecycleConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucketMultipartUploads",
      "s3:AbortMultipartUploads",
      "s3:ListMultipartUploadParts",
      "s3:DescribeSnapshots",
      "ec2:DescribeVolumes",
      "ec2:DescribeVolumeAttribute",
      "ec2:DescribeVolumesModifications",
      "ec2:DescribeVolumeStatus",
      "ec2:CreateTags",
      "ec2:CreateVolume",
      "ec2:CreateSnapshot",
      "ec2:DeleteSnapshot"
    ],
    "Resource": "*"
  }
 ]}
EOF
  # This requires AWS CLI 2.x
  # Note: for RHACM, the namespace is open-cluster-management-backup, not the default openshift-oadp

# NOTE: The documentation specifies tags. I tested without them and they are not required.
#POLICY_ARN=$(aws iam create-policy --policy-name "RosaOadpVer1" \
#--policy-document file:///${SCRATCH}/policy.json --query Policy.Arn \
#--tags Key=rosa_openshift_version,Value=${CLUSTER_VERSION} Key=rosa_role_prefix,Value=ManagedOpenShift Key=operator_namespace,Value=open-cluster-management-backup Key=operator_name,#Value=openshift-oadp \
#--output text)

# Without the tags
POLICY_ARN=$(aws iam create-policy --policy-name "RosaOadpVer1" \
--policy-document file:///${SCRATCH}/policy.json --query Policy.Arn \
--output text)

fi

echo $POLICY_ARN

# Create an IAM Role trust policy for the cluster - adjusted for open-cluster-management-backup namespace
cat <<EOF > ${SCRATCH}/trust-policy.json
{
   "Version": "2012-10-17",
   "Statement": [{
     "Effect": "Allow",
     "Principal": {
       "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_ENDPOINT}"
     },
     "Action": "sts:AssumeRoleWithWebIdentity",
     "Condition": {
       "StringEquals": {
          "${OIDC_ENDPOINT}:sub": [
            "system:serviceaccount:open-cluster-management-backup:openshift-adp-controller-manager",
            "system:serviceaccount:open-cluster-management-backup:velero"]
       }
     }
   }]
}
EOF

cat ${SCRATCH}/trust-policy.json

# NOTE: For RHACM, the namespace is not default openshift-oadp, but is open-cluster-management-backup instead and operator name is redhat-oadp-operator
# NOTE: The documentation specifies tags. I tested without them and they are not required.
#ROLE_ARN=$(aws iam create-role --role-name \
#  "${ROLE_NAME}" \
#   --assume-role-policy-document file://${SCRATCH}/trust-policy.json \
#   --tags Key=rosa_cluster_id,Value=${ROSA_CLUSTER_ID} Key=rosa_openshift_version,Value=${CLUSTER_VERSION} Key=rosa_role_prefix,Value=ManagedOpenShift Key=operator_namespace,#Value=open-cluster-management-backup Key=operator_name,Value=redhat-oadp-operator \
#   --query Role.Arn --output text)

# Without the tags
ROLE_ARN=$(aws iam create-role --role-name \
  "${ROLE_NAME}" \
   --assume-role-policy-document file://${SCRATCH}/trust-policy.json \
   --query Role.Arn --output text)

echo ${ROLE_ARN}

# Attach the IAM Policy to the IAM Role
aws iam attach-role-policy --role-name "${ROLE_NAME}" --policy-arn ${POLICY_ARN}
```
