# E-mailmeldingen

De webapp roept de Supabase Edge Function `send-notification` aan na:
- eerste inzending door een student;
- een nieuwe versie/herinzending;
- beoordeling door de docent (goedgekeurd of aanpassing gevraagd).

Benodigde Edge Function secrets:
- `RESEND_API_KEY`
- `NOTIFICATION_FROM_EMAIL` (bijvoorbeeld `Studentenportaal <portaal@jouwdomein.nl>`)
- `PORTAL_URL` (standaard `https://majoorpietersen.netlify.app`)

`SUPABASE_URL` en `SUPABASE_SERVICE_ROLE_KEY` zijn normaal automatisch beschikbaar in Supabase Edge Functions.

Deploy daarna de functie `send-notification` via het Supabase Dashboard of de Supabase CLI.
