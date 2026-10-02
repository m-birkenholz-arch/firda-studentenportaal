import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, apikey, content-type'}

Deno.serve(async(req)=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:corsHeaders})
  try{
    const url=Deno.env.get('SUPABASE_URL')!
    const key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const admin=createClient(url,key)
    const token=(req.headers.get('Authorization')||'').replace(/^Bearer\s+/i,'')
    const {data:userData,error:userError}=await admin.auth.getUser(token)
    if(userError||!userData.user)return json({error:'Niet ingelogd.'},401)
    const caller=userData.user
    const {data:me}=await admin.from('profiles').select('role').eq('id',caller.id).single()
    if(me?.role!=='admin')return json({error:'Alleen een beheerder kan docenten verwijderen.'},403)

    const {teacherId}=await req.json()
    if(!teacherId||teacherId===caller.id)return json({error:'Dit account kan niet worden verwijderd.'},400)
    const {data:target}=await admin.from('profiles').select('role').eq('id',teacherId).single()
    if(target?.role!=='teacher')return json({error:'Docent niet gevonden.'},404)

    const {data:subs}=await admin.from('submissions').select('id').eq('student_id',teacherId)
    const subIds=(subs||[]).map((x:any)=>x.id)
    if(subIds.length){
      const {data:versions}=await admin.from('submission_versions').select('storage_path').in('submission_id',subIds)
      const paths=(versions||[]).map((x:any)=>x.storage_path).filter(Boolean)
      if(paths.length){const {error:e}=await admin.storage.from('submissions').remove(paths);if(e)throw e}
    }

    // Deleting the Auth user removes rows that reference it through ON DELETE CASCADE.
    // If a database relation intentionally blocks deletion, abort instead of leaving partial account data.
    const {error:deleteError}=await admin.auth.admin.deleteUser(teacherId)
    if(deleteError)throw deleteError
    return json({ok:true})
  }catch(e){console.error(e);return json({error:String((e as Error)?.message||e)},500)}
})

function json(body:unknown,status=200){return new Response(JSON.stringify(body),{status,headers:{...corsHeaders,'Content-Type':'application/json'}})}
