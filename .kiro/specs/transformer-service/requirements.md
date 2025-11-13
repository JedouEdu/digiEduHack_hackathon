# Requirements Document

## Introduction

The Transformer Service is a processing microservice that converts various file formats into text representation. It receives requests from the MIME Decoder, retrieves files from Cloud Storage, performs format-specific transformations (text extraction, OCR, ASR, archive unpacking), saves the extracted text back to Cloud Storage, and forwards the text URI to the Tabular service for structured data analysis.

The Transformer operates as part of the pipeline: MIME Decoder → **Transformer** → Tabular → BigQuery.

## Glossary

- **Transformer Service**: Microservice that converts files to text format
- **Text Extraction**: Process of extracting text from documents (PDF, DOCX, etc.)
- **OCR**: Optical Character Recognition for extracting text from images
- **ASR**: Automatic Speech Recognition for transcribing audio to text
- **Archive Unpacking**: Extracting files from ZIP, TAR, and other archives
- **Text URI**: Cloud Storage URI pointing to extracted text (e.g., gs://bucket/text/file_id.txt)
- **Tabular Service**: Downstream service that analyzes text structure and loads to BigQuery
- **File Category**: Classification from MIME Decoder (text, image, audio, archive, other)

## Requirements

### Requirement 1: File Retrieval from Cloud Storage

**User Story:** As a developer, I want the Transformer to retrieve files from Cloud Storage, so that it can process uploaded files.

#### Acceptance Criteria

1. WHEN a processing request is received, THE Transformer SHALL retrieve the file from Cloud Storage using the provided bucket and object name
2. THE Transformer SHALL use the google-cloud-storage client library for file retrieval
3. WHEN the file size exceeds 100MB, THE Transformer SHALL stream the file instead of loading it entirely into memory
4. WHEN the file cannot be retrieved, THE Transformer SHALL return HTTP 500 with error details
5. THE Transformer SHALL log the file retrieval operation with file size and duration



### Requirement 2: Text Extraction from Documents

**User Story:** As a data engineer, I want text extracted from documents, so that tabular data can be analyzed.

#### Acceptance Criteria

1. WHEN the file category is "text" and content type is application/pdf, THE Transformer SHALL extract text using PyPDF2 or pdfplumber
2. WHEN the file category is "text" and content type is application/vnd.openxmlformats-officedocument.wordprocessingml.document, THE Transformer SHALL extract text using python-docx
3. WHEN the file category is "text" and content type is text/*, THE Transformer SHALL read the file as plain text with UTF-8 encoding
4. WHEN the file category is "text" and content type is application/vnd.ms-excel or CSV, THE Transformer SHALL preserve the raw text structure
5. WHEN text extraction fails, THE Transformer SHALL log the error and return HTTP 500
6. THE Transformer SHALL preserve line breaks and basic formatting in extracted text

### Requirement 3: ASR for Audio Files

**User Story:** As a data engineer, I want audio transcribed to text, so that spoken content can be analyzed.

#### Acceptance Criteria

1. WHEN the file category is "audio", THE Transformer SHALL use speech recognition to transcribe audio to text
2. THE Transformer SHALL support common audio formats (MP3, WAV, M4A, OGG)
3. THE Transformer SHALL use Google Cloud Speech-to-Text API or similar service
4. WHEN transcription is performed, THE Transformer SHALL specify language (English or Czech)
5. WHEN the audio contains no speech, THE Transformer SHALL return empty text with a warning
6. WHEN ASR fails, THE Transformer SHALL log the error and return HTTP 500
7. THE Transformer SHALL include audio metadata (duration, format) in logs

### Requirement 4: Archive Unpacking

**User Story:** As a data engineer, I want archives unpacked and each file processed, so that bulk uploads are handled automatically.

#### Acceptance Criteria

1. WHEN the file category is "archive", THE Transformer SHALL unpack the archive to a temporary directory
2. THE Transformer SHALL support ZIP, TAR, TAR.GZ, and RAR formats
3. WHEN an archive is unpacked, THE Transformer SHALL process each file individually
4. THE Transformer SHALL recursively unpack nested archives up to 2 levels deep
5. WHEN processing archive contents, THE Transformer SHALL save each extracted text with a unique name (file_id_001.txt, file_id_002.txt)
6. THE Transformer SHALL limit archive size to 500MB to prevent resource exhaustion
7. WHEN unpacking fails, THE Transformer SHALL log the error and return HTTP 500



### Requirement 5: Text Storage to Cloud Storage

**User Story:** As a system architect, I want extracted text saved to Cloud Storage, so that it can be accessed by downstream services.

#### Acceptance Criteria

1. WHEN text extraction completes, THE Transformer SHALL save the text to Cloud Storage
2. THE text file SHALL be saved to gs://{bucket}/text/{file_id}.txt
3. WHEN processing archives, THE Transformer SHALL save multiple text files (file_id_001.txt, file_id_002.txt, etc.)
4. THE Transformer SHALL use UTF-8 encoding for all text files
5. THE Transformer SHALL set appropriate metadata on the Cloud Storage object (content type, original file info)
6. WHEN saving fails, THE Transformer SHALL log the error and return HTTP 500
7. THE Transformer SHALL return the text_uri (or list of text_uris for archives) in the response

### Requirement 6: Tabular Service Integration

**User Story:** As a system architect, I want the Transformer to forward text to the Tabular service, so that structured data can be extracted.

#### Acceptance Criteria

1. WHEN text is saved to Cloud Storage, THE Transformer SHALL call the Tabular service with the text_uri
2. THE Transformer SHALL send file_id, region_id, text_uri, and original_content_type to Tabular
3. WHEN processing archives, THE Transformer SHALL call Tabular for each extracted text file
4. THE Transformer SHALL use HTTP POST to invoke the Tabular service endpoint
5. WHEN the Tabular service returns success, THE Transformer SHALL include the Tabular response in its own response
6. WHEN the Tabular service returns an error, THE Transformer SHALL log the error but still return success (text extraction succeeded)
7. THE Transformer SHALL set a timeout of 600 seconds for Tabular calls



### Requirement 7: Error Handling and Logging

**User Story:** As a DevOps engineer, I want comprehensive error logging, so that I can debug transformation failures.

#### Acceptance Criteria

1. WHEN any error occurs, THE Transformer SHALL log the error with full context (file_id, region_id, file_category, error message, stack trace)
2. THE Transformer SHALL use structured logging with JSON format
3. THE Transformer SHALL log at appropriate levels (INFO for success, WARNING for partial failures, ERROR for complete failures)
4. WHEN a file cannot be processed, THE Transformer SHALL return HTTP 500 to trigger MIME Decoder retry
5. THE Transformer SHALL include processing duration in all logs
6. THE Transformer SHALL include correlation IDs for request tracing

### Requirement 8: Health Check and Monitoring

**User Story:** As a DevOps engineer, I want health check endpoints, so that Cloud Run can monitor service health.

#### Acceptance Criteria

1. THE Transformer SHALL expose a GET /health endpoint
2. WHEN the service is healthy, THE /health endpoint SHALL return HTTP 200 with status "healthy"
3. THE /health endpoint SHALL check connectivity to Cloud Storage
4. THE /health endpoint SHALL check connectivity to Tabular service
5. WHEN dependencies are unavailable, THE /health endpoint SHALL return HTTP 503
6. THE /health endpoint SHALL respond within 10 seconds



### Requirement 10: Configuration Management

**User Story:** As a DevOps engineer, I want configuration via environment variables, so that I can deploy to different environments.

#### Acceptance Criteria

1. THE Transformer SHALL read TABULAR_SERVICE_URL from environment variables
2. THE Transformer SHALL read GCP_PROJECT_ID, GCP_REGION, and GCS_BUCKET_NAME from environment variables
3. THE Transformer SHALL read TESSERACT_LANG for OCR language configuration with default "eng+ces"
4. THE Transformer SHALL read MAX_FILE_SIZE_MB with default 100MB
5. THE Transformer SHALL read MAX_ARCHIVE_SIZE_MB with default 500MB
6. THE Transformer SHALL read LOG_LEVEL from environment variables with default "INFO"
7. THE configuration SHALL be validated at startup and log errors for missing required variables

### Requirement 11: Cloud Run Deployment

**User Story:** As a DevOps engineer, I want the Transformer deployed on Cloud Run, so that it scales with processing load.

#### Acceptance Criteria

1. THE Transformer SHALL be deployed as a Cloud Run service in the EU region
2. THE Cloud Run service SHALL be configured with 2GB memory minimum (for OCR and document processing)
3. THE Cloud Run service SHALL be configured with 2 vCPUs
4. THE Cloud Run service SHALL scale from 0 to 20 instances based on request load
5. THE Cloud Run service SHALL have a request timeout of 900 seconds (15 minutes for large files)
6. THE Cloud Run service SHALL require authentication for invocation
