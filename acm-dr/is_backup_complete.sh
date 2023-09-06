#!/bin/bash

acm_backup=acm-credentials-schedule
acm_backup_result() {
    oc get csv -n open-cluster-management-backup | grep OADP
}

acm_backup_result=$(oc get -n open-cluster-management-backup -o name $(oc get backup -n open-cluster-management-backup -o name | grep $acm_backup | tail -1) -ojson | jq -r .status.phase)
echo $acm_backup $acm_backup_result
expected_condition="Completed"
timeout="300"
i=1
until [ "$acm_backup_result" = "$expected_condition" ]
do
  ((i++))
  acm_backup_result=$(oc get -n open-cluster-management-backup -o name $(oc get backup -n open-cluster-management-backup -o name | grep $acm_backup | tail -1) -ojson | jq -r .status.phase)
  echo $acm_backup $acm_backup_result
  if [ "${i}" -gt "${timeout}" ]; then
      echo "Sorry it took too long"
      exit 1
  fi

  sleep 3
done
#echo "OK to proceed with next step"

acm_backup=acm-managed-clusters-schedule
acm_backup_result=$(oc get -n open-cluster-management-backup -o name $(oc get backup -n open-cluster-management-backup -o name | grep $acm_backup | tail -1) -ojson | jq -r .status.phase)
echo $acm_backup $acm_backup_result
expected_condition="Completed"
timeout="300"
i=1
until [ "$acm_backup_result" = "$expected_condition" ]
do
  ((i++))
  acm_backup_result=$(oc get -n open-cluster-management-backup -o name $(oc get backup -n open-cluster-management-backup -o name | grep $acm_backup | tail -1) -ojson | jq -r .status.phase)
  echo $acm_backup $acm_backup_result

  if [ "${i}" -gt "${timeout}" ]; then
      echo "Sorry it took too long"
      exit 1
  fi

  sleep 3
done
#echo "OK to proceed with next step"

acm_backup=acm-resources-generic-schedule
acm_backup_result=$(oc get -n open-cluster-management-backup -o name $(oc get backup -n open-cluster-management-backup -o name | grep $acm_backup | tail -1) -ojson | jq -r .status.phase)
echo $acm_backup $acm_backup_result
expected_condition="Completed"
timeout="300"
i=1
until [ "$acm_backup_result" = "$expected_condition" ]
do
  ((i++))
  acm_backup_result=$(oc get -n open-cluster-management-backup -o name $(oc get backup -n open-cluster-management-backup -o name | grep $acm_backup | tail -1) -ojson | jq -r .status.phase)
  echo $acm_backup $acm_backup_result

  if [ "${i}" -gt "${timeout}" ]; then
      echo "Sorry it took too long"
      exit 1
  fi

  sleep 3
done
#echo "OK to proceed with next step"

acm_backup=acm-resources-schedule
acm_backup_result=$(oc get -n open-cluster-management-backup -o name $(oc get backup -n open-cluster-management-backup -o name | grep $acm_backup | tail -1) -ojson | jq -r .status.phase)
echo $acm_backup $acm_backup_result
expected_condition="Completed"
timeout="300"
i=1
until [ "$acm_backup_result" = "$expected_condition" ]
do
  ((i++))
  acm_backup_result=$(oc get -n open-cluster-management-backup -o name $(oc get backup -n open-cluster-management-backup -o name | grep $acm_backup | tail -1) -ojson | jq -r .status.phase)
  echo $acm_backup $acm_backup_result

  if [ "${i}" -gt "${timeout}" ]; then
      echo "Sorry it took too long"
      exit 1
  fi

  sleep 3
done
#echo "OK to proceed with next step"

acm_backup=acm-validation-policy-schedule
acm_backup_result=$(oc get -n open-cluster-management-backup -o name $(oc get backup -n open-cluster-management-backup -o name | grep $acm_backup | tail -1) -ojson | jq -r .status.phase)
echo $acm_backup $acm_backup_result
expected_condition="Completed"
timeout="300"
i=1
until [ "$acm_backup_result" = "$expected_condition" ]
do
  ((i++))
  acm_backup_result=$(oc get -n open-cluster-management-backup -o name $(oc get backup -n open-cluster-management-backup -o name | grep $acm_backup | tail -1) -ojson | jq -r .status.phase)
  echo $acm_backup $acm_backup_result

  if [ "${i}" -gt "${timeout}" ]; then
      echo "Sorry it took too long"
      exit 1
  fi

  sleep 3
done
#echo "OK to proceed with next step"
