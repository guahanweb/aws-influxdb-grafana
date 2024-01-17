resource "aws_vpc" "vpc" {
    cidr_block = "10.0.0.0/16"

    tags = {
        Name = "${var.project_name}"
    }
}

resource "aws_internet_gateway" "gateway" {
    vpc_id = "${aws_vpc.vpc.id}"

    tags = {
        Name = "${var.project_name}"
    }
}

resource "aws_route" "internet_access" {
    route_table_id = aws_vpc.vpc.main_route_table_id
    destination_cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gateway.id
}

# Services go in their own subnet
resource "aws_subnet" "subnet" {
    vpc_id = aws_vpc.vpc.id
    cidr_block = "10.0.1.0/24"
    availability_zone = "us-east-1a"
    map_public_ip_on_launch = true

    tags = {
        Name = var.project_name
    }
}

# Security group for the EC2 instance. Only allows
# access from the ELB, except for SSH, which can be
# accessed using the instance IP directly
resource "aws_security_group" "default" {
    name = "${var.project_name}-default_secgroup"
    vpc_id = aws_vpc.vpc.id

    # SSH access from anywhere
    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    # Grafana
    ingress {
        from_port = 3000
        to_port = 3000
        protocol = "tcp"
        cidr_blocks = ["10.0.0.0/16"]
    }

    # InfluxDb
    ingress {
        from_port = 8086
        to_port = 8086
        protocol = "tcp"
        cidr_blocks = ["10.0.0.0/16"]
    }

    # Outbound internet access
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

# Security group for the ELB
resource "aws_security_group" "elb" {
    name = "${var.project_name}-elb_secgroup"
    vpc_id = aws_vpc.vpc.id

    # HTTP access to Grafana
    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    # HTTP access to Influx
    ingress {
        from_port = 8086
        to_port = 8086
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    # outbound internet access
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

# Generate an SSL cert
/*
resource "aws_acm_certificate" "cert" {
    domain_name = var.ssl_domain
    validation_method = "DNS"

    tags = {
        Name = var.project_name
    }

    lifecycle {
        create_before_destroy = true
    }
}
*/

resource "aws_ebs_volume" "volume" {
    availability_zone = "us-east-1a"
    size = 30

    tags = {
        Name = var.project_name
    }
}

resource "aws_volume_attachment" "vol_att" {
    device_name = "/dev/sdh"
    volume_id = aws_ebs_volume.volume.id
    instance_id = aws_instance.instance.id
}

resource "aws_key_pair" "access_key" {
    key_name = var.key_pair_name
    public_key = file(var.public_key_path)
}

# The EC2 instance
resource "aws_instance" "instance" {
    # Amazon Linux 2 AMI (HVM), SSD Volume Type
    ami = "ami-09def150731bdbcc2"
    instance_type = var.instance_type
    # key_name = aws_key_pari.accesskey.id

    # Our Security group to allow HTTP and SSH access
    vpc_security_group_ids = [aws_security_group.default.id]

    subnet_id = aws_subnet.subnet.id

    # credit_specification {
    #   cpu_credits = "unlimited"
    # }

    tags = {
        Name = var.project_name
    }
}

# We create a null_resource that doesn't do anything else than
# provision our instance. The aws_instance also provides provisioning
# options, but they would run before the ebs_volume is attached, so
# we create a separate resource who's provisioning is triggered by
# the volume attachment
resource "null_resource" "provisioner" {
    triggers = {
        volume_attachment = aws_volume_attachment.vol_att.id
    }

    connection {
        host = aws_instance.instance.public_ip
    }

    # We run a remote provisioner on the instance after creating it
    provisioner "file" {
        connection {
            type = "ssh"
            user = "ec2-user"
            private_key = file(var.private_key_path)
            host = aws_instance.instance.public_ip
        }

        source = "provisioning"
        destination = "/tmp"
    }

    provisioner "remote-exec" {
        connection {
            type = "ssh"
            user = "ec2-user"
            private_key = file(var.private_key_path)
            host = aws_instance.instance.public_ip
        }

        inline = [
            "chmod +x /tmp/provisioning/*.sh",
            "/tmp/provisioning/init-ebs.sh",
            "/tmp/provisioning/install-influxdb.sh ${var.influx_admin_pw} ${var.influx_user_pw}",
            "/tmp/provisioning/install-grafana.sh ${var.grafana_admin_pw} ${var.grafana_user_pw}",
        ]
    }
}