```bash
# delete backup schedules:
oc delete -n open-cluster-management-backup $(oc get backupschedule -n open-cluster-management-backup -o name)

# delete restores:
for restores in $(oc get restore -n open-cluster-management-backup -o name)
do
oc delete -n open-cluster-management-backup $restores
done

# delete backups
for backups in $(oc get backup -n open-cluster-management-backup -o name)
do
oc delete -n open-cluster-management-backup $backups
done

# Delete dpa
oc delete dpa velero -n open-cluster-management-backup

# Delete secret
oc delete secret cloud-credentials -n open-cluster-management-backup

# Disable managedserviceaccount (optional)
oc patch multiclusterengine multiclusterengine --type=merge -p '{"spec":{"overrides":{"components":[{"name":"managedserviceaccount","enabled":false}]}}}'
# ACM 2.8 and older: oc patch multiclusterengine multiclusterengine --type=merge -p '{"spec":{"overrides":{"components":[{"name":"managedserviceaccount-preview","enabled":false}]}}}'

# Delete OADP (optional)
oc patch MultiClusterHub multiclusterhub -n open-cluster-management --type=json -p='[{"op": "add", "path": "/spec/overrides/components/-","value":{"name":"cluster-backup","enabled":false}}]'
```

# Cloud specific steps
```bash
# AWS non-STS
# Delete credentials file
rm ./credentials-velero

# Delete access key
aws iam list-access-keys --user-name velero
aws iam delete-access-key --access-key-id <ACCESS KEY ID> --user-name velero
aws iam create-access-key --user-name velero

# Delete policy
aws iam delete-user-policy --user-name velero --policy-name velero

# Delete IAM user
aws iam delete-user --user-name velero

# Empty and Delete bucket
BUCKET=rhacm-dr-test-mmw
aws s3api list-buckets --query "Buckets[].Name" | grep $BUCKET
aws s3 rm s3://$BUCKET --recursive
aws s3api delete-bucket --bucket $BUCKET
```

# AWS STS

# Azure

