############################################
# VPC + subnet
############################################

resource "google_compute_network" "vpc" {
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${var.name_prefix}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.id

  # Required for Cloud Run / GKE-style private IP workloads that need
  # secondary ranges later; harmless to enable now.
  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata              = "INCLUDE_ALL_METADATA"
  }
}

############################################
# Private Services Access for Cloud SQL
# (Cloud SQL private IP requires a private connection to the VPC via
#  a reserved internal range + a service networking peering)
############################################

resource "google_compute_global_address" "private_ip_range" {
  name          = "${var.name_prefix}-sql-private-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]
}

############################################
# Serverless VPC Access connector
# Lets Cloud Run reach resources (Cloud SQL private IP) inside the VPC.
############################################

resource "google_vpc_access_connector" "connector" {
  name          = "${var.name_prefix}-connector"
  region        = var.region
  network       = google_compute_network.vpc.name
  ip_cidr_range = var.connector_cidr

  # Keep the connector small - min/max instances scale the underlying
  # connector VMs, not your app. Right-size instead of over-provisioning.
  min_instances = 2
  max_instances = 3
  machine_type  = "e2-micro"
}

############################################
# Firewall rules - deny by default, allow only what's required
############################################

# Google Cloud VPCs have an implied "deny all ingress" rule already, but
# we add explicit rules for clarity/auditability instead of relying on it.

resource "google_compute_firewall" "allow_connector_to_sql" {
  name    = "${var.name_prefix}-allow-connector-to-sql"
  network = google_compute_network.vpc.id

  direction = "EGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports    = ["5432", "3306"]
  }

  destination_ranges = [var.subnet_cidr]
  target_tags        = ["vpc-connector"]
}

resource "google_compute_firewall" "deny_all_ingress" {
  name      = "${var.name_prefix}-deny-all-ingress"
  network   = google_compute_network.vpc.id
  direction = "INGRESS"
  priority  = 65534

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]
}
