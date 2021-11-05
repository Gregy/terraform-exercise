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
      (info.global_reader == null ? false : info.global_reader) ? [postgresql_role.global_reader_role.name] : []
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
  name        = "global_reader_role"
  login       = false
  roles       = []
  search_path = []
}

##
## NOTE: I am using explicit dependencies a lot because I couldn't get implicit dependencies to work
##       Just accessing an input attribute from a resource I am depending on doesn't do the trick 
##       For example postgresql_grant.global_reader_db_grant uses postgresql_role.global_reader_role.name
##       but that is not enough to trigger the dependency. I had to explicitly set it too.
##


##
## Creating the databases and attached entities
##
resource "postgresql_database" "dbs" {
  for_each = var.databases
  name     = each.value
}
# revoke the default access permissions for everyone postgres creates by default
resource "postgresql_grant" "revoke_public_db" {
  for_each    = postgresql_database.dbs
  database    = each.value.name
  role        = "public"
  object_type = "database"
  privileges  = []
  depends_on = [
    postgresql_database.dbs
  ]
}
# revoke the default access permissions for everyone postgres creates by default
resource "postgresql_grant" "revoke_public_schema" {
  for_each    = postgresql_database.dbs
  database    = each.value.name
  role        = "public"
  schema      = "public"
  object_type = "schema"
  privileges  = []
  depends_on = [
    postgresql_database.dbs
  ]
}
resource "postgresql_grant" "global_reader_db_grant" {
  for_each    = postgresql_database.dbs
  database    = each.value.name
  role        = postgresql_role.global_reader_role.name
  object_type = "database"
  privileges  = ["CONNECT"]
  depends_on = [
    postgresql_database.dbs,
    postgresql_role.global_reader_role,
    # not including this leads to "tuple concurrently updated" errors
    # postgres doesn't like to do these concurently
    postgresql_grant.revoke_public_schema,
    postgresql_grant.revoke_public_db,
  ]
}
resource "postgresql_grant" "global_reader_schema_grant" {
  for_each    = postgresql_database.dbs
  database    = each.value.name
  schema      = "public"
  role        = postgresql_role.global_reader_role.name
  object_type = "schema"
  privileges  = ["USAGE"]
  depends_on = [
    postgresql_database.dbs,
    postgresql_role.global_reader_role,
    # not including this leads to "tuple concurrently updated" errors
    # postgres doesn't like to do these concurently
    postgresql_grant.global_reader_db_grant
  ]
}
# for the purposes of this excercise lets assume each db will only have a single schema ("public")
resource "postgresql_grant" "global_reader_grants_tables" {
  for_each    = postgresql_database.dbs
  database    = each.value.name
  role        = postgresql_role.global_reader_role.name
  schema      = "public"
  object_type = "table"
  privileges  = ["SELECT"]
  depends_on = [
    postgresql_database.dbs,
    postgresql_role.global_reader_role,
    # not including this leads to "tuple concurrently updated" errors
    # postgres doesn't like to do these concurently
    postgresql_grant.global_reader_schema_grant
  ]
}
resource "postgresql_grant" "global_reader_sequence_grant" {
  for_each    = postgresql_database.dbs
  database    = each.value.name
  role        = postgresql_role.global_reader_role.name
  schema      = "public"
  object_type = "sequence"
  privileges  = ["USAGE", "SELECT"]

  depends_on = [
    postgresql_database.dbs,
    postgresql_role.global_reader_role,
    # not including this leads to "tuple concurrently updated" errors
    # postgres doesn't like to do these concurently
    postgresql_grant.global_reader_grants_tables
  ]
}


