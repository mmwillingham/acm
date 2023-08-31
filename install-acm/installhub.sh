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
expected_condition="Succeeded"
timeout="300"
i=1
until [ "$operator_status" = "$expected_condition" ]
do
  ((i++))
  # acm v2.8.1:
  operator_status=$(oc get csv -n open-cluster-management | grep advanced-cluster-management | awk '{print $9}')
  # acm v2.7 and v2.8:
  # operator_status=$(oc get csv -n open-cluster-management | grep advanced-cluster-management | awk '{print $8}')
  # acm v2.6
  # operator_status=$(oc get csv -n open-cluster-management | grep advanced-cluster-management | awk '{print $9}')
  oc get csv -n open-cluster-management | grep advanced-cluster-management

  if [ "${i}" -gt "${timeout}" ]; then
      echo "Sorry it took too long"
      exit 1
  fi

  sleep 3
done
echo "OK to proceed with next step"

# Install MultiClusterHub
oc apply -f install-acm/multiclusterhub.yaml

# Check if it's ready: status.phase=Running
# oc -n open-cluster-management get mch -o=jsonpath='{.items[0].status.phase}'
# oc -n open-cluster-management get mch | grep multiclusterhub | awk '{print $2}'

echo "Waiting until ACM MCH is ready (Running)..."
timeout="3600"
expected_condition="Running"
i=1
until [ "$operator_status" = "$expected_condition" ]
do
  ((i++))
  operator_status=$(oc -n open-cluster-management get mch | grep multiclusterhub | awk '{print $2}')
  oc -n open-cluster-management get mch | grep multiclusterhub

  if [ "${i}" -gt "${timeout}" ]; then
      echo "Sorry it took too long"
      exit 1
  fi
  sleep 5
done
echo "OK to proceed with next step"

