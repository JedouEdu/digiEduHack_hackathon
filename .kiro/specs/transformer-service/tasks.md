# Implementation Plan

- [ ] 1. Set up project structure and core configuration
  - Create transformer module directory structure
  - Extend core/config.py with Transformer settings
  - Add new dependencies to requirements.txt
  - Verify configuration loads correctly
  - _Requirements: 10_

- [ ] 1.1 Create transformer module structure
  - Create src/eduscale/transformer/ directory
  - Create src/eduscale/transformer/__init__.py
  - Create src/eduscale/transformer/handlers/ directory
  - Create src/eduscale/transformer/handlers/__init__.py
  - _Requirements: 10_

- [ ] 1.2 Extend configuration settings
  - Add TransformerSettings class to src/eduscale/core/config.py
  - Include TABULAR_SERVICE_URL, MAX_FILE_SIZE_MB, MAX_ARCHIVE_SIZE_MB
  - Include SPEECH_LANGUAGE_EN, SPEECH_LANGUAGE_CS settings
  - Add configuration validation at startup
  - _Requirements: 10_

- [ ] 1.3 Update requirements.txt with new dependencies
  - Add pdfplumber>=0.10.3 for PDF extraction
  - Add python-docx>=1.1.0 for Word documents
  - Add google-cloud-speech>=2.21.0 for ASR
  - Add pydub>=0.25.1 for audio processing
  - Add mutagen>=1.47.0 for audio metadata
  - Add python-magic>=0.4.27 for MIME detection
  - Add httpx>=0.25.2 for async HTTP
  - Add structlog>=23.2.0 for structured logging
  - _Requirements: 10_

- [ ] 1.4 Test configuration loading
  - Create tests/test_transformer_config.py
  - Test TransformerSettings loads with valid environment variables
  - Test configuration validation catches missing required variables
  - Test default values are applied correctly
  - Run tests to verify configuration works
  - _Requirements: 10_

- [ ] 2. Implement Cloud Storage operations
  - Create storage.py module with GCS client
  - Implement file download from Cloud Storage
  - Implement text upload to Cloud Storage
  - Implement streaming for large files
  - Test storage operations with mocked GCS
  - _Requirements: 1, 5_

- [ ] 2.1 Create storage client module
  - Create src/eduscale/transformer/storage.py
  - Initialize google-cloud-storage client
  - Implement download_file() function for downloading files from GCS
  - Implement upload_text() function for uploading extracted text
  - Implement stream_large_file() for files > 100MB
  - _Requirements: 1, 5_

- [ ] 2.2 Add error handling for storage operations
  - Handle GCS exceptions (NotFound, Forbidden, etc.)
  - Add retry logic for transient failures
  - Log all storage operations with duration
  - _Requirements: 1, 5, 7_

- [ ] 2.3 Test storage operations
  - Create tests/test_transformer_storage.py
  - Mock google-cloud-storage client
  - Test download_file() with valid file
  - Test upload_text() saves text correctly
  - Test error handling for NotFound and other GCS exceptions
  - Test retry logic for transient failures
  - Run tests to verify storage operations work
  - _Requirements: 1, 5, 7_

- [ ] 3. Implement Text Handler for document extraction
  - Create text_handler.py module
  - Implement PDF text extraction
  - Implement DOCX text extraction
  - Implement plain text reading
  - Create test fixtures and verify extraction works
  - _Requirements: 2_

- [ ] 3.1 Create text handler module
  - Create src/eduscale/transformer/handlers/text_handler.py
  - Implement extract_text_from_pdf() using pdfplumber
  - Implement extract_text_from_docx() using python-docx
  - Implement extract_text_from_plain() with UTF-8 and latin-1 fallback
  - Implement extract_text() router function based on content_type
  - _Requirements: 2_

- [ ] 3.2 Add metadata extraction for text files
  - Extract page count from PDF files
  - Extract word count from all text
  - Return ExtractionMetadata with extraction_method
  - _Requirements: 2_

