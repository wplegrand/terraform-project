resource "aws_vpc" "vpc_01" {
    cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "subn_use_1a" {
    vpc_id = aws_vpc.vpc_01.id
    cidr_block = "10.0.0.0/24"
    availability_zone = "us-east-1a"
    map_public_ip_on_launch = true
}

resource "aws_subnet" "subn_use_1b" {
    vpc_id = aws_vpc.vpc_01.id
    cidr_block = "10.0.1.0/24"
    availability_zone = "us-east-1b"
    map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "igw_01" {
    vpc_id = aws_vpc.vpc_01.id
}

resource "aws_route_table" "rt_01" {
    vpc_id = aws_vpc.vpc_01.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw_01.id
    }
}

resource "aws_route_table_association" "rta_use_1a" {
    subnet_id      = aws_subnet.subn_use_1a.id
    route_table_id = aws_route_table.rt_01.id
}

resource "aws_route_table_association" "rta_use_1b" {
    subnet_id      = aws_subnet.subn_use_1b.id
    route_table_id = aws_route_table.rt_01.id
}

resource "aws_security_group" "sg_lb_01" {
    name        = "web-lb-sg"
    description = "Allow HTTP inbound traffic and all outbound traffic"
    vpc_id      = aws_vpc.vpc_01.id

    tags = {
        Name = "web-lb-sg"
    }
}

resource "aws_vpc_security_group_ingress_rule" "allow_http_ipv4" {
    security_group_id = aws_security_group.sg_lb_01.id
    cidr_ipv4         = "0.0.0.0/0"
    from_port         = 80
    to_port           = 80
    ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh_ipv4" {
    security_group_id = aws_security_group.sg_lb_01.id
    cidr_ipv4         = "0.0.0.0/0"
    from_port         = 22
    to_port           = 22
    ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
    security_group_id = aws_security_group.sg_lb_01.id
    cidr_ipv4         = "0.0.0.0/0"
    ip_protocol       = "-1" # semantically equivalent to all ports
}

#########################################################################################
resource "aws_security_group" "sg_ec2_01" {
    name        = "ec2-sg"
    description = "Allow traffic from ALB"
    vpc_id      = aws_vpc.vpc_01.id

    tags = {
        Name = "ec2-sg"
    }
}

resource "aws_vpc_security_group_ingress_rule" "allow_http_lb" {
    security_group_id = aws_security_group.sg_ec2_01.id
    referenced_security_group_id = aws_security_group.sg_lb_01.id
    from_port         = 80
    to_port           = 80
    ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh_lb" {
    security_group_id = aws_security_group.sg_ec2_01.id
    referenced_security_group_id = aws_security_group.sg_lb_01.id
    from_port         = 22
    to_port           = 22
    ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4_ec2" {
    security_group_id = aws_security_group.sg_ec2_01.id
    cidr_ipv4         = "0.0.0.0/0"
    ip_protocol       = "-1" 
}
############################################################################################

resource "aws_instance" "web_ec2_01" {
    ami = "ami-080e1f13689e07408"
    instance_type = "t2.micro"
    vpc_security_group_ids = [aws_security_group.sg_lb_01.id]
    subnet_id = aws_subnet.subn_use_1a.id
    user_data = base64encode(file("ec2_userdata.sh"))
}

resource "aws_instance" "web_ec2_02" {
    ami = "ami-080e1f13689e07408"
    instance_type = "t2.micro"
    vpc_security_group_ids = [aws_security_group.sg_lb_01.id]
    subnet_id = aws_subnet.subn_use_1b.id
    user_data = base64encode(file("ec2_userdata.sh"))
}

resource "aws_lb" "web_lb_01" {
    name = "web-lb"
    internal = false
    load_balancer_type = "application"

    security_groups = [aws_security_group.sg_lb_01.id]
    subnets = [aws_subnet.subn_use_1a.id, aws_subnet.subn_use_1b.id] 

    tags = {
        Name = "web_lb_01"
    }  
}

resource "aws_lb_target_group" "tg_lb_01" {
    name = "tg-lb"
    port = 80
    protocol = "HTTP"
    vpc_id = aws_vpc.vpc_01.id

    health_check {
      path = "/"
      port = "traffic-port"
    }
}

resource "aws_lb_target_group_attachment" "tg_t01" {
    target_group_arn = aws_lb_target_group.tg_lb_01.arn
    target_id = aws_instance.web_ec2_01.id
    port = 80
}

resource "aws_lb_target_group_attachment" "tg_t02" {
    target_group_arn = aws_lb_target_group.tg_lb_01.arn
    target_id = aws_instance.web_ec2_02.id
    port = 80
}

resource "aws_lb_listener" "lsnr_01" {
    load_balancer_arn = aws_lb.web_lb_01.arn
    port              = "80"
    protocol          = "HTTP"

    default_action {
        type             = "forward"
        target_group_arn = aws_lb_target_group.tg_lb_01.arn
    }
}

output "lb_dns" {
    value = aws_lb.web_lb_01.dns_name
}