"""SQLAlchemy-Engine + Session-Factory.

SQLite mit WAL-Mode für bessere concurrency. Bei Skalierung kann `db_url`
in `Settings` auf PostgreSQL umgestellt werden, ohne dass Code-Änderungen
nötig sind.
"""
from __future__ import annotations

from collections.abc import Iterator

from sqlalchemy import create_engine, event
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.config import get_settings


class Base(DeclarativeBase):
    """SQLAlchemy-Basisklasse für alle Modelle."""


settings = get_settings()

engine = create_engine(
    settings.db_url,
    # SQLite-spezifisch: erlaube Zugriff aus mehreren Threads. FastAPI läuft
    # asynchron und benötigt das für Dependency-basierte Sessions.
    connect_args={"check_same_thread": False} if settings.db_url.startswith("sqlite") else {},
    echo=settings.license_server_env == "development",
    pool_pre_ping=True,
)


@event.listens_for(engine, "connect")
def _enable_sqlite_wal(dbapi_connection, connection_record) -> None:  # noqa: ARG001
    """SQLite WAL + Foreign-Keys aktivieren.

    WAL = bessere Lese/Schreib-Concurrency (wichtig für License-Check unter Last).
    Foreign-Keys = SQLite macht FK-Constraints standardmäßig NICHT zu. Muss
    pro Connection explizit aktiviert werden.
    """
    if settings.db_url.startswith("sqlite"):
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA journal_mode=WAL;")
        cursor.execute("PRAGMA foreign_keys=ON;")
        cursor.close()


SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


def get_db() -> Iterator[Session]:
    """FastAPI-Dependency für DB-Session pro Request."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
