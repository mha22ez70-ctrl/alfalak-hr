#!/usr/bin/env node
/* ============================================================================
   اختبار الحقن الحيّ  —  هل يستطيع موظف أن يزرع شيفرة في البرنامج؟

     node tools/xsstest.js index.html

   لا يُخمّن ولا يقرأ الشيفرة. يزرع حمولةً خبيثة في كل حقل نصّي
   تُكتب قيمته من لوحة المفاتيح أو من ملف إكسل، ثم يفتح كل شاشة
   وكل نافذة ويسأل المتصفح نفسه: هل نُفِّذت؟

   ولماذا هذا أخطر ما في البرنامج: رمز الدخول محفوظ في المتصفح.
   فلو نجح حقنٌ واحد في اسم موظف، ثم فتح مديرُ النظام شاشة
   الموظفين، سُرقت جلسته — وبها يُقرأ كل شيء ويُكتب كل شيء.

   ثلاث حمولات، كلٌّ تكشف بابَ دخول مختلفاً:
     ١) وسم كامل   <img onerror>      — إدراج HTML في متن الصفحة
     ٢) كسر الخاصية " onmouseover=    — الخروج من قيمة خاصية
     ٣) خطف الإجراء " data-act="       — سرقة زر موجود أصلاً
        وهذه الأخطر هنا، لأن البرنامج يُشغّل أفعاله كلها عبر data-act،
        فمن زرع data-act في اسمه جعل كل زرٍّ يحمل اسمه قنبلة.
============================================================================ */

const { chromium } = require('/opt/node-tools/node_modules/playwright');
const path = require('path');
const FILE = path.resolve(process.argv[2] || 'index.html');

/* الحمولات — كلٌّ تُسجّل نفسها في window.__HIT عند التنفيذ */
const P1 = `<img src=x onerror="window.__HIT.push('tag')">`;
const P2 = `" onmouseover="window.__HIT.push('attr')" x="`;
const P3 = `" data-act="revokeAcc" data-id="HIJACK" x="`;
const PJ = `javascript:window.__HIT.push('href')`;

const poison = (base, p) => `${base}${p}`;

const STATE = p => `
me={id:'u1',role:'admin',name:${JSON.stringify(poison('مدير', p))},employee_id:'E1'};
S={org:{name:${JSON.stringify(poison('الفلك', p))}},
 projects:[{id:'PR1',name:${JSON.stringify(poison('مشروع', p))}}],
 profiles:[{id:'u1',employee_id:'E1'}],
 departments:[{id:'D1',name:${JSON.stringify(poison('قسم', p))}}],
 positions:[{id:'P1',name:${JSON.stringify(poison('منصب', p))},role:'employee'}],
 employers:[{id:'X1',name:${JSON.stringify(poison('منشأة', p))}}],
 emp:[{id:'E1',name:${JSON.stringify(poison('موظف', p))},title:'',
   nid:'1111111111',position:${JSON.stringify(poison('منصب', p))},position_id:'P1',
   dept:${JSON.stringify(poison('قسم', p))},dept_id:'D1',
   employer:${JSON.stringify(poison('منشأة', p))},employer_id:'X1',
   nat:${JSON.stringify(poison('جنسية', p))},phone:${JSON.stringify(poison('0551', p))},
   pno:${JSON.stringify(poison('A12', p))},iqama:'2027-01-15',
   passport:'2028-06-30',medical:'2027-03-01'}],
 veh:[{id:'V1',plate:${JSON.stringify(poison('ح ي م 4339', p))},
   model:${JSON.stringify(poison('طراز', p))},year:'2022',
   type:${JSON.stringify(poison('نوع', p))},driver:'E1',km:100,dept_id:'D1',
   istimara:'2026-12-01',insurance:'2026-12-01',inspect:'2026-12-01',
   status:${JSON.stringify(poison('نشطة', p))}}],
 leave:[{id:'L1',emp:'E1',type:'سنوية',from:'2026-11-01',to:'2026-11-05',
   status:'معلقة',note:${JSON.stringify(poison('ملاحظة', p))}}],
 rep:[{id:'R1',date:'2026-11-01',project:${JSON.stringify(poison('مشروع', p))},
   project_id:'PR1',emp:'E1',hours:8,task:${JSON.stringify(poison('مهمة', p))}}],
 custody:[{id:'C1',emp:'E1',amount:1000,date:'2026-11-01',
   note:${JSON.stringify(poison('عهدة', p))},status:'مفتوحة',settled:''}],
 cexp:[{id:'CE1',cust:'C1',date:'2026-11-02',cat:${JSON.stringify(poison('بند', p))},
   cost:50,veh:'V1',project:${JSON.stringify(poison('مشروع', p))},project_id:'PR1',
   note:${JSON.stringify(poison('مصروف', p))},receipt:${JSON.stringify(PJ)}}],
 log:[{id:'G1',veh:'V1',kind:${JSON.stringify(poison('صيانة', p))},date:'2026-11-01',
   cost:300,note:${JSON.stringify(poison('سجل', p))}}],
 adj:[{id:'A1',emp:'E1',kind:'إضافي',unit:'ساعة',qty:3,date:'2026-11-01',
   note:${JSON.stringify(poison('بدل', p))}}],
 ibatch:[{id:'B1',kind:'emp',file:${JSON.stringify(poison('ملف.xlsx', p))},
   at:'2026-11-01T00:00:00Z',added:1,updated:2,skipped:0,undone:false}],
 vfile:[{id:'VF1',veh:'V1',name:${JSON.stringify(poison('مرفق', p))},
   path:${JSON.stringify(poison('p/a.pdf', p))},date:'2026-11-01'}],
 vdrv:[{id:'VD1',veh:'V1',emp:'E1',from:'2026-01-01',to:'',
   note:${JSON.stringify(poison('تسليم', p))}}],
 period:[{id:'PD1',dept:'D1',month:'2026-11',status:'مسودة',at:''}],
 cdoc:[{id:'CD1',name:${JSON.stringify(poison('وثيقة', p))},
   cat:${JSON.stringify(poison('سجل', p))},issuer:${JSON.stringify(poison('جهة', p))},
   no:${JSON.stringify(poison('123', p))},issued:'2025-01-01',expiry:'2027-01-01',
   cost:1200,file:${JSON.stringify(poison('f.pdf', p))},
   note:${JSON.stringify(poison('ملاحظة', p))},active:true}],
 fuel:[{id:'F1',veh:'V1',plate:${JSON.stringify(poison('ح ي م 4339', p))},
   month:'2026-10',at:'2026-10-04T07:10:00Z',ltr:40,amt:87,
   station:${JSON.stringify(poison('محطة', p))},driver:${JSON.stringify(poison('سائق', p))},
   product:${JSON.stringify(poison('بنزين', p))},flag:'لا',src:'detail'}],
 fuPeriods:[{month:'2026-10',kind:'detail',liters:40,amount:87,tx_count:1,at:''}]};
`;

