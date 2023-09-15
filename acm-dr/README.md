# RHACM DR
## ACM Storage Design
![ACM Storage Design](/acm-dr/cluster_backup_controller_dataflow25.png)
### ACM Normal Backup Operation
![ACM Normal Backup Operation](/acm-dr/acm_active_passive_config_design.png)
### ACM DR Failover Process
![ACM DR Failover Process](/acm-dr/acm_disaster_recovery.png)
#
### References
#### https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/2.8/html-single/business_continuity/index
#### https://github.com/stolostron/cluster-backup-operator
#### https://github.com/stolostron/cluster-backup-operator/tree/main/config/samples
#### https://docs.openshift.com/container-platform/4.12/backup_and_restore/application_backup_and_restore/installing/installing-oadp-aws.html
#### https://mobb.ninja/docs/misc/oadp/rosa-sts/
#### https://docs.openshift.com/rosa/rosa_backing_up_and_restoring_applications/backing-up-applications.html
#### https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/2.8/html-single/business_continuity/index#auto-connect-clusters-msa
#### https://github.com/stolostron/cluster-backup-operator/tree/main#automatically-connecting-clusters-using-managedserviceaccount---tech-preview


# Assumptions
#### - ACM is installed on both Active and Passive clusters - IN THE SAME NAMESPACES
#### - All operators installed on Active are also be installed on passive cluster
    example: Ansible Automation Platform, Red Hat OpenShift GitOps, cert-manager, etc
#### - User has cluster-admin access to Active and Passive clusters
#### - Terminal shell to Active and Passive clusters
#### - Shell has oc, aws, and jq clients
#### - The aws cli has appropriate access to create AWS resources
##### To Install aws cli
#### https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
# Verify
aws --version
```

# High level steps
## Two options are described
### Option 1: AWS connections using IAM user (non-STS)
### Option 2: AWS connections using STS
##   Prepare AWS and OCP resources using IAM User (Option 1)
#### Create AWS S3 bucket
#### Create IAM user
#### Create policy file and attach to new IAM user - check on using STS roles instead of IAM user
#### Create access key for new IAM user - not allowed at Delta unless exception - would require rotating keys every 90 days
#### Create credentials-velero file
### Prepare Active Hub Cluster
#### Install OADP Operator
#### Enable restore of imported managed clusters
#### Create OCP secret from credentials-velero file
#### Create DataProtectionApplication CR
### Prepare Passive Hub Cluster
#### Install OADP Operator
#### Create credentials-velero file (same content as above)
#### Create OCP secret from credentials-velero file
#### Create DataProtectionApplication CR
### Go to "Backup Active Hub Cluster"

##   Prepare AWS and OCP resources using STS (Option 2)
### NOTE: this includes a configuration that works for CSI and non-CSI drivers. For CSI specific configuration, see the documentation.
#### Prepare AWS IAM policy to allow access to S3
#### Create  IAM role trust policy for the cluster
#### Attach policy to role
### Prepare Active Hub Cluster
#### Create OCP secret from AWS token file
#### Install OADP Operator
#### Create AWS cloud storage using your AWS credentials
#### Create DataProtectionApplication CR
### Prepare Passive Hub Cluster
#### Create OCP secret from AWS token file
#### Install OADP Operator
#### Create AWS cloud storage using your AWS credentials
#### Create DataProtectionApplication CR
### Go to "Backup Active Hub Cluster"

## Backup Active Hub Cluster
#### Create backup schedule
## Restore to Passive Hub Cluster
### Options
#### Restore everything except managed clusters (one time)
#### Restore everything except managed clusters and continue restoring new backups (sync)
#### Restore only managed clusters
#### Restore everything including managed clusters


# Detailed Steps
# Option 1: AWS connections using IAM user (non-STS)
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
aws iam delete-access-keys --access-key-id <ACCESS KEY ID> --user-name velero
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

## ACTIVE CLUSTER
## Install OADP Operator # It will be installed when setting cluster-backup: true in the mch
```bash
oc patch MultiClusterHub multiclusterhub -n open-cluster-management --type=json -p='[{"op": "add", "path": "/spec/overrides/components/-","value":{"name":"cluster-backup","enabled":true}}]'
# Wait until succeeded
echo "Waiting until ready (Succeeded)..."
output() {
    # oc get csv -n open-cluster-management-backup | grep OADP
    oc get -n open-cluster-management-backup $(oc get csv -n open-cluster-management-backup -o name | grep oadp) -ojson | jq -r [.status.phase] |jq -r '.[]'
}
#status=$(oc get csv -n open-cluster-management-backup | grep OADP | awk '{print $6}')
status=$(oc get -n open-cluster-management-backup $(oc get csv -n open-cluster-management-backup -o name | grep oadp) -ojson | jq -r [.status.phase] |jq -r '.[]')
  output
