module "github_repository" {
  source                   = "github.com/bicyclecat/tf-github-repository"
  github_owner             = var.GITHUB_OWNER
  github_token             = var.GITHUB_TOKEN
  repository_name          = var.FLUX_GITHUB_REPO
  public_key_openssh       = module.tls_private_key.public_key_openssh
  public_key_openssh_title = "flux0"
}

module "google_gke_cluster" {
  source = "github.com/bicyclecat/tf-google-gke-cluster"
  google_region       = var.GOOGLE_REGION
  google_project      = var.GOOGLE_PROJECT
  deletion_protection = var.GKE_DELETION_PROTECTION
  num_nodes           = var.GKE_NUM_NODES
  machine_type        = var.GKE_MACHINE_TYPE
  disk_type           = var.GKE_DISK_TYPE
  disk_size_gb        = var.GKE_DISK_SIZE_GB
}

module "flux_bootstrap" {
  source            = "github.com/bicyclecat/tf-fluxcd-flux-bootstrap"
  github_repository = "${var.GITHUB_OWNER}/${var.FLUX_GITHUB_REPO}"
  private_key       = module.tls_private_key.private_key_pem
  config_path       = module.google_gke_cluster.cluster_data.kubeconfig
  github_token      = var.GITHUB_TOKEN
}

module "kubernetes_add_sops" {
  source           = "github.com/bicyclecat/tf-kubernetes-sops"
  secret_name      = module.flux_bootstrap.flux_bootstrap_data.secret_name
  secret_namespace = "flux-system"
  private_key      = module.gpg_keys.private_key
  public_key       = module.gpg_keys.public_key
  config_path      = module.google_gke_cluster.cluster_data.kubeconfig
  public_key_path  = pathexpand("${path.root}/.sops.pub.asc")
}

terraform {
  backend "gcs" {
    bucket  = "tf-gke-flux-backend"
    prefix  = "terraform/state"
  }
}

module "tls_private_key" {
  source    = "github.com/bicyclecat/tf-hashicorp-tls-keys"
  algorithm = "RSA"
}

module "gpg_keys" {
  source   = "github.com/bicyclecat/tf-gpg-keys"
  gpg_name = var.SOPS_SECRET_NAME
}

output "kubepath" {
  value = module.google_gke_cluster.cluster_data.kubeconfig
}