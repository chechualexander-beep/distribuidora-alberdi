"""2A-2: PostgreSQL real efímero, sin red; ON sólo mediante fixture del owner.
STOCK_TEST_PG_BIN debe señalar bin de PostgreSQL. No usa la RPC de activación.
"""
import concurrent.futures
import json
import re
import subprocess
import sys
import uuid

from stock_automation_sql_test import postgres, lit, REPO, ADMIN, SELLER, P1, P2, P3

MIGRATION = '20261007030000_finalizacion_preventa_transaccional.sql'


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    with postgres() as (command, env, flags):
        checks = []

        def sql(query, role='postgres', actor=ADMIN, error=None):
            prefix = f"set request.jwt.claim.sub={lit(actor)}; set role {role}; "
            p = subprocess.run(command, input=prefix+query, text=True, encoding='utf-8', capture_output=True, env=env, **flags)
            if error:
                assert p.returncode and re.search(error, p.stderr, re.I), (query, p.stderr)
                return p.stderr
            assert not p.returncode, (query, p.stderr)
            return p.stdout.strip()

        def val(query, **kwargs):
            return json.loads(sql(query, **kwargs))

        def count(table, where='true'):
            return int(sql(f'select count(*) from {table} where {where};'))

        def ok(name):
            checks.append(name)
            print(f'OK {len(checks)}: {name}', flush=True)

        sql('''create role anon; create role authenticated; create role service_role;
          create schema auth; create schema extensions;
          create table auth.users(id uuid primary key,email text);
          create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
          grant usage on schema auth to anon,authenticated;
          alter default privileges in schema public grant all on tables to anon,authenticated,service_role;
          alter default privileges in schema public grant all on functions to anon,authenticated,service_role;''')
        sql((REPO/'test/fixtures/catalogo_storage_schema.sql').read_text(encoding='utf-8').replace('grant select on public.productos to authenticated;', ''))
        for file in sorted((REPO/'supabase/migrations').glob('*.sql')):
            if file.name > MIGRATION:
                continue
            content = file.read_text(encoding='utf-8-sig')
            content = re.sub(r'create extension if not exists pg_net;', '-- isolated: no HTTP', content, flags=re.I)
            for name in ['enviar_notificacion_nuevo_pedido', 'enviar_notificacion_pedido_editado']:
                pattern = r'(CREATE\s+OR\s+REPLACE\s+FUNCTION\s+(?:"?public"?\.)?"?'+name+r'"?\s*\(.*?\bAS\s+)(\$\w*\$).*?\2\s*;'
                content = re.sub(pattern, lambda m: m[1]+m[2]+' BEGIN RETURN; END; '+m[2]+';', content, flags=re.I|re.S)
            assert not re.search(r'net\.http_post|vault\.',content,re.I)
            sql(content)
        sql(f"insert into auth.users values('{ADMIN}','admin@test'),('{SELLER}','seller@test'); insert into usuarios(id,nombre,email,rol,activo) values('{ADMIN}','Admin','admin@test','administrador',true),('{SELLER}','Seller','seller@test','preventista',true);")
        for p in [P1,P2,P3]:
            sql(f"insert into productos(id,nombre,codigo,precio_normal,precio_promo,precio_interior,costo,comision_normal,comision_promo,comision_interior) values('{p}','Fixture {p}','{p}',10,8,9,2,5,4,3);")
        depot = sql("select id from ubicaciones_stock where codigo='deposito_alberdi';")

        def regime(on):
            if on:
                sql(f"update stock_configuracion set automatizacion_activa=true,integracion_version=1,fecha_corte='2025-01-01Z',activada_at=now(),activada_por='{ADMIN}';")
            else:
                sql('update stock_configuracion set automatizacion_activa=false,integracion_version=0,fecha_corte=null,activada_at=null,activada_por=null;')

        def order(lines=None, catalog=False, direct=False, client=None):
            client = client or sql(f"insert into clientes(nombre_comercio,direccion,preventista_id) values('Fixture','Fixture','{SELLER}') returning id;")
            pedido = sql(f"insert into pedidos(cliente_id,preventista_id,tipo_precio,tipo_operacion,facturado,origen,catalogo_preventista_id) values('{client}','{SELLER}','normal',{' '.join([lit('venta_directa' if direct else 'pedido')])},true,{lit('catalogo' if catalog else 'interno')},{lit(SELLER) if catalog else 'null'}) returning id;")
            detalles=[]
            for p,q,f in lines or [(P1,10,10)]:
                ident=sql(f"insert into pedido_detalles(pedido_id,producto_id,cantidad,cantidad_facturada,precio_unitario,subtotal,tipo_precio,costo_unitario,porcentaje_comision) values('{pedido}','{p}',{q},{f if f is not None else 'null'},10,{q*10},'normal',2,5) returning id;")
                detalles.append({'detalle_id':ident,'cantidad_entregada':f if f is not None else q})
            return pedido,detalles,client

        def query(pedido, originales, adds=None, key=None, payment='sin_pago', amount=None, stamp='2026-01-01T00:00:00Z'):
            return f"select finalizar_gestion_pedido_v2({lit(key or uuid.uuid4())},{lit(pedido)},{lit(stamp)}::timestamptz,'en_reparto',{lit(json.dumps(originales))}::jsonb,{lit(json.dumps(adds or []))}::jsonb,{lit(payment)},'Fixture',{amount if amount is not None else 'null'},{lit('Efectivo') if payment!='sin_pago' else 'null'});"

        def finish(pedido, originales, **kwargs):
            error=kwargs.pop('error',None)
            q=query(pedido,originales,**kwargs)
            return sql(q,role='authenticated',error=error) if error else val(q,role='authenticated')

        def balance(p, n):
            initialized=count('stock_movimientos',f"producto_id='{p}' and tipo='stock_inicial'")
            fn='ajustar_stock' if initialized else 'cargar_stock_inicial'
            if initialized:
                now=float(sql(f"select cantidad from stock_actual where producto_id='{p}';"))
                delta=n-now
                if delta:
                    sql(f"select ajustar_stock('{depot}','{p}',{n},'Fixture',null);",role='authenticated')
            else:
                sql(f"select cargar_stock_inicial('{depot}',{lit(json.dumps([{'producto_id':p,'cantidad':n}]))}::jsonb);",role='authenticated')

        def stock(p=P1):
            return float(sql(f"select cantidad from stock_actual where producto_id='{p}';"))

        if sys.argv[1:] == ['--venta-directa-contextual']:
            from venta_directa_contextual_cases import run
            run(sql, val, count, balance, stock, order)
            return

        if sys.argv[1:] == ['--devoluciones-contextuales']:
            from devoluciones_contextuales_cases import run
            run(sql, val, count, balance, stock, order)
            return

        def unchanged(pedido, before_events, before_pay, before_stock=None):
            assert sql(f"select resultado_entrega from pedidos where id='{pedido}';")=='pendiente'
            assert float(sql(f"select sum(cantidad_entregada) from pedido_detalles where pedido_id='{pedido}';"))==0
            assert count('stock_eventos')==before_events and count('cobros_cliente')==before_pay
            if before_stock is not None: assert stock()==before_stock

        regime(False)
        for name,qty,result in [('completa OFF',10,'entregado'),('parcial OFF',6,'parcial'),('no entregado OFF',0,'no_entregado')]:
            p,d,_=order(); d[0]['cantidad_entregada']=qty
            r=finish(p,d); assert r['resultado_entrega']==result and r['movimientos_stock']==0
            assert float(sql(f"select cantidad_no_entregada from pedido_detalles where pedido_id='{p}';"))==10-qty
            ok(name)
        p,d,_=order(); add=[{'producto_id':P2,'cantidad_entregada':2,'tipo_precio':'promo'}]
        r=finish(p,d,adds=add)
        assert count('pedido_detalles',f"pedido_id='{p}' and agregado_en_entrega and precio_unitario=8 and cantidad=0 and cantidad_facturada=0 and subtotal=0")==1
        ok('agregado OFF: precio/costo/comisión de servidor y semántica vigente')
        assert count('stock_movimientos')==0 and count('stock_eventos')==4
        ok('OFF registra eventos, no inventario ni movimientos')
        for product in [P1,P2]: balance(product,100)
        regime(True)
        for name,qty,result in [('completa ON',10,'entregado'),('parcial ON',6,'parcial'),('no entregado ON',0,'no_entregado')]:
            before=stock(); p,d,_=order(); d[0]['cantidad_entregada']=qty
            r=finish(p,d); assert r['resultado_entrega']==result and stock()==before-qty
            assert count('stock_movimientos',f"evento_id='{r['stock_evento_id']}'")==int(qty>0)
            ok(name)
        p,d,_=order([(P1,10,0)]); d[0]['cantidad_entregada']=10
        finish(p,d,error='Cantidad superior'); d[0]['cantidad_entregada']=0
        assert finish(p,d)['resultado_entrega']=='no_entregado'
        ok('cantidad facturada cero nunca toma cantidad pedida')
        for name,change,err in [
            ('original duplicado',lambda d:d+d,'duplicado'),
            ('original omitido',lambda d:d[:1],'Cobertura'),
            ('exceso base',lambda d:[dict(x,cantidad_entregada=11) for x in d],'superior'),
            ('negativa',lambda d:[dict(x,cantidad_entregada=-1) for x in d],'inválida'),
            ('no numérica NaN',lambda d:[dict(x,cantidad_entregada='NaN') for x in d],'inválido'),
            ('exceso precisión',lambda d:[dict(x,cantidad_entregada=1.001) for x in d],'inválida'),
            ('NULL',lambda d:[dict(x,cantidad_entregada=None) for x in d],'inválido'),
            ('ID ajeno',lambda d:[dict(x,detalle_id=str(uuid.uuid4())) for x in d],'ajeno'),
        ]:
            p,d,_=order([(P1,10,10),(P2,10,10)]); finish(p,change(d),error=err); ok(name)
        for name,adds,err in [
            ('agregado duplicado',add+add,'duplicado'),
            ('agregado original',[dict(add[0],producto_id=P1)],'duplica'),
            ('agregado cero',[dict(add[0],cantidad_entregada=0)],'inválido'),
            ('producto inexistente',[dict(add[0],producto_id=str(uuid.uuid4()))],'inexistente|inicializado'),
        ]:
            p,d,_=order(); finish(p,d,adds=adds,error=err); ok(name)
        balance(P1,3); p,d,_=order([(P1,5,5)]); ev,pay=count('stock_eventos'),count('cobros_cliente')
        finish(p,d,error='insuficiente'); unchanged(p,ev,pay,3); ok('insuficiente: rollback comercial/evento/stock')
        p,d,_=order([(P3,2,2)]); finish(p,d,error='no inicializado'); ok('producto sin inicializar')
        balance(P1,10); balance(P2,1); p,d,_=order([(P1,3,3),(P2,2,2)])
        ev,pay=count('stock_eventos'),count('cobros_cliente'); finish(p,d,error='insuficiente')
        unchanged(p,ev,pay,10); assert stock(P2)==1; ok('rollback multiproducto')
        for payment,amount in [('completo',50),('parcial',20)]:
            balance(P1,100); p,d,_=order([(P1,5,5)]); key=str(uuid.uuid4())
            r=finish(p,d,key=key,payment=payment,amount=amount)
            assert count('pedido_pagos',f"pedido_id='{p}'")==1 and r['saldo_pendiente']==50-amount and stock()==95
            before=(count('cobros_cliente'),count('pedido_pagos'),count('movimientos_credito_cliente'),count('stock_eventos'),count('stock_movimientos'))
            assert finish(p,d,key=key,payment=payment,amount=amount)==r
            assert before==(count('cobros_cliente'),count('pedido_pagos'),count('movimientos_credito_cliente'),count('stock_eventos'),count('stock_movimientos'))
            ok(f'pago {payment} + Stock; retry exacto sin segundo efecto')
        # Crédito vigente: pedido anterior sobrepagado, crédito se aplica antes de cobrar.
        source,sd,client=order([(P1,1,1)])
        sql(f"update pedidos set resultado_entrega='entregado',fecha_finalizacion=now() where id='{source}'; update pedido_detalles set cantidad_entregada=1 where pedido_id='{source}'; insert into pedido_pagos(pedido_id,importe,medio_pago) values('{source}',30,'Efectivo');")
        balance(P1,100); p,d,_=order([(P1,5,5)],client=client); key=str(uuid.uuid4())
        r=finish(p,d,key=key,payment='completo',amount=30)
        assert r['saldo_pendiente']==0 and count('movimientos_credito_cliente',f"pedido_destino_id='{p}'")==1
        assert finish(p,d,key=key,payment='completo',amount=30)==r
        assert count('movimientos_credito_cliente',f"pedido_destino_id='{p}'")==1
        ok('crédito + cobro + Stock idempotentes')
        balance(P1,3); p,d,_=order([(P1,5,5)]); ev,pay=count('stock_eventos'),count('cobros_cliente')
        finish(p,d,payment='completo',amount=50,error='insuficiente'); unchanged(p,ev,pay,3)
        ok('Stock fallido impide cobro y crédito')
        balance(P1,100); p,d,_=order([(P1,5,5)]); key=str(uuid.uuid4()); r=finish(p,d,key=key)
        finish(p,[dict(d[0],cantidad_entregada=4)],key=key,error='solicitud_incompatible')
        finish(p,d,error='operacion_ya_finalizada'); assert stock()==95
        ok('misma key cambiada y otra key finalizada: conflicto sin efectos')
        read=val(f"select consultar_finalizacion_solicitud('{key}');",role='authenticated')
        assert read=={'estado':'confirmada','resultado':r}
        assert val(f"select consultar_finalizacion_solicitud('{uuid.uuid4()}');",role='authenticated')=={'estado':'inexistente'}
        sql(f"select consultar_finalizacion_solicitud('{key}');",role='authenticated',actor=SELLER,error='administración')
        ok('recovery contract sólo lectura administrativa')
        balance(P1,100); p,d,_=order([(P1,5,5)]); key=str(uuid.uuid4()); q=query(p,d,key=key,payment='completo',amount=50)
        with concurrent.futures.ThreadPoolExecutor(2) as pool:
            futures=[pool.submit(val,q,role='authenticated') for _ in range(2)]
            responses=[f.result() for f in futures]
        assert responses[0]==responses[1] and stock()==95 and count('pedido_pagos',f"pedido_id='{p}'")==1
        ok('dos conexiones: misma solicitud converge con único cobro/evento')
        balance(P1,5); a,ad,_=order([(P1,4,4)]); b,bd,_=order([(P1,3,3)])
        def competing(q):
            try: return val(q,role='authenticated')
            except AssertionError as e:
                assert 'insuficiente' in str(e).lower(); return None
        with concurrent.futures.ThreadPoolExecutor(2) as pool:
            responses=list(pool.map(competing,[query(a,ad,payment='completo',amount=40),query(b,bd,payment='completo',amount=30)]))
        assert sum(x is not None for x in responses)==1 and stock() in (1,2)
        assert count('pedidos',f"id in ('{a}','{b}') and resultado_entrega='entregado'")==1
        assert count('pedido_pagos',f"pedido_id in ('{a}','{b}')")==1
        ok('dos conexiones: pedidos 4 y 3 compiten por 5; estado y pago atómicos')
        balance(P1,100); balance(P2,100); p,d,_=order([(P1,5,5)],catalog=True)
        r=finish(p,d,adds=add); assert stock()==95 and stock(P2)==98
        assert float(sql(f"select sum(importe_comision) from pedido_detalles where pedido_id='{p}';"))==3.14
        ok('catálogo y agregado ON: comisión única del trigger y dos deltas')
        regime(False); p,d,_=order([(P1,1,1)],direct=True)
        finish(p,d,error='Solo preventa')
        def legacy(p,d):
            payload=[dict(id=x['detalle_id'],cantidad_entregada=x['cantidad_entregada'],cantidad_no_entregada=0,precio_unitario=10,porcentaje_comision=5,importe_comision=.5) for x in d]
            return f"select finalizar_gestion_pedido('{p}','en_reparto','entregado',null,{lit(json.dumps(payload))}::jsonb,'sin_pago');"
        ev=count('stock_eventos'); sql(legacy(p,d),role='authenticated'); assert count('stock_eventos')==ev
        ok('venta directa legacy OFF sin integración Stock')
        p,d,_=order([(P1,1,1)]); sql(legacy(p,d),role='authenticated'); assert count('stock_eventos')==ev
        ok('preventa legacy OFF compatible')
        regime(True); p,d,_=order([(P1,1,1)]); sql(legacy(p,d),role='authenticated',error='actualizacion_requerida')
        for fn in ['finalizar_gestion_pedido_sin_nc','finalizar_gestion_pedido_legacy_interno']:
            sql(legacy(p,d).replace('finalizar_gestion_pedido(',fn+'('),role='service_role',error='permission denied')
        ok('legacy ON y cuerpos internos no permiten bypass')
        for query_ in [f"update pedidos set resultado_entrega='entregado' where id='{p}';",f"update pedido_detalles set cantidad_entregada=1 where pedido_id='{p}';",f"delete from pedido_detalles where pedido_id='{p}';",f"update pedido_detalles set porcentaje_comision=90 where pedido_id='{p}';"]:
            sql(query_,role='authenticated',error='permission denied')
        ok('grants críticos y DELETE directo denegados')
        sql(f"update pedido_detalles set cantidad_facturada=1 where pedido_id='{p}'; update pedidos set facturado=true,numero_comprobante='999',fecha_facturacion=now() where id='{p}';",role='authenticated')
        sql(f"insert into pedido_detalles(pedido_id,producto_id,cantidad,precio_unitario,subtotal,tipo_precio,cantidad_facturada) values('{p}','{P2}',1,10,10,'normal',1);",role='authenticated')
        ok('Facturación UPDATE e INSERT reales permitidos en pendiente')
        # RPC autorizada sigue actualizando un pedido editable (sin facturar).
        editable,ed,cl=order([(P1,1,1)]); sql(f"update pedidos set facturado=false where id='{editable}';")
        payload=[{'producto_id':P1,'cantidad':2,'precio_unitario':10,'tipo_precio':'normal'}]
        sql(f"select actualizar_pedido_activo('{editable}',20,'normal','pedido',null,'2026-10-08',{lit(json.dumps(payload))}::jsonb);",role='authenticated')
        assert float(sql(f"select cantidad from pedido_detalles where pedido_id='{editable}';"))==2
        ok('RPC edición pedido pendiente preservada')
        final,fd,_=order([(P1,1,1)]); balance(P1,100); finish(final,fd)
        for q in [f"update pedido_detalles set cantidad_facturada=2 where pedido_id='{final}';", f"update pedidos set numero_comprobante='123' where id='{final}';",f"insert into pedido_detalles(pedido_id,producto_id,cantidad,precio_unitario,subtotal,tipo_precio,cantidad_facturada) values('{final}','{P2}',1,10,10,'normal',1);"]:
            sql(q,role='authenticated',error='operacion_ya_finalizada')
        ok('detalles y facturación finalizados congelados para cliente')
        balance(P1,100); p,d,_=order([(P1,2,2),(P2,2,2)]); key=str(uuid.uuid4()); r=finish(p,d,key=key)
        assert finish(p,list(reversed(d)),key=key,stamp='2025-12-31T21:00:00-03:00')==r
        ok('normalización orden de arrays, números y zona horaria')
        p,d,_=order(); finish(p,d,stamp='infinity',error='Fecha'); finish(p,d,stamp='2999-01-01Z',error='Fecha')
        ok('fecha física infinita/futura rechazada')
        balance(P1,100); p,d,_=order([(P1,5,5)]); ev,pay=count('stock_eventos'),count('cobros_cliente')
        finish(p,d,payment='completo',amount=51,error='Cambió el saldo')
        unchanged(p,ev,pay,100)
        assert count('finalizacion_pedido_solicitudes',f"pedido_id='{p}'")==0
        ok('error financiero posterior revierte deltas, evento y detalles')
        balance(P1,3); source,sd,client=order([(P1,1,1)])
        sql(f"update pedidos set resultado_entrega='entregado',fecha_finalizacion=now() where id='{source}'; update pedido_detalles set cantidad_entregada=1 where pedido_id='{source}'; insert into pedido_pagos(pedido_id,importe,medio_pago) values('{source}',30,'Efectivo');")
        p,d,_=order([(P1,5,5)],client=client); credits=count('movimientos_credito_cliente')
        finish(p,d,payment='completo',amount=30,error='insuficiente')
        assert count('movimientos_credito_cliente')==credits
        assert float(sql(f"select saldo_a_favor from saldos_pendientes_pedidos where pedido_id='{source}';"))==20
        ok('Stock fallido conserva crédito disponible sin aplicaciones')
        balance(P1,100); p,d,_=order([(P1,10,10)]); d[0]['cantidad_entregada']=5
        def invoice():
            try:
                sql(f"begin; update pedido_detalles set cantidad_facturada=9 where pedido_id='{p}'; select pg_sleep(0.2); commit;",role='authenticated')
            except AssertionError as e:
                assert 'operacion_ya_finalizada' in str(e)
        with concurrent.futures.ThreadPoolExecutor(2) as pool:
            f1=pool.submit(invoice); f2=pool.submit(finish,p,d)
            f1.result(); r=f2.result()
        assert r['resultado_entrega']=='parcial' and stock()==95
        ok('Facturación y V2 concurrentes: serialización antes de filas sin deadlock')
        other='10000000-0000-0000-0000-000000000003'
        sql(f"insert into auth.users values('{other}','admin2@test'); insert into usuarios(id,nombre,email,rol,activo) values('{other}','Admin2','admin2@test','administrador',true);")
        key=str(uuid.uuid4()); p,d,_=order([(P1,1,1)]); finish(p,d,key=key)
        sql(query(p,d,key=key),role='authenticated',actor=other,error='solicitud_incompatible')
        assert val(f"select consultar_finalizacion_solicitud('{key}');",role='authenticated',actor=other)=={'estado':'inexistente'}
        ok('misma key con otro actor rechazada y consulta ajena oculta')
        assert sql("select has_table_privilege('service_role','detalles_administracion','UPDATE');")=='f'
        sql('select * from finalizacion_pedido_solicitudes;',role='authenticated',error='permission denied')
        ok('vista administrativa sin bypass de escritura e idempotencia privada')
        assert len(checks)>=35
        print(json.dumps({'passed':len(checks),'migration':MIGRATION,'real_backends':2,'remote_calls':0}))


if __name__=='__main__':
    main()
