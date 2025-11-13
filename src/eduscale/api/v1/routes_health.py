"""Health check endpoint for EduScale Engine."""

from fastapi import APIRouter

from eduscale.core.config import settings

router = APIRouter()


@router.get("/health")
async def health_check() -> dict:
    """Health check endpoint.
    
    Returns service status, name, and version information.
    
    Returns:
        dict: Health status response with status, service, and version fields
    """
    return {
        "status": "ok",
        "service": settings.SERVICE_NAME,
        "version": settings.SERVICE_VERSION,
    }
