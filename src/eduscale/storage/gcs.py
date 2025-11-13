"""Google Cloud Storage backend."""

import re
from typing import BinaryIO, Optional
from datetime import timedelta

from google.cloud import storage

from eduscale.core.config import settings
from eduscale.storage.base import StorageBackend


class GCSStorageBackend(StorageBackend):
    """Google Cloud Storage backend."""

    def __init__(self):
        self._client: Optional[storage.Client] = None
        self._bucket: Optional[storage.Bucket] = None

    def _get_bucket(self) -> storage.Bucket:
        """Lazy-load and cache GCS bucket."""
        if self._bucket is None:
            if not settings.GCS_BUCKET_NAME:
                raise ValueError("GCS_BUCKET_NAME not configured")

            self._client = storage.Client(project=settings.GCP_PROJECT_ID)
            self._bucket = self._client.bucket(settings.GCS_BUCKET_NAME)

        return self._bucket

    def get_target_path(self, file_id: str, file_name: str) -> str:
        """Generate GCS target path."""
        safe_name = self._sanitize_filename(file_name)
        blob_path = f"raw/{file_id}/{safe_name}"
        return f"gs://{settings.GCS_BUCKET_NAME}/{blob_path}"

    def generate_signed_upload_url(
        self,
        file_id: str,
        file_name: str,
        content_type: str,
        size_bytes: int,
        expiration_minutes: int = 15,
    ) -> tuple[str, str]:
        """Generate V4 signed URL for direct upload using IAM signBlob API.

        Returns:
            Tuple of (signed_url, blob_path)
        """
        from google.auth import default, iam
        from google.auth.transport import requests as auth_requests
        import google.auth.credentials
        
        bucket = self._get_bucket()

        safe_name = self._sanitize_filename(file_name)
        blob_path = f"raw/{file_id}/{safe_name}"
        blob = bucket.blob(blob_path)

        # Get default credentials (works in Cloud Run)
        credentials, project = default()
        
        # Create a signer using IAM signBlob API
        # This doesn't require a private key, just the iam.serviceAccountTokenCreator permission
        auth_request = auth_requests.Request()
        
        # Get the service account email
        if hasattr(credentials, 'service_account_email'):
            service_account_email = credentials.service_account_email
        else:
            # For compute engine, get from metadata
            service_account_email = credentials.signer_email if hasattr(credentials, 'signer_email') else None
            
        if not service_account_email:
            raise ValueError("Could not determine service account email from credentials")
        
        # Create IAM signer
        signer = iam.Signer(
            request=auth_request,
            credentials=credentials,
            service_account_email=service_account_email
        )
        
        # Create signing credentials
        signing_credentials = google.auth.credentials.Credentials()
        signing_credentials._signer = signer
        
        # Generate V4 signed URL for PUT using IAM signing
        signed_url = blob.generate_signed_url(
            version="v4",
            expiration=timedelta(minutes=expiration_minutes),
            method="PUT",
            content_type=content_type,
            headers={"Content-Type": content_type},
            credentials=signing_credentials,
            service_account_email=service_account_email,
        )

        return signed_url, blob_path

    def check_file_exists(self, file_id: str, file_name: str) -> bool:
        """Check if file exists in GCS."""
        bucket = self._get_bucket()
        safe_name = self._sanitize_filename(file_name)
        blob_path = f"raw/{file_id}/{safe_name}"
        blob = bucket.blob(blob_path)
        return blob.exists()

    async def store_file(
        self, file_id: str, file_name: str, content_type: str, file_data: BinaryIO
    ) -> str:
        """Upload file to GCS."""
        bucket = self._get_bucket()

        safe_name = self._sanitize_filename(file_name)
        blob_path = f"raw/{file_id}/{safe_name}"
        blob = bucket.blob(blob_path)

        # Stream upload in chunks
        blob.content_type = content_type
        blob.upload_from_file(file_data, rewind=True)

        return f"gs://{settings.GCS_BUCKET_NAME}/{blob_path}"

    def get_backend_name(self) -> str:
        return "gcs"

    @staticmethod
    def _sanitize_filename(filename: str) -> str:
        """Remove path traversal and dangerous characters."""
        safe = filename.replace("../", "").replace("..\\", "")
        safe = safe.replace("/", "_").replace("\\", "_")
        safe = re.sub(r"[^a-zA-Z0-9._-]", "_", safe)
        return safe[:255]


# Singleton instance
gcs_backend = GCSStorageBackend()
