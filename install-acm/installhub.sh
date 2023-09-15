#!/bin/bash
# This should be able to be run multiple times without issue.

# Create project
# The double command will ensure the command will exit 0
oc new-project open-cluster-management || oc project open-cluster-management

# Create Operator Group and Subscription
oc apply -f install-acm/install-acm-operator.yaml

# Approve Install Plan - not required with Automatic approval of subscription
# oc patch installplan install-4k2q8 --type merge --patch '{"spec":{"approved":true}}'

# Check if it's ready
#oc get csv | grep advanced-cluster-management | grep Succeeded

echo "Waiting until ACM Operator is ready (Succeeded)..."
export status=$(oc get $(oc get csv -n open-cluster-management -o name | grep advanced-cluster-management) -ojson | jq -r '.status.phase')
oc get csv -n open-cluster-management | grep advanced-cluster-management | awk '{print $1, $NF}'
expected_condition="Succeeded"
timeout="300"
i=1
until [ "$status" = "$expected_condition" ]
do
  ((i++))
  export status=$(oc get $(oc get csv -n open-cluster-management -o name | grep advanced-cluster-management) -ojson | jq -r '.status.phase')
  oc get csv -n open-cluster-management | grep advanced-cluster-management | awk '{print $1, $NF}'
  if [ "${i}" -gt "${timeout}" ]; then
      echo "Sorry it took too long"
      exit 1
  fi

  sleep 3
done

# Note, this loop is not exiting correctly when Succeeded. CTRL-C to cancel the loop once it reports as Succeeded - or fix the loop issue.
echo "OK to proceed with next step"

# Install MultiClusterHub
oc apply -f install-acm/multiclusterhub.yaml

# Check if it's ready: status.phase=Running
# oc -n open-cluster-management get mch -o=jsonpath='{.items[0].status.phase}'
# oc -n open-cluster-management get mch | grep multiclusterhub | awk '{print $2}'

echo "Waiting until ACM MCH is ready (Running)..."
sleep 5
mch_status=$(oc get -n open-cluster-management $(oc -n open-cluster-management get mch -o name) -ojson | jq -r '.status.phase')
oc -n open-cluster-management get mch | grep multiclusterhub | awk '{print $2}'
expected_condition="Running"
timeout="3600"
i=1
until [ "$mch_status" = "$expected_condition" ]
do
  ((i++))
  mch_status=$(oc get -n open-cluster-management $(oc -n open-cluster-management get mch -o name) -ojson | jq -r '.status.phase')
  oc -n open-cluster-management get mch | grep multiclusterhub
  if [ "${i}" -gt "${timeout}" ]; then
      echo "Sorry it took too long"
      exit 1
  fi
  sleep 5
done
echo "OK to proceed with next step"

