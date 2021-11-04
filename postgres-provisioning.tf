terraform {
  # allows for optional user arguments - when to play with experimental features if not now? :-)
  experiments = [module_variable_optional_attrs]

  required_providers {
    postgresql = {
      source = "cyrilgdn/postgresql"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

provider "postgresql" {
  host     = var.psql_host
  port     = var.psql_port
  database = var.psql_database
  username = var.psql_user
  password = var.psql_password
  # dangerous in real environment, acceptable for this excercise
  sslmode         = "disable"
  connect_timeout = 5
}

variable "psql_host" {
  type = string
}

variable "psql_port" {
  type = number
}

variable "psql_user" {
  type = string
}

variable "psql_database" {
  type    = string
  default = "postgres"
}

variable "psql_password" {
  type      = string
  sensitive = true
}

variable "users" {
  type        = map(object({ database = optional(string), global_reader = optional(bool) }))
  description = "A map of objects. Key of the map should be the desired username. The database object attribute sets the database name the user should have full access to or be empty if the user shouldn't have full access to any database. The global_reader attribute is a boolean which controls whether the user should be able to read all databases"
}

variable "databases" {
  type        = set(string)
  description = "A set of database names to provision"
}

locals {
  # Generates a map of lists with a key for each username and a list of the users roles
  # {"user" = ["global_reader", "writer_database1"]}
  user_roles = {
    for user, info in var.users : user => concat(
      info.database != null ? ["writer_${info.database}"] : [],
      (info.global_reader == null ? false:info.global_reader) ? [postgresql_role.global_reader_role.name] : []
    )
  }

  # Generates a map of objects with all the users and their assigned databases
  # {"user - mydb" = { user = "user", db = "mydb" }
  users_dbs_product = {
    for user, info in var.users :
    "${user} - ${info.database}" => {
      user = user
      db   = info.database
    }
    if info.database != null
  }
}

resource "random_password" "passwords" {
  for_each = var.users
  length   = 16
}

# one global reader role which will be assigned to individual global reader users
resource "postgresql_role" "global_reader_role" {
  name  = "global_reader_role"
  login = false
}



##
## Creating the databases and attached entities
##
resource "postgresql_database" "dbs" {
  for_each = var.databases
  name     = each.value
}
resource "postgresql_grant" "global_reader_db_grant" {
  for_each    = postgresql_database.dbs
  database    = each.value.name
  role        = postgresql_role.global_reader_role.name
  object_type = "database"
  privileges  = ["CONNECT"]
}
# for the purposes of this excercise lets assume each db will only have a single schema ("public")
resource "postgresql_grant" "global_reader_grants_tables" {
  for_each    = postgresql_database.dbs
  database    = each.value.name
  role        = postgresql_role.global_reader_role.name
  schema      = "public"
  object_type = "table"
  privileges  = ["SELECT"]
}
# one writer role per database which will be assigned to individual writer users later
resource "postgresql_role" "db_writer_role" {
  for_each = postgresql_database.dbs
  name     = "writer_${each.value.name}"
  login    = false
}
resource "postgresql_grant" "db_writer_db_grant" {
  for_each    = postgresql_database.dbs
  database    = each.value.name
  role        = postgresql_role.db_writer_role[each.key].name
  object_type = "database"
  privileges  = ["CONNECT"]
  depends_on = [
    postgresql_role.db_writer_role
  ]
}
resource "postgresql_grant" "db_writer_table_grant" {
  for_each    = postgresql_database.dbs
  database    = each.value.name
  role        = postgresql_role.db_writer_role[each.key].name
  schema      = "public"
  object_type = "table"
  privileges  = ["ALL"]
  depends_on = [
    postgresql_role.db_writer_role
  ]
}


##
## Setting up users and permissions
##
resource "postgresql_role" "roles" {
  for_each = var.users
  name     = each.key
  login    = true
  password = random_password.passwords[each.key].result
  roles    = local.user_roles[each.key]
}

# we have to make sure newly created tables are readable by the global reader role
resource "postgresql_default_privileges" "default_global_reader_grant" {
  for_each    = local.users_dbs_product
  role        = postgresql_role.global_reader_role.name
  database    = each.value.db
  owner       = each.value.user
  schema      = "public"
  object_type = "table"
  privileges  = ["SELECT"]
  depends_on = [
    postgresql_database.dbs,
    postgresql_role.roles
  ]
}

# we have to make sure newly created tables are accesible by the db writer role
resource "postgresql_default_privileges" "default_db_writer_grant" {
  for_each    = local.users_dbs_product
  role        = postgresql_role.db_writer_role[each.value.db].name
  database    = postgresql_database.dbs[each.value.db].name
  owner       = postgresql_role.roles[each.value.user].name
  schema      = "public"
  object_type = "table"
  privileges  = ["ALL"]
  depends_on = [
    postgresql_role.db_writer_role,
    postgresql_database.dbs,
    postgresql_role.roles
  ]
}