- [ ] 3.3 Create test fixtures and test text extraction
  - Create tests/fixtures/ directory
  - Create tests/fixtures/sample.pdf (simple 2-page PDF with text)
  - Create tests/fixtures/sample.docx (Word doc with paragraphs)
  - Create tests/fixtures/sample.txt (plain text UTF-8)
  - Create tests/fixtures/sample_latin1.txt (latin-1 encoded text)
  - Create tests/fixtures/corrupted.pdf (invalid PDF for error testing)
  - _Requirements: 2_

- [ ] 3.4 Test text handler functionality
  - Create tests/test_text_handler.py
  - Test extract_text_from_pdf() with sample.pdf
  - Test extract_text_from_docx() with sample.docx
  - Test extract_text_from_plain() with UTF-8 and latin-1 files
  - Test metadata extraction (page count, word count)
  - Test error handling with corrupted.pdf
  - Run tests to verify text extraction works
  - _Requirements: 2_

- [ ] 4. Implement Audio Handler for ASR transcription
  - Create audio_handler.py module
  - Implement Google Cloud Speech-to-Text integration
  - Handle short and long audio files
  - Extract audio metadata
  - Test with mocked Speech-to-Text API
  - _Requirements: 3_

- [ ] 4.1 Create audio handler module
  - Create src/eduscale/transformer/handlers/audio_handler.py
  - Implement transcribe_audio() using google-cloud-speech
  - Support synchronous recognition for files < 60 seconds
  - Support long-running recognition for files > 60 seconds
  - Handle language selection (en-US, cs-CZ)
  - _Requirements: 3_

- [ ] 4.2 Implement audio format conversion
  - Use pydub to convert audio to LINEAR16 if needed
  - Implement get_audio_metadata() using mutagen
  - Extract duration, format, sample rate
  - Return metadata with confidence scores
  - _Requirements: 3_

- [ ] 4.3 Create audio test fixtures
  - Create tests/fixtures/sample_short.mp3 (30-second audio file)
  - Create tests/fixtures/sample_long.mp3 (90-second audio file)
  - Create tests/fixtures/sample.wav (WAV format)
  - _Requirements: 3_

- [ ] 4.4 Test audio handler functionality
  - Create tests/test_audio_handler.py
  - Mock google-cloud-speech client
  - Test transcribe_audio() with short audio (synchronous)
  - Test transcribe_audio() with long audio (long-running)
  - Test get_audio_metadata() extracts duration and format
  - Test language selection (en-US, cs-CZ)
  - Test error handling for invalid audio files
  - Run tests to verify audio processing works
  - _Requirements: 3_

- [ ] 5. Implement Archive Handler for unpacking
  - Create archive_handler.py module
  - Implement archive format detection
  - Implement unpacking logic
  - Handle nested archives recursively
  - Test with various archive formats
  - _Requirements: 4_

- [ ] 5.1 Create archive handler module
  - Create src/eduscale/transformer/handlers/archive_handler.py
  - Implement detect_archive_format() using magic bytes
  - Implement unpack_and_process() for ZIP, TAR, TAR.GZ, TAR.BZ2
  - Use zipfile and tarfile built-in modules
  - _Requirements: 4_

- [ ] 5.2 Implement recursive archive processing
  - Unpack archives to temporary directory /tmp/{file_id}_{timestamp}/
  - Process each extracted file by detecting MIME type
  - Handle nested archives up to depth 2
  - Generate sequential text URIs (file_id_001.txt, file_id_002.txt)
  - Clean up temporary files after processing
  - _Requirements: 4_

- [ ] 5.3 Add archive size validation
  - Check archive size against MAX_ARCHIVE_SIZE_MB (500MB)
  - Raise FileTooLargeError if exceeded
  - Log archive processing with file count
  - _Requirements: 4_

