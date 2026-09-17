


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE OR REPLACE FUNCTION "public"."es_administrador"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (
    select 1
    from public.usuarios
    where id = auth.uid()
      and rol = 'administrador'
      and activo = true
  );
$$;


ALTER FUNCTION "public"."es_administrador"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."registrar_liquidacion"("p_preventista_id" "uuid", "p_fecha_desde" "date", "p_fecha_hasta" "date", "p_venta_entregada" numeric, "p_comision_total" numeric, "p_detalles" "jsonb") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_liquidacion_id uuid;
  v_detalle jsonb;
  v_pedido_detalle_id uuid;
  v_importe_comision numeric;
begin
  -- Seguridad extra: solo administrador activo
  if not exists (
    select 1
    from public.usuarios
    where id = auth.uid()
      and rol = 'administrador'
      and activo = true
  ) then
    raise exception 'No autorizado';
  end if;

  -- Validaciones básicas
  if p_preventista_id is null then
    raise exception 'Preventista requerido';
  end if;

  if p_fecha_desde is null or p_fecha_hasta is null then
    raise exception 'Periodo requerido';
  end if;

  if p_fecha_hasta < p_fecha_desde then
    raise exception 'Periodo inválido';
  end if;

  if p_detalles is null
     or jsonb_typeof(p_detalles) <> 'array'
     or jsonb_array_length(p_detalles) = 0 then
    raise exception 'La liquidación no tiene detalles';
  end if;

  -- Crear la cabecera ya como pagada
  insert into public.liquidaciones (
    preventista_id,
    fecha_desde,
    fecha_hasta,
    venta_entregada,
    comision_total,
    estado,
    fecha_pago
  )
  values (
    p_preventista_id,
    p_fecha_desde,
    p_fecha_hasta,
    coalesce(p_venta_entregada, 0),
    coalesce(p_comision_total, 0),
    'pagada',
    now()
  )
  returning id into v_liquidacion_id;

  -- Guardar cada detalle
  for v_detalle in
    select value
    from jsonb_array_elements(p_detalles)
  loop
    v_pedido_detalle_id :=
      (v_detalle ->> 'pedido_detalle_id')::uuid;

    v_importe_comision :=
      coalesce(
        (v_detalle ->> 'importe_comision')::numeric,
        0
      );

    if v_pedido_detalle_id is null then
      raise exception 'Detalle sin pedido_detalle_id';
    end if;

    -- Verificar que pertenezca al preventista
    if not exists (
      select 1
      from public.pedido_detalles pd
      join public.pedidos p
        on p.id = pd.pedido_id
      where pd.id = v_pedido_detalle_id
        and p.preventista_id = p_preventista_id
    ) then
      raise exception
        'El detalle % no pertenece al preventista',
        v_pedido_detalle_id;
    end if;

    -- Evitar pagar dos veces
    if exists (
      select 1
      from public.liquidacion_detalles ld
      where ld.pedido_detalle_id = v_pedido_detalle_id
    ) then
      raise exception
        'El detalle % ya fue liquidado',
        v_pedido_detalle_id;
    end if;

    insert into public.liquidacion_detalles (
      liquidacion_id,
      pedido_detalle_id,
      importe_comision
    )
    values (
      v_liquidacion_id,
      v_pedido_detalle_id,
      v_importe_comision
    );
  end loop;

  return v_liquidacion_id;
end;
$$;


ALTER FUNCTION "public"."registrar_liquidacion"("p_preventista_id" "uuid", "p_fecha_desde" "date", "p_fecha_hasta" "date", "p_venta_entregada" numeric, "p_comision_total" numeric, "p_detalles" "jsonb") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."clientes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "nombre_comercio" "text" NOT NULL,
    "propietario" "text",
    "telefono" "text",
    "direccion" "text" NOT NULL,
    "localidad" "text",
    "zona" "text",
    "observaciones" "text",
    "activo" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "preventista_id" "uuid",
    "tipo_precio_habitual" "text",
    "latitud" double precision,
    "longitud" double precision,
    "ubicacion_actualizada_at" timestamp with time zone,
    "codigo_original" bigint,
    CONSTRAINT "clientes_tipo_precio_habitual_check" CHECK (("tipo_precio_habitual" = ANY (ARRAY['normal'::"text", 'promo'::"text", 'interior'::"text"])))
);


