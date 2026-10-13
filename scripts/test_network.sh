#!/usr/bin/env bash
set -euo pipefail

FRONTEND=$(kubectl get pod -n app -l app=frontend -o name | cut -d/ -f2)
BACKEND=$(kubectl get pod -n app -l app=backend -o name | cut -d/ -f2)
CACHE=$(kubectl get pod -n app -l app=cache -o name | cut -d/ -f2)

echo "Проверка frontend и backend"
kubectl exec -n app "$FRONTEND" -- curl -s --connect-timeout 3 http://backend-svc || echo "BLOCKED (timeout)"
echo ""

echo "Проверка backend и cache"
kubectl exec -n app "$BACKEND" -- curl -s --connect-timeout 3 http://cache-svc || echo "BLOCKED (timeout)"
echo ""

echo "Проверка frontend и cache"
kubectl exec -n app "$FRONTEND" -- curl -s --connect-timeout 3 http://cache-svc || echo "BLOCKED (timeout)"
echo ""

echo "Проверка backend и frontend"
kubectl exec -n app "$BACKEND" -- curl -s --connect-timeout 3 http://frontend-svc || echo "BLOCKED (timeout)"
echo ""

echo "Проверка cache и backend"
kubectl exec -n app "$CACHE" -- curl -s --connect-timeout 3 http://backend-svc || echo "BLOCKED (timeout)"