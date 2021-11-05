databases = [
  "firstdb",
  "seconddb",
  "thirddb",
  "unassigneddb",
  "metrics"
]

users = {
  user1a = {
    database = "firstdb"
  }
  user1b = {
    database = "firstdb"
  }
  user2a = {
    database = "seconddb"
  }
  user2b = {
    database = "seconddb"
  }
  user3a = {
    database = "thirddb"
  }
  user3b = {
    database = "thirddb"
  }
  user_reader1 = {
    global_reader = true
  }
  user_reader2 = {
    global_reader = true
  }
  complicated_user = {
    global_reader = true
    database      = "metrics"
  }
}
