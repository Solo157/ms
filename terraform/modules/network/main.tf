resource "yandex_vpc_network" "this" {
  name = "${var.name}-net"
}

resource "yandex_vpc_subnet" "this" {
  count          = length(var.zones)
  name           = "${var.name}-subnet-${element(["a", "b", "c", "d"], count.index)}"
  zone           = var.zones[count.index]
  network_id     = yandex_vpc_network.this.id
  v4_cidr_blocks = [var.subnet_cidrs[count.index]]
}

# Permissive-for-demo security group. Allows all intra-VPC traffic + egress,
# and exposes the K8s API / ingress to the internet over 443/80 (public access
# via nginx-ingress and nip.io is a course requirement).
resource "yandex_vpc_security_group" "this" {
  name       = "${var.name}-sg-default"
  network_id = yandex_vpc_network.this.id

  # Allow all traffic inside the cloud (VPC + pod/service CIDRs live in 10/8).
  ingress {
    protocol       = "ANY"
    v4_cidr_blocks = ["10.0.0.0/8"]
  }

  ingress {
    protocol       = "TCP"
    port           = 443
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol       = "TCP"
    port           = 8082
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol       = "TCP"
    port           = 3000
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}
