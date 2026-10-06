-- En INSERT ... RETURNING PostgreSQL evalúa el alcance de lectura sobre la
-- fila nueva. La consulta recursiva de puede_leer_cliente no la ve aún en
-- esa misma sentencia. La asignación directa permite devolver solo la fila
-- recién creada al preventista que queda como responsable.
begin;

drop policy alcance_clientes_lectura on public.clientes;
create policy alcance_clientes_lectura on public.clientes as restrictive for select to authenticated
 using(public.es_personal_activo() and (
   public.es_administrador()
   or preventista_id=auth.uid()
   or exists(select 1 from public.pedidos p where p.cliente_id=clientes.id and p.preventista_id=auth.uid())
 ));

notify pgrst,'reload schema';
commit;
