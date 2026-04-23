"""SQLAlchemy-Modelle für die AdLuna Platform API.

Kernobjekte:
- Product    : unterschiedliche ALVA-Produkte (alva-text, alva-macos, ...)
- User       : eindeutig pro E-Mail
- ActivationCode: Einmal-Code mit 15-min-TTL, pro (User, Product, Device)
- Device     : pro (User, Product) ein oder mehrere Geräte
- License    : laufender Status eines Devices (beta/trial/paid/...)
- LicenseCheck: Audit-Log jedes License-Checks
- ServerConfig: Key-Value für Kill-Switch-Flags
"""
from __future__ import annotations

from datetime import datetime

from sqlalchemy import (
    DateTime,
    ForeignKey,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class Product(Base):
    __tablename__ = "products"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    name: Mapped[str] = mapped_column(String(128), nullable=False)
    slug: Mapped[str] = mapped_column(String(64), nullable=False, unique=True)
    default_trial_days: Mapped[int] = mapped_column(Integer, default=14, nullable=False)
    paddle_product_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    price_eur: Mapped[float | None] = mapped_column(Numeric(10, 2), nullable=True)
    active: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), nullable=False)

    devices: Mapped[list["Device"]] = relationship(back_populates="product")
    activation_codes: Mapped[list["ActivationCode"]] = relationship(back_populates="product")


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    email: Mapped[str] = mapped_column(String(256), nullable=False, unique=True, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), nullable=False)
    verified_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)

    devices: Mapped[list["Device"]] = relationship(back_populates="user", cascade="all, delete-orphan")
    activation_codes: Mapped[list["ActivationCode"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )


class ActivationCode(Base):
    __tablename__ = "activation_codes"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    product_id: Mapped[str] = mapped_column(
        ForeignKey("products.id"), nullable=False, index=True
    )
    code: Mapped[str] = mapped_column(String(16), nullable=False, index=True)
    device_uuid: Mapped[str] = mapped_column(String(128), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    used_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    ip_address: Mapped[str | None] = mapped_column(String(64), nullable=True)

    user: Mapped[User] = relationship(back_populates="activation_codes")
    product: Mapped[Product] = relationship(back_populates="activation_codes")


class Device(Base):
    __tablename__ = "devices"
    __table_args__ = (
        UniqueConstraint("user_id", "product_id", "device_uuid", name="uq_user_product_device"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    product_id: Mapped[str] = mapped_column(
        ForeignKey("products.id"), nullable=False, index=True
    )
    device_uuid: Mapped[str] = mapped_column(String(128), nullable=False, index=True)
    device_name: Mapped[str | None] = mapped_column(String(128), nullable=True)
    platform: Mapped[str | None] = mapped_column(String(32), nullable=True)  # macos, ios, ipados, ...
    token: Mapped[str] = mapped_column(String(128), nullable=False, unique=True, index=True)
    activated_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), nullable=False)
    last_check_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    last_check_ip: Mapped[str | None] = mapped_column(String(64), nullable=True)
    app_version: Mapped[str | None] = mapped_column(String(32), nullable=True)

    user: Mapped[User] = relationship(back_populates="devices")
    product: Mapped[Product] = relationship(back_populates="devices")
    license: Mapped["License"] = relationship(
        back_populates="device", uselist=False, cascade="all, delete-orphan"
    )


class License(Base):
    __tablename__ = "licenses"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    device_id: Mapped[int] = mapped_column(
        ForeignKey("devices.id", ondelete="CASCADE"), nullable=False, unique=True, index=True
    )
    status: Mapped[str] = mapped_column(String(32), default="beta", nullable=False)
    # Werte: beta | trial | active | expired | revoked
    tier: Mapped[str] = mapped_column(String(32), default="full", nullable=False)
    # Werte: full | limited | paid
    trial_expires_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    paid_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    revoked_reason: Mapped[str | None] = mapped_column(String(256), nullable=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), onupdate=func.now(), nullable=False
    )

    device: Mapped[Device] = relationship(back_populates="license")


class LicenseCheck(Base):
    __tablename__ = "license_checks"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    device_id: Mapped[int | None] = mapped_column(
        ForeignKey("devices.id", ondelete="SET NULL"), nullable=True, index=True
    )
    timestamp: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), nullable=False)
    status_returned: Mapped[str | None] = mapped_column(String(32), nullable=True)
    ip_address: Mapped[str | None] = mapped_column(String(64), nullable=True)
    app_version: Mapped[str | None] = mapped_column(String(32), nullable=True)


class ServerConfig(Base):
    __tablename__ = "server_config"

    key: Mapped[str] = mapped_column(String(64), primary_key=True)
    value: Mapped[str | None] = mapped_column(Text, nullable=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), onupdate=func.now(), nullable=False
    )
