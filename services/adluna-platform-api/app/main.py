"""FastAPI-Haupt-Einstiegspunkt."""
from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from loguru import logger
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

from app import __version__
from app.config import get_settings
from app.database import Base, engine
from app.endpoints import activation, admin, license, webhook
from app.schemas import HealthResponse


settings = get_settings()
limiter = Limiter(key_func=get_remote_address)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup/Shutdown-Hook.

    Bei Start: sicherstellen, dass DB-Schema existiert (im Dev-Betrieb;
    im Produktiv-Betrieb nutzt man Alembic-Migrations stattdessen).
    """
    if settings.license_server_env != "production":
        logger.info("Dev mode: creating DB tables if missing")
        Base.metadata.create_all(bind=engine)
    logger.info(f"AdLuna Platform API v{__version__} starting on {settings.license_server_bind_host}:{settings.license_server_port}")
    yield
    logger.info("Shutting down AdLuna Platform API")


app = FastAPI(
    title="AdLuna Platform API",
    description="License & activation service for AdLuna products (ALVA-TEXT, ALVA macOS, …)",
    version=__version__,
    lifespan=lifespan,
)

# Rate-Limiter
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# CORS — restriktiv: nur die Mac-App-Origins erlauben (keine Webapps)
# Macs machen den Call direkt als native Request; CORS ist hier im Wesentlichen
# irrelevant, aber wir setzen trotzdem sinnvolle Defaults für künftige
# Web-Dashboards.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"] if settings.license_server_env == "development" else [
        "https://adluna.de",
        "https://api.adluna.de",
        "https://downloads.adluna.de",
    ],
    allow_credentials=False,
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)


# Router registrieren (je ein Modul pro Endpoint-Gruppe)
app.include_router(activation.router, prefix="/v1", tags=["activation"])
app.include_router(license.router, prefix="/v1", tags=["license"])
app.include_router(webhook.router, prefix="/v1", tags=["webhook"])
app.include_router(admin.router, prefix="/v1/admin", tags=["admin"])


@app.get("/", response_model=HealthResponse)
@app.get("/health", response_model=HealthResponse)
def health():
    """Uptime-Check-Endpunkt für Monitoring (UptimeRobot o.ä.)."""
    return HealthResponse(version=__version__, env=settings.license_server_env)
