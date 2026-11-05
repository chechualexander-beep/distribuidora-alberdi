"""Read-only capability tests in the existing PostgreSQL 17 harness."""
from stock_automation_sql_test import ADMIN, SELLER, REPO, lit


def run(sql, val, count, balance, stock, order):
    for version in ('20261023010000','20261023011000','20261023012000',
                    '20261104010000','20261104020000','20261105010000'):
        path, = (REPO / 'supabase/migrations').glob(version + '_*.sql')
        sql(path.read_text(encoding='utf-8'))

    def protected():
        return sql("select md5(string_agg(pg_get_functiondef(oid)||coalesce(proacl::text,''),"
                   "'|' order by proname)) from pg_proc where pronamespace='public'::regnamespace"
                   " and proname in ('registrar_pago_cliente_contextual','registrar_pago_cliente');")

    def data():
        tables = sql("select string_agg(tablename,',' order by tablename) "
                     "from pg_tables where schemaname='public';").split(',')
        return [sql("select md5(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t))::text,'[]'))"
                    f" from public.{table} t;") for table in tables]

    original_functions, original_data = protected(), data()
    path, = (REPO / 'supabase/migrations').glob('20261105020000_*.sql')
    sql(path.read_text(encoding='utf-8'))
    assert protected() == original_functions
    assert data() == original_data

    query = 'select obtener_capacidad_cobros_contextuales();'
    result = val('begin read only; ' + query + ' rollback;', role='authenticated')
    assert result == dict(capacidad='cobros_contextuales', version=1, disponible=True,
                          actor_id=ADMIN, rpc='registrar_pago_cliente_contextual')
    print('PASS administrador activo y contrato explícito en transacción READ ONLY', flush=True)

    for actor in (SELLER, ''):
        sql(query, role='authenticated', actor=actor, error='Solo administración activa')
    for role in ('anon','service_role'):
        sql(query, role=role, error='permission denied')
    sql(f"update usuarios set activo=false where id={lit(ADMIN)};")
    sql(query, role='authenticated', error='Solo administración activa')
    sql(f"update usuarios set activo=true where id={lit(ADMIN)};")
    print('PASS administrador inactivo, preventista, sin identidad y roles no autorizados', flush=True)

    assert val("select jsonb_build_object('stable',provolatile='s','definer',prosecdef,"
               "'args',pronargs,'path',proconfig) from pg_proc where "
               "oid='public.obtener_capacidad_cobros_contextuales()'::regprocedure;") == {
        'stable':True,'definer':True,'args':0,'path':['search_path=pg_catalog, public, pg_temp']}
    sql("alter function public.registrar_pago_cliente_contextual(uuid,uuid,numeric,text,text)"
        " rename to fixture_cobro_contextual;")
    assert not val(query, role='authenticated')['disponible']
    sql("alter function public.fixture_cobro_contextual(uuid,uuid,numeric,text,text)"
        " rename to registrar_pago_cliente_contextual;")
    assert val(query, role='authenticated')['disponible']
    print('PASS STABLE, search_path seguro y contrato ausente rechazado', flush=True)

    assert data() == original_data and protected() == original_functions
    print('PASS sin cobros, imputaciones, inventario ni funciones de pago modificadas', flush=True)
    print('P123J_CAPACIDAD_SQL_PASS', flush=True)
