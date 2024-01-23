# ACM - Enable Observability
##### Instructions based on ACM 2.9 documentation
##### Reference: https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/2.9/html-single/observability/index
##### NOTE: See documentation for the following, as they are not addressed in the steps below:
##### - Modifying default retention
##### - Deploying on infra machine sets
##### - Excluding specific managed clusters from collecting observability data
##### - Disabling observability on all clusters or on a single cluster
##### - Removing observability
##### - Querying metrics using the observability API
##### - Exporting metrics to external endpoints
##### - Setting up the Grafana developer instance
##### - Custom alerts and rules
##### - SNO clusters
##### - Managing alerts (configuring Alertmanager, etc)
##### - Using managed cluster labels in Grafana
##### - Configuring search parameters


### Create namespace on ACM hub cluster
```bash
oc create namespace open-cluster-management-observability
```

### Generate pull-secret
#### If secret already exists in open-cluster-management namespace
```bash
DOCKER_CONFIG_JSON=`oc extract secret/multiclusterhub-operator-pull-secret -n open-cluster-management --to=-`
```
#### If not, copy from openshift-config
```bash
DOCKER_CONFIG_JSON=`oc extract secret/pull-secret -n openshift-config --to=-`
oc create secret generic multiclusterhub-operator-pull-secret \
    -n open-cluster-management-observability \
    --from-literal=.dockerconfigjson="$DOCKER_CONFIG_JSON" \
    --type=kubernetes.io/dockerconfigjson
```

### Create object storage and secret
#### Create thanos-object-storage.yaml based on your cloud provider
##### Example for AWS (non-STS)
```bash
BUCKET=acm-bucket-martin
REGION=us-east-2
AWS_ACCESS_KEY_ID=(redacted)
AWS_SECRET_ACCESS_KEY=(redacted)

aws s3api create-bucket --bucket $BUCKET --region $REGION --create-bucket-configuration LocationConstraint=$REGION
{
    "Location": "http://acm-bucket-martin.s3.amazonaws.com/"
}

S3_ENDPOINT=s3.amazonaws.com

cat << EOF > thanos-object-storage.yaml
apiVersion: v1
kind: Secret
metadata:
  name: thanos-object-storage
  namespace: open-cluster-management-observability
type: Opaque
stringData:
  thanos.yaml: |
    type: s3
    config:
      bucket: acm-bucket-martin
      endpoint: s3.amazonaws.com
      insecure: true
      access_key: (redacted)
      secret_key: (redacted)
EOF
```

##### Example for Azure
```bash
# use actual values for these
storage_account_name="mmwstorageaccount"
resource_group_name="openenv-v4z6r"
location="eastus"

az storage account create \
 - name $storage_account_name \
 - resource-group $resource_group_name \
 - location $location \
 - sku Standard_LRS \
 - kind StorageV2

# Take note of the information returned
account_key=$(az storage account keys list - resource-group $resource_group_name - account-name $storage_account_name | jq -r '.[] | select(.keyName == "key1") | .value')

YOUR_CONTAINER_NAME="observability"

cat << EOF > thanos-object-storage.yaml
apiVersion: v1
kind: Secret
metadata:
  name: thanos-object-storage
  namespace: open-cluster-management-observability
type: Opaque
stringData:
  thanos.yaml: |
    type: AZURE
    config:
      storage_account: $storage_account_name
      storage_account_key: $account_key
      container: $YOUR_CONTAINER_NAME
      endpoint: blob.core.windows.net 
      max_retries: 0
EOF
```

