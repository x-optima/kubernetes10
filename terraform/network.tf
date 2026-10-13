# terraform/network.tf
# Сетевая инфраструктура Cloud.ru для кластера K8s

# --- VPC ---
resource "cloudru_evolution_vpc_vpc" "k8s" {
  count       = var.cloud_provider == "cloudru" ? 1 : 0
  name        = "k8s-vpc-${var.project_name}"
  project_id  = var.cloudru_project_id
  description = "VPC для Kubernetes кластера"
}

# --- NAT gateway (SNAT для интернета для ВМ без внешних IP) ---
resource "cloudru_evolution_compute_nat_gateway" "k8s" {
  count       = var.cloud_provider == "cloudru" ? 1 : 0
  project_id  = var.cloudru_project_id
  zone        = { name = var.cloudru_zone }
  name        = "k8s-nat-${var.project_name}"
  description = "SNAT шлюз для исходящего интернета"
  vpc_id      = cloudru_evolution_vpc_vpc.k8s[0].id
}

# --- Подсеть ---
resource "cloudru_evolution_compute_subnet" "k8s" {
  count          = var.cloud_provider == "cloudru" ? 1 : 0
  project_id     = var.cloudru_project_id
  zone           = { name = var.cloudru_zone }
  name           = "k8s-subnet-${var.project_name}"
  description    = "Подсеть для K8s кластера"
  vpc_id         = cloudru_evolution_vpc_vpc.k8s[0].id
  subnet_address = "10.0.1.0/24"
  routed_network = true
}

# --- Security Group ---
resource "cloudru_evolution_compute_security_group" "k8s" {
  count       = var.cloud_provider == "cloudru" ? 1 : 0
  project_id  = var.cloudru_project_id
  zone        = { name = var.cloudru_zone }
  name        = "k8s-sg-${var.project_name}"
  description = "Security group для Kubernetes кластера"
}

# --- Правила SG ---

# SSH (входящий, TCP/22, отовсюду)
resource "cloudru_evolution_compute_security_group_rule" "ssh_ingress" {
  count             = var.cloud_provider == "cloudru" ? 1 : 0
  security_group_id = cloudru_evolution_compute_security_group.k8s[0].id
  direction         = "TRAFFIC_DIRECTION_INGRESS"
  ether_type        = "ETHER_TYPE_IPV4"
  ip_protocol       = "IP_PROTOCOL_TCP"
  port_range        = "22:22"
  remote_ip_prefix  = "0.0.0.0/0"
  description       = "SSH доступ"
}

# Внутренний трафик (TCP, входящий)
resource "cloudru_evolution_compute_security_group_rule" "internal_tcp" {
  count             = var.cloud_provider == "cloudru" ? 1 : 0
  security_group_id = cloudru_evolution_compute_security_group.k8s[0].id
  direction         = "TRAFFIC_DIRECTION_INGRESS"
  ether_type        = "ETHER_TYPE_IPV4"
  ip_protocol       = "IP_PROTOCOL_TCP"
  port_range        = "1:65535"
  remote_ip_prefix  = "10.0.1.0/24"
  description       = "Внутренний TCP-трафик кластера"
}

# Внутренний трафик (UDP, входящий)
resource "cloudru_evolution_compute_security_group_rule" "internal_udp" {
  count             = var.cloud_provider == "cloudru" ? 1 : 0
  security_group_id = cloudru_evolution_compute_security_group.k8s[0].id
  direction         = "TRAFFIC_DIRECTION_INGRESS"
  ether_type        = "ETHER_TYPE_IPV4"
  ip_protocol       = "IP_PROTOCOL_UDP"
  port_range        = "1:65535"
  remote_ip_prefix  = "10.0.1.0/24"
  description       = "Внутренний UDP-трафик кластера"
}

# Весь исходящий трафик (TCP)
resource "cloudru_evolution_compute_security_group_rule" "egress_tcp" {
  count             = var.cloud_provider == "cloudru" ? 1 : 0
  security_group_id = cloudru_evolution_compute_security_group.k8s[0].id
  direction         = "TRAFFIC_DIRECTION_EGRESS"
  ether_type        = "ETHER_TYPE_IPV4"
  ip_protocol       = "IP_PROTOCOL_TCP"
  port_range        = "1:65535"
  remote_ip_prefix  = "0.0.0.0/0"
  description       = "Исходящий TCP-трафик"
}

# Весь исходящий трафик (UDP)
resource "cloudru_evolution_compute_security_group_rule" "egress_udp" {
  count             = var.cloud_provider == "cloudru" ? 1 : 0
  security_group_id = cloudru_evolution_compute_security_group.k8s[0].id
  direction         = "TRAFFIC_DIRECTION_EGRESS"
  ether_type        = "ETHER_TYPE_IPV4"
  ip_protocol       = "IP_PROTOCOL_UDP"
  port_range        = "1:65535"
  remote_ip_prefix  = "0.0.0.0/0"
  description       = "Исходящий UDP-трафик"
}

# --- Yandex Cloud ---

# Создаем VPC-сеть для проекта
resource "yandex_vpc_network" "develop" {
  count = var.cloud_provider == "yandex" ? 1 : 0
  name  = "develop-fops-${var.project_name}"
}

# Создаем NAT gateway для исходящего доступа в интернет
resource "yandex_vpc_gateway" "nat_gateway" {
  count = var.cloud_provider == "yandex" ? 1 : 0
  name  = "fops-gateway-${var.project_name}"
  shared_egress_gateway {}
}

# Создаем таблицу маршрутов и отправляем весь внешний трафик через NAT gateway
resource "yandex_vpc_route_table" "rt" {
  count      = var.cloud_provider == "yandex" ? 1 : 0
  name       = "fops-route-table-${var.project_name}"
  network_id = yandex_vpc_network.develop[count.index].id

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat_gateway[count.index].id
  }
}

# Единственная подсеть в той же зоне, где будет ВМ
resource "yandex_vpc_subnet" "develop_a" {
  count          = var.cloud_provider == "yandex" ? 1 : 0
  name           = "develop-fops-${var.project_name}-${var.default_zone}"
  zone           = var.default_zone
  network_id     = yandex_vpc_network.develop[count.index].id
  v4_cidr_blocks = ["10.0.1.0/24"]
  route_table_id = yandex_vpc_route_table.rt[count.index].id
}

# Security group для доступа к ВМ и приложению
resource "yandex_vpc_security_group" "ha_cluster" {
  count      = var.cloud_provider == "yandex" ? 1 : 0
  name       = "k8s-cluster-${var.project_name}"
  network_id = yandex_vpc_network.develop[count.index].id

  ingress {
    description    = "SSH"
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }

  ingress {
    description    = "Internal cluster traffic"
    protocol       = "ANY"
    v4_cidr_blocks = ["10.0.1.0/24"]
  }

  egress {
    description    = "ANY outbound"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}