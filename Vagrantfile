# -*- mode: ruby -*-
# vi: set ft=ruby :

# =============================================================================
# CKA Lab - Kubernetes Cluster com HA
# =============================================================================
# Control Planes: 3 nodes (HA com kube-vip)
# Workers: 6 nodes
# CNI: Cilium (kubeProxyReplacement=true)
# Rede: libvirt default network (virbr0 - DHCP)
# VIP: Primeiro IP disponivel no range .100
# =============================================================================

NUM_CONTROL_PLANES = 3
NUM_WORKERS = 6

Vagrant.configure("2") do |config|
  config.vm.box = "debian/bookworm64"
  config.vm.synced_folder ".", "/vagrant", disabled: true

  # =====================
  # Control Planes
  # =====================
  (1..NUM_CONTROL_PLANES).each do |i|
    config.vm.define "control-plane-#{i}" do |cp|
      cp.vm.hostname = "control-plane-#{i}"

      cp.vm.provider :libvirt do |libvirt|
        libvirt.memory = 2048
        libvirt.cpus = 2
        libvirt.management_network_name = "default"
        libvirt.management_network_address = "192.168.122.0/24"
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
        libvirt.memory = 1024
        libvirt.cpus = 1
        libvirt.management_network_name = "default"
        libvirt.management_network_address = "192.168.122.0/24"
      end

      w.vm.provision "shell", path: "scripts/common-setup.sh"
      w.vm.provision "shell", path: "scripts/worker-setup.sh"
    end
  end
end
