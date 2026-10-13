#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="${ROOT_DIR}/terraform"
PROVIDER="${1:-cloudru}"
if [[ $# -gt 0 ]]; then
  shift
fi
if [[ ! "$PROVIDER" =~ ^(cloudru|yandex)$ ]]; then
  echo "Неверный провайдер: $PROVIDER" >&2
  echo "Использование: ./destroy.sh cloudru|yandex [аргументы Terraform]" >&2
  exit 1
fi

TFVARS_FILE="${TF_DIR}/terraform.tfvars.${PROVIDER}"
if [[ ! -f "$TFVARS_FILE" ]]; then
  TFVARS_FILE="${TF_DIR}/terraform.tfvars"
fi
if [[ ! -f "$TFVARS_FILE" ]]; then
  echo "Не найден файл параметров Terraform для $PROVIDER." >&2
  exit 1
fi

cd "$TF_DIR"
terraform init -input=false
if ! terraform workspace select "$PROVIDER"; then
  echo "Terraform workspace '$PROVIDER' не найден. Инфраструктура этого облака не развёрнута через deploy.sh." >&2
  exit 1
fi

# Удаляем инфраструктуру только из выбранного workspace.
echo "Terraform destroy: $PROVIDER"
terraform destroy -auto-approve -var-file="$TFVARS_FILE" -var="cloud_provider=$PROVIDER" "$@"

# Удаляем inventory, который Terraform создал для Kubespray.
echo "=== очистка inventory ==="
rm -f "$ROOT_DIR/ansible/inventory.yaml"

echo "=== destroy завершён ==="