expected_condition="Succeeded"
timeout="300"
i=1
until [ "$status" = "$expected_condition" ]
do
  ((i++))
  
  if [ "${i}" -gt "${timeout}" ]; then
      echo "Sorry it took too long"
      exit 1
  fi

  sleep 3
done
echo "OK to proceed"
```

## Enable restore of imported managed clusters
```bash
oc patch multiclusterengine multiclusterengine --type=merge -p '{"spec":{"overrides":{"components":[{"name":"managedserviceaccount-preview","enabled":true}]}}}'
# Verify it is set to true
#oc get multiclusterengine multiclusterengine -oyaml |grep managedserviceaccount-preview -A1 | tail -1 | awk '{print $3}'
oc get multiclusterengine multiclusterengine -ojson | jq -r '.spec.overrides.components[] | select(.name == "console-mce")' | jq .enabled
```

## Create a Secret with the default name:
```bash
oc create secret generic cloud-credentials -n open-cluster-management-backup --from-file cloud=credentials-velero
```

## Create DataProtectionApplication CR
### Change name in dpa.yaml to bucket specified above
```bash
oc create -f acm-dr/dpa.yaml
# Wait until complete
echo "Waiting until complete..."
output() {
    oc get dpa -n open-cluster-management-backup velero -ojson | jq '.status.conditions[] | select(.reason == "Complete")'
}
status=$(oc get dpa -n open-cluster-management-backup velero -ojson | jq '.status.conditions[] | select(.reason == "Complete")' |jq -r .status)
expected_condition=True
timeout="300"
i=1
until [ "$status" = "$expected_condition" ]
do
  ((i++))
  output
  
  if [ "${i}" -gt "${timeout}" ]; then
      echo "Sorry it took too long"
      exit 1
  fi
  sleep 3
done
 output
echo "OK to proceed"
```

### Verify success
```bash
oc get all -n open-cluster-management-backup
```
### Output should be similar
```
[rosa@bastion acm-acs]$ oc get pods -n open-cluster-management-backup
NAME                                                 READY   STATUS    RESTARTS   AGE
cluster-backup-chart-clusterbackup-5f7568884-k82sz   1/1     Running   0          90m
cluster-backup-chart-clusterbackup-5f7568884-ssltg   1/1     Running   0          90m
openshift-adp-controller-manager-544985898c-hksk6    1/1     Running   0          89m
restic-gwxs9                                         1/1     Running   0          3m2s
restic-pwfs7                                         1/1     Running   0          3m2s
velero-759f578c65-nmj2z                              1/1     Running   0          3m2s
[rosa@bastion acm-acs]$ oc get all -n open-cluster-management-backup
NAME                                                     READY   STATUS    RESTARTS   AGE
pod/cluster-backup-chart-clusterbackup-5f7568884-k82sz   1/1     Running   0          90m
pod/cluster-backup-chart-clusterbackup-5f7568884-ssltg   1/1     Running   0          90m
pod/openshift-adp-controller-manager-544985898c-hksk6    1/1     Running   0          89m
pod/restic-gwxs9                                         1/1     Running   0          3m13s
pod/restic-pwfs7                                         1/1     Running   0          3m13s
pod/velero-759f578c65-nmj2z                              1/1     Running   0          3m13s

NAME                                                       TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
service/openshift-adp-controller-manager-metrics-service   ClusterIP   172.30.67.227    <none>        8443/TCP   90m
service/openshift-adp-velero-metrics-svc                   ClusterIP   172.30.137.151   <none>        8085/TCP   3m13s

