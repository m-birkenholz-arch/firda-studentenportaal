import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
}

const esc = (v: unknown) => String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c] || c))

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const resendKey = Deno.env.get('RESEND_API_KEY')!
    const fromEmail = Deno.env.get('NOTIFICATION_FROM_EMAIL') || 'Studentenportaal <noreply@example.com>'
    const portalUrl = Deno.env.get('PORTAL_URL') || 'https://majoorpietersen.netlify.app'
    if (!resendKey) throw new Error('RESEND_API_KEY ontbreekt')

    const authHeader = req.headers.get('Authorization') || ''
    const admin = createClient(supabaseUrl, serviceKey)
    const token = authHeader.replace(/^Bearer\s+/i, '')
    const { data: userData, error: userError } = await admin.auth.getUser(token)
    if (userError || !userData.user) return new Response('Niet ingelogd', { status: 401, headers: corsHeaders })
    const caller = userData.user
    const body = await req.json()
    let to = '', subject = '', title = '', intro = '', detail = ''

    if (body.type === 'teacher_invite') {
      const { data: profile } = await admin.from('profiles').select('role').eq('id', caller.id).single()
      if (profile?.role !== 'admin') return new Response('Alleen een beheerder kan docentuitnodigingen versturen', { status: 403, headers: corsHeaders })
      const email = String(body.email || '').trim().toLowerCase()
      if (!email || !email.includes('@')) return new Response('Ongeldig e-mailadres', { status: 400, headers: corsHeaders })
      to = email
      subject = 'Uitnodiging als docent voor het Studentenportaal'
      title = 'Je bent uitgenodigd als docent'
      intro = 'Je bent uitgenodigd om het Studentenportaal als docent te gebruiken. Maak je account aan met dit e-mailadres om je docentomgeving te activeren.'
      detail = 'Gebruik bij het aanmaken van je account precies hetzelfde e-mailadres waarop je deze uitnodiging hebt ontvangen.'
    } else if (body.type === 'student_invite') {
      const { data: profile } = await admin.from('profiles').select('role').eq('id', caller.id).single()
      if (!['teacher','admin'].includes(profile?.role || '')) return new Response('Alleen een docent kan studenten uitnodigen', { status: 403, headers: corsHeaders })
      const email = String(body.email || '').trim().toLowerCase()
      const { data: klass } = await admin.from('classes').select('name,teacher_id').eq('id', body.classId).single()
      if (!klass || (profile?.role !== 'admin' && klass.teacher_id !== caller.id)) return new Response('Geen toegang tot deze klas', { status: 403, headers: corsHeaders })
      if (!email || !email.includes('@')) return new Response('Ongeldig e-mailadres', { status: 400, headers: corsHeaders })
      to = email
      subject = 'Uitnodiging voor het Studentenportaal'
      title = 'Je bent uitgenodigd als student'
      intro = `Je bent uitgenodigd voor de klas “${klass.name}”. Maak je account aan met dit e-mailadres; daarna word je automatisch aan de klas toegevoegd.`
      detail = 'Gebruik bij het aanmaken van je account precies hetzelfde e-mailadres waarop je deze uitnodiging hebt ontvangen.'
    } else if (body.type === 'submission' || body.type === 'resubmission') {
      const { data: assignment } = await admin.from('assignments').select('id,title,teacher_id,class_id').eq('id', body.assignmentId).single()
      if (!assignment) throw new Error('Opdracht niet gevonden')
      if (caller.id === assignment.teacher_id) throw new Error('Ongeldige afzender')
      const { data: membership } = await admin.from('class_members').select('student_id').eq('class_id',assignment.class_id).eq('student_id',caller.id).maybeSingle()
      if (!membership) return new Response('Geen toegang tot deze klas', { status: 403, headers: corsHeaders })
      const [{ data: student }, { data: klass }, teacherResult] = await Promise.all([
        admin.from('profiles').select('full_name').eq('id', caller.id).single(),
        admin.from('classes').select('name').eq('id', assignment.class_id).single(),
        admin.auth.admin.getUserById(assignment.teacher_id)
      ])
      to = teacherResult.data.user?.email || ''
      subject = body.type === 'resubmission' ? 'Nieuwe versie ingeleverd' : 'Nieuwe inzending'
      title = subject
      intro = `${student?.full_name || 'Een student'} heeft ${body.type === 'resubmission' ? 'een nieuwe versie ingeleverd voor' : 'werk ingeleverd voor'} “${assignment.title}”.`
      detail = klass?.name ? `Klas: ${klass.name}` : ''
    } else if (body.type === 'review') {
      const { data: submission } = await admin.from('submissions').select('id,student_id,assignment_id').eq('id', body.submissionId).single()
      if (!submission) throw new Error('Inzending niet gevonden')
      const { data: assignment } = await admin.from('assignments').select('title,teacher_id').eq('id', submission.assignment_id).single()
      if (!assignment || assignment.teacher_id !== caller.id) return new Response('Geen toegang tot deze beoordeling', { status: 403, headers: corsHeaders })
      const [{ data: review }, studentResult] = await Promise.all([
        admin.from('reviews').select('feedback,status').eq('submission_id',submission.id).eq('teacher_id',caller.id).order('created_at',{ascending:false}).limit(1).maybeSingle(),
        admin.auth.admin.getUserById(submission.student_id)
      ])
      to = studentResult.data.user?.email || ''
      const approved = body.status === 'approved'
      subject = approved ? 'Je opdracht is goedgekeurd' : 'Aanpassing gevraagd voor je opdracht'
      title = subject
      intro = approved ? `Je docent heeft “${assignment.title}” goedgekeurd.` : `Je docent heeft feedback gegeven op “${assignment.title}”.`
      detail = review?.feedback ? `Feedback: ${review.feedback}` : ''
    } else {
      return new Response('Onbekend meldingstype', { status: 400, headers: corsHeaders })
    }

    if (!to) throw new Error('Ontvanger heeft geen e-mailadres')
    const html = `<!doctype html><html><body style="margin:0;background:#f4f1e8;font-family:Arial,sans-serif;color:#18251f"><div style="max-width:620px;margin:auto;padding:28px 18px"><div style="background:#244d3c;color:white;padding:24px;border-radius:16px 16px 0 0"><div style="font-size:30px;font-weight:900">firda</div><div style="font-size:12px">studentenportaal</div></div><div style="background:white;padding:28px;border-radius:0 0 16px 16px"><h1 style="font-size:25px;margin-top:0">${esc(title)}</h1><p style="line-height:1.6">${esc(intro)}</p>${detail ? `<p style="background:#f4f1e8;padding:14px;border-radius:10px;line-height:1.5">${esc(detail)}</p>` : ''}<p style="margin-top:24px"><a href="${esc(portalUrl)}" style="display:inline-block;background:#244d3c;color:white;text-decoration:none;padding:12px 18px;border-radius:10px;font-weight:bold">${body.type === 'teacher_invite' || body.type === 'student_invite' ? 'Account activeren' : 'Open studentenportaal'}</a></p></div></div></body></html>`

    const mail = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${resendKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: fromEmail, to: [to], subject, html }),
    })
    const result = await mail.text()
    if (!mail.ok) throw new Error(`Resend: ${result}`)
    return new Response(result, { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  } catch (error) {
    console.error(error)
    return new Response(JSON.stringify({ error: String(error?.message || error) }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
})
