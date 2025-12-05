"""add email_confirmed flag and email confirmation tokens

Revision ID: f1e2d3c4b5a6
Revises: 06ea57115640
Create Date: 2025-11-16 00:19:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'f1e2d3c4b5a6'
down_revision = '06ea57115640'
branch_labels = None
depends_on = None


def upgrade():
    # Add email_confirmed flag to users
    op.add_column(
        'users',
        sa.Column('email_confirmed', sa.Boolean(), nullable=False, server_default=sa.text("0")),
    )

    # Create email confirmation token table (decoupled from PendingUser)
    op.create_table(
        'email_confirm_tokens',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('token_hash', sa.String(length=64), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('expires_at', sa.DateTime(), nullable=False),
        sa.Column('used_at', sa.DateTime(), nullable=True),
        sa.UniqueConstraint('token_hash', name='uq_email_confirm_tokens_token_hash'),
    )
    op.create_index(
        'ix_email_confirm_tokens_user_id',
        'email_confirm_tokens',
        ['user_id'],
        unique=False,
    )


def downgrade():
    op.drop_index('ix_email_confirm_tokens_user_id', table_name='email_confirm_tokens')
    op.drop_table('email_confirm_tokens')
    op.drop_column('users', 'email_confirmed')
