# Design Document

## Overview

The MIME Decoder Service is an orchestration microservice that receives file upload events from Eventarc, classifies files by MIME type, and routes them to the Transformer service for processing. It acts as the central coordinator in the event-driven data processing pipeline.

### Key Design Principles

1. **Lightweight Orchestration**: Minimal processing, focus on routing
2. **Fast Response**: Return quickly to Eventarc to avoid timeouts
3. **Fire-and-Forget**: Don't block on Backend status updates
4. **Structured Logging**: JSON logs with correlation IDs
5. **Fail-Fast**: Clear error responses for validation vs processing errors

## Architecture

### High-Level Flow

```
Eventarc → MIME Decoder (CloudEvents)
    ↓
Parse event & extract metadata
    ↓
Classify MIME type → category (text/image/audio/archive/other)
    ↓
Call Transformer service
    ↓
(async) Update Backend with status
    ↓
Return 200 to Eventarc
```

### Module Structure

```
src/eduscale/
├── mime_decoder/
│   ├── __init__.py
│   ├── classifier.py          # MIME type classification logic
│   ├── metadata.py            # File metadata extraction
│   └── orchestrator.py        # Main orchestration logic
├── api/
│   └── v1/
│       └── routes_mime.py     # FastAPI endpoints
└── core/
    └── config.py              # Configuration (extended)
```


## Components and Interfaces

### 1. CloudEvents Handler (routes_mime.py)

**Purpose**: Receive and parse CloudEvents from Eventarc

**Interface**:
```python
@router.post("/api/v1/mime/decode")
async def decode_file(request: Request) -> JSONResponse:
    """Receive CloudEvents from Eventarc and orchestrate processing."""
```

**CloudEvents Payload**:
```json
{
  "specversion": "1.0",
  "type": "google.cloud.storage.object.v1.finalized",
  "source": "//storage.googleapis.com/projects/_/buckets/BUCKET",
  "subject": "objects/uploads/region-123/file-456.pdf",
  "id": "event-id-123",
  "time": "2025-11-13T10:30:00Z",
  "data": {
    "bucket": "eduscale-uploads-eu",
    "name": "uploads/region-123/file-456.pdf",
    "contentType": "application/pdf",
    "size": "1048576"
  }
}
```

**Response**:
- 200: Successfully queued for processing
- 400: Invalid event payload (no retry)
- 500: Processing error (Eventarc will retry)



### 2. Metadata Extractor (metadata.py)

**Purpose**: Extract file_id and region_id from object path

**Interface**:
```python
@dataclass
class FileMetadata:
    file_id: str
    region_id: str
    bucket: str
    object_name: str
    content_type: str
    size: int

def extract_metadata(event_data: dict) -> FileMetadata:
    """Extract metadata from CloudEvents data."""
```

**Path Parsing**:
- Pattern: `uploads/{region_id}/{file_id}.{ext}`
- Example: `uploads/region-cz-01/abc123.pdf` → region_id=`region-cz-01`, file_id=`abc123`

### 3. MIME Type Classifier (classifier.py)

**Purpose**: Classify files into processing categories

**Interface**:
```python
def classify_mime_type(content_type: str) -> Literal["text", "image", "audio", "archive", "other"]:
    """Classify MIME type into processing category."""
```

**Classification Rules**:
```python
MIME_CATEGORIES = {
    "text": [
        "text/*",
        "application/pdf",
        "application/vnd.openxmlformats-officedocument.*",
        "application/vnd.ms-*",
        "application/json",
        "application/xml"
    ],
    "image": ["image/*"],
    "audio": ["audio/*", "video/*"],
    "archive": [
        "application/zip",
        "application/x-tar",
        "application/gzip",
        "application/x-rar"
    ]
}
```



### 4. Orchestrator (orchestrator.py)

**Purpose**: Coordinate the processing flow

**Interface**:
```python
@dataclass
class ProcessingRequest:
    file_id: str
    region_id: str
    bucket: str
    object_name: str
    content_type: str
    file_category: str
    size: int

@dataclass
class ProcessingResult:
    status: Literal["INGESTED", "FAILED"]
    message: str
    processing_time_ms: int

async def process_file(metadata: FileMetadata) -> ProcessingResult:
    """Orchestrate file processing."""
```

**Flow**:
1. Classify MIME type
2. Build ProcessingRequest
3. Call Transformer service (async with timeout)
4. Fire-and-forget status update to Backend
5. Return result



### 5. Transformer Client

**Purpose**: Call Transformer service

**Interface**:
```python
async def call_transformer(request: ProcessingRequest) -> dict:
    """Call Transformer service to process file."""
```

**Request to Transformer**:
```json
{
  "file_id": "abc123",
  "region_id": "region-cz-01",
  "bucket": "eduscale-uploads-eu",
  "object_name": "uploads/region-cz-01/abc123.pdf",
  "content_type": "application/pdf",
  "file_category": "text",
  "size": 1048576
}
```

