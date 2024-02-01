# RHACM DR
## ACM Storage Design
![ACM Storage Design](/acm-dr/cluster_backup_controller_dataflow25.png)
### ACM Normal Backup Operation
![ACM Normal Backup Operation](/acm-dr/acm_active_passive_config_design.png)
### ACM DR Failover Process
![ACM DR Failover Process](/acm-dr/acm_disaster_recovery.png)
#
### References
#### https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/2.9/html-single/business_continuity/index
#### https://github.com/stolostron/cluster-backup-operator
#### https://github.com/stolostron/cluster-backup-operator/tree/main/config/samples
#### https://docs.openshift.com/container-platform/4.12/backup_and_restore/application_backup_and_restoreopen-cluster-management-backup/installing/installing-oadp-aws.html
#### https://docs.openshift.com/container-platform/4.12/backup_and_restore/application_backup_and_restore/installing/installing-oadp-azure.html
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

## Three options are described
### Option 1: AWS connections using IAM user (non-STS)
### Option 2: AWS connections using STS
### Option 3: Azure

# Detailed Steps
# Option 1: AWS (non-STS)
## Configure prerequisite storage
### see configure_storage_aws_non-sts.md
## ACTIVE CLUSTER
### Install OADP Operator # It will be installed when setting cluster-backup: true in the mch
```bash
oc patch MultiClusterHub multiclusterhub -n open-cluster-management --type=json -p='[{"op": "add", "path": "/spec/overrides/components/-","value":{"name":"cluster-backup","enabled":true}}]'
# Wait until succeeded
oc get -n open-cluster-management-backup $(oc get csv -n open-cluster-management-backup -o name | grep oadp) -ojson | jq -r [.status.phase] |jq -r '.[]'
```

### Enable restore of imported managed clusters
```bash
# ACM 2.8 and older: oc patch multiclusterengine multiclusterengine --type=merge -p '{"spec":{"overrides":{"components":[{"name":"managedserviceaccount-preview","enabled":true}]}}}'
oc patch multiclusterengine multiclusterengine --type=merge -p '{"spec":{"overrides":{"components":[{"name":"managedserviceaccount","enabled":true}]}}}'
# Verify it is set to true
oc get multiclusterengine multiclusterengine -ojson | jq -r '.spec.overrides.components[] | select(.name == "console-mce")' | jq .enabled
```

### Create a Secret with the default name:
```bash
oc create secret generic cloud-credentials -n open-cluster-management-backup --from-file cloud=credentials-velero
```

### Create DataProtectionApplication CR
#### Change name in dpa.yaml to bucket specified above
```bash
oc create -f acm-dr/dpa.yaml
# Wait until complete
    oc get dpa -n open-cluster-management-backup velero -ojson | jq '.status.conditions[] | select(.reason == "Complete")'
```

#### Verify success
```bash
oc get all -n open-cluster-management-backup
oc get pods -n open-cluster-management-backup
```

# PASSIVE CLUSTER
### Repeat steps above for installing oadp using same secret
### Install OADP Operator # It will be installed when setting cluster-backup: true in the mch
```bash
oc patch MultiClusterHub multiclusterhub -n open-cluster-management --type=json -p='[{"op": "add", "path": "/spec/overrides/components/-","value":{"name":"cluster-backup","enabled":true}}]'
# Wait until succeeded
oc get -n open-cluster-management-backup $(oc get csv -n open-cluster-management-backup -o name | grep oadp) -ojson | jq -r [.status.phase] |jq -r '.[]'
```
### Enable managedserviceaccount-preview
```bash
# ACM 2.8 and older: oc patch multiclusterengine multiclusterengine --type=merge -p '{"spec":{"overrides":{"components":[{"name":"managedserviceaccount-preview","enabled":true}]}}}'
oc patch multiclusterengine multiclusterengine --type=merge -p '{"spec":{"overrides":{"components":[{"name":"managedserviceaccount","enabled":true}]}}}'
# Verify it is set to true
oc get multiclusterengine multiclusterengine -ojson | jq -r '.spec.overrides.components[] | select(.name == "console-mce")' | jq .enabled

```

### Create a Secret with the default name
#### Note: you will need to create the same file that was created above
```bash
oc create secret generic cloud-credentials -n open-cluster-management-backup --from-file cloud=credentials-velero
```

### Create DataProtectionApplication CR
#### Change name in dpa.yaml to bucket specified above
```bash
oc create -f acm-dr/dpa.yaml
# Wait until complete
    oc get dpa -n open-cluster-management-backup velero -ojson | jq '.status.conditions[] | select(.reason == "Complete")'
```

#### Verify success
```bash
oc get all -n open-cluster-management-backup
```

#### Verify ACM policy was created and it compliant
```bash
oc get policy -n open-cluster-management-backup
```
# Proceed to "Backup and Restore" section below.


