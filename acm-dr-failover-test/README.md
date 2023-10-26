# NOTE: This information is a little stale. Check with acm-dr/README.md for latest process and scripts.

# hello world
## The purpose of this procedure is to test the failover from an active to passive ACM hub cluster.
### This test includes migration of two managed clusters:
### managed1: Imported into Primary ACM cluster
### managed2: Created by Primary ACM cluster

## Steps:

### 1. Create three instances at demo.redhat.com > Catalog > Open Environments > AWS with ROSA Open Environment
#### Primary
#### Passive
#### managed1

### 2. Prepare Primary and Passive hub clusters (using steps from install-acm folder in this repo)
#### Primary: Install ACM and clusterSets: hub and managed
#### Passive: Install ACM and clusterSets: hub

### 3. Import managed1 cluster into Primary hub (using manual steps on console)

### 4. Create managed2 cluster from Primary hub (using manual steps on console)
```
# Create namespace for credential: aws-cred
oc new-project aws-cred
# Create aws credential: aws-cred
  Base: DNS domain: zjf6x.sandbox2151.opentlc.com
  Access key: redacted
  Secret: redacted
  Pull secret: https://console.redhat.com/openshift/install/pull-secret
  Private key and public key: <get from /home/mwilling/.ssh> or create one with ssh-keygen
# Create cluster
  Cred: aws-cred
  Cluster name: managed2
  Cluster set: managed
  Base: DNS domain: zjf6x.sandbox2151.opentlc.com # Get this from demo.redhat.com resource for the Primary cluster
  Release: OpenShift 4.12.31
  Region: us-east-2
  Arch: amd64
  Create!
```

### 5. Create backup system on Active and Passive hubs (see acm-dr folder in this repo)

#### Active:
```
Install OADP Operator
Enable managedserviceaccount-preview
Create bucket and access to it
  BUCKET=rhacm-dr-failover-test-mmw
Create DataProtectionApplication CR
  # Change name in dpa.yaml to bucket specified above
```
#### Passive:
```
Install OADP Operator
Enable managedserviceaccount-preview
Create a Secret with the default name - using same credentials as above
  vi credentials-velero # Add contents from Primary steps
  oc create secret generic cloud-credentials -n open-cluster-management-backup --from-file cloud=credentials-velero
Create DataProtectionApplication CR # Verify bucket name is correct in dpa.yaml
Verify success
  oc get backupStorageLocations -n open-cluster-management-backup
  oc describe -n open-cluster-management-backup $(oc get backupStorageLocations -n open-cluster-management-backup -o name)
```

### Active: Backup
```
Schedule a backup on active cluster
  oc create -f acm-dr/cluster_v1beta1_backupschedule_msa.yaml
Verify
  watch oc get backup -n open-cluster-management-backup
  oc get -n open-cluster-management-backup $(oc get backup -n open-cluster-management-backup -o name | grep acm-managed-clusters |tail -1) -oyaml
  oc get -n open-cluster-management-backup $(oc get backup -n open-cluster-management-backup -o name | grep acm-resources |tail -1) -oyaml
```

### 6. Passive: Restore everything except managed clusters - and keep in sync with backups on Primary hub
```
Restore
  oc create -f acm-dr/cluster_v1beta1_restore_passive_sync.yaml
Verify restore ran successfully
  watch oc get restore -n open-cluster-management-backup
  oc describe -n open-cluster-management-backup $(oc get restore -n open-cluster-management-backup -o name |  head -1) | grep -A9 "Status:"
  oc describe -n open-cluster-management-backup $(oc get restore -n open-cluster-management-backup -o name |  head -1)
Verify managed clusterset (and any other ACM data created on the Primary hub) exists on Passive (policies, applications, etc.)
This will not include managed clusters.
  oc get managedclustersets -n open-cluster-management
```

### 7. Failover from Primary to Passive (Passive will import managed clusters)
```
Primary:
  - To simulate controlled failover, delete backupschedule
      oc delete -f acm-dr/cluster_v1beta1_backupschedule_msa.yaml
      Stop Primary cluster (how to best do this in a real environment?)
  - To simulate unplanned failover (disaster on Primary)
      Stop Primary cluster
Restore on Passive hub
If you already restored in the previous step and it's up to date:
  oc delete -f acm-dr/cluster_v1beta1_restore_passive_sync.yaml
  oc create -f acm-dr/cluster_v1beta1_restore_passive_activate.yaml
  watch oc get restore -n open-cluster-management-backup
  oc describe -n open-cluster-management-backup $(oc get restore -n open-cluster-management-backup -o name |  head -1) | grep -A9 "Status:"
  oc describe -n open-cluster-management-backup $(oc get restore -n open-cluster-management-backup -o name |  head -1)
If you have not already run a restore:
  oc create -f acm-dr/cluster_v1beta1_restore_passive_sync.yaml
  watch oc get restore -n open-cluster-management-backup
  oc delete -f acm-dr/cluster_v1beta1_restore_passive_sync.yaml
  oc create -f acm-dr/cluster_v1beta1_restore_passive_activate.yaml
It is also possible to create a restore job that restores everything with a single restore.
  oc delete -f acm-dr/cluster_v1beta1_restore_passive_sync.yaml
  oc create -f acm-dr/cluster_v1beta1_restore_passive_all.yaml
Verify
  oc get managedclusters
Create backup - this will make it the active hub
  oc create -f acm-dr/cluster_v1beta1_backupschedule_msa.yaml
```
### 8. Failback
```
On passive hub, delete backupschedule. This will ensure no data collisions when it comes back online.
  oc delete -f acm-dr/cluster_v1beta1_backupschedule_msa.yaml
On passive hub, also delete restores (delete whichever ones you created above)
  oc delete -f acm-dr/cluster_v1beta1_restore_passive_sync.yaml
  oc delete -f acm-dr/cluster_v1beta1_restore_passive_activate.yaml
  oc delete -f acm-dr/cluster_v1beta1_restore_passive_all.yaml
Stop Passive cluster (not really necessary if doing previous step)
Start Primary cluster
  If recovering from controlled failover, everything should be good because no backupschedule exists
  If recovering from unplanned failover, backupschedule will exist, but system has logic to deal with collisions (see https://github.com/stolostron/cluster-backup-operator#backup-collisions)
  To best deal with it, delete backupschedule
    oc delete -f acm-dr/cluster_v1beta1_backupschedule_msa.yaml
Restore data and make it active
  oc create -f acm-dr/cluster_v1beta1_restore_passive_all.yaml
  watch oc get restore -n open-cluster-management-backup
When complete, delete the restore
  oc delete -f acm-dr/cluster_v1beta1_restore_passive_all.yaml

Verify
  oc get managedclusters
Create backup on Primary - this will make it the active hub again
  oc create -f acm-dr/cluster_v1beta1_backupschedule_msa.yaml
  watch oc get backup -n open-cluster-management-backup
```
