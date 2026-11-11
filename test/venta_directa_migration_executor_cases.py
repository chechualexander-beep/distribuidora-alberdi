"""A focused atomicity exercise, using the existing fictional PostgreSQL fixture."""
from stock_automation_sql_test import REPO
from venta_directa_migration_executor import NAME, SOURCE, VERSION, render


def run(sql, val, count):
    for version in ('20261023010000', '20261023011000', '20261023012000'):
        path, = (REPO / 'supabase/migrations').glob(f'{version}_*.sql')
        sql(path.read_text(encoding='utf-8'))
    sql("""
      create schema supabase_migrations;
      create table supabase_migrations.schema_migrations (
        version text primary key, statements text[], name text
      );
      insert into supabase_migrations.schema_migrations(version,name,statements)
       values ('20261023012000','fixture_historial','{fixture}');
      update public.stock_regimenes set automatizacion_activa=true,fecha_corte='2025-01-01Z';
      update public.stock_configuracion set automatizacion_activa=true,integracion_version=1,
       fecha_corte='2025-01-01Z',activada_at=now(),activada_por=auth.uid();
      update public.stock_transicion set mantenimiento=false where singleton;
    """)
    history = 'supabase_migrations.schema_migrations'
    migration_row = f"version='{VERSION}'"

    def snapshot():
        return val("""
          select jsonb_build_object(
            'functions', (select jsonb_object_agg(
              p.oid::regprocedure::text,
              jsonb_build_array(pg_get_functiondef(p.oid),p.proacl)
            ) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
            where n.nspname='public' and p.proname in (
              'crear_pedido_interno','actualizar_pedido_activo',
              'preparar_finalizacion_contexto','stock_base_finalizar_v2',
              'stock_exigir_venta_directa_v2'
            )),
            'history', (select jsonb_agg(to_jsonb(h) order by version)
              from supabase_migrations.schema_migrations h),
            'regime', (select to_jsonb(t) from public.stock_transicion t),
            'config', (select jsonb_agg(to_jsonb(c)) from public.stock_configuracion c),
            'stock', (select jsonb_agg(to_jsonb(s)) from public.stock_actual s),
            'movements', (select count(*) from public.stock_movimientos)
          );
        """)

    raw = SOURCE.read_bytes()
    statement = render(raw)
    try:
        render(raw + b'\n')
    except ValueError as error:
        assert 'SHA-256' in str(error)
    else:
        raise AssertionError('El ejecutor aceptó un hash incompatible')
    print('PASS hash original y rechazo de copia alterada', flush=True)

    sql(f'alter table {history} rename column statements to fixture_incompatible;')
    incompatible = snapshot()
    sql(statement, error='historial_migraciones_incompatible')
    assert snapshot() == incompatible
    sql(f'alter table {history} rename column fixture_incompatible to statements;')
    print('PASS historial incompatible rechazado sin cambios', flush=True)

    before = snapshot()
    assert len(before['functions']) == 4
    sql(render(raw, fail_before_commit=True), error='p118b_fallo_deliberado')
    assert snapshot() == before
    assert count(history, migration_row) == 0
    print('PASS rollback del SQL y del registro tras falla antes del COMMIT', flush=True)

    sql(statement)
    after = snapshot()
    assert count(history, migration_row) == 1
    assert len(after['functions']) == 5
    for name, (definition, acl) in before['functions'].items():
        assert after['functions'][name][0] != definition, name
        assert after['functions'][name][1] == acl, name
    assert after['history'][0] == before['history'][0]
    new_row = after['history'][1]
    assert new_row['version'] == VERSION and new_row['name'] == NAME
    assert len(new_row['statements']) == 1
    assert 'stock_exigir_venta_directa_v2' in new_row['statements'][0]
    for key in ('regime', 'config', 'stock', 'movements'):
        assert before[key] == after[key], key
    print('PASS SQL e historial confirmados juntos y privilegios conservados', flush=True)

    sql(statement, error='migracion_ya_registrada')
    assert snapshot() == after
    assert count(history, migration_row) == 1
    assert SOURCE.read_bytes() == raw
    print('PASS segundo intento rechazado sin duplicados', flush=True)
    print('P118B_EJECUTOR_TRANSACCIONAL_PASS', flush=True)
