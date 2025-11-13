"""Logging configuration for EduScale Engine."""

import logging
import sys


def setup_logging() -> None:
    """Configure structured logging for the application.
    
    Sets up logging to output structured logs to stdout, suitable for
    Cloud Run log ingestion. Log level is set based on environment.
    """
    from eduscale.core.config import settings

    # Determine log level based on environment
    log_level = logging.DEBUG if settings.ENV == "local" else logging.INFO

    # Configure root logger
    logging.basicConfig(
        level=log_level,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
        handlers=[logging.StreamHandler(sys.stdout)],
    )

    # Set uvicorn loggers to appropriate level
    logging.getLogger("uvicorn").setLevel(log_level)
    logging.getLogger("uvicorn.access").setLevel(log_level)
    logging.getLogger("uvicorn.error").setLevel(log_level)
