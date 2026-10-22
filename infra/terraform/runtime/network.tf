# 비용 최소화 네트워크: public subnet 2개 + IGW. NAT Gateway / private subnet 은 만들지 않는다.
#
# 태스크가 ECR 이미지 pull, CloudWatch Logs 전송을 하려면 인터넷 경로가 필요하다. 선택지:
#   - NAT Gateway            : 시간당 고정비 + GB당 처리비 (시연용으로는 가장 비쌈)
#   - VPC 인터페이스 엔드포인트 : ecr.api, ecr.dkr, logs (+ s3 gateway) × AZ 수만큼 시간당 과금
#   - 태스크 public IP        : public IPv4 시간당 과금 × 태스크 수(1~2개) ← 채택
# 대신 태스크 SG 인바운드를 ALB SG 에서 오는 8080 으로만 제한해 직접 접근을 막는다.
# (가격 비교는 infra/terraform/README.md)

locals {
  p   = var.name_prefix
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "${local.p}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.p}-igw" }
}

# ALB 는 서로 다른 AZ 의 서브넷 2개 이상이 필요하다.
resource "aws_subnet" "public" {
  count = length(local.azs)

  vpc_id                  = aws_vpc.main.id
  availability_zone       = local.azs[count.index]
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  map_public_ip_on_launch = false # 태스크는 서비스 설정(assign_public_ip)으로만 public IP 를 받는다

  tags = { Name = "${local.p}-public-${local.azs[count.index]}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${local.p}-public" }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "alb" {
  name        = "${local.p}-alb"
  description = "ALB ingress"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  for_each = toset(var.allowed_ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = each.value
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_tasks" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.task.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

resource "aws_security_group" "task" {
  name        = "${local.p}-task"
  description = "ECS tasks: only from ALB"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "task_from_alb" {
  security_group_id            = aws_security_group.task.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

# ECR pull / CloudWatch Logs (HTTPS) 용 아웃바운드.
# NAT·VPC 엔드포인트 없이 AWS 퍼블릭 엔드포인트로 나가야 하므로 대상 IP 를 좁힐 수 없다 (443 만 허용).
#trivy:ignore:AWS-0104
resource "aws_vpc_security_group_egress_rule" "task_https" {
  security_group_id = aws_security_group.task.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}
