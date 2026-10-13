#!/usr/bin/env bash
set -euo pipefail

# Пути к Terraform, Kubespray и SSH-ключу.
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="${ROOT_DIR}/terraform"
ANSIBLE_DIR="${ROOT_DIR}/ansible"
KUBESPRAY_VERSION="v2.32.0"
KUBESPRAY_DIR="${ANSIBLE_DIR}/.kubespray-${KUBESPRAY_VERSION}"
VENV_DIR="${ANSIBLE_DIR}/.venv-kubespray"
INVENTORY_DIR="${KUBESPRAY_DIR}/inventory/project"
SSH_PRIVATE_KEY_PATH="${SSH_PRIVATE_KEY_PATH:-${HOME}/.ssh/yandex}"

# Первый аргумент задаёт облако, остальные передаются Terraform.
PROVIDER="${1:-cloudru}"
if [[ $# -gt 0 ]]; then
  shift
fi
if [[ ! "$PROVIDER" =~ ^(cloudru|yandex)$ ]]; then
  echo "Неизвестное облако: $PROVIDER" >&2
  echo "Использование: ./deploy.sh cloudru|yandex [аргументы Terraform]" >&2
  exit 1
fi

if [[ "$PROVIDER" == "cloudru" ]]; then
  OTHER_PROVIDER="yandex"
else
  OTHER_PROVIDER="cloudru"
fi

# Проверяем необходимые команды и файлы настроек.
for command_name in git terraform python3 ssh-agent ssh-add ssh-keygen; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "Не найдена обязательная команда: $command_name" >&2
    exit 1
  }
done

if [[ ! -f "$SSH_PRIVATE_KEY_PATH" ]]; then
  echo "Не найден приватный SSH-ключ: $SSH_PRIVATE_KEY_PATH" >&2
  echo "Путь к ключу задаётся через SSH_PRIVATE_KEY_PATH." >&2
  exit 1
fi

TFVARS_FILE="${TF_DIR}/terraform.tfvars.${PROVIDER}"
if [[ ! -f "$TFVARS_FILE" ]]; then
  TFVARS_FILE="${TF_DIR}/terraform.tfvars"
fi
if [[ ! -f "$TFVARS_FILE" ]]; then
  echo "Создайте ${TF_DIR}/terraform.tfvars или terraform.tfvars.${PROVIDER}." >&2
  exit 1
fi

echo "Облако: $PROVIDER"

# Загружаем нужную версию Kubespray.
if [[ ! -d "${KUBESPRAY_DIR}/.git" ]]; then
  git clone --depth 1 --branch "$KUBESPRAY_VERSION" \
    https://github.com/kubernetes-sigs/kubespray.git "$KUBESPRAY_DIR"
else
  CHECKED_OUT_VERSION="$(git -C "$KUBESPRAY_DIR" describe --tags --exact-match HEAD 2>/dev/null || true)"
  if [[ "$CHECKED_OUT_VERSION" != "$KUBESPRAY_VERSION" ]]; then
    echo "$KUBESPRAY_DIR уже существует, но не соответствует $KUBESPRAY_VERSION." >&2
    exit 1
  fi
fi

# Устанавливаем зависимости Kubespray в отдельное окружение Python.
if [[ ! -x "${VENV_DIR}/bin/ansible-playbook" ]]; then
  python3 -m venv "$VENV_DIR"
  "${VENV_DIR}/bin/python" -m pip install --upgrade pip
  "${VENV_DIR}/bin/python" -m pip install -r "${KUBESPRAY_DIR}/requirements.txt"
fi

# Создаём каталог inventory и копируем настройки из примера Kubespray.
mkdir -p "$INVENTORY_DIR"
if [[ ! -d "${INVENTORY_DIR}/group_vars" ]]; then
  cp -a "${KUBESPRAY_DIR}/inventory/sample/group_vars" "$INVENTORY_DIR/group_vars"
fi

# Terraform создаёт инфраструктуру и формирует inventory для Kubespray.
cd "$TF_DIR"
echo "Инициализация Terraform"
terraform init -input=false

# Для каждого облака используется отдельное состояние Terraform.
if ! terraform workspace select "$PROVIDER" >/dev/null 2>&1; then
  terraform workspace new "$PROVIDER"
fi

echo "Рабочая область Terraform: $PROVIDER"
echo "Создание инфраструктуры"
terraform apply -auto-approve -var-file="$TFVARS_FILE" -var="cloud_provider=$PROVIDER" "$@"

# Передаём Kubespray inventory, созданный Terraform.
if [[ ! -f "${ANSIBLE_DIR}/inventory.yaml" ]]; then
  echo "Terraform не создал ${ANSIBLE_DIR}/inventory.yaml." >&2
  exit 1
fi

# Удаляем старые SSH-ключи только для worker-узлов из текущего inventory.
worker_addresses="$(
  "${VENV_DIR}/bin/ansible-inventory" \
    -i "${ANSIBLE_DIR}/inventory.yaml" \
    --list |
    "${VENV_DIR}/bin/python" -c 'import json, sys; inventory = json.load(sys.stdin); [print(hostvars["ansible_host"]) for hostname, hostvars in inventory["_meta"]["hostvars"].items() if hostname.startswith("worker-") and hostvars.get("ansible_host")]'
)"
while IFS= read -r worker_address; do
  [[ -n "$worker_address" ]] || continue
  if ssh-keygen -F "$worker_address" >/dev/null 2>&1; then
    ssh-keygen -R "$worker_address" >/dev/null
  fi
done <<< "$worker_addresses"

cp "${ANSIBLE_DIR}/inventory.yaml" "${INVENTORY_DIR}/hosts.yaml"

# Загружаем SSH-ключ для подключения к узлам.
cd "$KUBESPRAY_DIR"
eval "$(ssh-agent -s)" >/dev/null
trap 'ssh-agent -k >/dev/null' EXIT
ssh-add "$SSH_PRIVATE_KEY_PATH" >/dev/null

echo "Проверка SSH-подключения"
if ! "${VENV_DIR}/bin/ansible" \
  -i "${INVENTORY_DIR}/hosts.yaml" \
  all \
  -m ansible.builtin.raw \
  -a true \
  --one-line \
  --private-key "$SSH_PRIVATE_KEY_PATH"; then
  echo "Не удалось подключиться ко всем узлам. Проверьте адреса в inventory, SSH-ключ и доступ через master." >&2
  exit 1
fi

echo "Включение репозитория Ubuntu Universe"
if ! "${VENV_DIR}/bin/ansible" \
  -i "${INVENTORY_DIR}/hosts.yaml" \
  all \
  --become \
  -m ansible.builtin.raw \
  -a 'if ! command -v add-apt-repository >/dev/null 2>&1; then apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y software-properties-common || exit 1; fi && add-apt-repository -y universe && apt-get update' \
  --private-key "$SSH_PRIVATE_KEY_PATH"; then
  echo "Не удалось включить репозиторий Ubuntu Universe на всех узлах." >&2
  exit 1
fi

# Устанавливаем Kubernetes на узлах с помощью Kubespray.
echo "Установка Kubernetes через Kubespray $KUBESPRAY_VERSION"
"${VENV_DIR}/bin/ansible-playbook" \
  -i "${INVENTORY_DIR}/hosts.yaml" \
  cluster.yml \
  --become \
  --private-key "$SSH_PRIVATE_KEY_PATH" \
  -e kube_network_plugin=calico

echo "Установка завершена."
