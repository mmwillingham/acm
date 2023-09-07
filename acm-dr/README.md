# RHACM DR
### References
#### https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/2.8/html-single/business_continuity/index
#### https://github.com/stolostron/cluster-backup-operator
#### https://github.com/stolostron/cluster-backup-operator/tree/main/config/samples
#### https://docs.openshift.com/container-platform/4.12/backup_and_restore/application_backup_and_restore/installing/installing-oadp-aws.html

# Assumptions
### - ACM is installed on both Active and Passive clusters - IN THE SAME NAMESPACES
### - All operators installed on Active are also be installed on passive cluster
    example: Ansible Automation Platform, Red Hat OpenShift GitOps, cert-manager, etc
### - User has cluster-admin access to Active and Passive clusters
### - Terminal shell to Active and Passive clusters
### - Shell has oc, aws, and jq clients
### - The aws cli has appropriate access to create AWS resources

# High level steps
## Prepare Active Hub Cluster
### Install OADP Operator
### Enable restore of imported managed clusters
### Create AWS S3 bucket
### Create IAM user
### Create policy file and attach to new IAM user
### Create access key for new IAM user
### Create credentials-velero file
### Create OCP secret from credentials-velero file
### Create DataProtectionApplication CR
## Prepare Passive Hub Cluster
### Install OADP Operator
### Create credentials-velero file (same content as above)
### Create OCP secret from credentials-velero file
### Create DataProtectionApplication CR
## Backup Active Hub Cluster
### Schedule a backup
## Restore (sync) to Passive Hub Cluster (all except managed clusters)
### oc apply -f acm-dr/cluster_v1beta1_restore_passive_sync.yaml


# Detailed Steps
# ACTIVE CLUSTER
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

## Download aws cli
### https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
# Verify
aws --version
```

## Create AWS S3 bucketand access to it
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

## Schedule a backup on active cluster
```bash
oc create -f acm-dr/cluster_v1beta1_backupschedule_msa.yaml
```

### Check status of each backup component - this will check all backups, even older ones
```bash
oc get backup -n open-cluster-management-backup
for backup in $(oc get backup -n open-cluster-management-backup -o name); do oc get -n open-cluster-management-backup $backup -ojson | jq -r .status.phase; done

# If you don't have jq
for backup in $(oc get backup -n open-cluster-management-backup -o name); do oc get -n open-cluster-management-backup $backup -ojsonpath='{.status.phase}'; done

# To get the status of just the most recent backups
oc get -n open-cluster-management-backup -o name $(oc get backup -n open-cluster-management-backup -o name | grep acm-credentials-schedule | tail -1) -ojson | jq -r .status.phase
oc get -n open-cluster-management-backup -o name $(oc get backup -n open-cluster-management-backup -o name | grep acm-managed-clusters-schedule | tail -1) -ojson | jq -r .status.phase
oc get -n open-cluster-management-backup -o name $(oc get backup -n open-cluster-management-backup -o name | grep acm-resources-generic-schedule | tail -1) -ojson | jq -r .status.phase
oc get -n open-cluster-management-backup -o name $(oc get backup -n open-cluster-management-backup -o name | grep acm-resources-schedule | tail -1) -ojson | jq -r .status.phase
oc get -n open-cluster-management-backup -o name $(oc get backup -n open-cluster-management-backup -o name | grep acm-validation-policy-schedule | tail -1) -ojson | jq -r .status.phase

# To wait for all to complete - this will check the latest of each type of backup
. ./acm-dr/is_backup_complete.sh
# It will progress from null > InProgress > Complete
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
### Backup active hub - or wait for backup schedule interval - or change schedule in cluster_v1beta1_backupschedule_msa.yaml and apply
```bash
TODO commands
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

## Restore on passive cluster
### Read the possible collision issues here:
### https://github.com/stolostron/cluster-backup-operator#backup-collisions
### Restore and keep synced
#### https://github.com/stolostron/cluster-backup-operator/blob/main/config/samples/cluster_v1beta1_restore_passive_sync.yaml
### Activate passive to active
#### https://github.com/stolostron/cluster-backup-operator/blob/main/config/samples/cluster_v1beta1_restore_passive_activate.yaml

## oc login to passive hub
## Confirm the test-dr clusterset does NOT exist
```bash
oc get managedclustersets -n open-cluster-management
```

## Restore
### NOTE on Managed Clusters:
### Clusters created by ACM will be automatically imported (because it has a copy of kubeconfig).
### Clusters imported into ACM will be listed as Pending Import and must be re-imported.
### HOWEVER, there is a new feature to import automatically using a ManagedServiceAccount - which I will use below
#### https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/2.8/html-single/business_continuity/index#auto-connect-clusters-msa
#### https://github.com/stolostron/cluster-backup-operator/tree/main#automatically-connecting-clusters-using-managedserviceaccount---tech-preview


### Restore and keep restoring when new backups arrive (restore sync)
### NOTE: This will not restore managed clusters.
```bash
oc apply -f acm-dr/cluster_v1beta1_restore_passive_sync.yaml
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
### NOTE: Shutdown original active cluster
```bash
oc apply -f acm-dr/cluster_v1beta1_restore_passive_activate.yaml
```
### Verify managed clusters were imported
```bash
oc get managedclusters
```

### Create backup
```bash
cluster_v1beta1_backupschedule_msa.yaml
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
