#!/bin/bash

timeout="300"
expected_condition="Succeeded"
#expected_condition="NotSucceeded"

echo "Waiting until ACM Operator is ready (Succeeded)..."
i=1

until [ $operator_status = "$expected_condition" ]

do
  ((i++))
  operator_status=$(oc get csv | grep advanced-cluster-management | awk '{print $8}')
  oc get csv | grep advanced-cluster-management

  if [ "${i}" -gt "${timeout}" ]; then
      exit 1
  fi

  sleep 1
done

echo "OK to proceed with next step"