- [ ] 5.4 Create archive test fixtures
  - Create tests/fixtures/sample.zip (ZIP with 3 text files)
  - Create tests/fixtures/sample.tar.gz (TAR.GZ with mixed files)
  - Create tests/fixtures/nested.zip (ZIP containing another ZIP)
  - Create tests/fixtures/large.zip (Archive exceeding size limit for testing)
  - _Requirements: 4_

- [ ] 5.5 Test archive handler functionality
  - Create tests/test_archive_handler.py
  - Test detect_archive_format() with different formats
  - Test unpack_and_process() with sample.zip
  - Test TAR.GZ unpacking
  - Test nested archive handling (depth limit)
  - Test sequential naming (file_id_001.txt, file_id_002.txt)
  - Test size limit enforcement with large.zip
  - Test cleanup of temporary files
  - Run tests to verify archive processing works
  - _Requirements: 4_

- [ ] 6. Implement Orchestrator for main processing flow
  - Create orchestrator.py module
  - Implement transform_file() main function
  - Implement routing logic to handlers
  - Handle single and multiple text outputs
  - Test orchestration with mocked dependencies
  - _Requirements: 1, 2, 3, 4, 5, 6_

- [ ] 6.1 Create orchestrator module
  - Create src/eduscale/transformer/orchestrator.py
  - Implement transform_file() function
  - Validate request parameters (file_id, bucket, object_name)
  - Check file size against MAX_FILE_SIZE_MB
  - _Requirements: 1, 2, 3, 4, 5_

- [ ] 6.2 Implement handler routing logic
  - Implement route_to_handler() based on file_category
  - Route "text" → text_handler
  - Route "audio" → audio_handler
  - Route "archive" → archive_handler
  - Route "other" → attempt text extraction
  - _Requirements: 2, 3, 4_

- [ ] 6.3 Implement text upload and Tabular integration
  - Download file from GCS to temporary location
  - Call appropriate handler to extract text
  - Upload extracted text(s) to gs://{bucket}/text/{file_id}[_NNN].txt
  - Call Tabular service for each text URI
  - Aggregate Tabular responses
  - Clean up temporary files in finally block
  - _Requirements: 5, 6_

- [ ] 6.4 Test orchestrator functionality
  - Create tests/test_orchestrator.py
  - Mock storage, handlers, and Tabular client
  - Test transform_file() with text file category
  - Test transform_file() with audio file category
  - Test transform_file() with archive file category (multiple outputs)
  - Test file size validation
  - Test error handling and cleanup
  - Test Tabular service integration
  - Run tests to verify orchestration works
  - _Requirements: 1, 2, 3, 4, 5, 6_

- [ ] 7. Implement Tabular service client
  - Create tabular_client.py module
  - Implement HTTP client for Tabular service
  - Handle authentication and timeouts
  - Implement retry logic for transient failures
  - Test with mocked HTTP responses
  - _Requirements: 6_

- [ ] 7.1 Create Tabular client module
  - Create src/eduscale/transformer/tabular_client.py
  - Implement call_tabular() using httpx.AsyncClient
  - Set timeout to 600 seconds
  - Include authentication headers for Cloud Run service-to-service
  - _Requirements: 6_

- [ ] 7.2 Add error handling for Tabular calls
  - Catch httpx exceptions (timeout, connection errors)
  - Log Tabular errors but don't fail Transformer request
  - Return None if Tabular call fails
  - Retry on 503 errors with exponential backoff
  - _Requirements: 6, 7_

- [ ] 7.3 Test Tabular client functionality
  - Create tests/test_tabular_client.py
  - Mock httpx.AsyncClient
  - Test call_tabular() with successful response
  - Test timeout handling
  - Test connection error handling
  - Test retry logic on 503 errors
  - Test that Tabular failures don't fail the request
  - Run tests to verify Tabular client works
  - _Requirements: 6, 7_

- [ ] 8. Implement FastAPI endpoints
  - Create routes_transformer.py module
  - Define request/response models
  - Implement /api/v1/transformer/transform endpoint
  - Implement /health endpoint
  - Test API endpoints with FastAPI TestClient
  - _Requirements: 8_

