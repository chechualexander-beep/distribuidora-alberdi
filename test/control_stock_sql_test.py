"""Pruebas SQL de Fase 1A en un PostgreSQL temporal, sin acceso remoto.

Requiere initdb, pg_ctl y psql en PATH, o STOCK_TEST_PG_BIN apuntando a bin.
Reproduce las migraciones locales con Auth/Storage mínimos y notificaciones
no-op; crea y detiene su propio servidor restringido a 127.0.0.1.
"""
import json
import hashlib
import os
import pathlib
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import uuid

REPO = pathlib.Path(__file__).resolve().parents[1]
MIGRATION = "20261006024758_control_stock_fase1.sql"
ADMIN = "10000000-0000-0000-0000-000000000001"
SELLER = "10000000-0000-0000-0000-000000000002"
INACTIVE = "10000000-0000-0000-0000-000000000003"
PRODUCT = "20000000-0000-0000-0000-000000000001"
EMPTY_PRODUCT = "20000000-0000-0000-0000-000000000002"
FRACTION_PRODUCT = "20000000-0000-0000-0000-000000000003"
NOT_INITIALIZED = "20000000-0000-0000-0000-000000000004"
RACE_PRODUCT = "20000000-0000-0000-0000-000000000005"
MISSING = "ffffffff-ffff-ffff-ffff-ffffffffffff"


