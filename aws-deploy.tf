# Simple AWS web deployment

provider "aws" {
    region = "us-west-2"
    profile = "brainfood"
}

resource "aws_instance" "web" {
  ami               = "ami-e6d5969e"
  instance_type     = "t2.large"
  count             = 1
  source_dest_check = false
  key_name = "brainfood-dev"
  vpc_security_group_ids = ["sg-21a27f59"]
  subnet_id = "subnet-7d26cd34"

  root_block_device {
    volume_size = 20
  }

  tags {
    Name = "GIS IIIF"
  }
}

resource "aws_eip" "live" {
  vpc = true
  instance = "${aws_instance.web.id}"
}

data "template_file" "registry" {
  template = "${file("./s3-registry.yml")}"
  vars = {
    region = "us-west-2"
    bucket = "gisiiif-docker"
  }
}

resource "null_resource" "preparation" {
  triggers {
    instance = "${aws_instance.web.id}"
  }

  connection {
    host        ="${aws_eip.live.public_ip}"
    user        = "admin"
    timeout     = "30s"
    private_key = "${file("~/.ssh/brainfood-dev.pem")}"
    agent = false
  }

  # Install Docker
  provisioner "remote-exec" {
    inline = [
      # Install docker
      "sudo apt-get -qqy update",
      "sudo apt-get -qqy install time apt-transport-https ca-certificates curl gnupg2 software-properties-common",
      "curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -",
      "sudo add-apt-repository \"deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable\"",
      "sudo apt-get -qqy update",
      "sudo apt-get -qqy install docker-ce",
      "sudo curl -L https://github.com/docker/compose/releases/download/1.18.0/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose",
      "sudo chmod +x /usr/local/bin/docker-compose",
      "sudo adduser admin docker",
      "sudo mkdir /srv/gisapp",
      "sudo chown -R admin.admin /srv/gisapp",
      "mkdir ~/.aws",
      "echo '[default]' > ~/.aws/credentials",
      "echo 'aws_access_key_id = AKIAIIIDCEH6TZ6HOXTQ' >> ~/.aws/credentials",
      "echo 'aws_secret_access_key = 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' >> ~/.aws/credentials",
    ]
  }

  provisioner "file" {
    source = "gis-key"
    destination = "~/.ssh/id_rsa"
  }

  provisioner "file" {
    source = "gis-key.pub"
    destination = "~/.ssh/id_rsa.pub"
  }

  provisioner "file" {
    content = "${data.template_file.registry.rendered}"
    destination = "/srv/gisapp/registry.yml"
  }

  provisioner "remote-exec" {
    inline = [
      # Set up the application
      "sudo mv /srv/gisapp/registry.yml /etc/registry.yml",
      "sudo /etc/init.d/docker start",
      "docker run -d -p 80:5000 --detach --volume /etc/registry.yml:/etc/docker/registry/config.yml:ro --network host registry",
      "docker network create nginx",
      "sudo chown 600 ~/.ssh/id_rsa",
      "ssh -o StrictHostKeyChecking=no git@github.com",
      "sudo mkdir /srv/localdev && sudo chown admin.admin /srv/localdev && cd /srv/localdev && git clone --recursive git@github.com:Brainfood-com/localdev .",
      "echo LOCALDEV_NEXUS_SUFFIX=localhost > /srv/localdev/.env",
      "cd /srv/localdev && docker-compose up --build -d",
      "cd /srv/gisapp && git clone --recursive git@github.com:Brainfood-com/gis-docker-hosting.git .",
      "aws s3 sync s3://gis-app /srv/gisapp/data",
    ]
  }

  provisioner "file" {
    source = "env-sample"
    destination = "/srv/gisapp/.env"
  }

  provisioner "remote-exec" {
    inline = [
      "cd /srv/gisapp && ./gis.sh compose dev build",
      "cd /srv/gisapp && ./gis.sh compose dev up -d",
      "cd /srv/gisapp && make -j3 tableimport",
    ]
  }
}

output "ip" {
  value = "${aws_eip.live.public_ip}"
}
