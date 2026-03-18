Vagrant.configure("2") do |config|

  config.vm.box = "debian/bookworm64"
  config.vm.hostname = "monitoring"

  # Réseau — accès à Grafana depuis le navigateur de l'hôte
  config.vm.network "forwarded_port", guest: 3000, host: 3000   # Grafana
  config.vm.network "forwarded_port", guest: 9090, host: 9090   # Prometheus
  config.vm.network "forwarded_port", guest: 3100, host: 3100   # Loki

  # Réseau privé pour intégration avec les autres groupes
  config.vm.network "private_network", ip: "192.168.56.10"

  config.vm.provider "virtualbox" do |vb|
    vb.name   = "monitoring-stack"
    vb.memory = "2048"
    vb.cpus   = 2
  end

  # Provisioning — installe Docker et lance la stack
  config.vm.provision "shell", path: "provision.sh"

end
