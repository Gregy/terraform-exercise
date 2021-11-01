# Terraform training assignment

See [assignment](assignment - manage multiple deployments.pdf) for details

### Prerequisites

- Docker >=20.10
- docker-compose >=1.29

If you do not have a recent docker-compose, you can use a dockerized version by replacing all docker-compose calls in the steps below with calls to dockerized docker-compose:
```
alias docker-compose='docker run -it --rm -v /var/run/docker.sock:/var/run/docker.sock -v "$(pwd):$(pwd)" -w "$(pwd)"  docker/compose:1.29.2'
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
