terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  zone = "ru-central1-a"
}

resource "yandex_compute_disk" "disk-master" {
  name     = "disk-master"
  type     = "network-hdd"
  zone     = "ru-central1-a"
  size     = "30"
  image_id = "fd8e9t6fpgi13oh7q39f"
}
resource "yandex_compute_disk" "disk-worker" {
  name     = "disk-worker"
  type     = "network-hdd"
  zone     = "ru-central1-a"
  size     = "30"
  image_id = "fd8e9t6fpgi13oh7q39f"
}
resource "yandex_compute_disk" "disk-runner" {
  name     = "disk-runner"
  type     = "network-hdd"
  zone     = "ru-central1-a"
  size     = "20"
  image_id = "fd8e9t6fpgi13oh7q39f"
}

resource "yandex_compute_instance" "master" {
  name = "k8s-master"

  resources {
    cores  = 4
    memory = 8
  }

  boot_disk {
    disk_id = yandex_compute_disk.disk-master.id
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet-1.id
    nat       = true
  }

  scheduling_policy {
    preemptible = true
  }

  metadata = {
    user-data = "${file("meta.txt")}"
  }
}
resource "yandex_compute_instance" "worker" {
  name = "k8s-worker"

  resources {
    cores  = 4
    memory = 8
  }

  boot_disk {
    disk_id = yandex_compute_disk.disk-worker.id
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet-1.id
    nat       = true
  }

  scheduling_policy {
    preemptible = true
  }

  metadata = {
    user-data = "${file("meta.txt")}"
  }
}
resource "yandex_compute_instance" "runner" {
  name = "git-runner"

  resources {
    cores  = 2
    memory = 4
  }

  boot_disk {
    disk_id = yandex_compute_disk.disk-runner.id
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet-1.id
    nat       = true
  }

  scheduling_policy {
    preemptible = true
  }

  metadata = {
    user-data = "${file("meta.txt")}"
  }
}

resource "yandex_vpc_network" "network-1" {
  name = "network1"
}

resource "yandex_vpc_subnet" "subnet-1" {
  name           = "subnet1"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.network-1.id
  v4_cidr_blocks = ["192.168.10.0/24"]
}

output "master_public_ip" {
  value = yandex_compute_instance.master.network_interface.0.nat_ip_address
}

output "master_private_ip" {
  value = yandex_compute_instance.master.network_interface.0.ip_address
}

output "worker_public_ip" {
  value = yandex_compute_instance.worker.network_interface.0.nat_ip_address
}

output "worker_private_ip" {
  value = yandex_compute_instance.worker.network_interface.0.ip_address
}

output "runner_public_ip" {
  value = yandex_compute_instance.runner.network_interface.0.nat_ip_address
}
