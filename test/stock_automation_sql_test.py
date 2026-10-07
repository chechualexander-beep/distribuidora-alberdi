"""Fase 2A-1: PostgreSQL temporal real, dos conexiones y fixtures ficticios.

No red, no Supabase CLI. STOCK_TEST_PG_BIN debe apuntar a PostgreSQL bin.
No ejecuta activación exitosa: el régimen ON del motor es un fixture de propietario.
"""
import contextlib
import hashlib
import json
import os
import pathlib
import re
import socket
import subprocess
import sys
import tempfile
import time
import uuid

REPO = pathlib.Path(__file__).resolve().parents[1]
MIGRATION = '20261007020000_stock_infraestructura_automatizacion.sql'
ADMIN = '10000000-0000-0000-0000-000000000001'
SELLER = '10000000-0000-0000-0000-000000000002'
P1 = '20000000-0000-0000-0000-000000000001'
P2 = '20000000-0000-0000-0000-000000000002'
P3 = '20000000-0000-0000-0000-000000000003'


def lit(value):
    return "'" + str(value).replace("'", "''") + "'"


@contextlib.contextmanager
def postgres():
    bindir = pathlib.Path(os.environ['STOCK_TEST_PG_BIN'])
    suffix = '.exe' if os.name == 'nt' else ''
    programs = {n: str(bindir / (n + suffix)) for n in ['initdb', 'pg_ctl', 'psql']}
    flags = {'creationflags': subprocess.CREATE_NO_WINDOW} if os.name == 'nt' else {}
    env = dict(os.environ, PGCLIENTENCODING='UTF8')
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        port = s.getsockname()[1]
    with tempfile.TemporaryDirectory(prefix='alberdi-stock-2a1-local-') as directory:
        data = pathlib.Path(directory) / 'data'
        subprocess.run([programs['initdb'], '-D', str(data), '-U', 'postgres', '-A', 'trust', '-E', 'UTF8', '--no-locale'], capture_output=True, check=True, env=env, **flags)
        try:
            with (pathlib.Path(directory) / 'control.log').open('w') as output:
                subprocess.run([programs['pg_ctl'], '-D', str(data), '-l', str(pathlib.Path(directory) / 'postgres.log'), '-o', f'-h 127.0.0.1 -p {port}', '-w', 'start'], stdout=output, stderr=subprocess.STDOUT, check=True, env=env, **flags)
            command = [programs['psql'], '-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1', '-h', '127.0.0.1', '-p', str(port), '-U', 'postgres', '-d', 'postgres']
            yield command, env, flags
        finally:
            subprocess.run([programs['pg_ctl'], '-D', str(data), '-m', 'immediate', '-w', 'stop'], capture_output=True, env=env, **flags)


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    with postgres() as (command, env, flags):
        results = []

        def sql(statement, role='postgres', actor=ADMIN, error=None):
            prefix = f'set request.jwt.claim.sub={lit(actor)}; set role {role}; '
            p = subprocess.run(command, input=prefix + statement, text=True, encoding='utf-8', capture_output=True, env=env, **flags)
            if error:
                assert p.returncode and re.search(error, p.stderr, re.I), p.stderr
                return p.stderr
            assert p.returncode == 0, p.stderr
            return p.stdout.strip()

        def value(statement, **kwargs):
            query = ('with t as (' + statement + ') select to_json(t) from t;' if statement.lstrip().lower().startswith('insert ')
                     else 'select to_json(t) from (' + statement + ') t;')
            return json.loads(sql(query, **kwargs))

        def ok(name):
            results.append(name)
            print('OK: ' + name, flush=True)

        sql('''create role anon; create role authenticated; create role service_role;
            create schema auth; create schema extensions;
            create table auth.users(id uuid primary key,email text);
            create function auth.uid() returns uuid language sql stable as $$
              select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
            grant usage on schema auth to anon,authenticated;
            alter default privileges in schema public grant all on tables to anon,authenticated,service_role;
            alter default privileges in schema public grant all on functions to anon,authenticated,service_role;''')
        sql((REPO / 'test/fixtures/catalogo_storage_schema.sql').read_text(encoding='utf-8').replace('grant select on public.productos to authenticated;', ''))
        for file in sorted((REPO / 'supabase/migrations').glob('*.sql')):
            if file.name >= MIGRATION:
                continue
            content = file.read_text(encoding='utf-8-sig')
            content = re.sub(r'create extension if not exists pg_net;', '-- isolated: no HTTP', content, flags=re.I)
            for name in ['enviar_notificacion_nuevo_pedido', 'enviar_notificacion_pedido_editado']:
                pattern = r'(CREATE\s+OR\s+REPLACE\s+FUNCTION\s+(?:"?public"?\.)?"?' + name + r'"?\s*\(.*?\bAS\s+)(\$\w*\$).*?\2\s*;'
                content = re.sub(pattern, lambda m: m[1] + m[2] + ' BEGIN RETURN; END; ' + m[2] + ';', content, flags=re.I | re.S)
            assert not re.search(r'net\.http_post|vault\.', content, re.I)
            sql(content)
        protected = ['finalizar_gestion_pedido', 'finalizar_gestion_pedido_sin_nc', 'corregir_operacion_finalizada', 'corregir_operacion_sin_nc', 'recibir_nota_credito', 'cargar_stock_inicial', 'ajustar_stock', 'consultar_stock', 'resumen_stock']
        fingerprint = "select md5(string_agg(pg_get_functiondef(oid)||coalesce(proacl::text,''),'|' order by proname)) h from pg_proc where pronamespace='public'::regnamespace and proname in (" + ','.join(map(lit, protected)) + ')'
        before = value(fingerprint)
        sql((REPO / 'supabase/migrations' / MIGRATION).read_text(encoding='utf-8'))
        assert before == value(fingerprint)
        ok('25 migraciones reproducidas; nueve funciones Stock/comerciales y ACL idénticas')
        depot = value("select id from ubicaciones_stock where codigo='deposito_alberdi'")['id']
        assert value('select automatizacion_activa,fecha_corte,integracion_version from stock_configuracion')['automatizacion_activa'] is False
        sql("insert into stock_configuracion(ubicacion_id) select id from ubicaciones_stock where codigo='deposito_alberdi' on conflict do nothing;")
        assert value('select count(*) n from stock_configuracion')['n'] == 1
        ok('CASO 1: semilla idempotente OFF y corte NULL')
        sql(f"insert into auth.users values('{ADMIN}','admin@test'),('{SELLER}','seller@test'); insert into usuarios(id,nombre,email,rol,activo) values('{ADMIN}','Admin','admin@test','administrador',true),('{SELLER}','Seller','seller@test','preventista',true);")
        sql(f"update stock_configuracion set automatizacion_activa=true where ubicacion_id='{depot}';", role='authenticated', error='permission denied')
        sql('delete from stock_configuracion;', role='authenticated', error='permission denied')
        sql('insert into stock_configuracion(ubicacion_id) values(gen_random_uuid());', role='authenticated', error='permission denied')
        ok('CASO 2: INSERT/UPDATE/DELETE de configuración denegados')
        for product in [P1, P2, P3]:
            sql(f"insert into productos(id,nombre,codigo,precio_normal,costo) values('{product}','Ficticio {product[-1]}','{product}',10,1);")
        client = value("insert into clientes(nombre_comercio,direccion,preventista_id) values('Fixture','Fixture','" + SELLER + "') returning id")['id']

        def order():
            return value(f"insert into pedidos(cliente_id,preventista_id,tipo_precio) values('{client}','{SELLER}','normal') returning id")['id']

        def items(delta=-3, product=P1, kind='entrega'):
            return [{'producto_id': product, 'cantidad_delta': delta, 'tipo': kind}]

        def event(lines, key=None, origin=None, stamp='2026-01-01T00:00:00Z', event_type='finalizacion_pedido', error=None, actor=ADMIN):
            content = {'items': lines, 'motivo': ' Fixture '}
            query = f"select stock_registrar_evento('{depot}',{lit(event_type)},{lit(origin or order())},{lit(key or uuid.uuid4())},{lit(json.dumps(content))}::jsonb,{lit(stamp)}::timestamptz) id"
            if error:
                return sql(query, error=error, actor=actor)
            return value(query, actor=actor)['id']

        def apply(e, lines, error=None):
            return sql(f"select stock_aplicar_deltas('{depot}','{e}',{lit(json.dumps(lines))}::jsonb);", error=error)

        origin, key = order(), str(uuid.uuid4())
        e = event(items(), key, origin)
        assert event(items(-3.0), key, origin, stamp='2025-12-31T21:00:00-03:00') == e
        ok('CASOS 3/4: UUID estable y normalización decimal/zona horaria')
        event(items(-2), key, origin, error='duplicado incompatible')
        event(items(), key, origin, actor=SELLER, error='administraci')
        event(items(), origin=origin, error='otra solicitud')
        apply(e, items(-2), error='duplicado incompatible')
        sql(f"update stock_eventos set actor_id='{SELLER}';", role='authenticated', error='permission denied')
        sql('delete from stock_eventos;', role='authenticated', error='permission denied')
        sql('insert into stock_eventos(id) values(gen_random_uuid());', role='authenticated', error='permission denied')
        assert apply(e, items()) == '0'
        assert value('select count(*) n from stock_movimientos')['n'] == 0
        ok('CASO 5: contenido/origen incompatible e historia protegida; OFF no mueve')
        empty = event([])
        assert apply(empty, []) == '0'
        sql(f"select activar_automatizacion_stock('{depot}',now());", role='authenticated', error='sin inicializar')
        ok('CASO 17: activación con faltantes rechazada')
        for product in [P1, P2]:
            sql(f"select cargar_stock_inicial('{depot}',{lit(json.dumps([{'producto_id': product, 'cantidad': 10}]))}::jsonb);", role='authenticated')
        # Solo el propietario del PostgreSQL ficticio habilita un régimen ON.
        # No llamada exitosa a activar_automatizacion_stock, ni conexión remota.
        sql(f"update stock_configuracion set integracion_version=1,automatizacion_activa=true,fecha_corte='2025-01-01Z',activada_at=now(),activada_por='{ADMIN}';")
        assert apply(e, items()) == '0'  # evento OFF inmutable tras fixture ON
        e1 = event(items())
        assert apply(e1, items()) == '1'
        assert value(f"select cantidad from stock_actual where producto_id='{P1}'")['cantidad'] == 7
        ok('CASO 6: delta -3: 10 → 7 y movimiento')
        assert apply(e1, items()) == '1'
        assert value(f"select count(*) n from stock_movimientos where evento_id='{e1}'")['n'] == 1
        sql(f"insert into stock_movimientos select gen_random_uuid(),ubicacion_id,producto_id,tipo,cantidad_anterior,cantidad_delta,cantidad_nueva,motivo,observacion,usuario_id,referencia_tipo,referencia_id,created_at,evento_id from stock_movimientos where evento_id='{e1}';", error='duplicate key')
        ok('CASO 11: retry y UNIQUE evento/producto no duplican')
        e2 = event(items(-8))
        apply(e2, items(-8), error='Stock insuficiente')
        assert value(f"select cantidad from stock_actual where producto_id='{P1}'")['cantidad'] == 7
        ok('CASO 7: saldo insuficiente revierte')
        missing = event(items(-1, P3))
        apply(missing, items(-1, P3), error='no inicializado')
        absent = 'ffffffff-ffff-ffff-ffff-ffffffffffff'
        absent_event = event(items(-1, absent))
        apply(absent_event, items(-1, absent), error='Producto inexistente')
        ok('CASO 8: sin inicializar y producto inexistente distinguibles')
        multi = items(-1) + items(-11, P2)
        atomic = event(multi)
        apply(atomic, multi, error='Stock insuficiente')
        assert value(f"select cantidad from stock_actual where producto_id='{P1}'")['cantidad'] == 7
        assert value(f"select count(*) n from stock_movimientos where evento_id='{atomic}'")['n'] == 0
        atomic_key = str(uuid.uuid4())
        atomic_origin = order()
        content = lit(json.dumps({'items': multi, 'motivo': 'Fixture'}))
        sql(f"begin; select stock_aplicar_deltas('{depot}',stock_registrar_evento('{depot}','finalizacion_pedido','{atomic_origin}','{atomic_key}',{content}::jsonb,'2026-01-01Z'),{lit(json.dumps(multi))}::jsonb); commit;", error='Stock insuficiente')
        assert value(f"select count(*) n from stock_eventos where solicitud_id='{atomic_key}'")['n'] == 0
        ok('CASO 10: último producto falla; evento + todos los saldos/movimientos revierten')
        fractional = items(-0.123, P2)
        fraction_event = event(fractional)
        apply(fraction_event, fractional)
        assert value(f"select cantidad from stock_actual where producto_id='{P2}'")['cantidad'] == 9.877
        ok('CASO 13: precisión 3 decimales sin redondeo')
        for invalid in [items(-0.0001), items(float('nan')), items(-1) + items(-1), items(1), items(0)]:
            event(invalid, error='inválid|invalid|duplicado')
        normalization = "select stock_normalizar_solicitud(" + lit(json.dumps({'items': items(-1, P2) + items(-2), 'motivo': 'Fixture'})) + '::jsonb) n'
        reverse = "select stock_normalizar_solicitud(" + lit(json.dumps({'motivo': ' Fixture ', 'observacion': None, 'items': items(-2) + items(-1, P2)})) + '::jsonb) n'
        assert value(normalization) == value(reverse)
        ok('CASO 14: NaN/precisión/duplicados/signo/cero rechazados; orden normalizado')
        sql(f"select stock_aplicar_deltas('{depot}','{e1}','[]');", role='authenticated', actor=SELLER, error='permission denied')
        sql("select stock_normalizar_solicitud('{}');", role='authenticated', error='permission denied')
        sql(f"select stock_registrar_evento('{depot}','finalizacion_pedido','{origin}','{uuid.uuid4()}','{{}}',now());", role='authenticated', error='permission denied')
        sql(f"select diagnosticar_automatizacion_stock('{depot}');", role='authenticated', actor=SELLER, error='administraci')
        assert value('select count(*) n from stock_eventos', role='authenticated', actor=SELLER)['n'] == 0
        sql('select * from stock_eventos;', role='anon', actor='', error='permission denied')
        sql('select * from stock_configuracion;', role='anon', actor='', error='permission denied')
        sql(f"select diagnosticar_automatizacion_stock('{depot}');", role='anon', actor='', error='permission denied')
        ok('CASOS 15/16: motor privado, preventista sin lectura/diagnóstico, anon sin acceso')
        sql(f"select ajustar_stock('{depot}','{P1}',5,'Conteo ficticio');", role='authenticated')
        sql(f"select consultar_stock('{depot}'); select resumen_stock('{depot}');", role='authenticated')
        ok('CASO 12: RPC manuales Fase 1 funcionan con infraestructura')
        ea, eb = event(items(-4)), event(items(-3))
        prefix = f"set request.jwt.claim.sub='{ADMIN}'; begin; "
        a = b = None
        try:
            a = subprocess.Popen(command + ['-c', prefix + f"select stock_aplicar_deltas('{depot}','{ea}',{lit(json.dumps(items(-4)))}::jsonb); select pg_sleep(3); commit;"], env=dict(env, PGAPPNAME='stock2a1_a'), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding='utf-8', **flags)
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                if value("select count(*) n from pg_stat_activity where application_name='stock2a1_a' and wait_event='PgSleep'")['n']:
                    break
                time.sleep(0.05)
            else:
                raise AssertionError('Primer backend no alcanzó el lock')
            b = subprocess.Popen(command + ['-c', prefix + f"select stock_aplicar_deltas('{depot}','{eb}',{lit(json.dumps(items(-3)))}::jsonb); commit;"], env=dict(env, PGAPPNAME='stock2a1_b'), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding='utf-8', **flags)
            deadline = time.monotonic() + 2
            while time.monotonic() < deadline:
                if value("select count(*) n from pg_stat_activity where application_name='stock2a1_b' and wait_event_type='Lock'")['n']:
                    break
                time.sleep(0.05)
            else:
                raise AssertionError('Segundo backend no esperó lock real')
            _, err_a = a.communicate(timeout=10)
            _, err_b = b.communicate(timeout=10)
            assert a.returncode == 0, err_a
            assert b.returncode != 0 and 'Stock insuficiente' in err_b, err_b
        finally:
            for p in [a, b]:
                if p and p.poll() is None:
                    p.terminate()
                    p.communicate(timeout=5)
        assert value(f"select cantidad from stock_actual where producto_id='{P1}'")['cantidad'] == 1
        ok('CASO 9: dos backends reales; 5 - 4 = 1; entrega 3 espera y falla')
        sql('update stock_configuracion set automatizacion_activa=false,fecha_corte=null,activada_at=null,activada_por=null,integracion_version=0;')
        sql(f"select cargar_stock_inicial('{depot}',{lit(json.dumps([{'producto_id': P3, 'cantidad': 0}]))}::jsonb);", role='authenticated')
        sql(f"select activar_automatizacion_stock('{depot}',now());", role='authenticated', error='Activación bloqueada')
        diagnostic = value(f"select diagnosticar_automatizacion_stock('{depot}') d", role='authenticated')['d']
        assert diagnostic['configuracion']['automatizacion_activa'] is False
        assert diagnostic['cantidad_sin_inicializar'] == 0
        ok('CASO 18: activación completa bloqueada por integración pendiente; sigue OFF')
        # Regresión comercial en el esquema completo DESPUÉS de migrar.
        pid = order()
        did = value(f"insert into pedido_detalles(pedido_id,producto_id,cantidad,precio_unitario,subtotal,tipo_precio,costo_unitario) values('{pid}','{P1}',5,10,50,'normal',1) returning id")['id']
        unchanged = value("select md5(coalesce(string_agg(row_to_json(m)::text,'|' order by m.id),'')) h from stock_movimientos m")
        event_count = value('select count(*) n from stock_eventos')
        delivery = [{'id': did, 'cantidad_entregada': 5, 'cantidad_no_entregada': 0, 'precio_unitario': 10, 'porcentaje_comision': 0, 'importe_comision': 0}]
        sql(f"select finalizar_gestion_pedido('{pid}','en_reparto','entregado',null,{lit(json.dumps(delivery))}::jsonb,'sin_pago');", role='authenticated')
        sql(f"select corregir_operacion_finalizada('{pid}','Fixture',{lit(json.dumps([{'id': did, 'cantidad_entregada': 4}]))}::jsonb);", role='authenticated')
        note = value(f"select crear_nota_credito('{pid}','Fixture',{lit(json.dumps([{'detalle_id': did, 'cantidad': 1}]))}::jsonb,'fixture-nc-2a1-00001') id", role='authenticated')['id']
        nd = value(f"select id from nota_credito_detalles where nota_id='{note}'")['id']
        sql(f"select recibir_nota_credito('{nd}',true); select recibir_nota_credito('{nd}',true);", role='authenticated')
        assert unchanged == value("select md5(coalesce(string_agg(row_to_json(m)::text,'|' order by m.id),'')) h from stock_movimientos m")
        assert event_count == value('select count(*) n from stock_eventos')
        assert before == value(fingerprint)
        ok('REGRESIÓN: finalizar/corregir/emitir NC/recibir doble no alteran Stock ni eventos')
        print(json.dumps({'passed': len(results), 'migration': MIGRATION, 'sha256': hashlib.sha256((REPO / 'supabase/migrations' / MIGRATION).read_bytes()).hexdigest(), 'checks': results}, ensure_ascii=True))


if __name__ == '__main__':
    main()
