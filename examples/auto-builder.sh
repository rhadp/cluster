#!/usr/bin/env bash
source venv/bin/activate
set -e

NAMESPACE="automotive-dev-operator-system"

oc delete operatorconfig config -n $NAMESPACE
oc apply -f examples/oc-auto-builder.yaml 
