# terraform/main.tf
# Создание виртуальных машин для кластера Kubernetes в Cloud.ru

# Поиск ID ресурсов по их именам

# Cloud.ru (Evolution)
data "cloudru_evolution_compute_zone_collection" "all" {
  count      = var.cloud_provider == "cloudru" ? 1 : 0
  project_id = var.cloudru_project_id
}

data "cloudru_evolution_compute_flavor_collection" "all" {
  count      = var.cloud_provider == "cloudru" ? 1 : 0
  project_id = var.cloudru_project_id
}

data "cloudru_evolution_compute_image_collection" "all" {
  count      = var.cloud_provider == "cloudru" ? 1 : 0
  project_id = var.cloudru_project_id
}

data "cloudru_evolution_compute_disk_type_collection" "all" {
  count      = var.cloud_provider == "cloudru" ? 1 : 0
  project_id = var.cloudru_project_id
}

# Выбор ресурсов по имени

locals {
  selected_zone = var.cloud_provider == "cloudru" ? one([for z in data.cloudru_evolution_compute_zone_collection.all[0].zones : z if z.name == var.cloudru_zone]) : null

  # ID виртуальной машины для значения var.flavor
  flavor_id = var.cloud_provider == "cloudru" ? one([for f in data.cloudru_evolution_compute_flavor_collection.all[0].flavors : f.id if f.name == var.flavor]) : null

  # Образ Ubuntu
  image = var.cloud_provider == "cloudru" ? one([for img in data.cloudru_evolution_compute_image_collection.all[0].images : img if img.name == var.vm_image_name]) : null

  # Тип диска
  disk_type = var.cloud_provider == "cloudru" ? one([for dt in data.cloudru_evolution_compute_disk_type_collection.all[0].disk_types : dt if dt.name == var.disk_type_name]) : null

  # Настройки cloud-init для всех виртуальных машин
  cloud_init = templatefile("${path.module}/cloud-init.yaml.tpl", {
    USER        = var.vm_user
    SSH_KEY     = var.ssh_public_key
    DNS_SERVERS = join(" ", var.dns_servers)
  })
}

# Yandex Cloud

# Получение ID образа Ubuntu
data "yandex_compute_image" "ubuntu_2004" {
  count  = var.cloud_provider == "yandex" ? 1 : 0
  family = var.vm_image_family
}

# Виртуальные машины Yandex Cloud: один master-узел и число worker-узлов задаётся переменной worker_count
resource "yandex_compute_instance" "k8s_master" {
  count       = var.cloud_provider == "yandex" ? 1 : 0
  name        = "k8s-master-1-${var.project_name}"
  platform_id = "standard-v3"
  zone        = var.default_zone

  resources {
    cores  = 2
    memory = 4
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu_2004[0].id
      size     = 20
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.develop_a[count.index].id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.ha_cluster[count.index].id]
  }

  metadata = {
    user-data = local.cloud_init
  }
}

resource "yandex_compute_instance" "k8s_worker" {
  count       = var.cloud_provider == "yandex" ? var.worker_count : 0
  name        = "k8s-worker-${count.index + 1}-${var.project_name}"
  platform_id = "standard-v3"
  zone        = var.default_zone

  resources {
    cores  = 2
    memory = 4
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu_2004[0].id
      size     = 20
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.develop_a[0].id
    security_group_ids = [yandex_vpc_security_group.ha_cluster[0].id]
  }

  metadata = {
    user-data = local.cloud_init
  }
}

# Внешний IP для Master (для SSH)
resource "cloudru_evolution_compute_external_ip" "k8s_master" {
  count       = var.cloud_provider == "cloudru" ? 1 : 0
  project_id  = var.cloudru_project_id
  zone        = { name = var.cloudru_zone }
  name        = "k8s-master-extip-${var.project_name}"
  description = "Внешний IP для master ноды"
}

# Загрузочные диски

resource "cloudru_evolution_compute_disk" "k8s_master" {
  count      = var.cloud_provider == "cloudru" ? 1 : 0
  name       = "k8s-master-disk-${var.project_name}"
  project_id = var.cloudru_project_id
  zone       = { name = var.cloudru_zone }
  size       = var.disk_size
  disk_type  = { name = var.disk_type_name }
  image      = { id = local.image.id }
  bootable   = true
}

resource "cloudru_evolution_compute_disk" "k8s_worker" {
  count      = var.cloud_provider == "cloudru" ? var.worker_count : 0
  name       = "k8s-worker-${count.index + 1}-disk-${var.project_name}"
  project_id = var.cloudru_project_id
  zone       = { name = var.cloudru_zone }
  size       = var.disk_size
  disk_type  = { name = var.disk_type_name }
  image      = { id = local.image.id }
  bootable   = true
}

