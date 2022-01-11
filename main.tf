terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "0.68.0"
    }
  }
}

provider "yandex" {
  token     = "AQAAAABbbCeCAATuwdgA0RU1k0v0okfVuCK0nKI"
  cloud_id  = "b1gqlrb7p6gvtjhuv1pe"
  folder_id = "b1ggp5ocil88ffdsudak"
  zone      = "ru-central1-a"
}
resource "yandex_vpc_network" "network" {
  name = "netology"
}
resource "yandex_vpc_subnet" "subnet-a" {
  name           = "private-a"
  v4_cidr_blocks = ["192.168.30.0/24"]
  zone           = "ru-central1-a"
  description    = "cluster network"
  network_id     = yandex_vpc_network.network.id
}

resource "yandex_vpc_subnet" "subnet-b" {
  name           = "private-b"
  v4_cidr_blocks = ["192.168.40.0/24"]
  zone           = "ru-central1-b"
  description    = "Private instance"
  network_id     = yandex_vpc_network.network.id
}

resource "yandex_vpc_subnet" "subnet-c" {
  name           = "private-c"
  v4_cidr_blocks = ["192.168.50.0/24"]
  zone           = "ru-central1-c"
  description    = "Private instance"
  network_id     = yandex_vpc_network.network.id
}

resource "yandex_vpc_subnet" "subnet-kube-a" {
  name           = "private-kube-a"
  v4_cidr_blocks = ["192.168.60.0/24"]
  zone           = "ru-central1-a"
  description    = "Private instance"
  network_id     = yandex_vpc_network.network.id
}
resource "yandex_vpc_subnet" "subnet-kube-b" {
  name           = "private-kube-b"
  v4_cidr_blocks = ["192.168.70.0/24"]
  zone           = "ru-central1-b"
  description    = "Private instance"
  network_id     = yandex_vpc_network.network.id
}
resource "yandex_vpc_subnet" "subnet-kube-c" {
  name           = "private-kube-c"
  v4_cidr_blocks = ["192.168.80.0/24"]
  zone           = "ru-central1-c"
  description    = "Private instance"
  network_id     = yandex_vpc_network.network.id
}
locals {
  folder_id = "b1ggp5ocil88ffdsudak"
}

// Создание сервис аккаунта
resource "yandex_iam_service_account" "sa" {
  folder_id = local.folder_id
  name      = "kuber"
}

// Назначение роли
resource "yandex_resourcemanager_folder_iam_member" "sa-editor" {
  folder_id = local.folder_id
  role      = "editor"
  member    = "serviceAccount:${yandex_iam_service_account.sa.id}"
}

// Создание БД SQL
resource "yandex_mdb_mysql_cluster" "network" {
  name        = "study"
  environment = "PRESTABLE"
  network_id  = yandex_vpc_network.network.id
  deletion_protection = true
  version     = "8.0"

  resources {
    resource_preset_id = "b1.medium"
    disk_type_id       = "network-ssd"
    disk_size          = 20
  }

  database {
    name = "netology_db"
  }

  maintenance_window {
    type = "WEEKLY"
    day  = "SAT"
    hour = 12
  }

  backup_window_start {
    hours = 23
    minutes = 59
  }

  user {
    name     = "mixa"
    password = "12345678"
    permission {
      database_name = "netology_db"
      roles         = ["ALL"]
    }
  }

  host {
    zone      = "ru-central1-a"
    subnet_id = yandex_vpc_subnet.subnet-a.id
  }
  host {
    zone      = "ru-central1-b"
    subnet_id = yandex_vpc_subnet.subnet-b.id
  }
  host {
    zone      = "ru-central1-c"
    subnet_id = yandex_vpc_subnet.subnet-c.id
  }
}

// Создание регионального мастера kubernetes
resource "yandex_kubernetes_cluster" "regional_cluster_resource_kuber" {
  name        = "kuber"
  description = "regional cluster"

  network_id = yandex_vpc_network.network.id

  master {
    regional {
      region = "ru-central1"

      location {
        zone      = yandex_vpc_subnet.subnet-kube-a.zone
        subnet_id = yandex_vpc_subnet.subnet-kube-a.id
      }

      location {
        zone      = yandex_vpc_subnet.subnet-kube-b.zone
        subnet_id = yandex_vpc_subnet.subnet-kube-b.id
      }

      location {
        zone      = yandex_vpc_subnet.subnet-kube-c.zone
        subnet_id = yandex_vpc_subnet.subnet-kube-c.id
      }
    }

    version   = "1.20"
    public_ip = true

    maintenance_policy {
      auto_upgrade = true

      maintenance_window {
        day        = "monday"
        start_time = "15:00"
        duration   = "3h"
      }

      maintenance_window {
        day        = "friday"
        start_time = "10:00"
        duration   = "4h30m"
      }
    }
  }

  service_account_id      = yandex_iam_service_account.sa.id
  node_service_account_id = yandex_iam_service_account.sa.id

  labels = {
    my_key       = "value"
    my_other_key = "other_value"
  }

  release_channel = "STABLE"
}

// Создание группы узлов
resource "yandex_kubernetes_node_group" "my_node_group" {
  cluster_id  = yandex_kubernetes_cluster.regional_cluster_resource_kuber.id
  name        = "kube-group"
  description = "description"
  version     = "1.20"

  labels = {
    "key" = "value"
  }

  instance_template {
    platform_id = "standard-v2"

    network_interface {
      nat                = true
      subnet_ids         = ["${yandex_vpc_subnet.subnet-kube-a.id}"]
    }
    resources {
      memory = 2
      cores  = 2
    }

    boot_disk {
      type = "network-hdd"
      size = 64
    }

    scheduling_policy {
      preemptible = true
    }
  }

  scale_policy {
    auto_scale {
      min     = 3
      max     = 6
      initial = 3
    }
  }

  allocation_policy {
    location {
      zone = "ru-central1-a"

    }
  }

  maintenance_policy {
    auto_upgrade = true
    auto_repair  = true

    }
  }
mysql --host=rc1b-nw9zsy4cqcyfflxm.mdb.yandexcloud.net \
      --port=3306 \
      --ssl-ca=~/.mysql/root.crt \
      --ssl-mode=VERIFY_IDENTITY \
      --user=mixa \
      --password \
      netology_db