def literal(value):
    return "'" + str(value).replace("'", "''") + "'"


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    migration_sha256 = hashlib.sha256((REPO / "supabase/migrations" / MIGRATION).read_bytes()).hexdigest()
    bindir = os.environ.get("STOCK_TEST_PG_BIN")
    suffix = ".exe" if os.name == "nt" else ""
    programs = {}
    for name in ("initdb", "pg_ctl", "psql"):
        programs[name] = str(pathlib.Path(bindir) / (name + suffix)) if bindir else shutil.which(name)
        if not programs[name] or not pathlib.Path(programs[name]).is_file():
            raise RuntimeError("Falta " + name + "; indicar STOCK_TEST_PG_BIN.")
    with socket.socket() as available:
        available.bind(("127.0.0.1", 0))
        port = available.getsockname()[1]
    env = dict(os.environ, PGCLIENTENCODING="UTF8")
    flags = {"creationflags": subprocess.CREATE_NO_WINDOW} if os.name == "nt" else {}
    results = []
    with tempfile.TemporaryDirectory(prefix="alberdi-stock-local-") as workspace:
        data = pathlib.Path(workspace) / "data"
        subprocess.run([programs["initdb"], "-D", str(data), "-U", "postgres", "-A", "trust", "-E", "UTF8", "--no-locale"], env=env, capture_output=True, check=True, **flags)
        logfile = pathlib.Path(workspace) / "postgres.log"
        control_log = pathlib.Path(workspace) / "control.log"
        # Windows puede heredar pipes al servidor; un archivo evita esperar EOF
        # de un proceso que debe seguir vivo durante las pruebas.
        with control_log.open("w",encoding="utf-8") as output:
            started = subprocess.run([programs["pg_ctl"], "-D", str(data), "-l", str(logfile), "-o", f"-h 127.0.0.1 -p {port}", "-w", "start"], env=env, stdout=output, stderr=subprocess.STDOUT, **flags)
        if started.returncode:
            log = logfile.read_text(encoding="utf-8",errors="replace") if logfile.exists() else ""
            subprocess.run([programs["pg_ctl"], "-D", str(data), "-m", "immediate", "-w", "stop"], env=env, capture_output=True, **flags)
            raise RuntimeError("PostgreSQL local no pudo iniciar: " + control_log.read_text(encoding="utf-8",errors="replace") + log)
        command = [programs["psql"], "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1", "-h", "127.0.0.1", "-p", str(port), "-U", "postgres", "-d", "postgres"]

        def sql(statement, subject=None, role="authenticated", expected_error=None):
            if subject is not None:
                statement = "set request.jwt.claim.sub=" + literal(subject) + "; set role " + role + ";\n" + statement
            process = subprocess.run(command, input=statement, env=env, text=True, encoding="utf-8", capture_output=True, **flags)
            if expected_error is not None:
                assert process.returncode != 0, "Se esperaba rechazo: " + statement
                assert re.search(expected_error, process.stderr, re.I), process.stderr
                return
            assert process.returncode == 0, process.stderr
            return process.stdout.strip()

        def rows(statement, subject=None, role="authenticated"):
            output = sql("select coalesce(json_agg(t),'[]'::json) from (" + statement + ") t;", subject, role)
            return json.loads(output)

        def initial(items, subject=ADMIN, location=None, error=None):
            return sql("select public.cargar_stock_inicial(" + literal(location or depot) + "," + literal(json.dumps(items)) + "::jsonb);", subject, expected_error=error)

        def adjust(quantity, subject=ADMIN, product=PRODUCT, reason="Diferencia de inventario", location=None, error=None):
            statement = "select public.ajustar_stock(" + literal(location or depot) + "," + literal(product) + "," + str(quantity) + "," + literal(reason) + ");"
            return sql(statement, subject, expected_error=error)

        def pair(product=PRODUCT):
            return rows("select cantidad::text cantidad from public.stock_actual where ubicacion_id=" + literal(depot) + " and producto_id=" + literal(product))[0]["cantidad"]

        def audit(product=PRODUCT):
            return rows("select tipo,cantidad_anterior::text anterior,cantidad_delta::text delta,cantidad_nueva::text nueva,usuario_id from public.stock_movimientos where ubicacion_id=" + literal(depot) + " and producto_id=" + literal(product) + " order by created_at,id")

        def record(name):
            results.append(name)
            print("OK: " + name, flush=True)

        def concurrent(first_sql, second_sql, second_error=None):
            # A mantiene su bloqueo después del RPC; B debe esperar en otro backend.
            prefix = "begin; set local request.jwt.claim.sub=" + literal(ADMIN) + "; set local role authenticated; "
            aenv = dict(env, PGAPPNAME="stock_test_concurrent_a")
            benv = dict(env, PGAPPNAME="stock_test_concurrent_b")
            a = subprocess.Popen(command + ["-c", prefix + first_sql + " select pg_sleep(5); commit;"], env=aenv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding="utf-8", **flags)
            b = None
            try:
                deadline = time.monotonic() + 4
                while time.monotonic() < deadline:
                    if rows("select 1 from pg_stat_activity where application_name='stock_test_concurrent_a' and wait_event='PgSleep'"):
                        break
                    time.sleep(0.05)
                else:
                    raise AssertionError("El primer backend no llegó a mantener su bloqueo.")
                b = subprocess.Popen(command + ["-c", prefix + second_sql + " commit;"], env=benv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding="utf-8", **flags)
                deadline = time.monotonic() + 3
                while time.monotonic() < deadline:
                    if rows("select 1 from pg_stat_activity where application_name='stock_test_concurrent_b' and wait_event_type='Lock'"):
                        break
                    time.sleep(0.05)
                else:
                    raise AssertionError("El segundo backend no esperó un bloqueo real.")
                _, error_a = a.communicate(timeout=12)
                _, error_b = b.communicate(timeout=12)
                assert a.returncode == 0, error_a
                if second_error:
                    assert b.returncode != 0 and re.search(second_error, error_b, re.I), error_b
                else:
                    assert b.returncode == 0, error_b
            finally:
                for process in (a, b):
                    if process is not None and process.poll() is None:
                        process.terminate()
                        process.communicate(timeout=5)

        try:
            sql("""create role anon; create role authenticated; create role service_role;
                create schema auth; create schema extensions;
                create table auth.users(id uuid primary key,email text);
                create function auth.uid() returns uuid language sql stable as $$
                  select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
                $$;
                grant usage on schema auth to anon,authenticated;
                alter default privileges in schema public grant all on tables to anon,authenticated,service_role;
                alter default privileges in schema public grant all on functions to anon,authenticated,service_role;""")
            sql((REPO / "test/fixtures/catalogo_storage_schema.sql").read_text(encoding="utf-8").replace("grant select on public.productos to authenticated;", ""))
            for file in sorted((REPO / "supabase/migrations").glob("*.sql")):
                if file.name > MIGRATION:
                    continue
                content = file.read_text(encoding="utf-8-sig")
                content = re.sub(r"create extension if not exists pg_net;", "-- HTTP omitted in the isolated test", content, flags=re.I)
                for name in ("enviar_notificacion_nuevo_pedido", "enviar_notificacion_pedido_editado"):
                    pattern = r'(CREATE\s+OR\s+REPLACE\s+FUNCTION\s+(?:"?public"?\.)?"?' + name + r'"?\s*\(.*?\bAS\s+)(\$\w*\$).*?\2\s*;'
                    content = re.sub(pattern, lambda match: match[1] + match[2] + " BEGIN RETURN; END; " + match[2] + ";", content, flags=re.I | re.S)
                assert not re.search(r"net\.http_post|vault\.", content, re.I), "No-op isolation failed"
                sql(content)
            record("24 migraciones reproducidas en PostgreSQL aislado, notificaciones no-op")
            depot = rows("select id from public.ubicaciones_stock where codigo='deposito_alberdi'")[0]["id"]
            # Reejecutar únicamente la semilla prueba su idempotencia.
            sql("insert into public.ubicaciones_stock(codigo,nombre) values('deposito_alberdi','Depósito Distribuidora Alberdi') on conflict(codigo) do nothing;")
            assert rows("select count(*) n from public.ubicaciones_stock")[0]["n"] == 1
            sql(f"insert into auth.users(id,email) values('{ADMIN}','admin@stock.test'),('{SELLER}','vendedor@stock.test'),('{INACTIVE}','inactivo@stock.test');")
            sql(f"insert into public.usuarios(id,nombre,email,rol,activo) values('{ADMIN}','Admin','admin@stock.test','administrador',true),('{SELLER}','Preventista','vendedor@stock.test','preventista',true),('{INACTIVE}','Admin inactivo','inactivo@stock.test','administrador',false);")
            for product, name, cost in ((PRODUCT, "Tutuca", 50), (EMPTY_PRODUCT, "Inicial cero", 100), (FRACTION_PRODUCT, "Fraccionado", 2), (NOT_INITIALIZED, "Sin inicializar", 5), (RACE_PRODUCT, "Inicial concurrente", 10)):
                sql(f"insert into public.productos(id,nombre,codigo,costo) values('{product}',{literal(name)},{literal(name)},{cost});")

            initial([{"producto_id": PRODUCT, "cantidad": 20, "usuario_id": SELLER}])
            assert pair() == "20.000" and audit()[0] == {"tipo": "stock_inicial", "anterior": "0.000", "delta": "20.000", "nueva": "20.000", "usuario_id": ADMIN}
            record("CASO 1: inicial 20, auditoría 0/+20/20 y usuario autenticado")
            initial([{"producto_id": PRODUCT, "cantidad": 30}], error="ya tiene stock inicial")
            assert pair() == "20.000" and len(audit()) == 1
            record("CASO 2: segunda inicialización rechazada sin cambios")
            adjust(25)
            assert pair() == "25.000" and audit()[-1]["tipo"] == "ajuste_entrada" and audit()[-1]["anterior"] == "20.000" and audit()[-1]["delta"] == "5.000"
            record("CASO 3: ajuste 20/+5/25")
            adjust(22)
            assert pair() == "22.000" and audit()[-1]["tipo"] == "ajuste_salida" and audit()[-1]["anterior"] == "25.000" and audit()[-1]["delta"] == "-3.000"
            record("CASO 4: ajuste 25/-3/22")
            adjust(-1, error="cantidad")
            assert pair() == "22.000" and len(audit()) == 3
            record("CASO 5: cantidad negativa rechazada")
            initial([{"producto_id": NOT_INITIALIZED, "cantidad": 1}], subject=SELLER, error="administrador")
            record("CASO 6: preventista no puede inicializar")
            adjust(50, subject=SELLER, error="administrador")
            record("CASO 7: preventista no puede ajustar")
            sql("update public.stock_actual set cantidad=99;", ADMIN, expected_error="permission denied")
            record("CASO 8: UPDATE directo denegado incluso al administrador")
            for operation in ("update public.stock_movimientos set motivo='Editado';", "delete from public.stock_movimientos;"):
                sql(operation, ADMIN, expected_error="permission denied")
            record("CASO 9: UPDATE/DELETE de auditoría denegados")
            concurrent(f"select public.ajustar_stock('{depot}','{PRODUCT}',30,'Conteo A');", f"select public.ajustar_stock('{depot}','{PRODUCT}',18,'Conteo B');")
            assert pair() == "18.000"
            movements = audit()
            assert movements[-2]["anterior"] == "22.000" and movements[-2]["delta"] == "8.000"
            assert movements[-1]["anterior"] == "30.000" and movements[-1]["delta"] == "-12.000"
            assert all(a["nueva"] == b["anterior"] for a, b in zip(movements, movements[1:]))
            record("CASO 10: dos backends concurrentes, espera real de bloqueo y cadena 22/30/18")

            # Integridad/seguridad adicionales que no se resuelven solo en Flutter.
            for quantity in ("'NaN'::numeric", "'Infinity'::numeric", "null", "1.0001", "100000000000"):
                adjust(quantity, error="cantidad")
            adjust(18, error="coincide")
            adjust(17, reason="   ", error="motivo")
            adjust(1, product=NOT_INITIALIZED, error="todavía no tiene stock inicial")
            for subject in (INACTIVE, "", str(uuid.uuid4())):
                initial([{"producto_id": NOT_INITIALIZED, "cantidad": 1}], subject=subject, error="administrador")
                adjust(17, subject=subject, error="administrador")
            for role in ("anon", "service_role"):
                sql("select * from public.stock_actual;", "", role, expected_error="permission denied")
                sql(f"select public.resumen_stock('{depot}');", "", role, expected_error="permission denied")
            for table in ("ubicaciones_stock", "stock_actual", "stock_movimientos"):
                assert rows("select * from public." + table, SELLER) == []
                for operation in ("insert into public." + table + " default values;", "delete from public." + table + ";", "truncate public." + table + ";"):
                    sql(operation, ADMIN, expected_error="permission denied")
            for function in ("consultar_stock", "resumen_stock"):
                sql(f"select * from public.{function}('{depot}');", SELLER, expected_error="administrador")
            record("Anon, usuario desconocido, inactivo, preventista y escrituras directas bloqueados; entradas numéricas validadas")

            before = rows("select (select count(*) from public.stock_actual) saldos,(select count(*) from public.stock_movimientos) movimientos")[0]
            initial([{"producto_id": NOT_INITIALIZED, "cantidad": 10}, {"producto_id": MISSING, "cantidad": 1}], error="no existe")
            assert rows("select (select count(*) from public.stock_actual) saldos,(select count(*) from public.stock_movimientos) movimientos")[0] == before
            initial([{"producto_id": NOT_INITIALIZED, "cantidad": 1}, {"producto_id": NOT_INITIALIZED.upper(), "cantidad": 2}], error="duplicado")
            for value in ("null", "{}", "[]", '[{"producto_id":"mal","cantidad":1}]', '[{"producto_id":"' + NOT_INITIALIZED + '","cantidad":"NaN"}]'):
                sql(f"select public.cargar_stock_inicial('{depot}',{literal(value)}::jsonb);", ADMIN, expected_error="arreglo|entre 1|UUID|numérica")
            record("Carga masiva atómica, rollback de lote parcialmente recorrido, duplicados y JSON inválido")

            initial([{"producto_id": EMPTY_PRODUCT, "cantidad": 0}, {"producto_id": FRACTION_PRODUCT, "cantidad": 1.234}])
            initial([{"producto_id": EMPTY_PRODUCT, "cantidad": 0}], error="ya tiene stock inicial")
            summary = rows(f"select * from public.resumen_stock('{depot}')", ADMIN)[0]
            assert summary == {"productos_distintos": 3, "unidades_totales": 19.234, "valor_estimado_total": 902.468}, summary
            details = rows(f"select * from public.consultar_stock('{depot}')", ADMIN)
            assert len(details) == 5 and next(x for x in details if x["producto_id"] == EMPTY_PRODUCT)["inicializado"] is True
            assert next(x for x in details if x["producto_id"] == NOT_INITIALIZED)["inicializado"] is False
            sql(f"update public.productos set costo=60 where id='{PRODUCT}';")
            assert rows(f"select * from public.resumen_stock('{depot}')", ADMIN)[0]["valor_estimado_total"] == 1082.468
            assert rows(f"select stock from public.productos where id='{PRODUCT}'")[0]["stock"] == 0
            record("Inicial cero y fracciones, productos distintos, consulta completa, costo actual y columna legacy intacta")

            other = str(uuid.uuid4())
            sql(f"insert into public.ubicaciones_stock(id,codigo,nombre) values('{other}','local_prueba','Local prueba');")
            initial([{"producto_id": PRODUCT, "cantidad": 3}], location=other)
            assert pair() == "18.000" and rows(f"select * from public.resumen_stock('{other}')", ADMIN)[0]["unidades_totales"] == 3
            sql(f"update public.ubicaciones_stock set activo=false where id='{other}';")
            adjust(2, location=other, error="inactiva")
            initial([{"producto_id": NOT_INITIALIZED, "cantidad": 1}], location=other, error="inactiva")
            assert rows(f"select * from public.resumen_stock('{other}')", ADMIN)[0]["unidades_totales"] == 3
            record("Ubicaciones independientes; ubicación inactiva impide escrituras y conserva consulta histórica")

            concurrent(f"select public.cargar_stock_inicial('{depot}','[{{\"producto_id\":\"{RACE_PRODUCT}\",\"cantidad\":7}}]');", f"select public.cargar_stock_inicial('{depot}','[{{\"producto_id\":\"{RACE_PRODUCT}\",\"cantidad\":8}}]');", "ya tiene stock inicial")
            assert pair(RACE_PRODUCT) == "7.000" and len(audit(RACE_PRODUCT)) == 1
            record("Dos inicializaciones concurrentes: una sola auditoría y saldo 7")

            for bad in ("-1", "'NaN'::numeric"):
                sql("update public.stock_actual set cantidad=" + bad + ";", expected_error="check constraint")
            sql(f"insert into public.stock_movimientos(ubicacion_id,producto_id,tipo,cantidad_anterior,cantidad_delta,cantidad_nueva,motivo,usuario_id) values('{depot}','{PRODUCT}','ajuste_entrada',18,1,25,'Prueba','{ADMIN}');", expected_error="check constraint")
            sql(f"insert into public.stock_movimientos(ubicacion_id,producto_id,tipo,cantidad_anterior,cantidad_delta,cantidad_nueva,motivo,usuario_id) values('{depot}','{PRODUCT}','stock_inicial',0,1,1,'Prueba','{ADMIN}');", expected_error="unique constraint")
            sql(f"delete from public.productos where id='{PRODUCT}';", expected_error="foreign key")
            sql(f"delete from public.usuarios where id='{ADMIN}';", expected_error="foreign key")
            record("CHECK, UNIQUE parcial y FK RESTRICT protegen saldos y auditoría aun frente a SQL privilegiado")

            assert hashlib.sha256((REPO / "supabase/migrations" / MIGRATION).read_bytes()).hexdigest() == migration_sha256
            result = {"passed": True, "tests": results, "postgres_version": rows("select version() version")[0]["version"], "isolation": "native local PostgreSQL, two independent backends; no remote connections", "migration": MIGRATION, "migration_sha256": migration_sha256, "temporary_data_removed_on_exit": True}
            if os.environ.get("STOCK_TEST_RESULT"):
                pathlib.Path(os.environ["STOCK_TEST_RESULT"]).write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding="utf-8")
            print("Todas las pruebas de stock pasaron; sin datos remotos creados.", flush=True)
        finally:
            subprocess.run([programs["pg_ctl"], "-D", str(data), "-m", "immediate", "-w", "stop"], env=env, capture_output=True, check=True, **flags)


if __name__ == "__main__":
    main()