# one writer role per database which will be assigned to individual writer users later
resource "postgresql_role" "db_writer_role" {
  for_each    = postgresql_database.dbs
  name        = "writer_${each.value.name}"
  login       = false
  roles       = []
  search_path = []
}
resource "postgresql_grant" "db_writer_db_grant" {
  for_each    = postgresql_database.dbs
  database    = each.value.name
  role        = postgresql_role.db_writer_role[each.key].name
  object_type = "database"
  privileges  = ["CONNECT", "TEMPORARY"]
  depends_on = [
    postgresql_database.dbs,
    postgresql_role.db_writer_role,
    # not including this leads to "tuple concurrently updated" errors
    # postgres doesn't like to do these concurently
    postgresql_grant.revoke_public_schema,
    postgresql_grant.revoke_public_db,
    postgresql_grant.global_reader_sequence_grant
  ]
}
resource "postgresql_grant" "db_writer_schema_grant" {
  for_each    = postgresql_database.dbs
  database    = each.value.name
  schema      = "public"
  role        = postgresql_role.db_writer_role[each.key].name
  object_type = "schema"
  privileges  = ["CREATE", "USAGE"]
  depends_on = [
    postgresql_database.dbs,
    postgresql_role.db_writer_role,
    # not including this leads to "tuple concurrently updated" errors
    # postgres doesn't like to do these concurently
    postgresql_grant.db_writer_db_grant,
  ]
}
resource "postgresql_grant" "db_writer_table_grant" {
  for_each    = postgresql_database.dbs
  database    = each.value.name
  role        = postgresql_role.db_writer_role[each.key].name
  schema      = "public"
  object_type = "table"
  privileges  = ["DELETE", "INSERT", "REFERENCES", "SELECT", "TRIGGER", "TRUNCATE", "UPDATE"]

  depends_on = [
    postgresql_database.dbs,
    postgresql_role.db_writer_role,
    # not including this leads to "tuple concurrently updated" errors
    # postgres doesn't like to do these concurently
    postgresql_grant.db_writer_schema_grant,
  ]
}
resource "postgresql_grant" "db_writer_sequence_grant" {
  for_each    = postgresql_database.dbs
  database    = each.value.name
  role        = postgresql_role.db_writer_role[each.key].name
  schema      = "public"
  object_type = "sequence"
  privileges  = ["USAGE", "SELECT", "UPDATE"]

  depends_on = [
    postgresql_database.dbs,
    postgresql_role.db_writer_role,
    # not including this leads to "tuple concurrently updated" errors
    # postgres doesn't like to do these concurently
    postgresql_grant.db_writer_table_grant,
  ]
}
resource "postgresql_grant" "db_writer_function_grant" {
  for_each    = postgresql_database.dbs
  database    = each.value.name
  role        = postgresql_role.db_writer_role[each.key].name
  schema      = "public"
  object_type = "function"
  privileges  = ["EXECUTE"]

  depends_on = [
    postgresql_database.dbs,
    postgresql_role.db_writer_role,
    # not including this leads to "tuple concurrently updated" errors
    # postgres doesn't like to do these concurently
    postgresql_grant.db_writer_sequence_grant,
  ]
}


##
## Setting up users and permissions
##
resource "postgresql_role" "roles" {
  for_each    = var.users
  name        = each.key
  login       = true
  password    = random_password.passwords[each.key].result
  roles       = local.user_roles[each.key]
  search_path = ["public"]
  depends_on = [
    postgresql_role.global_reader_role,
    postgresql_role.db_writer_role
  ]
}

# we have to make sure newly created object permissions are set up correctly

resource "postgresql_default_privileges" "default_global_reader_table_grant" {
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
resource "postgresql_default_privileges" "default_global_reader_sequence_grant" {
  for_each    = local.users_dbs_product
  role        = postgresql_role.global_reader_role.name
  database    = each.value.db
  owner       = each.value.user
  schema      = "public"
  object_type = "sequence"
  privileges  = ["USAGE", "SELECT"]
  depends_on = [
    postgresql_database.dbs,
    postgresql_role.roles
  ]
}

resource "postgresql_default_privileges" "default_db_writer_table_grant" {
  for_each    = local.users_dbs_product
  role        = postgresql_role.db_writer_role[each.value.db].name
  database    = postgresql_database.dbs[each.value.db].name
  owner       = postgresql_role.roles[each.value.user].name
  schema      = "public"
  object_type = "table"
  privileges  = ["DELETE", "INSERT", "REFERENCES", "SELECT", "TRIGGER", "TRUNCATE", "UPDATE"]
  depends_on = [
    postgresql_database.dbs,
    postgresql_role.roles
  ]
}
resource "postgresql_default_privileges" "default_db_writer_sequence_grant" {
  for_each    = local.users_dbs_product
  role        = postgresql_role.db_writer_role[each.value.db].name
  database    = postgresql_database.dbs[each.value.db].name
  owner       = postgresql_role.roles[each.value.user].name
  schema      = "public"
  object_type = "sequence"
  privileges  = ["USAGE", "SELECT", "UPDATE"]
  depends_on = [
    postgresql_database.dbs,
    postgresql_role.roles
  ]
}
resource "postgresql_default_privileges" "default_db_writer_function_grant" {
  for_each    = local.users_dbs_product
  role        = postgresql_role.db_writer_role[each.value.db].name
  database    = postgresql_database.dbs[each.value.db].name
  owner       = postgresql_role.roles[each.value.user].name
  schema      = "public"
  object_type = "function"
  privileges  = ["EXECUTE"]
  depends_on = [
    postgresql_database.dbs,
    postgresql_role.roles
  ]
}



output "users" {
  description = "The same format as the users input but also includes the 'password' field in the users information"
  # lets not print this to cli - we can still get the passwords from the state file
  sensitive = true
  value     = { for user, info in var.users : user => merge(info, { password = postgresql_role.roles[user].password }) }
}
