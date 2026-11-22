#!/usr/bin/env node
/* ============================================================================
   فاحص أمان البرنامج  —  يقرأ index.html ولا يغيّره

     node tools/appaudit.js index.html

   يفحص سبعة أبواب:
     ١) الأسرار المزروعة في الملف
     ٢) الحقن في HTML  (أخطرها: اسم موظف يحمل شيفرة)
     ٣) حقن مرشّحات PostgREST  (قيمة تحمل & أو , تغيّر الاستعلام)
     ٤) أين يُحفَظ رمز الدخول
     ٥) ما يُطبع في console
     ٦) ما يُحمَّل من الشبكة  (مكتبات خارجية)
     ٧) حقن الصيغ في ملفات إكسل المُصدَّرة

   لا يحكم وحده: كل إشارة تحتاج قراءة بشرية. وهو يقول ذلك صراحةً
   في آخر تقريره.
============================================================================ */

const fs = require('fs');
const file = process.argv[2] || 'index.html';
const html = fs.readFileSync(file, 'utf8');
const script = (html.match(/<script>([\s\S]*)<\/script>/) || [, ''])[1];
const lineOf = (src, i) => src.slice(0, i).split('\n').length;
const htmlOffset = html.indexOf(script);

const F = [];                       /* النتائج */
const add = (sev, chk, detail, line) => F.push({ sev, chk, detail, line });

