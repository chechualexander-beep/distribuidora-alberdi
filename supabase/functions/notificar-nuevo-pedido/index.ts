import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";
import { importPKCS8, SignJWT } from "npm:jose@5.9.6";

async function obtenerAccessToken(
  clientEmail: string,
  privateKey: string,
): Promise<string> {
  const ahora = Math.floor(Date.now() / 1000);

  const clave = await importPKCS8(
    privateKey,
    "RS256",
  );

  const jwt = await new SignJWT({
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  })
    .setProtectedHeader({
      alg: "RS256",
      typ: "JWT",
    })
    .setIssuer(clientEmail)
    .setSubject(clientEmail)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(ahora)
    .setExpirationTime(ahora + 3600)
    .sign(clave);

  const respuesta = await fetch(
    "https://oauth2.googleapis.com/token",
    {
      method: "POST",
      headers: {
        "Content-Type":
          "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({
        grant_type:
          "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion: jwt,
      }),
    },
  );

  if (!respuesta.ok) {
    throw new Error(
      `No se pudo obtener token OAuth: ${respuesta.status}`,
    );
  }

  const datos = await respuesta.json();

  if (!datos.access_token) {
    throw new Error(
      "Google no devolvió un access token.",
    );
  }

  return datos.access_token;
}

function formatearPrecio(valor: unknown): string {
  const numero = Number(valor ?? 0);

  return `$${Math.round(numero)
    .toString()
    .replace(/\B(?=(\d{3})+(?!\d))/g, ".")}`;
}

export default {
  fetch: withSupabase(
    { auth: "secret:notificaciones" },
    async (req, ctx) => {
      try {
        const body = await req.json();
        const pedidoId = body?.pedido_id?.toString();

        if (!pedidoId) {
          throw new Error(
            "No se recibió pedido_id.",
          );
        }

        const { data: pedido, error: errorPedido } =
          await ctx.supabaseAdmin
            .from("pedidos")
            .select(`
              id,
              total,
              clientes (
                nombre_comercio
              ),
              usuarios (
                nombre,
                apellido
              )
            `)
            .eq("id", pedidoId)
            .single();

        if (errorPedido || !pedido) {
          throw new Error(
            "No se pudo cargar el pedido.",
          );
        }

        const cliente =
          pedido.clientes as {
            nombre_comercio?: string | null;
          } | null;

        const preventista =
          pedido.usuarios as {
            nombre?: string | null;
            apellido?: string | null;
          } | null;

        const nombreCliente =
          cliente?.nombre_comercio?.trim() ||
          "Cliente sin nombre";

        const nombrePreventista = [
          preventista?.nombre?.trim(),
          preventista?.apellido?.trim(),
        ]
          .filter(Boolean)
          .join(" ");

        const totalTexto =
          formatearPrecio(pedido.total);

        const firebaseB64 =
          Deno.env.get(
            "FIREBASE_SERVICE_ACCOUNT_B64",
          );

        if (!firebaseB64) {
          throw new Error(
            "No se encontró FIREBASE_SERVICE_ACCOUNT_B64",
          );
        }

        const firebaseJson = atob(firebaseB64);
        const credenciales =
          JSON.parse(firebaseJson);

        const projectId =
          credenciales.project_id?.toString();

        const clientEmail =
          credenciales.client_email?.toString();

        const privateKey =
          credenciales.private_key?.toString();

        if (
          !projectId ||
          !clientEmail ||
          !privateKey
        ) {
          throw new Error(
            "Las credenciales de Firebase están incompletas.",
          );
        }

        const { data: dispositivos, error } =
          await ctx.supabaseAdmin
            .from("dispositivos_notificaciones")
            .select("token")
            .eq("activo", true)
            .eq("plataforma", "android");

        if (error) {
          throw new Error(
            `No se pudieron consultar los dispositivos: ${error.message}`,
          );
        }

        if (
          !dispositivos ||
          dispositivos.length === 0
        ) {
          throw new Error(
            "No hay dispositivos Android activos registrados.",
          );
        }

        const accessToken =
          await obtenerAccessToken(
            clientEmail,
            privateKey,
          );

        let enviados = 0;

        for (const dispositivo of dispositivos) {
          const token =
            dispositivo.token?.toString();

          if (!token) continue;

          const respuestaFcm = await fetch(
            `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
            {
              method: "POST",
              headers: {
                Authorization:
                  `Bearer ${accessToken}`,
                "Content-Type":
                  "application/json",
              },
              body: JSON.stringify({
                message: {
                  token: token,
                  notification: {
                    title:
                      "Nuevo pedido recibido",
                    body:
                      `${nombreCliente} — ${totalTexto}` +
                      (nombrePreventista
                        ? `\nPreventista: ${nombrePreventista}`
                        : ""),
                  },
                  android: {
                    priority: "high",
                    notification: {
                      channel_id:
                        "pedidos_importantes",
                      sound: "default",
                    },
                  },
                },
              }),
            },
          );

          if (respuestaFcm.ok) {
            enviados++;
          } else {
            const errorFcm =
              await respuestaFcm.text();

            console.error(
              "Error FCM:",
              errorFcm,
            );
          }
        }

        return Response.json({
          ok: true,
          enviados,
        });
      } catch (error) {
        console.error(error);

        return Response.json(
          {
            ok: false,
            error:
              error instanceof Error
                ? error.message
                : "Error desconocido.",
          },
          { status: 500 },
        );
      }
    },
  ),
};