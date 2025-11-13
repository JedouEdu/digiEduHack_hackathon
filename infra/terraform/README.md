# EduScale Engine - Terraform Infrastructure

This folder contains Terraform configuration to provision core GCP infrastructure for the EduScale Engine service, including:

- **Google Artifact Registry**: Docker repository for container images
- **Google Cloud Run**: Managed container platform for the FastAPI application

## Prerequisites

Before using this Terraform configuration, ensure you have:

1. **Terraform CLI** installed (version >= 1.5)
   ```bash
   terraform version
   ```

2. **gcloud CLI** installed and authenticated
   ```bash
   gcloud auth application-default login
   ```

3. **GCP Project** already created
   ```bash
   gcloud projects list
   ```

4. **IAM Permissions**: Your user or service account needs the following roles:
   - `roles/run.admin` (Cloud Run Admin)
   - `roles/artifactregistry.admin` (Artifact Registry Admin)
   - `roles/serviceusage.serviceUsageAdmin` (Service Usage Admin - to enable APIs)
   - `roles/iam.serviceAccountUser` (if using a custom service account)
   
   Or simply `roles/editor` for a hackathon/development environment.

## Quick Start

### 1. Configure Variables

Create a `terraform.tfvars` file from the example:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and set your GCP project ID:

```hcl
project_id = "my-gcp-project-id"
region     = "europe-west1"
```

### 2. Initialize Terraform

```bash
terraform init
```

This downloads the Google Cloud provider and prepares your workspace.

### 3. Review the Plan

```bash
terraform plan
```

Review the resources that will be created:
- Artifact Registry repository
- Cloud Run service
- API enablement (run.googleapis.com, artifactregistry.googleapis.com)
- IAM policy for public access

### 4. Apply the Configuration

```bash
terraform apply
```

Type `yes` when prompted. Terraform will:
1. Enable required Google Cloud APIs
2. Create the Artifact Registry repository
3. Create the Cloud Run service (will fail initially if no image exists)
4. Configure public access

**Note**: The first `terraform apply` may fail if the Docker image doesn't exist yet. See "Building and Pushing Images" below.

### 5. View Outputs

After successful apply:

```bash
terraform output
```

You'll see:
- `cloud_run_url`: The public URL of your service
- `artifact_registry_repository`: The repository URL for pushing images
- `full_image_path`: The complete image path

## Building and Pushing Docker Images

Terraform does NOT build or push Docker images. You must do this separately:

### Build the Image

From the repository root:

```bash
docker build -f docker/Dockerfile -t europe-west1-docker.pkg.dev/YOUR_PROJECT_ID/eduscale-engine-repo/eduscale-engine:latest .
```

### Authenticate Docker with Artifact Registry

```bash
gcloud auth configure-docker europe-west1-docker.pkg.dev
```

### Push the Image

```bash
docker push europe-west1-docker.pkg.dev/YOUR_PROJECT_ID/eduscale-engine-repo/eduscale-engine:latest
```

### Deploy the New Image

After pushing a new image, update Cloud Run:

```bash
terraform apply
```

Or to deploy a specific tag:

```bash
terraform apply -var="image_tag=v1.0.0"
```

## Configuration Variables

### Required Variables

- `project_id`: Your GCP project ID (no default)

### Optional Variables (with defaults)

| Variable | Default | Description |
|----------|---------|-------------|
| `region` | `europe-west1` | GCP region for all resources |
| `service_name` | `eduscale-engine` | Cloud Run service name |
| `repository_id` | `eduscale-engine-repo` | Artifact Registry repository ID |
| `image_tag` | `latest` | Docker image tag to deploy |
| `service_version` | `0.1.0` | Service version (env var) |
| `environment` | `prod` | Environment name (env var) |
| `min_instance_count` | `0` | Minimum Cloud Run instances (0 = scale to zero) |
| `max_instance_count` | `10` | Maximum Cloud Run instances |
| `cpu` | `1` | CPU allocation (1 or 2 vCPU) |
| `memory` | `512Mi` | Memory allocation (512Mi, 1Gi, etc.) |
| `container_port` | `8080` | Container port (must match app) |
| `allow_unauthenticated` | `true` | Allow public access |

## Environment Variables

The Cloud Run service is configured with these environment variables (matching the FastAPI app):

- `ENV`: Deployment environment (from `var.environment`)
- `SERVICE_NAME`: Service name (from `var.service_name`)
- `SERVICE_VERSION`: Service version (from `var.service_version`)
- `GCP_PROJECT_ID`: GCP project ID (from `var.project_id`)
- `GCP_REGION`: GCP region (from `var.region`)
- `GCP_RUN_SERVICE`: Cloud Run service name (from `var.service_name`)

## Testing the Deployment

After successful deployment, test the health endpoint:

```bash
# Get the Cloud Run URL
CLOUD_RUN_URL=$(terraform output -raw cloud_run_url)

# Test the health endpoint
curl $CLOUD_RUN_URL/health
```

