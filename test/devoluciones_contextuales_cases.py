"""Devoluciones contextuales en el clúster temporal del laboratorio existente."""
from concurrent.futures import ThreadPoolExecutor
import json
from uuid import uuid4

from stock_automation_sql_test import ADMIN, P1, P2, REPO, SELLER, lit


def run(sql, val, count, balance, stock, order):
    def rpc(query, **kwargs):
        return sql(query, role='authenticated', **kwargs)

    def result(query):
        return json.loads(rpc(query))

    def sale(lines, *, direct=False, paid=0, client=None):
        pedido, details, client = order(
            [(product, qty, qty) for product, qty, _, _ in lines],
            direct=direct, client=client)
        ids = [row['detalle_id'] for row in details]
        total = sum(qty * price for _, qty, price, _ in (lines[:1] if direct else lines))
        for index, (detail, (_, qty, price, commission)) in enumerate(zip(ids, lines)):
            extra = direct and index > 0
            sql(f"update pedido_detalles set cantidad_entregada={qty},precio_unitario={price},"
                f"subtotal={qty * price},importe_comision={commission},"
                f"agregado_en_entrega={str(extra).lower()},cantidad={0 if extra else qty},"
                f"cantidad_facturada={'null' if direct else qty} "
                f"where id='{detail}';")
        sql(f"update pedidos set total={total},resultado_entrega='entregado',"
            f"facturado={'false' if direct else 'true'},fecha_finalizacion='2024-01-01Z' where id='{pedido}';")
        if paid:
            sql(f"insert into pedido_pagos(pedido_id,importe,medio_pago) "
                f"values('{pedido}',{paid},'Efectivo');")
        return pedido, ids, client

    def note(pedido, lines, key=None, legacy=False):
        payload = lit(json.dumps([dict(detalle_id=d, cantidad=q) for d, q in lines]))
        if legacy:
            return f"select crear_nota_credito('{pedido}','Fixture',{payload},'{key or uuid4()}');"
        return f"select emitir_nota_credito_contextual('{key or uuid4()}','{pedido}','Fixture',{payload});"

    def receipt(detail, good, bad, key=None):
        return f"select recibir_nota_credito_contextual('{key or uuid4()}','{detail}',{good},{bad});"

    def note_line(nota, original=None):
        where = f" and pedido_detalle_id='{original}'" if original else ''
        return sql(f"select id from nota_credito_detalles where nota_id='{nota}'{where};")

    def summary_cost():
        return result("select resumen_comercial('2000-01-01Z','infinity');")['costo_recuperado']

    def liquidation(detail):
        selection = f"'{SELLER}',array['{detail}'::uuid]"
        preview = result(f"select previsualizar_liquidacion_nc({selection});")
        ident = rpc(f"select registrar_liquidacion_con_nc('{SELLER}',current_date,current_date,"
                    f"array['{detail}'::uuid],{lit(preview['token'])});")
        return ident, preview

    def race(queries, expected):
        def attempt(query):
            try:
                return result(query)
            except AssertionError as exc:
                assert expected in str(exc), exc
                return None
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(attempt, queries))
        assert sum(item is not None for item in results) == 1, results
        return next(item for item in results if item is not None)

    migrations = REPO / 'supabase/migrations'
    for version in ('20261023010000', '20261023011000', '20261023012000', '20261104010000'):
        path, = migrations.glob(f'{version}_*.sql')
        sql(path.read_text(encoding='utf-8'))
    sql("update stock_transicion set mantenimiento=false;")
    balance(P1, 100)
    old, (old_line,), _ = sale([(P1, 2, 10, 1)])
    historical_key = uuid4()
    old_note = rpc(note(old, [(old_line, 1)], historical_key, legacy=True))
    old_detail = note_line(old_note)
    rpc(f"select recibir_nota_credito('{old_detail}',true);")
    assert summary_cost() == 2

    path, = migrations.glob('20261104020000_*.sql')
    sql(path.read_text(encoding='utf-8'))
    assert summary_cost() == 2
    assert sql(f"select cantidad_apta is null from recepciones_nota_credito where detalle_id='{old_detail}';") == 't'
    rpc(note(old, [(old_line, 1)], historical_key), error='clave_nota_historica_en_uso')
    sql("update stock_regimenes set automatizacion_activa=true,fecha_corte='2025-01-01Z';"
        " update stock_configuracion set automatizacion_activa=true,integracion_version=1,"
        f" fecha_corte='2025-01-01Z',activada_at=now(),activada_por='{ADMIN}';")

    pedido, (original, extra), _ = sale([(P1, 3, 10, 3), (P1, 1, 8, 0.8)], direct=True)
    issued = note(pedido, [(original, 2), (extra, 1)])
    before = (stock(), count('stock_eventos'), count('stock_movimientos'))
    first = result(issued)
    assert first['total'] == 28 and result(issued) == first
    assert before == (stock(), count('stock_eventos'), count('stock_movimientos'))
    assert count('recepciones_nota_credito', f"detalle_id in (select id from nota_credito_detalles where nota_id='{first['nota_id']}')") == 0
    assert val(f"select to_jsonb(s) from saldos_pendientes_pedidos s where pedido_id='{pedido}';")['saldo_pendiente'] == 10
    assert val(f"select jsonb_agg(jsonb_build_array(precio_unitario,comision) order by precio_unitario)"
               f" from nota_credito_detalles where nota_id='{first['nota_id']}';") == [[8, 0.8], [10, 2]]
    assert float(sql(f"select total from pedidos where id='{pedido}';")) == 30
    commercial_tables = ('notas_credito','nota_credito_detalles','movimientos_credito_cliente',
                         'solicitudes_devolucion_contextual')
    snapshot = tuple(count(t) for t in commercial_tables)
    rpc(note(pedido, [(original, 1), (extra, 1)]), error='supera lo entregado')
    assert snapshot == tuple(count(t) for t in commercial_tables)
    rpc(note(pedido, [(original, 2)]), error='supera lo entregado')
    rpc(note(pedido, [(original, 1)], first['solicitud_id']), error='solicitud_devolucion_incompatible')
    assert result(note(pedido, [(extra, 1), (original, 2)], first['solicitud_id'])) == first
    second = result(note(pedido, [(original, 1)]))
    assert second['total'] == 10
    assert float(sql(f"select saldo_pendiente from saldos_pendientes_pedidos where pedido_id='{pedido}';")) == 0

    mixed = note_line(first['nota_id'], original)
    damaged = note_line(first['nota_id'], extra)
    good = note_line(second['nota_id'])
    rpc(receipt(mixed, 1, 0), error='recepcion_debe_completar_renglon')
    mixed_request = receipt(mixed, 1, 1)
    mixed_result = result(mixed_request)
    assert result(mixed_request) == mixed_result
    rpc(receipt(mixed, 2, 0, mixed_result['solicitud_id']), error='solicitud_devolucion_incompatible')
    rpc(receipt(mixed, 1, 1), error='renglon_nota_ya_recibido')
    damaged_result = result(receipt(damaged, 0, 1))
    assert damaged_result['movimientos_stock'] == 0
    assert count('stock_eventos', f"id='{damaged_result['evento_id']}' and solicitud_id=recepcion_id") == 1
    assert val("select solicitud->'contenido'->'items' from stock_eventos "
               f"where id='{damaged_result['evento_id']}';") == []
    good_result = race([receipt(good, 1, 0), receipt(good, 1, 0)], 'renglon_nota_ya_recibido')
    for confirmed in (mixed_result, good_result):
        event = confirmed['evento_id']
        assert count('stock_movimientos', f"evento_id='{event}' and cantidad_delta=1 and tipo='devolucion_apta'") == 1
        assert count('stock_eventos', f"id='{event}' and fecha_fisica>=fecha_corte_aplicable and automatizacion_activa") == 1
    assert stock() == before[0] + 2 and summary_cost() == 6

    paid, (paid_line,), client = sale([(P1, 2, 10, 2)], paid=20)
    initial_liq, _ = liquidation(paid_line)
    debt, (debt_line,), _ = sale([(P1, 2, 10, 2)], client=client)
    credit = race([note(paid, [(paid_line, 2)]), note(paid, [(paid_line, 2)])], 'supera lo entregado')
    assert credit['total'] == 20
    assert count('pedido_pagos', f"pedido_id='{paid}' and importe=20") == 1
    assert count('movimientos_credito_cliente', f"pedido_origen_id='{paid}' and pedido_destino_id='{debt}' and importe=20") == 1
    later_liq, preview = liquidation(debt_line)
    assert preview['descuento'] >= 2 and initial_liq != later_liq
    assert count('liquidaciones', f"id='{initial_liq}' and comision_total=2") == 1

    no_stock, (no_stock_line,), _ = sale([(P2, 1, 10, 1)])
    rollback_note = result(note(no_stock, [(no_stock_line, 1)]))
    rollback_line = note_line(rollback_note['nota_id'])
    rollback_key = uuid4()
    rollback_query = receipt(rollback_line, 1, 0, rollback_key)
    snapshot = tuple(count(t) for t in ('recepciones_nota_credito','stock_eventos','stock_movimientos','solicitudes_devolucion_contextual'))
    rpc(rollback_query, error='Stock no inicializado')
    assert snapshot == tuple(count(t) for t in ('recepciones_nota_credito','stock_eventos','stock_movimientos','solicitudes_devolucion_contextual'))
    balance(P2, 100)
    assert result(rollback_query)['movimientos_stock'] == 1

    other_admin = '10000000-0000-0000-0000-000000000003'
    sql(f"insert into auth.users values('{other_admin}','other@test');"
        f"insert into usuarios(id,nombre,email,rol,activo) values('{other_admin}','Other','other@test','administrador',true);")
    rpc(mixed_request, actor=other_admin, error='solicitud_devolucion_incompatible')
    rpc(mixed_request, actor=SELLER, error='Solo administración')
    rpc("select * from solicitudes_devolucion_contextual;", error='permission denied')
    rpc(note(pedido, [(original, 1)], legacy=True), error='camino_stock_no_integrado')
    rpc(f"select recibir_nota_credito('{mixed}',true);", error='camino_stock_no_integrado')
    rpc(f"select stock_base_crear_nota_credito('{pedido}','Fixture','[]','fixture-privado');",
        error='permission denied')
    sql("update stock_transicion set mantenimiento=true;")
    assert result(issued) == first and result(mixed_request) == mixed_result
    rpc(note(pedido, [(original, 1)]), error='stock_en_mantenimiento')
    rpc(receipt(mixed, 1, 1), error='stock_en_mantenimiento')
    sql("update stock_regimenes set cerrado_at=clock_timestamp() where cerrado_at is null;"
        " with next as (insert into stock_regimenes(protocolo,automatizacion_activa,evidencia)"
        " values(2,false,'{}') returning id)"
        " update stock_transicion set regimen_id=next.id,mantenimiento=false from next;"
        " update stock_configuracion set automatizacion_activa=false,integracion_version=0,"
        " fecha_corte=null,activada_at=null,activada_por=null;")
    assert result(issued) == first and result(mixed_request) == mixed_result
    print('PASS: devoluciones contextuales, conciliación comercial y movimientos atómicos', flush=True)