- [ ] 8.1 Create API endpoint module
  - Create src/eduscale/api/v1/routes_transformer.py
  - Define TransformRequest and TransformResponse Pydantic models
  - Define ExtractionMetadata model
  - Implement POST /api/v1/transformer/transform endpoint
  - _Requirements: 1, 2, 3, 4, 5, 6_

- [ ] 8.2 Implement health check endpoint
  - Implement GET /health endpoint
  - Check connectivity to Cloud Storage
  - Check connectivity to Tabular service
  - Return 200 if healthy, 503 if dependencies unavailable
  - Respond within 10 seconds
  - _Requirements: 8_

- [ ] 8.3 Register routes in main application
  - Import routes_transformer in src/eduscale/main.py
  - Register transformer router with FastAPI app
  - _Requirements: 8_

- [ ] 8.4 Test API endpoints
  - Create tests/test_transformer_api.py
  - Use FastAPI TestClient
  - Mock orchestrator.transform_file()
  - Test POST /api/v1/transformer/transform with valid request
  - Test request validation (invalid file_id, missing fields)
  - Test GET /health endpoint returns 200 when healthy
  - Test GET /health endpoint returns 503 when dependencies unavailable
  - Test error responses (400, 500)
  - Run tests to verify API endpoints work
  - _Requirements: 8_

- [ ] 9. Implement error handling and logging
  - Define custom exception classes
  - Implement structured logging
  - Add error handling to all components
  - _Requirements: 7_

- [ ] 9.1 Define custom exceptions
  - Create TransformerException base class
  - Create FileTooLargeError exception
  - Create ExtractionError exception
  - Create StorageError exception
  - _Requirements: 7_

- [ ] 9.2 Implement structured logging
  - Use structlog for JSON logging
  - Include file_id, region_id, file_category in all logs
  - Include operation and duration_ms in logs
  - Log at appropriate levels (INFO, WARNING, ERROR)
  - _Requirements: 7_

- [ ] 9.3 Add error handling to orchestrator
  - Wrap transform_file() in try/except
  - Return 500 for retryable errors (GCS, extraction)
  - Return 400 for permanent errors (invalid format, too large)
  - Log all errors with full context and stack trace
  - Ensure cleanup in finally block
  - _Requirements: 7_

- [ ] 9.4 Test error handling and logging
  - Create tests/test_error_handling.py
  - Test custom exceptions are raised correctly
  - Test structured logging includes all required fields
  - Test error responses (400 vs 500)
  - Test cleanup happens even on errors
  - Verify log output format is JSON
  - Run tests to verify error handling works
  - _Requirements: 7_

- [ ] 10. Create Docker configuration
  - Create Dockerfile for Transformer service
  - Install system dependencies (ffmpeg, libmagic1)
  - Configure container for Cloud Run deployment
  - _Requirements: 11_

- [ ] 10.1 Create Dockerfile
  - Create docker/Dockerfile.transformer
  - Use python:3.11-slim base image
  - Install ffmpeg and libmagic1 for audio/document processing
  - Copy requirements.txt and install dependencies
  - Copy source code
  - Set CMD to run uvicorn
  - _Requirements: 11_

- [ ] 10.2 Test Docker build
  - Build Docker image locally
  - Verify all dependencies are installed
  - Test container starts successfully
  - Verify health endpoint is accessible
  - _Requirements: 11_

- [ ] 11. Create deployment configuration
  - Create Cloud Run service configuration
  - Document environment variables
  - Create deployment script
  - _Requirements: 11_

- [ ] 11.1 Create Cloud Run configuration
  - Create infra/cloud-run-transformer.yaml
  - Configure memory: 2Gi, cpu: 2, timeout: 900s
  - Set max-instances: 20, min-instances: 0
  - Set concurrency: 10, ingress: internal
  - _Requirements: 11_

- [ ] 11.2 Document deployment steps
  - Add deployment instructions to README.md
  - Document required environment variables
  - Document service account permissions needed
  - _Requirements: 10, 11_
