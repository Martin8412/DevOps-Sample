# ReadMe

## What I've done
I've started out by creating a base image using Packer and Ansible. I've configured it to output a Docker image that will be pushed to AWS ECR. As requested I use the Ansible provisioner to provision the image with Apache2, PHP and the MySQL libraries needed to communicate with the database. I modify paths for logging to be stdout and stderr and fix up permissions. The Packer file uses two post processors, one to tag and one to push the image to AWS ECR. 

The first item of the Terraform manifest is to create the ECR repository needed to host the image that will be runnng. After that I start defining the network infrastructure to the visual image in my head. I define a simple VPC with an Internet Gateway, two subnets and a routing table routing 0.0.0.0/0 towards the internet gateway. My belief is that everything should be locked down as tightly as possible, so I define security groups only allowing traffic on the very needed ports. Those are applied to the various services I am using. 

The RDS database requires a special resource for it's HA mode, that lists the two subnets created earlier. The database will be running in these subnets. After that resource has been created I pass it in, to create the actual database instance. For this example I've just stuck with tiny instance types.

After I've finished up with the database, I start the process of creating the ECS cluster that our Wordpress installation will run in. The only customization from defaults is that I enable container insights since that can be used for monitoring stuff. Since we need the host, username and password for the database, we need to be a bit creative. The fields are not know until the database has been created, so we can't hardcode them into the image. I've choosen to use a way I've often used, injecting data with environment variables. I used the task definition to supply the environment variables. I've provided a start script that is used as the entrypoint for the container which takes the environment variables and spits out a wp-config.php file which makes using the setup quite easy. 

The task definition specifes image, log configuration, limits, etc. I've chosen to use Fargate for running the containers since it seems to require less configuration. For it to work, there needs to be an IAM service linked role. I've commented it out in the manifest since I have one. 

I proceed to start making a load balancer to put in front of the container. I create a target group that uses IPs(instead of instances), because that's needed for Fargate. I let the load balancer live in both subnets in the VPC for good measure, and I apply the security group to it such that only port 80 and 443 will be allowed through. There's a listener configured for port 80 that forwards to services running in the target group created earlier. I've commented out the stuff for HTTPS which I'll explain why later. 

Finally I create the ECS service. The service runs in the ECS cluster and will execute the task definition. The service will register itself with the target group so requests can be routed to it. Lastly I configure the network for it, I let it live in both subnets, and I apply a security group that only allows traffic from the load balancer.

## How did you run your project
There are definite improvements that could be done. One of the issues is that Terraform creates the ECR repository that Packer needs to push to, and I couldn't find a way to invoke Packer from Terraform. 

Therefore I run it like this
```
aws ecr get-login-password --region eu-west-1 | docker login --username AWS --password-stdin xxxxxxxxxxxxxx.dkr.ecr.eu-west-1.amazonaws.com
cd infrastruture
terraform apply

## In another terminal once the ECR repository has been created

cd images
packer build wordpress.pkr.hcl
```

That should spin everything up, if you are logged in to my AWS account. There are a few hardcoded URLs here and there assuming my account ID.

## What are the components interacting with each other
You have the RDS database running in two subnets in the VPC. All services for this run in the same VPC, but they can't reach each other unless specifically allowed to. There's the ECS service running in an ECS cluster. The ECS service talks to the RDS database. The ECS service also talks back and forth to the load balancers. The ECS service updates the target group that the load balancer uses, and the load balancer sends traffic coming in from the internet to the ECS service.

## What problems did you encounter
I ran into a bunch of different problems, most of them related to not really being familiar with ECS. Though I will start out with why the HTTPS stuff is crossed out in the Terraform manifest. I would have loved to have HTTPS support for the site, and the stuff commented out would have worked if just not for the fact that my domain has DNSSEC enabled. This means, that I would have to start messing with delegating a subzone and having that signed because I don't want to delegate my entire domain to Route53. Because of that, any secure DNS resolver will simply refuse to serve requests to wp.martin8412.dk because that's not trusted. Had I bought another domain and used that it would have worked.

