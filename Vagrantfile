Vagrant.configure("2") do |config|

  config.vm.box = "debian/bookworm64"
  config.vm.hostname = "monitoring"

  config.vm.network "forwarded_port", guest: 3000, host: 3000
  config.vm.network "forwarded_port", guest: 9090, host: 9090
  config.vm.network "forwarded_port", guest: 3100, host: 3100

  config.vm.provider "virtualbox" do |vb|
    vb.name   = "monitoring-stack"
    vb.memory = "2048"
    vb.cpus   = 2
  end

  config.vm.provision "shell", path: "provision.sh"

end
