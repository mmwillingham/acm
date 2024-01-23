ACM - Enable Observability
These are old steps and may need revising.

oc create namespace open-cluster-management-observability

DOCKER_CONFIG_JSON=`oc extract secret/pull-secret -n openshift-config --to=-`

oc create secret generic multiclusterhub-operator-pull-secret \
    -n open-cluster-management-observability \
    --from-literal=.dockerconfigjson="$DOCKER_CONFIG_JSON" \
    --type=kubernetes.io/dockerconfigjson

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

oc create -f thanos-object-storage.yaml -n open-cluster-management-observability

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

watch 'oc describe mco observability | grep -A 6 Status'

# If grafana is not in ACM console > Overview, moved to Infrastructure page

oc get routes -n open-cluster-management

https://grafana-open-cluster-management-observability.apps.cluster-tfh7h.sandbox506.opentlc.com/
