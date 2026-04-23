"""Environment-basierte Konfiguration.

Alle Werte werden aus der `.env`-Datei oder Prozess-Environment gelesen. Der
Resend-API-Key und der Admin-Token MÜSSEN im Produktivbetrieb aus der `.env`
kommen; das Repository enthält nur `.env.example` mit Platzhaltern.
"""
from __future__ import annotations

from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Prozess-weit verfügbare Konfiguration.

    Wird einmal zum Start instanziiert (siehe `get_settings()`) und über
    FastAPI-Dependencies injiziert.
    """

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # Resend
    resend_api_key: str = Field(..., description="Resend API key (starts with re_)")
    resend_from_email: str = "no-reply@mail.adluna.de"
    resend_from_name: str = "AdLuna Platform"

    # Server
    license_server_env: str = "production"
    license_server_port: int = 8080
    license_server_bind_host: str = "127.0.0.1"
    license_server_db_path: str = "./data/license.db"

    # Admin
    adluna_admin_token: str = Field(..., description="Random high-entropy admin bearer token")

    # Defaults (können via `server_config`-Tabelle überschrieben werden)
    beta_mode_global: bool = True
    default_trial_days: int = 14
    activation_code_ttl_minutes: int = 15
    license_check_ttl_seconds: int = 86400

    @property
    def db_url(self) -> str:
        path = Path(self.license_server_db_path).expanduser().resolve()
        path.parent.mkdir(parents=True, exist_ok=True)
        return f"sqlite:///{path}"


_settings: Settings | None = None


def get_settings() -> Settings:
    """Singleton settings loader.

    Bewusst nicht via `@lru_cache`, weil Pytest mit Override-Fixtures
    sonst nicht sauber resetten kann.
    """
    global _settings
    if _settings is None:
        _settings = Settings()
    return _settings
