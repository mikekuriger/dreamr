"""add interpreter_id to dream

Revision ID: c8a91e2d4b6f
Revises: a7fed3616e08
Create Date: 2026-05-03 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'c8a91e2d4b6f'
down_revision = 'a7fed3616e08'
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table('dream', schema=None) as batch_op:
        batch_op.add_column(sa.Column('interpreter_id', sa.Integer(), nullable=True))
        batch_op.create_index('ix_dream_interpreter_id', ['interpreter_id'], unique=False)
        batch_op.create_foreign_key(
            'fk_dream_interpreter_id_interpreters',
            'interpreters',
            ['interpreter_id'], ['id'],
        )


def downgrade():
    with op.batch_alter_table('dream', schema=None) as batch_op:
        batch_op.drop_constraint('fk_dream_interpreter_id_interpreters', type_='foreignkey')
        batch_op.drop_index('ix_dream_interpreter_id')
        batch_op.drop_column('interpreter_id')
