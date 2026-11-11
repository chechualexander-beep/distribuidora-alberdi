"""Render the exact transaction for 118B. This module never connects to a database."""
import argparse
import hashlib
from pathlib import Path
import re

VERSION = '20261104010000'
NAME = 'venta_directa_stock_contextual'
SHA256 = '62C9DB80E468CADC34175CB28A795E30549060F41944DF151CA97C4679303E6C'
SOURCE = Path(__file__).resolve().parents[1] / f'supabase/migrations/{VERSION}_{NAME}.sql'


def render(raw, *, fail_before_commit=False):
    if hashlib.sha256(raw).hexdigest().upper() != SHA256:
        raise ValueError('SHA-256 de migracion incompatible')
    # Remove only the first and last outer statements of the hash-pinned file.
    # Leave all nested PL/pgSQL blocks and statements byte-for-byte intact.
    source = raw.decode('utf-8')
    bounds = re.fullmatch(
        r'((?:-- [^\r\n]*\r?\n)+)begin;\r?\n(.+?)\r?\ncommit;\r?\n?',
        source,
        flags=re.S,
    )
    if not bounds:
        raise ValueError('Limites transaccionales incompatibles')
    body = bounds[1] + bounds[2]
    delimiter = '$alberdi_118_history$'
    if delimiter in body:
        raise ValueError('Delimitador de historial incompatible')
    failure = "do $$ begin raise exception 'p118b_fallo_deliberado'; end $$;" if fail_before_commit else ''
    return f"""begin;
select pg_advisory_xact_lock(829001);
lock table supabase_migrations.schema_migrations in share row exclusive mode;
do $$
begin
 if not exists (
  select 1 from pg_constraint
  where conrelid='supabase_migrations.schema_migrations'::regclass
    and contype='p' and pg_get_constraintdef(oid)='PRIMARY KEY (version)'
 ) or (
  select count(*) from pg_attribute
  where attrelid='supabase_migrations.schema_migrations'::regclass
    and not attisdropped and (
     (attname in ('version','name') and atttypid='text'::regtype) or
     (attname='statements' and atttypid='text[]'::regtype)
    )
 ) <> 3 then
  raise exception 'historial_migraciones_incompatible';
 end if;
 if exists (select 1 from supabase_migrations.schema_migrations where version='{VERSION}') then
  raise exception 'migracion_ya_registrada';
 end if;
end;
$$;
{body}
insert into supabase_migrations.schema_migrations(version,name,statements)
 values ('{VERSION}','{NAME}',array[{delimiter}{body}{delimiter}]);
{failure}
commit;
"""


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--emit', type=Path, required=True)
    args = parser.parse_args()
    sql = render(SOURCE.read_bytes())
    with args.emit.open('xb') as destination:
        destination.write(sql.encode('utf-8'))
