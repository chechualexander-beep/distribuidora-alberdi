-- Prepare only. Run in an independently authorized TESTING window.
-- Pin the TESTING connection and validate TLS verify-full in the client.
begin isolation level repeatable read read only;
set local statement_timeout = '15s';
with functions(signature, required_anon, required_auth) as (
  values ('public.obtener_catalogo_cliente(text)', true, true),
    ('public.crear_pedido_catalogo(text,uuid,jsonb,text)', true, true),
    ('public.configurar_catalogo_cliente_v2(uuid,text,jsonb,jsonb,boolean,boolean,uuid)', false, true),
    ('public.catalogo_productos_internos(uuid)', false, false),
    ('public.actualizar_pedido_activo(uuid,numeric,text,text,text,date,jsonb)', false, true),
    ('public.stock_exigir_admin()', null, null),
    ('public.stock_exigir_operativo()', null, null),
    ('public.programar_entrega_catalogo(uuid,date)', false, true)
),
checked_functions as (
  select f.*, p.oid, p.proargnames, p.prosecdef, p.proconfig,
    md5(pg_get_functiondef(p.oid) || coalesce(p.proacl::text, '') || p.proowner::text) as fingerprint,
    has_function_privilege('anon',p.oid,'execute') as anon_exec,
    has_function_privilege('authenticated',p.oid,'execute') as auth_exec,
    has_function_privilege('service_role',p.oid,'execute') as service_exec
  from functions f left join pg_proc p on p.oid=to_regprocedure(f.signature)
),
tables(name) as (
  values ('public.catalogos_clientes'),('public.catalogo_solicitudes'),
    ('public.productos'),('public.pedidos'),('public.pedido_detalles'),('public.clientes')
),
checked_tables as (
  select t.name, c.oid, c.relrowsecurity,
    has_table_privilege('anon',c.oid,'select') as anon_read,
    has_table_privilege('anon',c.oid,'insert,update,delete') as anon_write,
    has_any_column_privilege('anon',c.oid,'select,insert,update') as anon_column_access
  from tables t left join pg_class c on c.oid=to_regclass(t.name)
)
select jsonb_build_object(
  'db',current_database(),
  'tls_backend',(select ssl from pg_stat_ssl where pid=pg_backend_pid()),
  'read_only',current_setting('transaction_read_only')='on',
  'catalog_migrations',(select coalesce(jsonb_agg(version order by version),'[]'::jsonb)
    from supabase_migrations.schema_migrations where version between '20261001120000' and '20261001142000'),
  'programacion_registrada',(select count(*) from supabase_migrations.schema_migrations where version='20261106010000'),
  'history_columns',(select jsonb_object_agg(column_name,data_type)
    from information_schema.columns where table_schema='supabase_migrations' and table_name='schema_migrations'),
  'history_pk',(select pg_get_constraintdef(oid) from pg_constraint
    where conrelid='supabase_migrations.schema_migrations'::regclass and contype='p'),
  'functions',(select jsonb_agg(to_jsonb(f) order by signature) from checked_functions f),
  'tables',(select jsonb_agg(to_jsonb(t) order by name) from checked_tables t),
  'columnas',(select jsonb_object_agg(table_name || '.' || column_name,
    jsonb_build_object('tipo',data_type,'nullable',is_nullable,'default',column_default))
    from information_schema.columns where table_schema='public' and
      ((table_name='pedidos' and column_name in ('fecha_entrega','origen','resultado_entrega','tipo_operacion','estado'))
        or (table_name='productos' and column_name in ('foto_path','categoria','activo','visible_preventistas'))
        or (table_name='catalogos_clientes' and column_name in ('vence_at','token_hash','preventista_comision_id')))),
  'bucket',(select jsonb_build_object('public',public,'file_size_limit',file_size_limit)
    from storage.buckets where id='productos-fotos'),
  'stock',(select jsonb_build_object('regimen',r.id,'protocolo',r.protocolo,
    'on',c.automatizacion_activa,'coherente',c.automatizacion_activa=r.automatizacion_activa
      and c.fecha_corte is not distinct from r.fecha_corte and r.cerrado_at is null,
    'integracion',c.integracion_version,'corte',c.fecha_corte,
    'mantenimiento',t.mantenimiento,'paso',t.paso_instalacion)
    from public.stock_transicion t join public.stock_regimenes r on r.id=t.regimen_id
    cross join public.stock_configuracion c where t.singleton),
  'preparaciones_pendientes',(select count(*) from public.stock_preparaciones p
    where p.revision or not exists(select from public.finalizacion_pedido_solicitudes f where f.solicitud_id=p.solicitud_id))
);
rollback;
