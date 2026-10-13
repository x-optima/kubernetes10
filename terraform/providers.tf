# terraform/providers.tf
# Провайдеры Cloud.ru (Evolution) и Yandex Cloud
# Активный провайдер выбирается переменной cloud_provider

terraform {
  required_version = ">= 1.12.0"

  required_providers {
    cloudru = {
      source  = "cloudru/cloud"
      version = "2.1.3"
    }
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "0.213.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

# --- Cloud.ru (Evolution) ---
provider "cloudru" {
  project_id  = var.cloudru_project_id
  auth_key_id = var.cloudru_auth_key_id
  auth_secret = var.cloudru_auth_secret
  region      = "ru-central-1"
}

# --- Yandex Cloud ---
provider "yandex" {
  cloud_id                 = var.cloud_id
  folder_id                = var.folder_id
  zone                     = var.default_zone
  service_account_key_file = pathexpand(var.service_account_key_file)
}
