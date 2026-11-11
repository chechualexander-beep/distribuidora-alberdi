# Migraciones pendientes (no se aplican)

Estas migraciones están guardadas pero **fuera de `supabase/migrations`**, así que
`supabase db push` no las aplica.

- `20261029010000_boletas_internas_transaccionales.sql`: boletas internas. Nunca se
  instaló en TESTING y la app la tiene apagada (`ENABLE_INTERNAL_BOLETAS`). Para
  activarla, moverla a `supabase/migrations` con una versión nueva (fecha actual),
  probar en TESTING y recién después en producción.