ALTER TABLE "public"."clientes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."liquidacion_detalles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "liquidacion_id" "uuid" NOT NULL,
    "pedido_detalle_id" "uuid" NOT NULL,
    "importe_comision" numeric(12,2) DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."liquidacion_detalles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."liquidaciones" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "preventista_id" "uuid" NOT NULL,
    "fecha_desde" "date" NOT NULL,
    "fecha_hasta" "date" NOT NULL,
    "venta_entregada" numeric(12,2) DEFAULT 0 NOT NULL,
    "comision_total" numeric(12,2) DEFAULT 0 NOT NULL,
    "estado" "text" DEFAULT 'pendiente'::"text" NOT NULL,
    "fecha_pago" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "liquidaciones_estado_check" CHECK (("estado" = ANY (ARRAY['pendiente'::"text", 'pagada'::"text"])))
);


ALTER TABLE "public"."liquidaciones" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."pedido_detalles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "pedido_id" "uuid" NOT NULL,
    "producto_id" "uuid" NOT NULL,
    "cantidad" numeric(12,2) NOT NULL,
    "precio_unitario" numeric(12,2) NOT NULL,
    "subtotal" numeric(12,2) NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "tipo_precio" "text",
    "cantidad_entregada" numeric(12,2) DEFAULT 0 NOT NULL,
    "cantidad_no_entregada" numeric(12,2) DEFAULT 0 NOT NULL,
    "porcentaje_comision" numeric(5,2),
    "importe_comision" numeric(12,2) DEFAULT 0 NOT NULL,
    "cantidad_facturada" numeric,
    "costo_unitario" numeric DEFAULT '0'::numeric,
    CONSTRAINT "pedido_detalles_cantidad_check" CHECK (("cantidad" > (0)::numeric)),
    CONSTRAINT "pedido_detalles_precio_unitario_check" CHECK (("precio_unitario" >= (0)::numeric)),
    CONSTRAINT "pedido_detalles_subtotal_check" CHECK (("subtotal" >= (0)::numeric)),
    CONSTRAINT "pedido_detalles_tipo_precio_check" CHECK (("tipo_precio" = ANY (ARRAY['normal'::"text", 'promo'::"text", 'interior'::"text"])))
);


ALTER TABLE "public"."pedido_detalles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."pedido_pagos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "pedido_id" "uuid",
    "importe" numeric,
    "medio_pago" "text",
    "fecha_pago" timestamp with time zone DEFAULT "now"(),
    "observacion" "text"
);


ALTER TABLE "public"."pedido_pagos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."pedidos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "cliente_id" "uuid" NOT NULL,
    "preventista_id" "uuid" NOT NULL,
    "tipo_precio" "text" NOT NULL,
    "estado" "text" DEFAULT 'pendiente'::"text" NOT NULL,
    "observaciones" "text",
    "total" numeric(12,2) DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "forma_pago" "text",
    "resultado_entrega" "text" DEFAULT 'pendiente'::"text",
    "motivo_no_entrega" "text",
    "fecha_entrega" "date",
    "facturado" boolean DEFAULT false NOT NULL,
    "fecha_facturacion" timestamp with time zone,
    "numero_comprobante" "text",
    "tipo_operacion" "text" DEFAULT 'pedido'::"text" NOT NULL,
    "observacion" "text",
    CONSTRAINT "pedidos_estado_check" CHECK (("estado" = ANY (ARRAY['pendiente'::"text", 'confirmado'::"text", 'preparado'::"text", 'en_reparto'::"text", 'entregado'::"text", 'anulado'::"text"]))),
    CONSTRAINT "pedidos_forma_pago_check" CHECK (("forma_pago" = ANY (ARRAY['contado'::"text", 'transferencia'::"text", 'cuenta_corriente'::"text"]))),
    CONSTRAINT "pedidos_resultado_entrega_check" CHECK (("resultado_entrega" = ANY (ARRAY['pendiente'::"text", 'entregado'::"text", 'no_entregado'::"text", 'parcial'::"text"]))),
    CONSTRAINT "pedidos_tipo_precio_check" CHECK (("tipo_precio" = ANY (ARRAY['normal'::"text", 'promo'::"text", 'interior'::"text"])))
);


