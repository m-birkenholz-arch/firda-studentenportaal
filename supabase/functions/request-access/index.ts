import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'apikey, content-type'}
const esc=(v:unknown)=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]||c))

Deno.serve(async(req)=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers:cors})
 try{
  const url=Deno.env.get('SUPABASE_URL')!,key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,resend=Deno.env.get('RESEND_API_KEY')!
  const from=Deno.env.get('NOTIFICATION_FROM_EMAIL')||'Studentenportaal <noreply@example.com>'
  const portal=Deno.env.get('PORTAL_URL')||'https://majoorpietersen.netlify.app'
  const {full_name,email}=await req.json(),name=String(full_name||'').trim(),mail=String(email||'').trim().toLowerCase()
  if(name.length<2||!mail.includes('@'))return json({error:'Vul een geldige naam en e-mailadres in.'},400)
  const admin=createClient(url,key)
  const {data:existing}=await admin.from('access_requests').select('id').eq('email',mail).eq('status','pending').maybeSingle()
  if(!existing){
   const {error}=await admin.from('access_requests').insert({full_name:name,email:mail})
   if(error)throw error
  }
  const {data:staff}=await admin.from('profiles').select('id').in('role',['teacher','admin'])
  const recipients:string[]=[]
  for(const p of staff||[]){const u=await admin.auth.admin.getUserById(p.id);if(u.data.user?.email)recipients.push(u.data.user.email)}
  if(recipients.length){
   const html=`<!doctype html><html><body style="font-family:Arial,sans-serif;background:#f4f1e8;color:#18251f"><div style="max-width:620px;margin:auto;padding:28px"><div style="background:#244d3c;color:white;padding:24px;border-radius:16px 16px 0 0"><b style="font-size:30px">firda</b></div><div style="background:white;padding:28px;border-radius:0 0 16px 16px"><h1>Nieuwe toegangsaanvraag</h1><p><b>${esc(name)}</b> heeft toegang tot het Studentenportaal aangevraagd.</p><p>${esc(mail)}</p><a href="${esc(portal)}" style="display:inline-block;background:#244d3c;color:white;text-decoration:none;padding:12px 18px;border-radius:10px;font-weight:bold">Open docentdashboard</a></div></div></body></html>`
   const r=await fetch('https://api.resend.com/emails',{method:'POST',headers:{Authorization:`Bearer ${resend}`,'Content-Type':'application/json'},body:JSON.stringify({from,to:recipients,subject:'Nieuwe toegangsaanvraag Studentenportaal',html})})
   if(!r.ok)throw new Error('E-mailmelding kon niet worden verzonden')
  }
  return json({ok:true})
 }catch(e){console.error(e);return json({error:String((e as Error)?.message||e)},500)}
})
function json(body:unknown,status=200){return new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json'}})}
