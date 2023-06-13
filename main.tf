resource "aws_ecr_repository" "harsh_ecr_repo" {
  name = "harsh-repo"
  image_scanning_configuration {
	    scan_on_push = true
	}
  tags= var.tags
}

resource "aws_ecs_cluster" "ecs_cluster" {
  name = var.ecsclustername
  tags= var.tags
}


# Create an IAM role for the task execution
resource "aws_iam_role" "harsh_execution_role" {
  name = var.role_name

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "ecsTaskExecutionRole_policy" {
  role       = "${aws_iam_role.harsh_execution_role.name}"
  policy_arn = var.policy_arn
}


resource "aws_ecs_task_definition" "harsh_task_definition" {
  family = var.family
  network_mode = var.network_mode
  requires_compatibilities = [var.required_compatability]
  tags=var.tags
  execution_role_arn = aws_iam_role.harsh_execution_role.arn
  cpu= 256
  memory= 512
  container_definitions = <<TASKDEFINITION
    [
      {
        "name": "harsh-repo",
        "image": "${aws_ecr_repository.harsh_ecr_repo.repository_url}",
        "portMappings": [
          {
            "containerPort": 8000,
            "hostPort": 8000
          }
        ],
        "memory": 512,
        "cpu": 256
      }
    ]
  TASKDEFINITION
}

resource "aws_vpc" "harsh" {
  cidr_block = "10.0.0.0/16"
  tags= var.tags
}

# Create the first subnet in us-west-2a availability zone
resource "aws_subnet" "harsh_subnet1" {
  vpc_id                  = aws_vpc.harsh.id
  cidr_block              = "10.0.1.0/24"  
  availability_zone       = "ap-southeast-1a" 
  tags= var.tags
}

# Create the second subnet in us-west-2b availability zone
resource "aws_subnet" "harsh_subnet2" {
  vpc_id                  = aws_vpc.harsh.id
  cidr_block              = "10.0.2.0/24"  
  availability_zone       = "ap-southeast-1b"  
  tags= var.tags
}

resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.harsh.id
  tags=var.tags
}

# Create a route table
resource "aws_route_table" "harsh_route_table" {
  vpc_id = aws_vpc.harsh.id
  tags=var.tags
}

# Create a route for internet access via the internet gateway
# resource "aws_route" "internet_access" {
#   route_table_id            = aws_route_table.harsh_route_table.id
#   destination_cidr_block    = "0.0.0.0/0"
#   gateway_id                = aws_internet_gateway.my_igw.id
# }

# Associate the first subnet with the route table
resource "aws_route_table_association" "harsh_route1" {
  subnet_id      = aws_subnet.harsh_subnet1.id
  route_table_id = aws_route_table.harsh_route_table.id
}

# Associate the second subnet with the route table
resource "aws_route_table_association" "harsh_route2" {
  subnet_id      = aws_subnet.harsh_subnet2.id
  route_table_id = aws_route_table.harsh_route_table.id
}

resource "aws_security_group" "load_balancer_security_group" {
  vpc_id = aws_vpc.harsh.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allow traffic in from all sources
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "service_security_group" {
  vpc_id = aws_vpc.harsh.id
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    # Only allowing traffic in from the load balancer security group
    security_groups = ["${aws_security_group.load_balancer_security_group.id}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_alb" "application_load_balancer" {
  name               = "harsh-load-balancer"
  load_balancer_type = "application"
  subnets = [ "${aws_subnet.harsh_subnet1.id}","${aws_subnet.harsh_subnet2.id}"]
  security_groups = ["${aws_security_group.load_balancer_security_group.id}"]
}


resource "aws_lb_target_group" "target_group" {
  name        = "target-group"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = "${aws_vpc.harsh.id}"
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = "${aws_alb.application_load_balancer.arn}" #  load balancer
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.target_group.arn}" # target group
  }
}


resource "aws_ecs_service" "my_service" {
  name            = "my-ecs-service"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.harsh_task_definition.arn
  launch_type = "FARGATE"
  desired_count   = 2
  load_balancer {
    target_group_arn = "${aws_lb_target_group.target_group.arn}" # Reference the target group
    container_name   = "harsh-repo"
    container_port   = 8000 # Specify the container port
  }
   network_configuration {
    subnets          = ["${aws_subnet.harsh_subnet1.id}", "${aws_subnet.harsh_subnet2.id}"]
    assign_public_ip = true     # Provide the containers with public IPs
    security_groups  = ["${aws_security_group.service_security_group.id}"] # Set up the security group
  }
}
