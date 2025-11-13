"""Main application entrypoint for EduScale Engine."""

from fastapi import FastAPI

from eduscale.api.v1 import routes_health
from eduscale.core.config import settings
from eduscale.core.logging import setup_logging


def create_app() -> FastAPI:
    """Create and configure the FastAPI application.
    
    Returns:
        FastAPI: Configured FastAPI application instance
    """
    # Initialize logging first
    setup_logging()

    # Create FastAPI application
    app = FastAPI(
        title=settings.SERVICE_NAME,
        version=settings.SERVICE_VERSION,
    )

    # Register routers
    app.include_router(routes_health.router, tags=["health"])

    return app


# Export app instance for ASGI servers
app = create_app()
