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
