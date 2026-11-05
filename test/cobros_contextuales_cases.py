"""Contextual payments in the existing ephemeral PostgreSQL 17 harness."""
from concurrent.futures import ThreadPoolExecutor
import json
from uuid import uuid4

from stock_automation_sql_test import ADMIN, SELLER, P1, REPO, lit


def run(sql, val, count, balance, stock, order):
    checks = []

    def ok(name):
        checks.append(name)
        print(f"PASS {len(checks)}: {name}", flush=True)

    def rpc(query, **kwargs):
        return sql(query, role='authenticated', **kwargs)

    def result(query):
        return json.loads(rpc(query))

    def payment(client, amount, medium='Efectivo', key=None, note=None):
        observation = 'null' if note is None else lit(note)
        return (f"select registrar_pago_cliente_contextual('{key or uuid4()}',"
                f"'{client}',{amount},{lit(medium)},{observation});")

    def sale(qty=10, client=None, stamp='2026-01-01Z'):
        pedido, details, client = order([(P1, qty, qty)], client=client)
        detail = details[0]['detalle_id']
        sql(f"update pedido_detalles set cantidad_entregada={qty},importe_comision={qty},"
            f"porcentaje_comision=10 where id='{detail}';"
            f"update pedidos set total={qty * 10},resultado_entrega='entregado',"
            f"fecha_finalizacion='{stamp}' where id='{pedido}';")
        return pedido, detail, client

    def outstanding(pedido):
        return float(sql("select saldo_pendiente from saldos_pendientes_pedidos "
                         f"where pedido_id='{pedido}';"))

    def frozen():
        tables = ('pedidos', 'pedido_detalles', 'notas_credito', 'nota_credito_detalles',
                  'recepciones_nota_credito', 'ajustes_comision_aplicados',
                  'liquidaciones', 'liquidacion_detalles', 'stock_actual',
                  'stock_eventos', 'stock_movimientos', 'stock_configuracion',
                  'stock_regimenes', 'stock_transicion')
        return [sql("select md5(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t))::text,'[]'))"
                    f" from public.{table} t;") for table in tables]

    for version in ('20261023010000', '20261023011000', '20261023012000',
                    '20261104010000', '20261104020000'):
        path, = (REPO / 'supabase/migrations').glob(f'{version}_*.sql')
        sql(path.read_text(encoding='utf-8'))
    sql("update stock_transicion set mantenimiento=false;")
    balance(P1, 100)
    sql("update stock_regimenes set automatizacion_activa=true,fecha_corte='2025-01-01Z';"
        "update stock_configuracion set automatizacion_activa=true,integracion_version=1,"
        f"fecha_corte='2025-01-01Z',activada_at=now(),activada_por='{ADMIN}';")
    legacy = sql("select md5(pg_get_functiondef(oid)||coalesce(proacl::text,'')) from pg_proc "
                 "where oid='public.registrar_pago_cliente(uuid,numeric,text,text)'::regprocedure;")
    path, = (REPO / 'supabase/migrations').glob('20261105010000_*.sql')
    sql(path.read_text(encoding='utf-8'))
    assert legacy == sql("select md5(pg_get_functiondef(oid)||coalesce(proacl::text,'')) from pg_proc "
                         "where oid='public.registrar_pago_cliente(uuid,numeric,text,text)'::regprocedure;")
    ok('RPC anterior y privilegios conservados')

    pedido, _, client = sale()
    before = frozen()
    query = payment(client, 100, note='Cobro fixture')
    paid = result(query)
    assert paid['importe'] == 100 and paid['medio_pago'] == 'Efectivo'
    assert paid['actor_id'] == ADMIN and paid['cliente_id'] == client
    assert paid['imputaciones'] == [dict(pedido_id=pedido, importe_aplicado=100, saldo_restante=0)]
    assert outstanding(pedido) == 0 and before == frozen()
    ok('pago total sin cambios de stock, venta, notas o comisiones')

    assert result(query) == paid
    assert count('cobros_cliente', f"id='{paid['cobro_id']}'") == 1
    assert count('pedido_pagos', f"cobro_id='{paid['cobro_id']}'") == 1
    canonical = payment(client, '100.00', ' efectivo ', paid['solicitud_id'], ' Cobro fixture ')
    assert result(canonical) == paid
    ok('respuesta perdida después del commit y replay canónico sin segundo cobro')

    for changed in (payment(client, 99, key=paid['solicitud_id']),
                    payment(client, 100, 'Transferencia', paid['solicitud_id']),
                    payment(client, 100, key=paid['solicitud_id'], note='Otro')):
        rpc(changed, error='solicitud_cobro_incompatible')
    other = '10000000-0000-0000-0000-000000000003'
    sql(f"insert into auth.users values('{other}','other@test');"
        f"insert into usuarios(id,nombre,email,rol,activo) "
        f"values('{other}','Other','other@test','administrador',true);")
    rpc(query, actor=other, error='solicitud_cobro_incompatible')
    rpc(query, actor=SELLER, error='Solo administración')
    rpc('select * from solicitudes_cobro_cliente;', error='permission denied')
    sql(query, role='anon', error='permission denied')
    sql(query, role='service_role', error='permission denied')
    ok('conflictos de UUID y actor, RLS y ejecución administrativa')

    older, _, client = sale(stamp='2025-01-01Z')
    newer, _, _ = sale(client=client, stamp='2026-01-01Z')
    paid = result(payment(client, '125.25', ' transferencia '))
    assert paid['medio_pago'] == 'Transferencia'
    assert paid['imputaciones'] == [
        dict(pedido_id=older, importe_aplicado=100, saldo_restante=0),
        dict(pedido_id=newer, importe_aplicado=25.25, saldo_restante=74.75)]
    assert outstanding(older) == 0 and outstanding(newer) == 74.75
    assert count('pedido_pagos', f"cobro_id='{paid['cobro_id']}'") == 2
    ok('pago parcial decimal, transferencia y distribución FIFO entre pedidos')

    source, source_detail, client = sale(qty=2)
    result(payment(client, 20))
    note_payload = lit(json.dumps([dict(detalle_id=source_detail, cantidad=1)]))
    issued = result(f"select emitir_nota_credito_contextual('{uuid4()}','{source}',"
                    f"'Fixture',{note_payload});")
    debt, _, _ = sale(qty=2, client=client)
    before = frozen()
    paid = result(payment(client, 10))
    assert paid['imputaciones'] == [dict(pedido_id=debt, importe_aplicado=10, saldo_restante=0)]
    assert count('movimientos_credito_cliente',
                 f"pedido_origen_id='{source}' and pedido_destino_id='{debt}' and importe=10") == 1
    assert before == frozen()
    assert count('nota_credito_detalles', f"nota_id='{issued['nota_id']}' and comision=1") == 1
    ok('crédito disponible aplicado con trazabilidad, notas y comisiones conservadas')

    pedido, _, client = sale()
    for amount in ('101', '0', '-1', '1.001', "'NaN'::numeric", "'Infinity'::numeric"):
        code = 'supera la deuda' if amount == '101' else 'solicitud_cobro_invalida'
        before = (count('cobros_cliente'), count('pedido_pagos'), count('solicitudes_cobro_cliente'))
        rpc(payment(client, amount), error=code)
        assert before == (count('cobros_cliente'), count('pedido_pagos'), count('solicitudes_cobro_cliente'))
    rpc(payment(client, 10, 'Tarjeta'), error='medio_cobro_invalido')
    ok('excesos e importes inválidos rechazados sin efectos parciales')

    query = payment(client, 30)
    with ThreadPoolExecutor(max_workers=2) as pool:
        twins = list(pool.map(result, [query, query]))
    assert twins[0] == twins[1] and outstanding(pedido) == 70
    assert count('cobros_cliente', f"cliente_id='{client}'") == 1
    ok('dos conexiones con el mismo UUID confirman un solo cobro')

    def attempt(query):
        try:
            return result(query)
        except AssertionError as error:
            assert 'supera la deuda' in str(error), error
            return None

    with ThreadPoolExecutor(max_workers=2) as pool:
        outcomes = list(pool.map(attempt, [payment(client, 50), payment(client, 50)]))
    assert sum(item is not None for item in outcomes) == 1
    assert outstanding(pedido) == 20
    ok('dos dispositivos con UUID distintos no sobrecobran un saldo concurrente')

    rollback_order, _, client = sale()
    query = payment(client, 10)
    counts = (count('cobros_cliente'), count('pedido_pagos'), count('solicitudes_cobro_cliente'))
    rpc('begin; ' + query + ' select 1/0; commit;', error='division by zero')
    assert counts == (count('cobros_cliente'), count('pedido_pagos'), count('solicitudes_cobro_cliente'))
    assert outstanding(rollback_order) == 100
    assert result(query)['importe'] == 10
    ok('fallo antes del commit revierte cobro, imputaciones y registro de solicitud')

    # Force a failure specifically when persisting the recovery record, after
    # the legacy payment and credit allocations have run.
    source, detail, client = sale(qty=2)
    result(payment(client, 20))
    payload = lit(json.dumps([dict(detalle_id=detail, cantidad=1)]))
    result(f"select emitir_nota_credito_contextual('{uuid4()}','{source}','Fixture',{payload});")
    debt, _, _ = sale(qty=2, client=client)
    sql("create function public.fixture_fail_payment() returns trigger language plpgsql as $$"
        "begin raise exception 'fixture_ledger_failure'; end$$;"
        "create trigger fixture_fail before insert on solicitudes_cobro_cliente "
        "for each row execute function fixture_fail_payment();")
    counts = tuple(count(table) for table in
                   ('cobros_cliente','pedido_pagos','solicitudes_cobro_cliente','movimientos_credito_cliente'))
    query = payment(client, 10)
    rpc(query, error='fixture_ledger_failure')
    assert counts == tuple(count(table) for table in
                           ('cobros_cliente','pedido_pagos','solicitudes_cobro_cliente','movimientos_credito_cliente'))
    assert outstanding(debt) == 20
    sql('drop trigger fixture_fail on solicitudes_cobro_cliente; drop function fixture_fail_payment();')
    confirmed = result(query)
    assert outstanding(debt) == 0
    ok('fallo del registro idempotente revierte también la aplicación de crédito')

    sql('update stock_transicion set mantenimiento=true;')
    assert result(query) == confirmed
    rpc(payment(client, 1), error='stock_en_mantenimiento')
    ok('recuperación confirmada durante pausa sin ejecutar otro pago')
    print(f'P123B_COBROS_CONTEXTUALES_PASS ({len(checks)} grupos)', flush=True)
