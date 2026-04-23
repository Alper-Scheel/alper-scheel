"""initial schema

Revision ID: 20260423_0001
Revises:
Create Date: 2026-04-23

Alle Tabellen initial anlegen. Spätere Migrations leben als separate
Dateien in `alembic/versions/` und werden chronologisch versioniert.
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "20260423_0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "products",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column("name", sa.String(length=128), nullable=False),
        sa.Column("slug", sa.String(length=64), nullable=False, unique=True),
        sa.Column("default_trial_days", sa.Integer(), nullable=False, server_default="14"),
        sa.Column("paddle_product_id", sa.String(length=128), nullable=True),
        sa.Column("price_eur", sa.Numeric(10, 2), nullable=True),
        sa.Column("active", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
    )

    op.create_table(
        "users",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("email", sa.String(length=256), nullable=False),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
        sa.Column("verified_at", sa.DateTime(), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.UniqueConstraint("email", name="uq_users_email"),
    )
    op.create_index("ix_users_email", "users", ["email"])

    op.create_table(
        "activation_codes",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("product_id", sa.String(length=64), sa.ForeignKey("products.id"), nullable=False),
        sa.Column("code", sa.String(length=16), nullable=False),
        sa.Column("device_uuid", sa.String(length=128), nullable=False),
        sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
        sa.Column("expires_at", sa.DateTime(), nullable=False),
        sa.Column("used_at", sa.DateTime(), nullable=True),
        sa.Column("ip_address", sa.String(length=64), nullable=True),
    )
    op.create_index("ix_activation_codes_user_id", "activation_codes", ["user_id"])
    op.create_index("ix_activation_codes_product_id", "activation_codes", ["product_id"])
    op.create_index("ix_activation_codes_code", "activation_codes", ["code"])

    op.create_table(
        "devices",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("product_id", sa.String(length=64), sa.ForeignKey("products.id"), nullable=False),
        sa.Column("device_uuid", sa.String(length=128), nullable=False),
        sa.Column("device_name", sa.String(length=128), nullable=True),
        sa.Column("platform", sa.String(length=32), nullable=True),
        sa.Column("token", sa.String(length=128), nullable=False),
        sa.Column("activated_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
        sa.Column("last_check_at", sa.DateTime(), nullable=True),
        sa.Column("last_check_ip", sa.String(length=64), nullable=True),
        sa.Column("app_version", sa.String(length=32), nullable=True),
        sa.UniqueConstraint("user_id", "product_id", "device_uuid", name="uq_user_product_device"),
        sa.UniqueConstraint("token", name="uq_devices_token"),
    )
    op.create_index("ix_devices_user_id", "devices", ["user_id"])
    op.create_index("ix_devices_product_id", "devices", ["product_id"])
    op.create_index("ix_devices_device_uuid", "devices", ["device_uuid"])
    op.create_index("ix_devices_token", "devices", ["token"])

    op.create_table(
        "licenses",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column(
            "device_id",
            sa.Integer(),
            sa.ForeignKey("devices.id", ondelete="CASCADE"),
            nullable=False,
            unique=True,
        ),
        sa.Column("status", sa.String(length=32), nullable=False, server_default="beta"),
        sa.Column("tier", sa.String(length=32), nullable=False, server_default="full"),
        sa.Column("trial_expires_at", sa.DateTime(), nullable=True),
        sa.Column("paid_at", sa.DateTime(), nullable=True),
        sa.Column("revoked_at", sa.DateTime(), nullable=True),
        sa.Column("revoked_reason", sa.String(length=256), nullable=True),
        sa.Column(
            "updated_at",
            sa.DateTime(),
            server_default=sa.func.now(),
            onupdate=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_index("ix_licenses_device_id", "licenses", ["device_id"])

    op.create_table(
        "license_checks",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column(
            "device_id",
            sa.Integer(),
            sa.ForeignKey("devices.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("timestamp", sa.DateTime(), server_default=sa.func.now(), nullable=False),
        sa.Column("status_returned", sa.String(length=32), nullable=True),
        sa.Column("ip_address", sa.String(length=64), nullable=True),
        sa.Column("app_version", sa.String(length=32), nullable=True),
    )
    op.create_index("ix_license_checks_device_id", "license_checks", ["device_id"])

    op.create_table(
        "server_config",
        sa.Column("key", sa.String(length=64), primary_key=True),
        sa.Column("value", sa.Text(), nullable=True),
        sa.Column(
            "updated_at",
            sa.DateTime(),
            server_default=sa.func.now(),
            onupdate=sa.func.now(),
            nullable=False,
        ),
    )


def downgrade() -> None:
    op.drop_table("server_config")
    op.drop_index("ix_license_checks_device_id", table_name="license_checks")
    op.drop_table("license_checks")
    op.drop_index("ix_licenses_device_id", table_name="licenses")
    op.drop_table("licenses")
    op.drop_index("ix_devices_token", table_name="devices")
    op.drop_index("ix_devices_device_uuid", table_name="devices")
    op.drop_index("ix_devices_product_id", table_name="devices")
    op.drop_index("ix_devices_user_id", table_name="devices")
    op.drop_table("devices")
    op.drop_index("ix_activation_codes_code", table_name="activation_codes")
    op.drop_index("ix_activation_codes_product_id", table_name="activation_codes")
    op.drop_index("ix_activation_codes_user_id", table_name="activation_codes")
    op.drop_table("activation_codes")
    op.drop_index("ix_users_email", table_name="users")
    op.drop_table("users")
    op.drop_table("products")