Expected response:
```json
{
  "status": "ok",
  "service": "eduscale-engine",
  "version": "0.1.0"
}
```

## Connection to the FastAPI Application

The Cloud Run service expects:
- A FastAPI application listening on port 8080
- A `/health` endpoint returning JSON
- Environment variables: `ENV`, `SERVICE_NAME`, `SERVICE_VERSION`, `GCP_PROJECT_ID`, `GCP_REGION`

The application code is in `src/eduscale/` and uses:
- `src/eduscale/main.py`: FastAPI app factory
- `src/eduscale/core/config.py`: Configuration management
- `src/eduscale/api/v1/routes_health.py`: Health endpoint

## Updating the Infrastructure

### Change Configuration

Edit `terraform.tfvars` or pass variables via command line:

```bash
terraform apply -var="max_instance_count=20" -var="memory=1Gi"
```

### Deploy New Image Tag

```bash
# Build and push new image with tag
docker build -f docker/Dockerfile -t europe-west1-docker.pkg.dev/YOUR_PROJECT_ID/eduscale-engine-repo/eduscale-engine:v1.0.0 .
docker push europe-west1-docker.pkg.dev/YOUR_PROJECT_ID/eduscale-engine-repo/eduscale-engine:v1.0.0

# Update Terraform
terraform apply -var="image_tag=v1.0.0"
```

### Scale to Zero for Cost Savings

```bash
terraform apply -var="min_instance_count=0"
```

## Destroying Resources

To remove all infrastructure:

```bash
terraform destroy
```

**Warning**: This will delete:
- The Cloud Run service
- The Artifact Registry repository (and all images)
- IAM policies

## Remote State (Optional)

For team collaboration, consider using remote state in GCS:

1. Create a GCS bucket:
   ```bash
   gsutil mb -l europe-west1 gs://your-terraform-state-bucket
   ```

2. Enable versioning:
   ```bash
   gsutil versioning set on gs://your-terraform-state-bucket
   ```

3. Uncomment the backend block in `versions.tf`:
   ```hcl
   backend "gcs" {
     bucket = "your-terraform-state-bucket"
     prefix = "eduscale-engine/terraform/state"
   }
   ```

4. Re-initialize:
   ```bash
   terraform init -migrate-state
   ```

## Future Enhancements

This Terraform configuration is phase 1. Future additions will include:

- **Cloud Storage buckets** for file uploads
- **BigQuery datasets** for analytics
- **Cloud SQL** or **Firestore** for metadata storage
- **Cloud Functions** for ML model inference
- **VPC configuration** for private networking
- **Custom service accounts** with fine-grained IAM
- **Cloud Monitoring** alerts and dashboards
- **Cloud CDN** for static assets

## Troubleshooting

### Error: Image not found

```
Error: Error creating Service: Image 'europe-west1-docker.pkg.dev/...' not found
```

**Solution**: Build and push the Docker image first (see "Building and Pushing Images" above).

### Error: API not enabled

```
Error: Error creating Repository: googleapi: Error 403: Artifact Registry API has not been used
```

**Solution**: Wait a few minutes for API enablement to propagate, then run `terraform apply` again.

### Error: Permission denied

```
Error: Error creating Service: Permission denied
```

**Solution**: Ensure your user has the required IAM roles (see Prerequisites).

### Cloud Run service not accessible

**Solution**: Check that `allow_unauthenticated = true` and the IAM policy was created:

```bash
gcloud run services get-iam-policy eduscale-engine --region=europe-west1
```

## Support

For issues related to:
- **Terraform configuration**: Check this README and Terraform docs
- **GCP resources**: Check Google Cloud documentation
- **Application code**: See the main repository README at `../../README.md`

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                     Developer                            │
│                                                          │
│  1. terraform apply                                      │
│  2. docker build & push                                  │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│              Google Cloud Platform                       │
│                                                          │
│  ┌──────────────────────────────────────────────────┐  │
│  │     Artifact Registry (europe-west1)             │  │
│  │                                                  │  │
│  │  eduscale-engine-repo/                          │  │
│  │    └── eduscale-engine:latest                   │  │
│  └──────────────────────────────────────────────────┘  │
│                         │                               │
│                         │ pulls image                   │
│                         ▼                               │
│  ┌──────────────────────────────────────────────────┐  │
│  │     Cloud Run (europe-west1)                     │  │
│  │                                                  │  │
│  │  Service: eduscale-engine                       │  │
│  │  ├── Min instances: 0                           │  │
│  │  ├── Max instances: 10                          │  │
│  │  ├── CPU: 1                                     │  │
│  │  ├── Memory: 512Mi                              │  │
│  │  └── Port: 8080                                 │  │
│  │                                                  │  │
│  │  Public URL: https://eduscale-engine-xxx.run.app│  │
│  └──────────────────────────────────────────────────┘  │
│                         │                               │
└─────────────────────────┼───────────────────────────────┘
                          │
                          ▼
                    ┌──────────┐
                    │  Users   │
                    │  /health │
                    └──────────┘
```

## License

This infrastructure code is part of the EduScale Engine project.
