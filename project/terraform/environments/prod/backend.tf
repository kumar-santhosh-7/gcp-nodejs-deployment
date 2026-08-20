# Remote state in GCS with locking, so CI runs and local runs never
# clobber each other and state is never committed to git.
#
# Create the bucket once, manually, before first `terraform init`:
#   gsutil mb -l asia-south1 gs://YOUR_PROJECT_ID-tfstate
#   gsutil versioning set on gs://YOUR_PROJECT_ID-tfstate
#
# Then fill in the bucket name below (or pass -backend-config in CI).

terraform {
  backend "gcs" {
    bucket = "REPLACE_WITH_YOUR_TFSTATE_BUCKET"
    prefix = "nodeapp/prod"
  }
}