const NAMES = { tag: 'وسم كامل <img onerror>', attr: 'كسر الخاصية " onmouseover=',
                hijack: 'خطف الإجراء " data-act=', href: 'رابط javascript:' };

(async () => {
  const browser = await chromium.launch();
  const results = [];

  for (const [key, payload] of [['tag', P1], ['attr', P2], ['hijack', P3]]) {
    const pg = await browser.newPage({ viewport: { width: 1280, height: 1000 } });
    const errs = [];
    pg.on('pageerror', e => errs.push(String(e)));
    await pg.route('**/*', r => r.request().url().startsWith('file://')
      ? r.continue()
      : r.fulfill({ status: 200, contentType: 'application/json', body: '[]' }));
    await pg.addInitScript(() => { window.__HIT = []; });
    await pg.goto('file://' + FILE);
    await pg.waitForTimeout(1300);

    await pg.evaluate(STATE(payload) + `$('#gate').hidden=true;$('#app').hidden=false;paintChrome();`);

    /* كل الشاشات */
    const views = await pg.evaluate(() => Object.keys(VIEWS));
    for (const v of views) {
      await pg.evaluate(v => { try { go(v) } catch (e) { } }, v);
      await pg.waitForTimeout(40);
      /* تحريك المؤشّر فوق كل شيء — حمولة onmouseover لا تنفجر بلا ذلك */
      await pg.evaluate(() => {
        document.querySelectorAll('#view *').forEach(el =>
          el.dispatchEvent(new MouseEvent('mouseover', { bubbles: true })));
      });
    }

    /* النوافذ المنبثقة */
    await pg.evaluate(async () => {
      try { go('vehicles'); openVehFuel('V1') } catch (e) { }
      await new Promise(r => setTimeout(r, 150));
      try { const d = document.getElementById('dlg'); if (d) d.close() } catch (e) { }
      try { go('employees'); document.querySelector('[data-act="editEmp"]').click() } catch (e) { }
      await new Promise(r => setTimeout(r, 150));
      try { const d = document.getElementById('dlg'); if (d) d.close() } catch (e) { }
      try { go('settings') } catch (e) { }
      document.querySelectorAll('#dlg *, #view *').forEach(el =>
        el.dispatchEvent(new MouseEvent('mouseover', { bubbles: true })));
    });

    const hits = await pg.evaluate(() => window.__HIT || []);

    /* خطف الإجراء: نبحث عن عنصر صار يحمل data-act لم يضعه البرنامج */
    const hijack = await pg.evaluate(() => {
      let n = 0;
      document.querySelectorAll('[data-id="HIJACK"]').forEach(() => n++);
      return n;
    });

    /* إدراج HTML ولو لم ينفجر: هل وُجد وسم img الدخيل؟ */
    const injected = await pg.evaluate(() => document.querySelectorAll('img[src="x"]').length);

    results.push({ key, hits: [...new Set(hits)], hijack, injected, errs: errs.length });
    await pg.close();
  }

  /* ═══ التقرير ═══ */
  console.log('\n  اختبار الحقن الحيّ — ' + FILE);
  console.log('  ' + '─'.repeat(78));
  let bad = 0;
  for (const r of results) {
    const fired = r.hits.length > 0 || r.hijack > 0 || r.injected > 0;
    if (fired) bad++;
    console.log('\n  ' + (fired ? '🔴 نجح الحقن' : '✔ صُدّ') + '   ' + NAMES[r.key]);
    console.log('     نُفِّذت الحمولة : ' + (r.hits.length ? '🔴 نعم (' + r.hits.join(', ') + ')' : 'لا'));
    console.log('     وسم دخيل مُدرَج : ' + (r.injected ? '🔴 ' + r.injected : 'لا'));
    console.log('     زر مخطوف       : ' + (r.hijack ? '🔴 ' + r.hijack : 'لا'));
  }
  console.log('\n  ' + '─'.repeat(78));
  console.log(bad
    ? '  🔴 ' + bad + ' من ' + results.length + ' حمولات نجحت — الحقن ممكن.'
    : '  ✔ الحمولات الثلاث صُدّت كلها في كل شاشة ونافذة.');
  console.log('');
  await browser.close();
  process.exit(bad ? 1 : 0);
})();