/* ═══ ١) الأسرار ═══ */
{
  const pats = [
    [/sb_secret_[A-Za-z0-9_\-]+/g, 'مفتاح Supabase السرّي'],
    [/service_role/g, 'إشارة إلى service_role'],
    [/eyJ[A-Za-z0-9_\-]{30,}\.[A-Za-z0-9_\-]{10,}/g, 'رمز JWT مكتوب في الملف'],
    [/-----BEGIN [A-Z ]*PRIVATE KEY/g, 'مفتاح خاص'],
    [/VAPID_PRIVATE\s*=\s*['"][^'"]{10,}/g, 'مفتاح VAPID الخاص'],
  ];
  let hit = false;
  for (const [re, what] of pats)
    for (const m of html.matchAll(re)) {
      hit = true;
      add('🔴 خطر', 'سرٌّ في الملف', what + ' — سطر ' + lineOf(html, m.index), lineOf(html, m.index));
    }
  if (!hit) add('✔ سليم', 'الأسرار', 'لا مفتاح سرّي ولا رمز في الملف');

  const pub = html.match(/sb_publishable_[A-Za-z0-9_\-]+/);
  if (pub) add('ℹ معلومة', 'المفتاح العام',
    'موجود كما ينبغي — مصمَّم ليُنشر، و RLS هو الحماية');
}

/* ═══ ٢) الحقن في HTML ═══ */
/*  لا نفحصه هنا. جرّبتُ الفحص الساكن فأنتج مئتَي إشارة أغلبها
    كاذب — ومعيارٌ يصرخ مئتَي مرة لا يُسمَع حين يصرخ بحقّ.
    بديله اختبارٌ حيّ لا يُخمّن:  node tools/xsstest.js          */
{
  const esc = /const\s+esc\s*=\s*[^\n]*replace\([^\n]*&lt;/.test(script);
  add(esc ? '✔ سليم' : '🔴 خطر', 'دالة التهريب',
    esc ? 'esc() موجودة وتهرّب < و > و " — شغّل tools/xsstest.js للتأكّد من استعمالها في كل موضع'
        : 'esc() مفقودة أو لا تهرّب — خطر حقن مباشر');
}

/* ═══ ٢ب) رفع الملفات: الامتداد ونوع المحتوى ═══ */
{
  const wl = /UP_OK\s*=\s*\{/.test(script);
  const raw = /Content-Type['"]?\s*:\s*file\.type/.test(script);
  if (!wl || raw)
    add('🔴 خطر', 'رفع الملفات',
      'الامتداد أو نوع المحتوى مأخوذ من اسم الملف كما هو — ملف svg أو html يُنفَّذ عند فتحه');
  else
    add('✔ سليم', 'رفع الملفات', 'قائمة امتدادات مغلقة، ونوع المحتوى يفرضه البرنامج');
}

/* ═══ ٣) حقن مرشّحات PostgREST ═══ */
/*  api.sel('t', '&id=eq.' + x) — لو حمل x محرف & أو , غيّر الاستعلام.  */
{
  const re = /api\.(sel|del)\(\s*(['"`][^'"`]+['"`])\s*,\s*([^),]*)\)/g;
  let m, hit = false;
  while ((m = re.exec(script))) {
    const arg = m[3].trim();
    if (/['"`]\s*\+|\+\s*[A-Za-z_$]/.test(arg)) {
      hit = true;
      add('⚠ راجعه', 'مرشّح مبنيّ بالدمج النصّي',
        m[1] + '(' + m[2] + ', ' + arg.replace(/\s+/g, ' ').slice(0, 70) + ')   (سطر ' + lineOf(script, m.index) + ')',
        lineOf(script, m.index));
    }
  }
  if (!hit) add('✔ سليم', 'مرشّحات الاستعلام', 'لا مرشّح مبنيّ بدمج نصّي غير مُرمَّز');
}

/* ═══ ٤) أين يُحفَظ رمز الدخول ═══ */
{
  /*  المفتاح قد يمرّ عبر غلاف (LS.set) لا عبر localStorage.setItem مباشرةً،
      فنجمع كل ما يُكتب بأي من الصيغتين ثم نرشّح ما يشبه الجلسة.        */
  const ls = [...script.matchAll(/(?:localStorage\.setItem|LS\.set|\bstore\.set)\(\s*['"]([^'"]+)['"]/g)]
    .map(x => x[1]);
  const wraps = /localStorage\.setItem/.test(script);
  const tok = ls.filter(k => /sess|tok|auth|jwt/i.test(k));
  if (tok.length)
    add('ℹ معلومة', 'تخزين الجلسة',
      'localStorage: ' + tok.join(', ') + ' — يبقى بعد إغلاق المتصفح. مقبول لبرنامج يُستعمل يومياً، '
      + 'لكنه يعني أن ثغرة حقن واحدة تسرق الجلسة. وهذا ما يجعل الباب ٢ أعلاه هو الأهم.');
  else add(wraps ? '⚠ راجعه' : 'ℹ معلومة', 'تخزين الجلسة',
    wraps ? 'البرنامج يكتب في localStorage لكن لم أتعرّف على مفتاح الجلسة — اقرأه بنفسك'
          : 'لا يُحفَظ في localStorage');
}

/* ═══ ٥) ما يُطبع في console ═══ */
{
  const logs = [...script.matchAll(/console\.(log|info|debug|warn)\s*\(([^)\n]{0,80})/g)];
  const bad = logs.filter(x => !/^\s*['"`]/.test(x[2]));
  if (bad.length)
    for (const b of bad.slice(0, 8))
      add('⚠ راجعه', 'طباعة متغيّر في console',
        b[2].replace(/\s+/g, ' ').slice(0, 70) + '   (سطر ' + lineOf(script, b.index) + ')', lineOf(script, b.index));
  else add('✔ سليم', 'console', logs.length + ' نداء، لا يطبع بيانات');
}

/* ═══ ٦) ما يُحمَّل من الشبكة ═══ */
{
  const ext = [...html.matchAll(/(?:src|href)\s*=\s*['"](https?:\/\/[^'"]+)['"]/g)].map(x => x[1]);
  const cdn = ext.filter(u => !/^https?:\/\/(fonts\.googleapis|fonts\.gstatic)/.test(u));
  if (cdn.length)
    for (const u of [...new Set(cdn)])
      add('⚠ راجعه', 'مورد خارجي', u + ' — يُحمَّل من خادم غيرك');
  else add('✔ سليم', 'الموارد الخارجية', 'لا مكتبة ولا ملف من خارج الملف نفسه');

  const sb = html.match(/https:\/\/[a-z0-9]+\.supabase\.co/);
  if (sb) add('ℹ معلومة', 'عنوان القاعدة', sb[0] + ' — ظاهر بالضرورة');
}

/* ═══ ٧) حقن الصيغ في إكسل ═══ */
{
  const guard = /replace\([^)]*\[=\+\-@\]|^'\s*\+|formulaGuard|csvSafe/.test(script);
  if (!guard)
    add('⚠ راجعه', 'حقن الصيغ في إكسل',
      'القيم تُكتب في الخلايا كما هي. اسمٌ يبدأ بـ = أو + أو - أو @ يصير صيغةً '
      + 'تُنفَّذ عند فتح الملف في إكسل. الخطر محدود (بياناتك من موظفيك)، لكنه قائم.');
  else add('✔ سليم', 'حقن الصيغ في إكسل', 'القيم محميّة');
}

/* ═══ التقرير ═══ */
const order = s => s.startsWith('🔴') ? 0 : s.startsWith('⚠') ? 1 : s.startsWith('ℹ') ? 2 : 3;
F.sort((a, b) => order(a.sev) - order(b.sev) || (a.line || 0) - (b.line || 0));

const W = (s, n) => { s = String(s); const w = [...s].length; return s + ' '.repeat(Math.max(0, n - w)) };
console.log('\n  فحص أمان البرنامج — ' + file + '\n  ' + '─'.repeat(100));
let last = '';
for (const f of F) {
  if (f.sev !== last) { console.log(''); last = f.sev }
  console.log('  ' + W(f.sev, 10) + W(f.chk, 30) + f.detail);
}
const red = F.filter(f => f.sev.startsWith('🔴')).length;
const amb = F.filter(f => f.sev.startsWith('⚠')).length;
console.log('\n  ' + '─'.repeat(100));
console.log('  ' + red + ' خطر · ' + amb + ' يحتاج قراءة · ' + F.filter(f => f.sev.startsWith('✔')).length + ' سليم');
console.log('  الإشارة ليست حكماً: كل سطر «يحتاج قراءة» يُقرأ في موضعه قبل أن يُسمّى ثغرة.\n');
