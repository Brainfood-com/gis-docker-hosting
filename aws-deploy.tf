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
    volume_size = 50
  }

  tags {
    Name = "GIS IIIF"
  }
}

data "aws_route53_zone" "hostdomain" {
  name         = "brnfd.com."
}

resource "aws_route53_record" "gisapp" {
  zone_id = "${data.aws_route53_zone.hostdomain.zone_id}"
  name    = "gis-app.${data.aws_route53_zone.hostdomain.name}"
  type    = "A"
  ttl     = "300"
  records = ["${aws_eip.live.public_ip}"]
}

resource "aws_route53_record" "gisappwild" {
  zone_id = "${data.aws_route53_zone.hostdomain.zone_id}"
  name    = "*.gis-app.${data.aws_route53_zone.hostdomain.name}"
  type    = "A"
  ttl     = "300"
  records = ["${aws_eip.live.public_ip}"]
}

resource "aws_eip" "live" {
  vpc = true
  instance = "${aws_instance.web.id}"
}

data "template_file" "registry" {
  template = "${file("./s3-registry.yml")}"
  vars = {
    accesskey = "${aws_iam_access_key.dockerreg.id}"
    secretkey = "${aws_iam_access_key.dockerreg.secret}"
    region = "us-west-2"
    bucket = "gisiiif-docker"
  }
}

resource "aws_iam_user" "dockerreg" {
  name = "dockerreg"
}

resource "aws_iam_access_key" "dockerreg" {
  user = "${aws_iam_user.dockerreg.name}"
}

resource "aws_iam_user_policy" "dockerreg_ro" {
  name = "gisapps3"
  user = "${aws_iam_user.dockerreg.name}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:*"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
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
      "echo 'aws_access_key_id = ${aws_iam_access_key.dockerreg.id}' >> ~/.aws/credentials",
      "echo 'aws_secret_access_key = ${aws_iam_access_key.dockerreg.secret}' >> ~/.aws/credentials",
    ]
  }

  provisioner "file" {
    content = "${data.template_file.registry.rendered}"
    destination = "/srv/gisapp/registry.yml"
  }

  provisioner "file" {
    source = "gis-key"
    destination = "~/.ssh/id_rsa"
  }

  provisioner "file" {
    source = "gis-key.pub"
    destination = "~/.ssh/id_rsa.pub"
  }

  provisioner "remote-exec" {
    inline = [
      # Set up the application
#      "ssh-keygen -q -t rsa -f ~/.ssh/id_rsa -N '' -C for_git_checkout",
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
      "while [ $(docker ps -a | grep nexus3_nexus_1 | grep healthy | wc -l) -eq 0 ]; do echo 'waiting for localdev'; sleep 1; done",
      "cd /srv/gisapp && ./gis.sh compose dev build",
      "cd /srv/gisapp && ./gis.sh compose dev up -d",
      "while [ $(docker ps -a | grep gis_postgresql_1 | grep healthy | wc -l) -eq 0 ]; do echo 'waiting for postgres'; sleep 1; done",
      "cd /srv/gisapp && make -j3 tableimport iiif-import",
    ]
  }
}

output "ip" {
  value = "${aws_eip.live.public_ip}"
}
