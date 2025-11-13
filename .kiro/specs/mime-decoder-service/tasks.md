# Implementation Plan

- [ ] 1. Set up project structure and dependencies
  - Create src/eduscale/mime_decoder/ directory
  - Add dependencies to requirements.txt (httpx for async HTTP, pydantic for validation)
  - Create __init__.py files for package structure
  - _Requirements: 9.1_

- [ ] 2. Extend configuration for MIME Decoder
  - Update src/eduscale/core/config.py with MIME Decoder settings
  - Add TRANSFORMER_SERVICE_URL, BACKEND_SERVICE_URL
  - Add REQUEST_TIMEOUT, BACKEND_UPDATE_TIMEOUT, LOG_LEVEL
  - Validate required environment variables at startup
  - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6_

- [ ] 3. Implement MIME type classifier
  - Create src/eduscale/mime_decoder/classifier.py
  - Define MIME_CATEGORIES mapping
  - Implement classify_mime_type() function
  - Handle text/*, image/*, audio/*, archive types
  - Return "other" for unrecognized types
  - Log classification decisions
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8_

- [ ] 4. Implement metadata extractor
  - Create src/eduscale/mime_decoder/metadata.py
  - Define FileMetadata dataclass
  - Implement extract_metadata() function
  - Parse object path pattern: uploads/{region_id}/{file_id}.{ext}
  - Extract file_id and region_id from path
  - Handle invalid path formats with warnings
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_

- [ ] 5. Implement Transformer client
  - Create src/eduscale/mime_decoder/clients.py
  - Implement call_transformer() async function
  - Use httpx.AsyncClient for HTTP calls
  - Set timeout to REQUEST_TIMEOUT (300s)
  - Build request payload with file metadata and category
  - Parse response and extract status
  - Handle timeouts and errors appropriately
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7_


- [ ] 6. Implement Backend client
  - Add update_backend_status() async function to clients.py
  - Use fire-and-forget pattern (don't await response)
  - Set short timeout (5s) for Backend calls
  - Log errors but don't fail the request if Backend update fails
  - Include file_id, status, stage, timestamp in payload
  - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5_

- [ ] 7. Implement orchestrator
  - Create src/eduscale/mime_decoder/orchestrator.py
  - Define ProcessingRequest and ProcessingResult dataclasses
  - Implement process_file() async function
  - Orchestrate: classify → call Transformer → update Backend
  - Measure processing time
  - Return ProcessingResult with status and timing
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 5.1_

- [ ] 8. Implement CloudEvents handler endpoint
  - Create src/eduscale/api/v1/routes_mime.py
  - Implement POST /api/v1/mime/decode endpoint
  - Parse CloudEvents payload from request body
  - Extract event data (bucket, name, contentType, size)
  - Validate required fields are present
  - Return 400 for validation errors, 500 for processing errors
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6_

- [ ] 9. Implement error handling and logging
  - Configure structured JSON logging
  - Add correlation IDs from CloudEvents event ID
  - Log at appropriate levels (INFO/WARNING/ERROR)
  - Include full context in error logs (file_id, region_id, error, stack trace)
  - Distinguish between 400 (no retry) and 500 (retry) errors
  - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6_

- [ ] 10. Implement health check endpoint
  - Add GET /health endpoint in routes_mime.py
  - Check connectivity to Transformer service
  - Return 200 if healthy, 503 if dependencies unavailable
  - Respond within 5 seconds
  - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5_


- [ ] 11. Write unit tests for classifier
  - Create tests/test_mime_classifier.py
  - Test classification for text/*, image/*, audio/*, archive types
  - Test PDF classified as "text"
  - Test Office documents classified as "text"
  - Test unknown types return "other"
  - Run tests: `pytest tests/test_mime_classifier.py -v`
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_

- [ ] 12. Write unit tests for metadata extractor
  - Create tests/test_mime_metadata.py
  - Test parsing valid path: uploads/region-cz-01/abc123.pdf
  - Test extracting file_id and region_id correctly
  - Test handling invalid path formats
  - Test with various file extensions
  - Run tests: `pytest tests/test_mime_metadata.py -v`
  - _Requirements: 2.1, 2.2, 2.3, 2.4_

- [ ] 13. Write unit tests for orchestrator
  - Create tests/test_mime_orchestrator.py
  - Mock Transformer and Backend clients
  - Test successful processing flow
  - Test error handling when Transformer fails
  - Test that Backend failures don't fail the request
  - Verify processing time is measured
  - Run tests: `pytest tests/test_mime_orchestrator.py -v`
  - _Requirements: 4.1, 4.2, 4.3, 5.4, 5.5_

- [ ] 14. Write integration tests for CloudEvents
  - Create tests/test_mime_cloudevents.py
  - Create fixture CloudEvents payloads (tests/fixtures/cloudevents.json)
  - Test parsing valid CloudEvents
  - Test validation errors for missing fields
  - Test end-to-end flow with mocked Transformer
  - Run tests: `pytest tests/test_mime_cloudevents.py -v`
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6_

- [ ] 15. Create Cloud Run deployment configuration
  - Create infra/cloud-run-mime-decoder.yaml
  - Configure memory: 512MB, CPU: 1 vCPU
  - Configure autoscaling: min 0, max 10
  - Configure timeout: 300 seconds
  - Set environment variables (TRANSFORMER_SERVICE_URL, BACKEND_SERVICE_URL, etc.)
  - Configure service account with Cloud Run Invoker permissions
  - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 9.6_


- [ ] 16. Create Dockerfile for MIME Decoder
  - Create docker/Dockerfile.mime-decoder
  - Use Python 3.11 slim base image
  - Install dependencies from requirements.txt
  - Copy source code
  - Set entrypoint to run FastAPI with uvicorn
  - Expose port 8080
  - _Requirements: 9.1_

- [ ] 17. Register MIME Decoder router in main app
  - Update src/eduscale/main.py
  - Import and include routes_mime router
  - Register at /api/v1/mime prefix
  - Ensure health check is accessible at /health
  - _Requirements: 1.1, 7.1_

- [ ] 18. Test with Eventarc integration
  - Deploy MIME Decoder to Cloud Run
  - Configure Eventarc trigger to call MIME Decoder
  - Upload a test file to Cloud Storage
  - Verify MIME Decoder receives CloudEvents
  - Check logs for classification and Transformer call
  - Verify status is returned to Eventarc
  - _Requirements: 1.1, 1.2, 1.3, 3.8, 4.1_

- [ ] 19. Test error handling and retries
  - Temporarily make Transformer return 500 error
  - Upload a test file
  - Verify MIME Decoder returns 500 to trigger Eventarc retry
  - Check logs for error details
  - Test with invalid CloudEvents payload (should return 400)
  - Verify 400 errors don't trigger retries
  - _Requirements: 6.4, 6.5_

- [ ] 20. Create deployment documentation
  - Document environment variables required
  - Document Cloud Run deployment steps
  - Add troubleshooting section for common issues
  - Document integration with Eventarc and Transformer
  - Add example CloudEvents payload for testing
  - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6_