NAME                    DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
daemonset.apps/restic   2         2         2       2            2           <none>          3m13s

NAME                                                 READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/cluster-backup-chart-clusterbackup   2/2     2            2           90m
deployment.apps/openshift-adp-controller-manager     1/1     1            1           89m
deployment.apps/velero                               1/1     1            1           3m13s

NAME                                                           DESIRED   CURRENT   READY   AGE
replicaset.apps/cluster-backup-chart-clusterbackup-5f7568884   2         2         2       90m
replicaset.apps/openshift-adp-controller-manager-544985898c    1         1         1       89m
replicaset.apps/velero-759f578c65                              1         1         1       3m13s
```

# PASSIVE CLUSTER
## Repeat steps above for installing oadp using same secret
## Install OADP Operator # It will be installed when setting cluster-backup: true in the mch
```bash
oc patch MultiClusterHub multiclusterhub -n open-cluster-management --type=json -p='[{"op": "add", "path": "/spec/overrides/components/-","value":{"name":"cluster-backup","enabled":true}}]'
# Wait until succeeded
echo "Waiting until ready (Succeeded)..."
output() {
    # oc get csv -n open-cluster-management-backup | grep OADP
    oc get -n open-cluster-management-backup $(oc get csv -n open-cluster-management-backup -o name | grep oadp) -ojson | jq -r [.status.phase] |jq -r '.[]'
}
#status=$(oc get csv -n open-cluster-management-backup | grep OADP | awk '{print $6}')
status=$(oc get -n open-cluster-management-backup $(oc get csv -n open-cluster-management-backup -o name | grep oadp) -ojson | jq -r [.status.phase] |jq -r '.[]')
  output
expected_condition="Succeeded"
timeout="300"
i=1
until [ "$status" = "$expected_condition" ]
do
  ((i++))
  
  if [ "${i}" -gt "${timeout}" ]; then
      echo "Sorry it took too long"
      exit 1
  fi

  sleep 3
done
echo "OK to proceed"
```
## Enable managedserviceaccount-preview
```bash
oc patch multiclusterengine multiclusterengine --type=merge -p '{"spec":{"overrides":{"components":[{"name":"managedserviceaccount-preview","enabled":true}]}}}'
# Verify it is set to true
#oc get multiclusterengine multiclusterengine -oyaml |grep managedserviceaccount-preview -A1 | tail -1 | awk '{print $3}'
oc get multiclusterengine multiclusterengine -ojson | jq -r '.spec.overrides.components[] | select(.name == "console-mce")' | jq .enabled

```

## Create a Secret with the default name
### Note: you will need to create the same file that was created above
```bash
oc create secret generic cloud-credentials -n open-cluster-management-backup --from-file cloud=credentials-velero
```

## Create DataProtectionApplication CR
### Change name in dpa.yaml to bucket specified above
```bash
oc create -f acm-dr/dpa.yaml
# Wait until complete
echo "Waiting until complete..."
output() {
    oc get dpa -n open-cluster-management-backup velero -ojson | jq '.status.conditions[] | select(.reason == "Complete")'
}
status=$(oc get dpa -n open-cluster-management-backup velero -ojson | jq '.status.conditions[] | select(.reason == "Complete")' |jq -r .status)
expected_condition=True
timeout="300"
i=1
until [ "$status" = "$expected_condition" ]
do
  ((i++))
  output
  
  if [ "${i}" -gt "${timeout}" ]; then
      echo "Sorry it took too long"
      exit 1
  fi
  sleep 3
done
 output
