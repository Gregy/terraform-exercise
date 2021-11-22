# Terraform training assignment

See [assignment](assignment-manage-multiple-deployments.pdf) for details

### Prerequisites

- Docker >=20.10
- docker-compose >=1.29
- terraform >=1
- j2cli
- bash

If you do not have a recent docker-compose, you can use a dockerized version by replacing all docker-compose calls in the steps below with calls to dockerized docker-compose:
```
alias docker-compose='docker run -it --rm -e COMPOSE_DB_SCALE="$COMPOSE_DB_SCALE" -v /var/run/docker.sock:/var/run/docker.sock -v "$(pwd):$(pwd)" -w "$(pwd)"  docker/compose:1.29.2'
```

If you do not have a recent terraform, you can use a dockerized version by replacing all terraform calls in the steps below with calls to dockerized terraform:
```
alias terraform='docker run -it --net=host --rm -v $(pwd):/mnt -w /mnt -u "$(id -u):$(id -g)" hashicorp/terraform:latest'
```

If you do not have j2cli installed you can use a dockerized version like this
```
alias j2='docker run -it --net=host --rm -v $(pwd):/mnt -w /mnt -u "$(id -u):$(id -g)" dcagatay/j2cli'
```

### Initial setup

1. Generate a postgres password which will be used when spinning up PostgreSQL containers
```
openssl rand -base64 15 > postgrespass.secret
```

2. Start database servers. You can start as many as you want
```
export COMPOSE_DB_SCALE=5
docker-compose up
```

3. Export connection variables for terraform
```
./generate-psql-connection-config.sh > psql.connection.auto.tfvars.json
```

The script above will inspect running containers and generate a json file with connection information


4. (Optional) Modify the contents of the terraform.tfvars file to customize the created users and databases

5. Run Jinja preprocessor on the main terraform module. Unfortunatelly terraform doesn't yet support dynamic provider configuration so I had to bypass the problem by using a templating engine. It is not ideal but definitely workable. Relevant [issue](https://github.com/hashicorp/terraform/issues/24476)
```
j2 -f json -o start.tf start.tf.jinja psql.connection.auto.tfvars.json
```

4. Initialize terraform
```
terraform init
```

6. Run terraform (assuming interactive shell so we can confirm the operation after inspecting the plan)
```
terraform apply
```

7. Get the user list and passwords
```
terraform output users
```