##### Example for AWS Security Service (I have not yet tested this)
##### Setup AWS environment (for AWS Security Service example)
```bash
export POLICY_VERSION=$(date +"%m-%d-%y")
export TRUST_POLICY_VERSION=$(date +"%m-%d-%y")
export CLUSTER_NAME=<my-cluster>
export S3_BUCKET=$CLUSTER_NAME-acm-observability
export REGION=us-east-2
export NAMESPACE=open-cluster-management-observability
export SA=tbd
export SCRATCH_DIR=/tmp/scratch
export OIDC_PROVIDER=$(oc get authentication.config.openshift.io cluster -o json | jq -r .spec.serviceAccountIssuer| sed -e "s/^https:\/\///")
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_PAGER=""
rm -rf $SCRATCH_DIR
mkdir -p $SCRATCH_DIR
```
##### Create bucket (for AWS Security Service example)
```bash
aws s3 mb s3://$S3_BUCKET
```
##### Create policy (for AWS Security Service example)
```bash
{
    "Version": "$POLICY_VERSION",
    "Statement": [
        {
            "Sid": "Statement",
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket",
                "s3:GetObject",
                "s3:DeleteObject",
                "s3:PutObject",
                "s3:PutObjectAcl",
                "s3:CreateBucket",
                "s3:DeleteBucket"
            ],
            "Resource": [
                "arn:aws:s3:::$S3_BUCKET/*",
                "arn:aws:s3:::$S3_BUCKET"
            ]
        }
    ]
 }
```
##### Apply policy (for AWS Security Service example)
```bash
S3_POLICY=$(aws iam create-policy --policy-name $CLUSTER_NAME-acm-obs \
--policy-document file://$SCRATCH_DIR/s3-policy.json \
--query 'Policy.Arn' --output text)
echo $S3_POLICY
```
##### Create TrustPolicy JSON file (for AWS Security Service example)
```bash
{
 "Version": "$TRUST_POLICY_VERSION",
 "Statement": [
   {
     "Effect": "Allow",
     "Principal": {
       "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
     },
     "Action": "sts:AssumeRoleWithWebIdentity",
     "Condition": {
       "StringEquals": {
         "${OIDC_PROVIDER}:sub": [
           "system:serviceaccount:${NAMESPACE}:observability-thanos-query",
           "system:serviceaccount:${NAMESPACE}:observability-thanos-store-shard",
           "system:serviceaccount:${NAMESPACE}:observability-thanos-compact"
           "system:serviceaccount:${NAMESPACE}:observability-thanos-rule",
           "system:serviceaccount:${NAMESPACE}:observability-thanos-receive",
         ]
       }
     }
   }
 ]
}
```
##### Apply policy (for AWS Security Service example)
```bash
S3_POLICY=$(aws iam create-policy --policy-name $CLUSTER_NAME-acm-obs \
--policy-document file://$SCRATCH_DIR/s3-policy.json \
--query 'Policy.Arn' --output text)
echo $S3_POLICY
```

##### Create role and attach policies to role (for AWS Security Service example)
```bash
S3_ROLE=$(aws iam create-role \
  --role-name "$CLUSTER_NAME-acm-obs-s3" \
  --assume-role-policy-document file://$SCRATCH_DIR/TrustPolicy.json \
  --query "Role.Arn" --output text)
echo $S3_ROLE
aws iam attach-role-policy \
  --role-name "$CLUSTER_NAME-acm-obs-s3" \
  --policy-arn $S3_POLICY
```
##### Create thanos-object-storage.yaml (for AWS Security Service example)
```bash
apiVersion: v1
kind: Secret
metadata:
  name: thanos-object-storage
  namespace: open-cluster-management-observability
type: Opaque
stringData:
  thanos.yaml: |
 type: s3
 config:
   bucket: $S3_BUCKET
   endpoint: s3.$REGION.amazonaws.com
   signature_version2: false
```

### Create thanos-object-storage secret
```bash
oc create -f thanos-object-storage.yaml -n open-cluster-management-observability
```

### Create MultiClusterObservability CR
```bash
cat << EOF > multiclusterobservability_cr.yaml
apiVersion: observability.open-cluster-management.io/v1beta2
kind: MultiClusterObservability
metadata:
  name: observability
spec:
  observabilityAddonSpec: {}
  storageConfig:
    metricObjectStorage:
      name: thanos-object-storage
      key: thanos.yaml
EOF
oc apply -f multiclusterobservability_cr.yaml
```
#### Verify progress
```bash
watch 'oc describe mco observability | grep -A 6 Status'
oc get deploy multicluster-observability-operator -n open-cluster-management --show-labels
```

### Click the Grafana link that is near the console header, from either the console Overview page or the Clusters page.

oc get routes -n open-cluster-management

https://grafana-open-cluster-management-observability.apps.cluster-tfh7h.sandbox506.opentlc.com/