ALTER TABLE "public"."pedidos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."productos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "codigo" "text",
    "nombre" "text" NOT NULL,
    "descripcion" "text",
    "precio_normal" numeric(12,2) DEFAULT 0 NOT NULL,
    "precio_promo" numeric(12,2) DEFAULT 0 NOT NULL,
    "precio_interior" numeric(12,2) DEFAULT 0 NOT NULL,
    "stock" numeric(12,2) DEFAULT 0,
    "activo" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "codigo_original" integer,
    "comision_normal" numeric(5,2),
    "comision_promo" numeric(5,2),
    "comision_interior" numeric(5,2),
    "costo" numeric DEFAULT 0 NOT NULL,
    "visible_preventistas" boolean DEFAULT true NOT NULL,
    "tipo_margen" "text" DEFAULT 'normal'::"text" NOT NULL
);


ALTER TABLE "public"."productos" OWNER TO "postgres";


COMMENT ON COLUMN "public"."productos"."tipo_margen" IS 'Tipo de margen aplicado al producto';



CREATE TABLE IF NOT EXISTS "public"."usuarios" (
    "id" "uuid" NOT NULL,
    "nombre" "text" NOT NULL,
    "apellido" "text",
    "email" "text" NOT NULL,
    "rol" "text" NOT NULL,
    "activo" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "usuarios_rol_check" CHECK (("rol" = ANY (ARRAY['administrador'::"text", 'preventista'::"text"])))
);


ALTER TABLE "public"."usuarios" OWNER TO "postgres";


ALTER TABLE ONLY "public"."clientes"
    ADD CONSTRAINT "clientes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."liquidacion_detalles"
    ADD CONSTRAINT "liquidacion_detalles_pedido_detalle_id_key" UNIQUE ("pedido_detalle_id");



ALTER TABLE ONLY "public"."liquidacion_detalles"
    ADD CONSTRAINT "liquidacion_detalles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."liquidaciones"
    ADD CONSTRAINT "liquidaciones_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pedido_detalles"
    ADD CONSTRAINT "pedido_detalles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pedido_pagos"
    ADD CONSTRAINT "pedido_pagos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pedidos"
    ADD CONSTRAINT "pedidos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."productos"
    ADD CONSTRAINT "productos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."usuarios"
    ADD CONSTRAINT "usuarios_email_key" UNIQUE ("email");



ALTER TABLE ONLY "public"."usuarios"
    ADD CONSTRAINT "usuarios_pkey" PRIMARY KEY ("id");



CREATE UNIQUE INDEX "productos_nombre_unico_idx" ON "public"."productos" USING "btree" ("lower"(TRIM(BOTH FROM "nombre")));



ALTER TABLE ONLY "public"."clientes"
    ADD CONSTRAINT "clientes_preventista_id_fkey" FOREIGN KEY ("preventista_id") REFERENCES "public"."usuarios"("id");



ALTER TABLE ONLY "public"."liquidacion_detalles"
    ADD CONSTRAINT "liquidacion_detalles_liquidacion_id_fkey" FOREIGN KEY ("liquidacion_id") REFERENCES "public"."liquidaciones"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."liquidacion_detalles"
    ADD CONSTRAINT "liquidacion_detalles_pedido_detalle_id_fkey" FOREIGN KEY ("pedido_detalle_id") REFERENCES "public"."pedido_detalles"("id");



ALTER TABLE ONLY "public"."liquidaciones"
    ADD CONSTRAINT "liquidaciones_preventista_id_fkey" FOREIGN KEY ("preventista_id") REFERENCES "public"."usuarios"("id");