#  Option 2: AWS STS
### see configure_storage_aws_sts.md

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
oc get -n open-cluster-management-backup $(oc get csv -n open-cluster-management-backup -o name | grep oadp) -ojson | jq -r [.status.phase] |jq -r '.[]'
```
## Enable managedserviceaccount-preview
```bash
oc patch multiclusterengine multiclusterengine --type=merge -p '{"spec":{"overrides":{"components":[{"name":"managedserviceaccount-preview","enabled":true}]}}}'
# Verify it is set to true
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
# Wait for the status to be "Available"
oc get sc
```

### Prepare Passive Hub Cluster
```bash
# Perform same steps as active EXCEPT, adjust DataProtectionApplication and CloudStorage resources: set REGION variable to where the S3 bucket is located.
# When complete, check if backups are available (this will verify connectivity to backups in S3 created by active hub)
oc get backup -n open-cluster-management-backup
```
# Proceed to "Backup and Restore" section below.


# Option 3: Azure
### Prepare storage
#### see configure_storage_azure.md

## ACTIVE CLUSTER
## Install OADP Operator # It will be installed when setting cluster-backup: true in the mch
```bash
oc patch MultiClusterHub multiclusterhub -n open-cluster-management --type=json -p='[{"op": "add", "path": "/spec/overrides/components/-","value":{"name":"cluster-backup","enabled":true}}]'
# Wait until succeeded
oc get -n open-cluster-management-backup $(oc get csv -n open-cluster-management-backup -o name | grep oadp) -ojson | jq -r [.status.phase] |jq -r '.[]'
```

## Enable restore of imported managed clusters
```bash
# ACM 2.8 and older: oc patch multiclusterengine multiclusterengine --type=merge -p '{"spec":{"overrides":{"components":[{"name":"managedserviceaccount-preview","enabled":true}]}}}'
oc patch multiclusterengine multiclusterengine --type=merge -p '{"spec":{"overrides":{"components":[{"name":"managedserviceaccount","enabled":true}]}}}'
# Verify it is set to true
oc get multiclusterengine multiclusterengine -ojson | jq -r '.spec.overrides.components[] | select(.name == "console-mce")' | jq .enabled
```

## Create a Secret with the default name (see documentation for using a different credential)
```bash
oc create secret generic cloud-credentials-azure -n open-cluster-management-backup --from-file cloud=credentials-velero
```

## Create DataProtectionApplication CR
### IMPORTANT: Change values in dpa_azure.yaml to use details obtained above
```bash
oc create -f acm-dr/dpa_azure.yaml
# Wait until complete
oc get dpa -n open-cluster-management-backup velero -ojson | jq '.status.conditions[] | select(.reason == "Complete")'
```

### Verify success
```bash
oc get all -n open-cluster-management-backup
oc get pods -n open-cluster-management-backup
```

# PASSIVE CLUSTER
## Repeat steps above for installing oadp using same secret
## Install OADP Operator # It will be installed when setting cluster-backup: true in the mch
```bash
oc patch MultiClusterHub multiclusterhub -n open-cluster-management --type=json -p='[{"op": "add", "path": "/spec/overrides/components/-","value":{"name":"cluster-backup","enabled":true}}]'
# Wait until succeeded
oc get -n open-cluster-management-backup $(oc get csv -n open-cluster-management-backup -o name | grep oadp) -ojson | jq -r [.status.phase] |jq -r '.[]'
```
## Enable managedserviceaccount-preview
```bash
#ACM 2.8 and older: oc patch multiclusterengine multiclusterengine --type=merge -p '{"spec":{"overrides":{"components":[{"name":"managedserviceaccount-preview","enabled":true}]}}}'
oc patch multiclusterengine multiclusterengine --type=merge -p '{"spec":{"overrides":{"components":[{"name":"managedserviceaccount","enabled":true}]}}}'
# Verify it is set to true
oc get multiclusterengine multiclusterengine -ojson | jq -r '.spec.overrides.components[] | select(.name == "console-mce")' | jq .enabled
```

## Create a Secret with the default name
### Note: you will need to create the same file that was created above
```bash
oc create secret generic cloud-credentials-azure -n openshift-adp --from-file cloud=credentials-velero
```

## Create DataProtectionApplication CR
### Change name in dpa.yaml to bucket specified above
```bash
oc create -f acm-dr/dpa.yaml
# Wait until complete
    oc get dpa -n open-cluster-management-backup velero -ojson | jq '.status.conditions[] | select(.reason == "Complete")'
```

### Verify success
```bash
oc get all -n open-cluster-management-backup
```

### Verify ACM policy was created and it compliant
```bash
oc get policy -n open-cluster-management-backup
```
## Proceed to "Backup and Restore" section below.

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
oc get -n open-cluster-management-backup $(oc get restore -n open-cluster-management-backup -o name | tail -1) -ojson | jq -r .status.phase
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
oc get -n open-cluster-management-backup $(oc get restore -n open-cluster-management-backup -o name | tail -1) -ojson | jq -r .status.phase

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
# If everything works on active cluster, and passive says the cloudstorage and dpa are available, but it doesn't list the backups, check the velero pod logs. May say something like this
# time="2023-09-25T18:34:56Z" level=error msg="Error getting backup metadata from backup store" backup=acm-resources-generic-schedule-20230925173327 backupLocation=dl-rosa10-2s-dpa-1 controller=backup-sync error="rpc error: code = Unknown desc = error getting object backups/acm-resources-generic-schedule-20230925173327/velero-backup.json: AccessDenied: User: arn:aws:sts::693101272312:assumed-role/delegate-admin-rhacm-bkp-restore-us-west-2/1695666895356145449 is not authorized to perform: kms:Decrypt on resource: arn:aws:kms:us-east-1:693101272312:key/dfa432ed-0f3a-45a0-b545-617cadb64911 because no identity-based policy allows the kms:Decrypt action\n\tstatus code: 403, request id: 4MAQKWC0BMJXSCJ8, host id: kdjIg/Iiz/8kGodFriPLyu837ouYE/Mewwynv0pfrw+KVtMB4g+PPoTREnEPlG5eWVKTtNs5rag=" error.file="/remote-source/velero/app/pkg/persistence/object_store.go:294" error.function="github.com/vmware-tanzu/velero/pkg/persistence.(*objectBackupStore).GetBackupMetadata" logSource="/remote-source/velero/app/pkg/controlle...
# Customer switched and used same KMS Key ID as was used in primary AWS region. Then it worked.
```
