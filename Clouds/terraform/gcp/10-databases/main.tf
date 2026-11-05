# Terraform owns the servers. The loader owns the databases and logins (D9).

locals {
  project   = "floci-local"
  zone      = "us-central1-a"
  namespace = "local-gcp" # FLOCI_GCP_DOCKER_RESOURCE_NAMESPACE
  # floci-gcp names the VM container floci-gcp-<namespace>-compute-<project>-<zone>-<instance>.
  # Docker DNS only resolves names up to 63 characters, so the instance name is kept short.
  mssql_instance = "mssql-vm"
}

# --- PostgreSQL: Cloud SQL -------------------------------------------------
resource "google_sql_database_instance" "postgres" {
  name                = "cloud-postgres"
  database_version    = "POSTGRES_17"
  region              = "us-central1"
  deletion_protection = false

  settings {
    tier = "db-custom-1-3840"
  }
}

# --- SQL Server: Compute Engine + container (Cloud SQL has no SQL Server here) ---
resource "google_compute_network" "cloud" {
  name                    = "cloud-net"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "cloud" {
  name          = "cloud-subnet"
  network       = google_compute_network.cloud.id
  region        = "us-central1"
  ip_cidr_range = "10.43.0.0/24"
}

resource "google_compute_firewall" "allow_mssql" {
  name    = "allow-mssql"
  network = google_compute_network.cloud.name

  allow {
    protocol = "tcp"
    ports    = ["1433"]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_instance" "mssql" {
  name         = local.mssql_instance
  machine_type = "e2-standard-2" # floci-gcp catalog: e2-standard-2, n2-standard-4/8, c3/g2 only
  zone         = local.zone

  boot_disk {
    initialize_params {
      image = "cos-cloud/cos-stable"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.cloud.id
  }

  metadata = {
    gce-container-declaration = yamlencode({
      spec = {
        containers = [{
          name  = "mssql"
          image = "mcr.microsoft.com/mssql/server:2025-latest"
          env = [
            { name = "ACCEPT_EULA", value = "Y" },
            { name = "MSSQL_SA_PASSWORD", value = var.db_admin_password },
            { name = "MSSQL_AGENT_ENABLED", value = "true" },
          ]
        }]
        restartPolicy = "Always"
      }
    })
  }

  depends_on = [google_compute_firewall.allow_mssql]
}
