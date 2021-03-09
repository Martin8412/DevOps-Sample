source "docker" "wordpress" {
    image = "ubuntu:20.04"
    commit = true
    changes = [
      "WORKDIR /var/www",
      "EXPOSE 80",
      "ENTRYPOINT /start.sh"
    ]
}

build {
    sources = [
        "source.docker.wordpress"
    ]

    provisioner "ansible" {
      playbook_file = "../provisioning/wordpress.yml"
    }

    post-processors {
      post-processor "docker-tag" {
          repository = "381501831417.dkr.ecr.eu-west-1.amazonaws.com/wordpress"
          tags = ["latest"]
      }

      post-processor "docker-push" {

      }
    }
}