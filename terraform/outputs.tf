# terraform/outputs.tf
# IP адреса ВМ кластера (Cloud.ru / Yandex Cloud)

# --- Cloud.ru (Evolution) ---
output "master_external_ip" {
  description = "Внешний IP master-ноды (для SSH)"
  value       = var.cloud_provider == "cloudru" ? cloudru_evolution_compute_external_ip.k8s_master[0].ip_address : null
}

output "master_internal_ip" {
  description = "Внутренний IP master-ноды"
  value       = var.cloud_provider == "cloudru" ? cloudru_evolution_compute_interface.k8s_master[0].ip_address : null
}

output "worker_internal_ips" {
  description = "Внутренние IP рабочих нод"
  value       = var.cloud_provider == "cloudru" ? [for iface in cloudru_evolution_compute_interface.k8s_worker : iface.ip_address] : null
}

# --- Yandex Cloud ---
output "master_external_ip_yandex" {
  description = "Внешний IP master (NAT)"
  value       = var.cloud_provider == "yandex" ? yandex_compute_instance.k8s_master[0].network_interface.0.nat_ip_address : null
}

output "master_internal_ip_yandex" {
  description = "Внутренний IP master"
  value       = var.cloud_provider == "yandex" ? yandex_compute_instance.k8s_master[0].network_interface.0.ip_address : null
}

output "worker_external_ips_yandex" {
  description = "Внешние IP рабочих нод k8s"
  value       = var.cloud_provider == "yandex" ? [for i in yandex_compute_instance.k8s_worker : i.network_interface.0.nat_ip_address] : null
}

output "worker_internal_ips_yandex" {
  description = "Внутренние IP рабочих нод k8s"
  value       = var.cloud_provider == "yandex" ? [for i in yandex_compute_instance.k8s_worker : i.network_interface.0.ip_address] : null
}