**Response from Transformer**:
```json
{
  "status": "INGESTED",
  "text_uri": "gs://eduscale-uploads-eu/text/abc123.txt",
  "processing_time_ms": 5000
}
```

### 6. Backend Client

**Purpose**: Update Backend with processing status (fire-and-forget)

**Interface**:
```python
async def update_backend_status(file_id: str, status: str, details: dict) -> None:
    """Update Backend with processing status (non-blocking)."""
```

**Request to Backend**:
```json
{
  "file_id": "abc123",
  "status": "PROCESSING",
  "stage": "TRANSFORMER",
  "timestamp": "2025-11-13T10:30:05Z"
}
```



## Error Handling

### Error Categories

| Error Type | HTTP Status | Eventarc Action | Example |
|------------|-------------|-----------------|---------|
| Invalid CloudEvents | 400 | No retry | Missing required fields |
| Invalid path format | 400 | No retry | Cannot parse file_id |
| Transformer timeout | 500 | Retry | Request timeout after 300s |
| Transformer error | 500 | Retry | Transformer returns 500 |
| Backend update failure | - | Log only | Don't fail the request |

### Logging Strategy

**Structured JSON Logs**:
```json
{
  "timestamp": "2025-11-13T10:30:00Z",
  "level": "INFO",
  "correlation_id": "event-id-123",
  "file_id": "abc123",
  "region_id": "region-cz-01",
  "event": "file_classified",
  "mime_type": "application/pdf",
  "category": "text"
}
```

**Log Levels**:
- INFO: Successful processing steps
- WARNING: Retryable errors (Transformer timeout)
- ERROR: Non-retryable errors (invalid payload)



## Configuration

### Environment Variables

```python
class Settings(BaseSettings):
    # Service URLs
    TRANSFORMER_SERVICE_URL: str
    BACKEND_SERVICE_URL: str
    
    # GCP Configuration
    GCP_PROJECT_ID: str
    GCP_REGION: str = "europe-west1"
    
    # Timeouts
    REQUEST_TIMEOUT: int = 300  # seconds
    BACKEND_UPDATE_TIMEOUT: int = 5  # seconds
    
    # Logging
    LOG_LEVEL: str = "INFO"
    
    # Cloud Run
    PORT: int = 8080
```

## Deployment

### Cloud Run Configuration

```yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: mime-decoder
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/minScale: "0"
        autoscaling.knative.dev/maxScale: "10"
    spec:
      containerConcurrency: 80
      timeoutSeconds: 300
      containers:
      - image: gcr.io/PROJECT_ID/mime-decoder:latest
        resources:
          limits:
            memory: 512Mi
            cpu: "1"
        env:
        - name: TRANSFORMER_SERVICE_URL
          value: "https://transformer-service-xxx.run.app"
        - name: BACKEND_SERVICE_URL
          value: "https://backend-service-xxx.run.app"
        - name: GCP_PROJECT_ID
          value: "eduscale-prod"
        - name: GCP_REGION
          value: "europe-west1"
```

### Health Check

```python
@router.get("/health")
async def health_check():
    """Health check endpoint for Cloud Run."""
    # Check Transformer connectivity
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{settings.TRANSFORMER_SERVICE_URL}/health",
                timeout=5
            )
            transformer_healthy = response.status_code == 200
    except:
        transformer_healthy = False
    
    if transformer_healthy:
        return {"status": "healthy", "transformer": "ok"}
    else:
        return JSONResponse(
            status_code=503,
            content={"status": "unhealthy", "transformer": "unavailable"}
        )
```



## Testing Strategy

### Unit Tests

1. **test_classifier.py**: Test MIME type classification logic
2. **test_metadata.py**: Test path parsing and metadata extraction
3. **test_orchestrator.py**: Test orchestration flow with mocked Transformer

### Integration Tests

1. **test_cloudevents.py**: Test CloudEvents parsing
2. **test_transformer_integration.py**: Test Transformer service calls
3. **test_error_handling.py**: Test error scenarios and retries

### Test Fixtures

```python
# tests/fixtures/cloudevents.json
{
  "valid_pdf_event": {
    "specversion": "1.0",
    "type": "google.cloud.storage.object.v1.finalized",
    "data": {
      "bucket": "test-bucket",
      "name": "uploads/region-test/file123.pdf",
      "contentType": "application/pdf",
      "size": "1024"
    }
  }
}
```

## Security Considerations

1. **Authentication**: Cloud Run requires authentication, only Eventarc service account can invoke
2. **No Data Access**: MIME Decoder never reads file content, only metadata
3. **Timeout Protection**: 300s timeout prevents hanging requests
4. **Input Validation**: Strict validation of CloudEvents payload
5. **Regional Deployment**: EU region for data locality

