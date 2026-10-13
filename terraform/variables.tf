# Переменные Cloud.ru и Yandex Cloud

variable "cloud_provider" {
  type        = string
  default     = "cloudru"
  description = "Провайдер облака: cloudru или yandex"
}

variable "cloudru_project_id" {
  type        = string
  description = "ID проекта Cloud.ru (из console.cloud.ru)"
}

variable "cloudru_auth_key_id" {
  type        = string
  description = "ID ключа доступа сервисного аккаунта Cloud.ru"
  sensitive   = true
}

variable "cloudru_auth_secret" {
  type        = string
  description = "Секрет ключа доступа сервисного аккаунта Cloud.ru"
  sensitive   = true
}

variable "cloudru_zone" {
  type        = string
  default     = "ru.AZ-1"
  description = "Зона доступности Cloud.ru"
}

variable "flavor" {
  type        = string
  default     = "gen-2-4"
  description = "Размер виртуальных машин Cloud.ru"
}

variable "worker_count" {
  type        = number
  default     = 3
  description = "Количество worker-узлов в Kubernetes-кластере"

  validation {
    condition     = var.worker_count >= 1 && var.worker_count <= 4 && floor(var.worker_count) == var.worker_count
    error_message = "worker_count должен быть целым числом от 1 до 4."
  }
}

variable "ssh_public_key" {
  type        = string
  description = "Публичный SSH-ключ для доступа к ВМ"
}

variable "dns_servers" {
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
  description = "DNS-серверы для виртуальных машин"
}

variable "vm_user" {
  type        = string
  default     = "ubuntu"
  description = "Имя пользователя для ВМ"
}

variable "project_name" {
  type        = string
  default     = "k8s-homework"
  description = "Префикс имени проекта для именования ресурсов"
}

variable "vm_image_name" {
  type        = string
  default     = "ubuntu-22.04"
  description = "Имя образа операционной системы в облаке"
}

variable "disk_size" {
  type        = number
  default     = 20
  description = "Размер загрузочного диска в ГБ"
}

variable "disk_type_name" {
  type        = string
  default     = "SSD"
  description = "Тип диска: SSD или HDD"
}



# --- Переменные Yandex Cloud (используются при cloud_provider = "yandex") ---

variable "cloud_id" {
  type        = string
  description = "ID облака Yandex Cloud (из console.cloud.yandex.net)"
}

variable "folder_id" {
  type        = string
  description = "ID папки Yandex Cloud (из console.cloud.yandex.net)"
}

variable "default_zone" {
  type        = string
  default     = "ru-central1-a"
  description = "Зона доступности Yandex Cloud"
}

variable "service_account_key_file" {
  type        = string
  description = "Путь к JSON-ключу сервисного аккаунта Yandex Cloud"
}

variable "vm_image_family" {
  type        = string
  default     = "ubuntu-2004-lts"
  description = "Семейство образов Yandex Cloud"
}