ALTER TABLE ONLY "public"."pedido_detalles"
    ADD CONSTRAINT "pedido_detalles_pedido_id_fkey" FOREIGN KEY ("pedido_id") REFERENCES "public"."pedidos"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."pedido_detalles"
    ADD CONSTRAINT "pedido_detalles_producto_id_fkey" FOREIGN KEY ("producto_id") REFERENCES "public"."productos"("id");



ALTER TABLE ONLY "public"."pedido_pagos"
    ADD CONSTRAINT "pedido_pagos_pedido_id_fkey" FOREIGN KEY ("pedido_id") REFERENCES "public"."pedidos"("id");



ALTER TABLE ONLY "public"."pedidos"
    ADD CONSTRAINT "pedidos_cliente_id_fkey" FOREIGN KEY ("cliente_id") REFERENCES "public"."clientes"("id");



ALTER TABLE ONLY "public"."pedidos"
    ADD CONSTRAINT "pedidos_preventista_id_fkey" FOREIGN KEY ("preventista_id") REFERENCES "public"."usuarios"("id");



ALTER TABLE ONLY "public"."usuarios"
    ADD CONSTRAINT "usuarios_auth_id_fk" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



CREATE POLICY "Administradores gestionan detalles liquidacion" ON "public"."liquidacion_detalles" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."usuarios"
  WHERE (("usuarios"."id" = "auth"."uid"()) AND ("usuarios"."rol" = 'administrador'::"text") AND ("usuarios"."activo" = true))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."usuarios"
  WHERE (("usuarios"."id" = "auth"."uid"()) AND ("usuarios"."rol" = 'administrador'::"text") AND ("usuarios"."activo" = true)))));



CREATE POLICY "Administradores gestionan liquidaciones" ON "public"."liquidaciones" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."usuarios"
  WHERE (("usuarios"."id" = "auth"."uid"()) AND ("usuarios"."rol" = 'administrador'::"text") AND ("usuarios"."activo" = true))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."usuarios"
  WHERE (("usuarios"."id" = "auth"."uid"()) AND ("usuarios"."rol" = 'administrador'::"text") AND ("usuarios"."activo" = true)))));



CREATE POLICY "Policy Name: administradores pueden actualizar productos" ON "public"."productos" FOR UPDATE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."usuarios"
  WHERE (("usuarios"."id" = "auth"."uid"()) AND ("usuarios"."rol" = 'administrador'::"text") AND ("usuarios"."activo" = true))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."usuarios"
  WHERE (("usuarios"."id" = "auth"."uid"()) AND ("usuarios"."rol" = 'administrador'::"text") AND ("usuarios"."activo" = true)))));



CREATE POLICY "administradores pueden actualizar detalles de pedidos" ON "public"."pedido_detalles" FOR UPDATE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."usuarios" "u"
  WHERE (("u"."id" = "auth"."uid"()) AND ("u"."rol" = 'administrador'::"text") AND ("u"."activo" = true))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."usuarios" "u"
  WHERE (("u"."id" = "auth"."uid"()) AND ("u"."rol" = 'administrador'::"text") AND ("u"."activo" = true)))));



CREATE POLICY "administradores pueden actualizar pedidos" ON "public"."pedidos" FOR UPDATE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."usuarios" "u"
  WHERE (("u"."id" = "auth"."uid"()) AND ("u"."rol" = 'administrador'::"text") AND ("u"."activo" = true))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."usuarios" "u"
  WHERE (("u"."id" = "auth"."uid"()) AND ("u"."rol" = 'administrador'::"text") AND ("u"."activo" = true)))));



CREATE POLICY "administradores pueden crear productos" ON "public"."productos" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."usuarios"
  WHERE (("usuarios"."id" = "auth"."uid"()) AND ("usuarios"."rol" = 'administrador'::"text") AND ("usuarios"."activo" = true)))));



CREATE POLICY "administradores pueden eliminar productos" ON "public"."productos" FOR DELETE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."usuarios"
  WHERE (("usuarios"."id" = "auth"."uid"()) AND ("usuarios"."rol" = 'administrador'::"text") AND ("usuarios"."activo" = true)))));



CREATE POLICY "administradores pueden leer usuarios" ON "public"."usuarios" FOR SELECT TO "authenticated" USING ("public"."es_administrador"());



