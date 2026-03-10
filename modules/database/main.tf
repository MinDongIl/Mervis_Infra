# Secret Manager에서 데이터베이스 비밀번호 동적 조회
data "google_secret_manager_secret_version" "db_password" {
  secret  = "mervis-db-password"
  project = var.project_id
}

resource "google_sql_database_instance" "mervis_db" {
  name             = "mervis-test-db"
  database_version = "POSTGRES_14"
  region           = var.region

  settings {
    tier = "db-f1-micro"

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
    }

    ip_configuration {
      ipv4_enabled = true
    }
  }
  
  deletion_protection = false 
}

resource "google_sql_database" "default" {
  name     = "mervis_db"
  instance = google_sql_database_instance.mervis_db.name
}

resource "google_sql_user" "default" {
  name     = "mervis_admin"
  instance = google_sql_database_instance.mervis_db.name
  
  # 데이터 블록을 통해 가져온 비밀번호 주입
  password = data.google_secret_manager_secret_version.db_password.secret_data
}