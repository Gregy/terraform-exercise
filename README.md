# Terraform training assignment

See [assignment](assignment - manage multiple deployments.pdf) for details

### Prerequisites

- Docker >=20.10
- docker-compose >=1.29
- terraform >=1

If you do not have a recent docker-compose, you can use a dockerized version by replacing all docker-compose calls in the steps below with calls to dockerized docker-compose:
```
alias docker-compose='docker run -it --rm -v /var/run/docker.sock:/var/run/docker.sock -v "$(pwd):$(pwd)" -w "$(pwd)"  docker/compose:1.29.2'
```

If you do not have a recent terraform, you can use a dockerized version by replacing all terraform calls in the steps below with calls to dockerized terraform:
```
alias terraform='docker run -it --net=host --rm -v $(pwd):/mnt -w /mnt -u "$(id -u):$(id -g)" hashicorp/terraform:latest'
```

### Initial setup

1. Generate a postgres password which will be used when spinning up PostgreSQL containers
```
openssl rand -base64 15 > postgrespass.secret
```

2. Start database servers
```
docker-compose up
```

3. Initialize terraform
```
terraform init
```

4. Export connection variables for terraform
```
cat << EOF > psql.connection.auto.tfvars
psql_host="127.0.0.1"
psql_user="postgres"
psql_password="$(cat postgrespass.secret)"
psql_port="$(docker inspect terraform-test_database_1 -f '{{index .NetworkSettings.Ports "5432/tcp" 0 "HostPort"}}')"

EOF
```

The short script above will get the postgres password from the secret file we have created in step 1.
It will also inspect the docker metadata of the running postgres container and get the assigned port

5. (Optional) Modify the contents of the terraform.tfvars file to customize the created users and databases

6. Run terraform (assuming interactive shell so we can confirm the operation after inspecting the plan)
```
terraform apply
```

7. Get the user list and passwords
```
terraform output users
```