A bunch of my problems with ECS probably came from the fact that I hadn't gathered that you needed to enable logging in the task definition. So a lot of the time I was sorta blindly guessing what the problem was. Originally I was trying to use ECS with EC2 instances, but it wasn't immediately obvious to me that you would need to lunch EC2 instances as well, so I ended using Fargate which took a bit of messing with, but eventually worked brilliantly. 

I ran into issues with Terraform not always managing to destroy resources again after they had been created. If it was due to slow API calls or what happened I'm not entirely certain. 

## How would you have done things to have the best HA/automated architecture
I feel like the setup is suited for HA. The ECS service containers run behind a load balancer, so I can just change the amount of desired nodes to have in the ECS cluster. The RDS instance can also be scaled up if needed. I do however feel like things would need to be improved to have it be more automated. The service should probably be run in an auto scaling group such that it can scale up and down according to demand. From a more automation stand point, I feel like the manifests should probably be more flexible. Currently I have a bunch of things that are hardcoded, and it would be much improved if data could dynamically be injected into the Terraform and Packer flows. I'm not certain if my use of a script to inject data is the most optimal, but it has not failed me so far.

Another thing that I'm annoyed at, and I couldn't find a way to fix, is that I'm using the latest tag for the Docker images. I would strictly prefer to find a way to output the sha256 value from Packer, and be able to use it Terraform in some automated way. That way the images are always the same, and if a container dies, it won't pull whatever has been pushed latest. Therefore giving us better reproducibility. 

## Tomorrow we want to put this project in production. What would be your advice and choices to achieve that
I would say that there should probably be a second(or more) pair of eyes having a look at it first. For now it's a rather basic setup, with a lot of smart features not setup quite yet. Though it depends on the amount of expected customers, and how much should be spent on it. Due consideration should be taken to the price of Fargate vs EC2 hosted ECS nodes. Fargate allows for less powerful configurations, but if more powerful, or multiple less powerful nodes are needed, then EC2 can be cheaper given the right parameters. Another consideration is the ability to run multiple instances of WordPress on the same physical nodes which might be an even further cost optimization.

The setup should definitely have an auto scaling group added to it, such that it will automatically scale depending on load. Depending on the ratio of reads to writes, it might be preferable to add a caching proxy in the mix, like Varnish. Perhaps something like Redis could be of use. 

The hardcoded variables should be given a look for sure. A solution could be to use Terraform input variables to make it more dynamic than it currently is.

For monitoring there's Prometheus that I'd like to have. Being able to collect data from the Apache processs on how they are doing, and from the RDS databases seem like the bare minimum. The more data we can gather(without impairing performance too much), the better. It will allow us to finely tune the parts that need tuning. Having access to average, low and mean values for response time can be an invaluable tool to plan for eventual capacity upgrades or downgrades. Ideally the application should have exactly the right amount of resources to run smoothly at any given time, without wasting money. Amazon has their CloudWatch product as well, but I don't feel like it suffices for monitoring performance. Sure, it can show basics about CPU utilization and RAM utilization, but that doesn't say much about how the actual application is doing.

If we are doing user registrations, then we might want to add in SES as well, so that we can send emails to users.

Depending on what addons we want to use, additional PHP modules and dependencies might be needed.

We'd need to find a better way to go about the salts needed in wp-config.php. For now I've just hardcoded it because the generated ones messed up my templating, but a better templating engine than Bash would probably resolve that. Another issue with the current Wordpress setup is that it can't really be updated without external intervention. Plugins can't be installed either. If the user upgrades the image, then they'll lose the upgrades if the container restarts. This might break the application if the database has had migrations ran on it that are not compatible with the old format stored in the built Docker image. The same goes for user uploads in the wp-content folder. A solution could be to use an EFS volume shared between container replicas for storing Wordpress. Alternatively or maybe even in combination, storage of Wordpress could be in S3. 