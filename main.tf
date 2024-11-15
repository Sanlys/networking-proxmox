terraform {
  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "3.0.1-rc4"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.0.2"
    }
  }
}

provider "proxmox" {
  pm_api_url      = "https://10.0.5.101:8006/api2/json"
  pm_tls_insecure = true
}

variable "proxmox_node" {
  default = "pve1"
}

resource "proxmox_vm_qemu" "docker" {
  name                   = "networking-docker"
  clone                  = "ubuntu-2204-ceph"
  target_node            = var.proxmox_node
  cores                  = 2
  memory                 = 2048
  scsihw                 = "virtio-scsi-pci"
  define_connection_info = true

  boot  = "order=sata0"
  agent = 1

  disks {
    sata {
      sata0 {
        disk {
          size    = "10G"
          storage = "vms"
          cache   = "writeback"
        }
      }
    }
    ide {
      ide3 {
        cloudinit {
          storage = "vms"
        }
      }
    }
  }

  network {
    model  = "virtio"
    bridge = "vmbr0"
  }

  ciuser     = "bob"
  cipassword = "bob"
  sshkeys    = local.ssh_pub_key_content
  ipconfig0  = "ip=dhcp"
}

output "ip" {
  value       = proxmox_vm_qemu.docker.ssh_host
  description = "IP Address"
}
output "ssh_pub" {
  value       = local.ssh_pub_key_path
  description = "SSH Pubkey path"
}
output "ssh_priv" {
  value       = local.ssh_priv_key_path
  description = "SSH Privkey path"
}

provider "docker" {
  host     = "ssh://${proxmox_vm_qemu.docker.ciuser}@${proxmox_vm_qemu.docker.ssh_host}:22"
  ssh_opts = ["-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null", "-i", local.ssh_priv_key_path]
}

resource "docker_image" "nginx" {
  name = "nginx"
}

resource "docker_container" "nginx" {
  name  = "nginx"
  image = docker_image.nginx.image_id
  labels {
    label = "traefik.enable"
    value = "true"
  }
  labels {
    label = "traefik.http.routers.nginx.rule"
    value = "PathPrefix(`/`)"
  }
  labels {
    label = "traefik.http.routers.nginx.entrypoints"
    value = "http"
  }
  labels {
    label = "traefik.http.services.nginx.loadbalancer.server.port"
    value = "80"
  }
  lifecycle {
    ignore_changes = [log_opts]
  }
}

resource "docker_image" "traefik" {
  name = "traefik:v3.2"
}

resource "docker_container" "traefik" {
  name  = "traefik"
  image = docker_image.traefik.image_id
  ports {
    internal = 80
    external = 80
  }
  ports {
    internal = 8080
    external = 8080
  }
  command = ["--api.insecure=true", "--providers.docker"]

  lifecycle {
    ignore_changes = [log_opts]
  }
  volumes {
    container_path = "/var/run/docker.sock"
    host_path      = "/var/run/docker.sock"
  }
}
