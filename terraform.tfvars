ecsclustername = "harsh-ecs-cluster"
tags={
    Name= "Harsh Mittal"
    Owner= "harsh.mittal@cloudeq.com"
    Purpose= "fargate with terraform"
}

family="service"
network_mode = "awsvpc"
role_name = "harsh-execution-role"
policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
required_compatability = "FARGATE"