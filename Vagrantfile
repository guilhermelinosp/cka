# -*- mode: ruby -*-
# vi: set ft=ruby :


# =============================================================================
# CKA Lab - Kubernetes Cluster com HA
# =============================================================================
# HAProxy: 1 node (Load Balancer para API Server)
# Control Planes: 3 nodes (HA com HAProxy)
# Workers: 6 nodes
# CNI: Calico (suporta NetworkPolicy para CKA)
# Rede: libvirt default network (virbr0 - DHCP)
# =============================================================================

NUM_CONTROL_PLANES = 3
NUM_WORKERS = 6
HAPROXY_MEMORY = 512
HAPROXY_CPUS = 1
CONTROL_PLANE_MEMORY = 2048
CONTROL_PLANE_CPUS = 2
WORKER_MEMORY = 2048
WORKER_CPUS = 1

Vagrant.configure("2") do |config|
  config.vm.box = "debian/bookworm64"
  config.vm.synced_folder ".", "/vagrant", disabled: true

  # =====================
  # HAProxy Load Balancer (deve ser provisionado primeiro)
  # =====================
  config.vm.define "haproxy", primary: true do |lb|
    lb.vm.hostname = "haproxy"

    lb.vm.provider :libvirt do |libvirt|
      libvirt.memory = HAPROXY_MEMORY
      libvirt.cpus = HAPROXY_CPUS
    end

    lb.vm.provision "shell", path: "scripts/haproxy-setup.sh"
  end

  # =====================
  # Control Planes
  # =====================
  (1..NUM_CONTROL_PLANES).each do |i|
    config.vm.define "control-plane-#{i}" do |cp|
      cp.vm.hostname = "control-plane-#{i}"

      cp.vm.provider :libvirt do |libvirt|
        libvirt.memory = CONTROL_PLANE_MEMORY
        libvirt.cpus = CONTROL_PLANE_CPUS
      end

      cp.vm.provision "shell", path: "scripts/common-setup.sh"
      cp.vm.provision "shell", path: "scripts/control-plane-setup.sh", env: {
        "NODE_NUMBER" => i.to_s
      }
    end
  end

  # =====================
  # Worker Nodes
  # =====================
  (1..NUM_WORKERS).each do |i|
    config.vm.define "worker-node-#{i}" do |w|
      w.vm.hostname = "worker-node-#{i}"

      w.vm.provider :libvirt do |libvirt|
        libvirt.memory = WORKER_MEMORY
        libvirt.cpus = WORKER_CPUS
      end

      w.vm.provision "shell", path: "scripts/common-setup.sh"
      w.vm.provision "shell", path: "scripts/worker-setup.sh"
    end
  end
end