# Сетевые интерфейсы

# Интерфейс master (с внешним IP)
resource "cloudru_evolution_compute_interface" "k8s_master" {
  count                      = var.cloud_provider == "cloudru" ? 1 : 0
  project_id                 = var.cloudru_project_id
  zone                       = { name = var.cloudru_zone }
  name                       = "k8s-master-iface-${var.project_name}"
  description                = "Сетевой интерфейс master ноды"
  type                       = "INTERFACE_TYPE_REGULAR"
  subnet                     = { id = cloudru_evolution_compute_subnet.k8s[0].id }
  interface_security_enabled = true
  security_groups            = [{ id = cloudru_evolution_compute_security_group.k8s[0].id }]
  attach_external_ip         = { id = cloudru_evolution_compute_external_ip.k8s_master[0].id }
}

# Интерфейсы worker (без внешних IP — интернет через NAT gateway)
resource "cloudru_evolution_compute_interface" "k8s_worker" {
  count                      = var.cloud_provider == "cloudru" ? var.worker_count : 0
  project_id                 = var.cloudru_project_id
  zone                       = { name = var.cloudru_zone }
  name                       = "k8s-worker-${count.index + 1}-iface-${var.project_name}"
  description                = "Сетевой интерфейс worker-${count.index + 1}"
  type                       = "INTERFACE_TYPE_REGULAR"
  subnet                     = { id = cloudru_evolution_compute_subnet.k8s[0].id }
  interface_security_enabled = true
  security_groups            = [{ id = cloudru_evolution_compute_security_group.k8s[0].id }]
}

# Виртуальные машины

resource "cloudru_evolution_compute_vm" "k8s_master" {
  count               = var.cloud_provider == "cloudru" ? 1 : 0
  project_id          = var.cloudru_project_id
  zone                = { name = var.cloudru_zone }
  name                = "k8s-master-1-${var.project_name}"
  description         = "Master-нода Kubernetes"
  flavor              = { name = var.flavor }
  disks               = [{ id = cloudru_evolution_compute_disk.k8s_master[0].id }]
  network_interfaces  = [{ id = cloudru_evolution_compute_interface.k8s_master[0].id }]
  cloud_init_userdata = base64encode(local.cloud_init)
}

resource "cloudru_evolution_compute_vm" "k8s_worker" {
  count               = var.cloud_provider == "cloudru" ? var.worker_count : 0
  project_id          = var.cloudru_project_id
  zone                = { name = var.cloudru_zone }
  name                = "k8s-worker-${count.index + 1}-${var.project_name}"
  description         = "Worker-нода ${count.index + 1} Kubernetes"
  flavor              = { name = var.flavor }
  disks               = [{ id = cloudru_evolution_compute_disk.k8s_worker[count.index].id }]
  network_interfaces  = [{ id = cloudru_evolution_compute_interface.k8s_worker[count.index].id }]
  cloud_init_userdata = base64encode(local.cloud_init)
}

# Генерация Ansible inventory

# Cloud.ru (Evolution)
resource "local_file" "ansible_inventory" {
  count = var.cloud_provider == "cloudru" ? 1 : 0

  content = templatefile("${path.module}/inventory.yaml.tpl", {
    master_ext = cloudru_evolution_compute_external_ip.k8s_master[0].ip_address
    master_int = cloudru_evolution_compute_interface.k8s_master[0].ip_address
    workers    = [for worker in cloudru_evolution_compute_interface.k8s_worker : worker.ip_address]
  })
  filename = "${path.module}/../ansible/inventory.yaml"
}

# Yandex Cloud
resource "local_file" "ansible_inventory_yandex" {
  count = var.cloud_provider == "yandex" ? 1 : 0

  content = templatefile("${path.module}/inventory.yaml.tpl", {
    master_ext = yandex_compute_instance.k8s_master[0].network_interface.0.nat_ip_address
    master_int = yandex_compute_instance.k8s_master[0].network_interface.0.ip_address
    workers    = [for worker in yandex_compute_instance.k8s_worker : worker.network_interface[0].ip_address]
  })
  filename = "${path.module}/../ansible/inventory.yaml"
}

# Генерация манифеста сетевых политик с IP node-local-dns (для обоих облаков)
resource "local_file" "network_policies" {
  content = templatefile("${path.module}/network-policies.yaml.tpl", {
    NODELOCALDNS_IP = var.nodelocaldns_ip
  })
  filename = "${path.module}/../manifests/network-policies.yaml"
}