echo "OK to proceed"
```

### Verify success
```bash
oc get all -n open-cluster-management-backup
```

### Verify ACM policy was created and it compliant
```bash
oc get policy -n open-cluster-management-backup
```

##   Prepare AWS and OCP resources using STS (Option 2)
### NOTE: this includes a configuration that works for CSI and non-CSI drivers. For CSI specific configuration, see the documentation.
#### Set variables
```bash
export ENV=preprod # Substitute environment name - this is optional but is used for naming the S3 bucket and a few other resources below
export CLUSTER_NAME=$(rosa describe cluster -c ${CLUSTER_NAME} --output json | jq -r .name)
echo $CLUSTER_NAME
export ROSA_CLUSTER_ID=$(rosa describe cluster -c ${CLUSTER_NAME} --output json | jq -r .id)
echo $ROSA_CLUSTER_ID
export REGION=$(rosa describe cluster -c ${CLUSTER_NAME} --output json | jq -r .region.id)
echo $REGION
# Set S3_REGION to same as active hub. Passive hub will use the same value, not its own region.
export S3_REGION=us-east-2 
echo $S3_REGION


# The next command results in null - in a ROSA lab environment
export OIDC_ENDPOINT=$(oc get authentication.config.openshift.io cluster -o jsonpath='{.spec.serviceAccountIssuer}' | sed 's|^https://||')
echo $OIDC_ENDPOINT
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo $AWS_ACCOUNT_ID
export CLUSTER_VERSION=$(rosa describe cluster -c ${CLUSTER_NAME} -o json | jq -r .version.raw_id | cut -f -2 -d '.')
echo $CLUSTER_VERSION
export ROLE_NAME="${CLUSTER_NAME}-openshift-oadp-aws-cloud-credentials"
echo $ROLE_NAME
export SCRATCH="/tmp/${CLUSTER_NAME}/oadp"
echo $SCRATCH
mkdir -p ${SCRATCH}
echo "Cluster ID: ${ROSA_CLUSTER_ID}, Region: ${REGION}, S3 Region: ${S3_REGION}, OIDC Endpoint:
${OIDC_ENDPOINT}, AWS Account ID: ${AWS_ACCOUNT_ID}"
# NOTE: OIDC_ENDPONT is null in this RH demo environment, but the cluster isn't STS.
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
POLICY_ARN=$(aws iam create-policy --policy-name "RosaOadpVer1" \
--policy-document file:///${SCRATCH}/policy.json --query Policy.Arn \
--tags Key=rosa_openshift_version,Value=${CLUSTER_VERSION} Key=rosa_role_prefix,Value=ManagedOpenShift Key=operator_namespace,Value=open-cluster-management-backup Key=operator_name,Value=openshift-oadp \
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

# Note: for RHACM, the namespace is not default openshift-oadp, but is open-cluster-management-backup instead and operator name is redhat-oadp-operator
ROLE_ARN=$(aws iam create-role --role-name \
  "${ROLE_NAME}" \
   --assume-role-policy-document file://${SCRATCH}/trust-policy.json \
   --tags Key=rosa_cluster_id,Value=${ROSA_CLUSTER_ID} Key=rosa_openshift_version,Value=${CLUSTER_VERSION} Key=rosa_role_prefix,Value=ManagedOpenShift Key=operator_namespace,Value=open-cluster-management-backup Key=operator_name,Value=redhat-oadp-operator \
   --query Role.Arn --output text)

echo ${ROLE_ARN}

# Attach the IAM Policy to the IAM Role
aws iam attach-role-policy --role-name "${ROLE_NAME}" --policy-arn ${POLICY_ARN}
```

### Prepare Hub Cluster
```bash
# Create credentials file
cat <<EOF > ${SCRATCH}/credentials
[default]
role_arn = ${ROLE_ARN}
web_identity_token_file = /var/run/secrets/openshift/serviceaccount/token
EOF

cat ${SCRATCH}/credentials

# Create secret
oc create namespace open-cluster-management-backup
oc -n open-cluster-management-backup create secret generic cloud-credentials --from-file=${SCRATCH}/credentials

oc get -n open-cluster-management-backup secret cloud-credentials
```

#### Install OADP Operator
```bash
# It will be installed when setting cluster-backup: true in the mch
oc patch MultiClusterHub multiclusterhub -n open-cluster-management --type=json -p='[{"op": "add", "path": "/spec/overrides/components/-","value":{"name":"cluster-backup","enabled":true}}]'
# Wait until succeeded
echo "Waiting until ready (Succeeded)..."
oc get -n open-cluster-management-backup $(oc get csv -n open-cluster-management-backup -o name | grep oadp) -ojson | jq -r [.status.phase] |jq -r '.[]'
#status=$(oc get csv -n open-cluster-management-backup | grep OADP | awk '{print $6}')
status=$(oc get -n open-cluster-management-backup $(oc get csv -n open-cluster-management-backup -o name | grep oadp) -ojson | jq -r [.status.phase] |jq -r '.[]')
  oc get -n open-cluster-management-backup $(oc get csv -n open-cluster-management-backup -o name | grep oadp) -ojson | jq -r [.status.phase] |jq -r '.[]'
expected_condition="Succeeded"
timeout="300"
i=1
until [ "$status" = "$expected_condition" ]
do
  ((i++))
  oc get -n open-cluster-management-backup $(oc get csv -n open-cluster-management-backup -o name | grep oadp) -ojson | jq -r [.status.phase] |jq -r '.[]'
  if [ "${i}" -gt "${timeout}" ]; then
      echo "Sorry it took too long"
      exit 1
  fi

  sleep 3
done

echo "OK to proceed"
# NOTE: The script will initially check for resources that do not exist, but will eventually appear
```
## Enable managedserviceaccount-preview
```bash
oc patch multiclusterengine multiclusterengine --type=merge -p '{"spec":{"overrides":{"components":[{"name":"managedserviceaccount-preview","enabled":true}]}}}'
# Verify it is set to true
#oc get multiclusterengine multiclusterengine -oyaml |grep managedserviceaccount-preview -A1 | tail -1 | awk '{print $3}'
oc get multiclusterengine multiclusterengine -ojson | jq -r '.spec.overrides.components[] | select(.name == "console-mce")' | jq .enabled
```

#### Create AWS cloud storage using your AWS credentials
```bash
# Note: ensure namespace is open-cluster-management-backup
cat << EOF | oc create -f -
apiVersion: oadp.openshift.io/v1alpha1
kind: CloudStorage
metadata:
  name: rhacm-${ENV}-oadp
  namespace: open-cluster-management-backup
spec:
  creationSecret:
    key: credentials
    name: cloud-credentials
  enableSharedConfig: true
  name: rhacm-${ENV}-oadp
  provider: aws
# For passive cluster, use the region where bucket, not the cluster, is located,   
  region: $S3_REGION
EOF

# Verify name and region have expected values
oc get CloudStorage -n open-cluster-management-backup -oyaml
```
#### Create DataProtectionApplication CR
```bash
cat << EOF | oc create -f -
apiVersion: oadp.openshift.io/v1alpha1
kind: DataProtectionApplication
metadata:
  name: ${CLUSTER_NAME}-dpa
  namespace: open-cluster-management-backup
spec:
  backupLocations:
  - bucket:
      cloudStorageRef:
        name: rhacm-${ENV}-oadp
      credential:
        key: credentials
        name: cloud-credentials
      default: true
      config:
# For passive cluster, use the region where bucket, not the cluster, is located, 
        region: ${S3_REGION}
  configuration:
    velero:
      defaultPlugins:
      - openshift
      - aws
    restic:
      enable: false
  snapshotLocations:
    - velero:
        config:
          credentialsFile: /tmp/credentials/openshift-adp/cloud-credentials-credentials 
          enableSharedConfig: "true" 
          profile: default 
# For passive cluster, use the region where bucket, not the cluster, is located, 
          region: ${S3_REGION} 
        provider: aws
EOF

oc get DataProtectionApplication -n open-cluster-management-backup -oyaml
# Verify status is ok
oc get DataProtectionApplication -n open-cluster-management-backup -ojson | jq .items[].status

# Verify storage location is ok
oc get backupStorageLocations -n open-cluster-management-backup
sleep 30
oc get -n open-cluster-management-backup $(oc get backupStorageLocations -n open-cluster-management-backup -o name) -ojson | jq '.status'
oc get sc
```

### Prepare Passive Hub Cluster
```bash
# Perform same steps as active EXCEPT, adjust DataProtectionApplication and CloudStorage resources: set REGION variable to where the S3 bucket is located.
# When complete, check if backups are available (this will verify connectivity to backups in S3 created by active hub)
oc get backup -n open-cluster-management-backup
```


# Backup and Restore
## Schedule a backup on active cluster
```bash
oc create -f acm-dr/cluster_v1beta1_backupschedule_msa.yaml
```

### Check status of each backup component - this will check all backups, even older ones
```bash
oc get backup -n open-cluster-management-backup

# To wait for all to complete - this will check the latest of each type of backup
. ./acm-dr/is_backup_complete.sh
# It will progress from null > InProgress > Complete

# To get the status of just the most recent backups
oc get -n open-cluster-management-backup -o name $(oc get backup -n open-cluster-management-backup -o name | grep acm-credentials-schedule | tail -1) -ojson | jq -r .status.phase
oc get -n open-cluster-management-backup -o name $(oc get backup -n open-cluster-management-backup -o name | grep acm-managed-clusters-schedule | tail -1) -ojson | jq -r .status.phase
oc get -n open-cluster-management-backup -o name $(oc get backup -n open-cluster-management-backup -o name | grep acm-resources-generic-schedule | tail -1) -ojson | jq -r .status.phase
oc get -n open-cluster-management-backup -o name $(oc get backup -n open-cluster-management-backup -o name | grep acm-resources-schedule | tail -1) -ojson | jq -r .status.phase
oc get -n open-cluster-management-backup -o name $(oc get backup -n open-cluster-management-backup -o name | grep acm-validation-policy-schedule | tail -1) -ojson | jq -r .status.phase

# To check the status of ALL backups, and there might be a lot:
while true; do \
for backup in $(oc get backup -n open-cluster-management-backup -o name); do oc get -n open-cluster-management-backup $backup -ojson | jq -r .status.phase; done
sleep 3
done
```


### Verify ACM policy was created and is compliant
```bash
oc get policy -n open-cluster-management-backup
```

### Troubleshoot issues
```bash
oc get backupStorageLocations -n open-cluster-management-backup
oc describe -n open-cluster-management-backup $(oc get backupStorageLocations -n open-cluster-management-backup -o name)
oc get BackupSchedule -n open-cluster-management-backup
oc get schedules -n open-cluster-management-backup
oc describe BackupSchedule -n open-cluster-management-backup
oc get backup -n open-cluster-management-backup
# View "Items Backed Up" by one of the backups (this backup includes ACM stuff)
oc describe -n open-cluster-management-backup $(oc get backup -n open-cluster-management-backup -o name | grep acm-resources-schedule | tail -1) | grep "Phase:"
oc describe -n open-cluster-management-backup $(oc get backup -n open-cluster-management-backup -o name | grep acm-resources-schedule | head -1) | grep -A9 "Status:"
oc describe -n open-cluster-management-backup $(oc get backup -n open-cluster-management-backup -o name | grep acm-resources-schedule | head -1) | grep "Phase:"
# View contents of s3 bucket after backup
aws s3api list-objects --bucket rhacm-dr-failover-test-mmw --output table
```

## As a test, create an object on active hub to be restored
### oc login to active hub
### create new clusterset on the active hub
```bash
oc create -f acm-dr/create-clusterset-test-dr.yaml
oc get managedclustersets -n open-cluster-management
```
### Backup active hub
```bash
# Check backup schedule
oc get BackupSchedule -n open-cluster-management-backup
# Wait for next backup to complete or change in the cron setting
oc edit BackupSchedule -n open-cluster-management-backup
# Watch progress
# To wait for all to complete - this will check the latest of each type of backup
. ./acm-dr/is_backup_complete.sh
# It will progress from null > InProgress > Complete
```


## Restore on passive cluster
#### Regarding possible collision issues here:
##### https://github.com/stolostron/cluster-backup-operator#backup-collisions

### NOTE on Managed Clusters:
### Clusters created by ACM will be automatically imported (because it has a copy of kubeconfig).
### Clusters imported into ACM will be listed as Pending Import and must be re-imported. HOWEVER, there is a new feature to import automatically using a ManagedServiceAccount - which I will use below.

### oc login to passive hub
### Confirm the test-dr clusterset does NOT exist
```bash
oc get managedclustersets -n open-cluster-management
```

### Restore and keep restoring when new backups arrive (restore sync)
### NOTE: This will not restore managed clusters.
```bash
oc apply -f acm-dr/cluster_v1beta1_restore_passive_sync.yaml

# Check if complete
restore_status=$(oc get -n open-cluster-management-backup $(oc get restore -n open-cluster-management-backup -o name | tail -1) -ojson | jq -r .status.phase)
echo $restore_status
expected_condition="Enabled"
timeout="300"
i=1
until [ "$restore_status" = "$expected_condition" ]
do
  ((i++))
  restore_status=$(oc get -n open-cluster-management-backup $(oc get restore -n open-cluster-management-backup -o name | tail -1) -ojson | jq -r .status.phase)
  echo $restore_status
  if [ "${i}" -gt "${timeout}" ]; then
      echo "Sorry it took too long"
      exit 1
  fi

  sleep 3
done
echo "Restore Complete"
```

### View restore events
```bash
oc get restore -n open-cluster-management-backup
oc describe -n open-cluster-management-backup $(oc get restore -n open-cluster-management-backup -o name)
```

## Verify test-dr clusterset exists
```bash
oc get managedclustersets -n open-cluster-management
```

### Restore Managed Clusters - this will also make this the active cluster
### IMPORTANT: To ensure no collisions, login to active cluster and delete backup schedule
```bash
# oc login to active node
oc delete -n open-cluster-management-backup $(oc get backupschedule -n open-cluster-management-backup -o name)
```

### Now login to passive node
```bash
# oc login to passive node
# You can only have one active restore, so delete any existing ones
for restores in $(oc get restore -n open-cluster-management-backup -o name)
do
oc delete -n open-cluster-management-backup $restores
done

# Now perform the restore
oc apply -f acm-dr/cluster_v1beta1_restore_passive_activate.yaml

# Check if complete
restore_status=$(oc get -n open-cluster-management-backup $(oc get restore -n open-cluster-management-backup -o name | tail -1) -ojson | jq -r .status.phase)
echo $restore_status
expected_condition="Finished"
timeout="300"
i=1
until [ "$restore_status" = "$expected_condition" ]
do
  ((i++))
  restore_status=$(oc get -n open-cluster-management-backup $(oc get restore -n open-cluster-management-backup -o name | tail -1) -ojson | jq -r .status.phase)
  echo $restore_status
  if [ "${i}" -gt "${timeout}" ]; then
      echo "Sorry it took too long"
      exit 1
  fi

  sleep 5
done
echo "Restore Complete"

```
### Verify managed clusters were imported
```bash
oc get managedclusters
```

### Create backup
```bash
oc apply -f acm-dr/cluster_v1beta1_backupschedule_msa.yaml
```

## Verify
```bash
oc get backupStorageLocations -n open-cluster-management-backup
oc describe -n open-cluster-management-backup $(oc get backupStorageLocations -n open-cluster-management-backup -o name)
oc get BackupSchedule -n open-cluster-management-backup
oc get schedules -n open-cluster-management-backup
oc describe BackupSchedule -n open-cluster-management-backup
oc get backup -n open-cluster-management-backup
# View "Items Backed Up" by one of the backups (this backup includes ACM stuff)
oc describe -n open-cluster-management-backup $(oc get backup -n open-cluster-management-backup -o name | grep acm-resources-schedule | tail -1) | grep -A9 "Status:"
# View contents of s3 bucket after backup
aws s3api list-objects --bucket rhacm-dr-test-mmw --output table
```

## Troubleshooting backups and restores
### https://github.com/openshift/oadp-operator/blob/master/docs/TROUBLESHOOTING.md#backup
```bash
oc get backup -n open-cluster-management-backup
oc describe backup <backupName> -n open-cluster-management-backup
oc logs -f deploy/velero -n open-cluster-management-backup
alias velero='oc -n open-cluster-management-backup exec deployment/velero -c velero -it -- ./velero'
velero backup describe <backupName> --details
velero backup logs <backupName>
```
