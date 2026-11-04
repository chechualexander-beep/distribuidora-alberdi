"""Cases run by preventa_finalizacion_sql_test.py in ephemeral PostgreSQL."""
from concurrent.futures import ThreadPoolExecutor
import json
from uuid import uuid4

from stock_automation_sql_test import ADMIN, P1, P2, REPO, SELLER, lit


def run(sql, val, count, balance, stock, order):
    migrations = REPO / 'supabase/migrations'
    for version in ('20261023010000', '20261023011000', '20261023012000',
                    '20261104010000'):
        path, = migrations.glob(f'{version}_*.sql')
        sql(path.read_text(encoding='utf-8'))

    def rpc(query, **kwargs):
        return sql(query, role='authenticated', **kwargs)

    def payload(value):
        return lit(json.dumps(value)) + '::jsonb'

    def create(client, qty=2, actor=ADMIN, error=None):
        key = str(uuid4())
        lines = payload([dict(producto_id=P1, cantidad=qty,
                              precio_unitario=10, tipo_precio='normal')])
        rpc(f"select crear_pedido_interno('{key}','{client}','normal',"
            f"'venta_directa',null,current_date,{lines});", actor=actor, error=error)
        return key

    def client():
        return sql("insert into clientes(nombre_comercio,direccion,preventista_id)"
                   f" values('Fixture','Fixture','{SELLER}') returning id;")

    def prepare(pedido, key=None, error=None):
        key = key or str(uuid4())
        result = rpc(f"select preparar_finalizacion_contexto('{key}','{pedido}');",
                     error=error)
        return json.loads(result) if not error else None

    def finish(context, delivered, adds=(), amount=None):
        pedido = context['pedido_id']
        detail = sql(f"select id from pedido_detalles where pedido_id='{pedido}'"
                     " and not agregado_en_entrega;")
        originals = payload([dict(detalle_id=detail, cantidad_entregada=delivered)])
        payment = "'sin_pago'" if amount is None else "'parcial'"
        medium = 'null' if amount is None else "'Efectivo'"
        importe = 'null' if amount is None else str(amount)
        return (f"select finalizar_gestion_pedido_contexto('{context['solicitud_id']}',"
                f"'{pedido}','{context['fecha_fisica']}','en_reparto',{originals},"
                f"{payload(adds)},{payment},'{context['regimen_id']}',"
                f"{context['protocolo']},'Fixture',{importe},{medium});")

    sql("update stock_transicion set mantenimiento=false where singleton;")
    create(client(), error='venta_directa_requiere_stock_v2_on')
    balance(P1, 100)
    balance(P2, 100)
    sql("update stock_regimenes set automatizacion_activa=true,fecha_corte='2025-01-01Z';"
        " update stock_configuracion set automatizacion_activa=true,integracion_version=1,"
        f" fecha_corte='2025-01-01Z',activada_at=now(),activada_por='{ADMIN}';")
    create(client(), actor=SELLER, error='Solo administración')

    for delivered, adds, expected in [
        (2, [], {P1: 2}),
        (2, [dict(producto_id=P2, cantidad_entregada=1, tipo_precio='normal')], {P1: 2, P2: 1}),
        (0, [], {}),
    ]:
        pedido = create(client())
        before = {p: stock(p) for p in (P1, P2)}
        result = json.loads(rpc(finish(prepare(pedido), delivered, adds)))
        assert result['resultado_entrega'] == ('entregado' if delivered else 'no_entregado')
        assert result['movimientos_stock'] == len(expected)
        for p in before:
            assert stock(p) == before[p] - expected.get(p, 0)

    # Original + agregado del mismo producto con precios distintos y cobro parcial.
    pedido = create(client())
    edited = payload([dict(producto_id=P1, cantidad=2, precio_unitario=10,
                           tipo_precio='normal')])
    edit = (f"select actualizar_pedido_activo('{pedido}',20,'normal','venta_directa',"
            f"null,current_date,{edited});")
    rpc(edit)
    context = prepare(pedido)
    rpc(edit, error='venta_directa_preparada')
    prepare(pedido, error='venta_directa_preparada')
    adds = [dict(producto_id=P1, cantidad_entregada=0.5, tipo_precio='promo')]
    before_stock = stock()
    before_pay = count('cobros_cliente')
    request = finish(context, 1, adds, amount=5)
    # Dos conexiones reales compiten por el mismo UUID. Ambas deben ver un resultado.
    with ThreadPoolExecutor(max_workers=2) as pool:
        first, second = list(pool.map(rpc, [request, request]))
    result = json.loads(first)
    assert result == json.loads(second) == json.loads(rpc(request))
    assert result['resultado_entrega'] == 'parcial'
    assert result['movimientos_stock'] == 1 and stock() == before_stock - 1.5
    assert count('cobros_cliente') == before_pay + 1
    assert float(result['saldo_pendiente']) == 9
    lines = val(f"select jsonb_agg(jsonb_build_array(agregado_en_entrega,precio_unitario,"
                f"cantidad_entregada,cantidad_no_entregada,importe_comision)"
                f" order by agregado_en_entrega) from pedido_detalles where pedido_id='{pedido}';")
    assert lines == [[False, 10, 1, 1, 0.5], [True, 8, 0.5, 0, 0.16]]
    rpc(finish(context, 2, adds, amount=5), error='solicitud_incompatible')
    prepare(pedido, error='Pedido no disponible')

    pedido = create(client(), qty=999)
    context = prepare(pedido)
    before = (stock(), count('stock_eventos'), count('stock_movimientos'),
              count('cobros_cliente'), count('pedido_pagos'))
    rpc(finish(context, 999, amount=5), error='Stock insuficiente')
    assert before == (stock(), count('stock_eventos'), count('stock_movimientos'),
                      count('cobros_cliente'), count('pedido_pagos'))
    assert count('finalizacion_pedido_solicitudes', f"pedido_id='{pedido}'") == 0
    assert sql(f"select resultado_entrega from pedidos where id='{pedido}';") == 'pendiente'
    rpc(finish(dict(context, protocolo=1), 1), error='solicitud_incompatible')

    pedido, _, _ = order([(P1, 2, 2)])
    rpc(finish(prepare(pedido), 1, adds), error='Agregado duplica producto original')
    print('PASS: matriz PostgreSQL Venta directa contextual', flush=True)