ALTER TABLE "public"."clientes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."liquidacion_detalles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."liquidaciones" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."pedido_detalles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."pedido_pagos" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."pedidos" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."productos" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."usuarios" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "usuarios autenticados pueden crear clientes" ON "public"."clientes" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "preventista_id"));



CREATE POLICY "usuarios autenticados pueden crear detalles de pedidos" ON "public"."pedido_detalles" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "usuarios autenticados pueden crear pedidos" ON "public"."pedidos" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "usuarios autenticados pueden editar clientes" ON "public"."clientes" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "usuarios autenticados pueden leer clientes" ON "public"."clientes" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "usuarios autenticados pueden leer detalles de pedidos" ON "public"."pedido_detalles" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "usuarios autenticados pueden leer pagos de pedidos" ON "public"."pedido_pagos" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "usuarios autenticados pueden leer pedidos" ON "public"."pedidos" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "usuarios autenticados pueden leer productos" ON "public"."productos" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "usuarios autenticados pueden registrar pagos de pedidos" ON "public"."pedido_pagos" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "usuarios puede leer su propio perfil" ON "public"."usuarios" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "id"));



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



REVOKE ALL ON FUNCTION "public"."es_administrador"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."es_administrador"() TO "anon";
GRANT ALL ON FUNCTION "public"."es_administrador"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."es_administrador"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."registrar_liquidacion"("p_preventista_id" "uuid", "p_fecha_desde" "date", "p_fecha_hasta" "date", "p_venta_entregada" numeric, "p_comision_total" numeric, "p_detalles" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."registrar_liquidacion"("p_preventista_id" "uuid", "p_fecha_desde" "date", "p_fecha_hasta" "date", "p_venta_entregada" numeric, "p_comision_total" numeric, "p_detalles" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."registrar_liquidacion"("p_preventista_id" "uuid", "p_fecha_desde" "date", "p_fecha_hasta" "date", "p_venta_entregada" numeric, "p_comision_total" numeric, "p_detalles" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."registrar_liquidacion"("p_preventista_id" "uuid", "p_fecha_desde" "date", "p_fecha_hasta" "date", "p_venta_entregada" numeric, "p_comision_total" numeric, "p_detalles" "jsonb") TO "service_role";



GRANT ALL ON TABLE "public"."clientes" TO "anon";
GRANT ALL ON TABLE "public"."clientes" TO "authenticated";
GRANT ALL ON TABLE "public"."clientes" TO "service_role";



GRANT ALL ON TABLE "public"."liquidacion_detalles" TO "anon";
GRANT ALL ON TABLE "public"."liquidacion_detalles" TO "authenticated";
GRANT ALL ON TABLE "public"."liquidacion_detalles" TO "service_role";



GRANT ALL ON TABLE "public"."liquidaciones" TO "anon";
GRANT ALL ON TABLE "public"."liquidaciones" TO "authenticated";
GRANT ALL ON TABLE "public"."liquidaciones" TO "service_role";



GRANT ALL ON TABLE "public"."pedido_detalles" TO "anon";
GRANT ALL ON TABLE "public"."pedido_detalles" TO "authenticated";
GRANT ALL ON TABLE "public"."pedido_detalles" TO "service_role";



GRANT ALL ON TABLE "public"."pedido_pagos" TO "anon";
GRANT ALL ON TABLE "public"."pedido_pagos" TO "authenticated";
GRANT ALL ON TABLE "public"."pedido_pagos" TO "service_role";



GRANT ALL ON TABLE "public"."pedidos" TO "anon";
GRANT ALL ON TABLE "public"."pedidos" TO "authenticated";
GRANT ALL ON TABLE "public"."pedidos" TO "service_role";



GRANT ALL ON TABLE "public"."productos" TO "anon";
GRANT ALL ON TABLE "public"."productos" TO "authenticated";
GRANT ALL ON TABLE "public"."productos" TO "service_role";



GRANT ALL ON TABLE "public"."usuarios" TO "anon";
GRANT ALL ON TABLE "public"."usuarios" TO "authenticated";
GRANT ALL ON TABLE "public"."usuarios" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";







