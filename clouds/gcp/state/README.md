# Terraform module to provision a GCS bucket for the Terraform state backend
This module creates a Google Cloud Storage bucket with versioning enabled for the Terraform state of the `clouds/gcp` module.

## Requirements
- Terraform on the host machine.
- The Google Cloud CLI, authenticated with Application Default Credentials (`gcloud auth application-default login`), or `GOOGLE_CREDENTIALS` set to a service account key.
- Permission to create buckets in the target project (`roles/storage.admin`).

## Inputs

| Name          | Type     | Description                                                                             | Required |
| ------------- | -------- | --------------------------------------------------------------------------------------- | -------- |
| `PROJECT_ID`  | `string` | ID of the GCP project for the bucket.                                                   | Yes      |
| `REGION`      | `string` | GCP region of the bucket. Defaults to `us-central1`.                                    | No       |
| `BUCKET_NAME` | `string` | Prefix of the bucket name. The module appends a random suffix to keep the name unique.  | No       |

## Outputs

| Name          | Description                                  |
| ------------- | -------------------------------------------- |
| `bucket_name` | Name of the bucket for the Terraform state.  |

## Usage
Create the bucket:

```bash
terraform init
terraform apply \
  -var="PROJECT_ID=my-project-id" \
  -var="REGION=us-central1" \
  -var="BUCKET_NAME=tfstate"
```

Copy the `bucket_name` output into the `backend "gcs"` block of `clouds/gcp/versions.tf` before you initialize the main module.

Keep the bucket for as long as the environment exists. Destroy the main module before this one.

The bucket keeps every version of the state file, and GCS refuses to delete a bucket that still holds objects. Empty it before you run `terraform destroy`:

```bash
gcloud storage rm --recursive --all-versions "gs://<bucket_name>/**"
```
