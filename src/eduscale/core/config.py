"""Configuration management for EduScale Engine."""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    model_config = SettingsConfigDict(
        env_file=".env",
        case_sensitive=True,
    )

    ENV: str = "local"
    SERVICE_NAME: str = "eduscale-engine"
    SERVICE_VERSION: str = "0.1.0"

    # GCP Configuration
    GCP_PROJECT_ID: str = ""
    GCP_REGION: str = "europe-west1"
    GCP_RUN_SERVICE: str = "eduscale-engine"


# Singleton settings instance
settings = Settings()
