"""
MIME Decoder service implementation.

Handles CloudEvent processing and routes files to appropriate transformers.
"""

import json
import logging
from typing import Dict, Any

from eduscale.services.mime_decoder.classifier import classify_mime_type
from eduscale.services.mime_decoder.models import CloudEvent, ProcessingRequest

# Configure structured logging for Cloud Logging
logger = logging.getLogger(__name__)


def process_cloud_event(event_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process a CloudEvent from Eventarc.

    Args:
        event_data: Raw CloudEvent data from Eventarc

    Returns:
        Response dictionary with status and details

    Raises:
        ValueError: If event data is invalid
        Exception: For unexpected processing errors
    """
    try:
        # Parse CloudEvent
        cloud_event = CloudEvent(**event_data)

        # Log event receipt
        logger.info(
            "CloudEvent received",
            extra={
                "event_id": cloud_event.id,
                "event_type": cloud_event.type,
                "bucket": cloud_event.data.bucket,
                "object_name": cloud_event.data.name,
                "content_type": cloud_event.data.contentType,
                "size_bytes": cloud_event.data.size,
                "timestamp": cloud_event.time.isoformat(),
            },
        )

        # Classify file type
        file_category = classify_mime_type(cloud_event.data.contentType)

        # Create processing request
        processing_req = ProcessingRequest.from_cloud_event(
            cloud_event, file_category.value
        )

        # Log successful classification
        logger.info(
            "File classified successfully",
            extra={
                "event_id": cloud_event.id,
                "file_id": processing_req.file_id,
                "file_category": file_category.value,
                "content_type": cloud_event.data.contentType,
            },
        )

        # TODO: Route to Transformer service based on file_category
        # For now, just return success

        return {
            "status": "success",
            "event_id": cloud_event.id,
            "file_id": processing_req.file_id,
            "file_category": file_category.value,
            "message": "Event processed successfully",
        }

    except ValueError as e:
        # Client error - invalid event data (4xx)
        logger.error(
            "Invalid CloudEvent data",
            extra={
                "error": str(e),
                "error_type": "validation_error",
                "event_data": json.dumps(event_data, default=str),
            },
            exc_info=True,
        )
        raise

    except Exception as e:
        # Server error - unexpected processing error (5xx)
        # Extract event metadata if possible for logging
        event_id = event_data.get("id", "unknown")
        event_type = event_data.get("type", "unknown")
        bucket = event_data.get("data", {}).get("bucket", "unknown")
        object_name = event_data.get("data", {}).get("name", "unknown")
        content_type = event_data.get("data", {}).get("contentType", "unknown")
        size = event_data.get("data", {}).get("size", "unknown")

        # Structured error log with full context for failed events
        logger.error(
            "Failed to process CloudEvent",
            extra={
                "event_id": event_id,
                "event_type": event_type,
                "bucket": bucket,
                "object_name": object_name,
                "content_type": content_type,
                "size_bytes": size,
                "error": str(e),
                "error_type": type(e).__name__,
            },
            exc_info=True,
        )
        raise


def log_retry_failure(
    event_id: str,
    bucket: str,
    object_name: str,
    content_type: str,
    size_bytes: str,
    error_message: str,
    retry_count: int,
    initial_timestamp: str,
    final_timestamp: str,
) -> None:
    """
    Log final failure after all retry attempts are exhausted.

    This is called by Eventarc after all retries fail.
    The log entry contains all information needed for manual reprocessing.

    Args:
        event_id: Unique CloudEvent ID
        bucket: Cloud Storage bucket name
        object_name: Object path in bucket
        content_type: MIME type of the file
        size_bytes: File size in bytes
        error_message: Last error message from MIME Decoder
        retry_count: Total number of retry attempts
        initial_timestamp: Timestamp of first attempt
        final_timestamp: Timestamp of final failure
    """
    logger.error(
        "Event processing failed after all retries exhausted",
        extra={
            "severity": "ERROR",
            "event_id": event_id,
            "bucket": bucket,
            "object_name": object_name,
            "content_type": content_type,
            "size_bytes": size_bytes,
            "error_message": error_message,
            "retry_count": retry_count,
            "initial_timestamp": initial_timestamp,
            "final_timestamp": final_timestamp,
            "manual_reprocessing_required": True,
        },
    )
