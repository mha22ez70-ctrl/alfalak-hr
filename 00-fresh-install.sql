-- ============================================================================
--  نظام الموارد البشرية والمركبات — تثبيت نظيف من الصفر
--  يحذف كل ما سبق ويبني قاعدة البيانات كاملة بلصقة واحدة.
--
--  الاستخدام:  Supabase → SQL Editor → New query → الصق الكل → Run
--  يغني عن الملفات 01 إلى 05 جميعها.
--
--  ⚠ تحذير: يمسح كل الجداول والبيانات والحسابات. لا تشغّله على نظام يعمل.
-- ============================================================================


-- ════════════════════════════════════════════════════════════
--  الجزء الأول: مسح كل ما سبق
-- ════════════════════════════════════════════════════════════

drop trigger if exists on_auth_user_created on auth.users;

drop table if exists public.fleet_log         cascade;
drop table if exists public.custody_expenses  cascade;
drop table if exists public.custody           cascade;
drop table if exists public.daily_reports     cascade;
drop table if exists public.leaves            cascade;
drop table if exists public.payroll_approvals cascade;
drop table if exists public.vehicles          cascade;
drop table if exists public.profiles          cascade;
drop table if exists public.employees         cascade;
drop table if exists public.positions         cascade;
drop table if exists public.projects          cascade;
drop table if exists public.departments       cascade;
drop table if exists public.org_settings      cascade;
drop table if exists public.companies         cascade;   -- من نسخة الشركات المتعددة

drop function if exists public.handle_new_user()                cascade;
drop function if exists public.my_role()                        cascade;
drop function if exists public.my_employee_id()                 cascade;
drop function if exists public.is_staff()                       cascade;
drop function if exists public.is_manager()                     cascade;
drop function if exists public.bootstrap_admin(text, text)      cascade;

-- حذف كل حسابات الدخول السابقة
-- (احذف هذا السطر وحده إن أردت الإبقاء على الحسابات)
delete from auth.users;


-- ════════════════════════════════════════════════════════════
--  الجزء الثاني: الجداول
-- ════════════════════════════════════════════════════════════

-- اسم الشركة — صف واحد لا غير
create table public.org_settings (
  id         boolean primary key default true check (id),
  name       text not null default 'شركتي',
  updated_at timestamptz not null default now()
);
insert into public.org_settings (id, name) values (true, 'شركتي');

-- الأقسام
create table public.departments (
  id         uuid primary key default gen_random_uuid(),
  name       text not null unique,
  created_at timestamptz not null default now()
);

-- المشاريع
create table public.projects (
  id         uuid primary key default gen_random_uuid(),
  name       text not null unique,
  active     boolean not null default true,
  created_at timestamptz not null default now()
);

-- المناصب — كل منصب يحمل صلاحيته، ومنها تُشتق صلاحية من يشغله
create table public.positions (
  id         uuid primary key default gen_random_uuid(),
  name       text not null unique,
  role       text not null default 'employee'
             check (role in ('admin','hr','accountant','employee')),
  created_at timestamptz not null default now()
);

-- الموظفون
create table public.employees (
  id              uuid primary key default gen_random_uuid(),
  name            text not null,
  national_id     text,
  position_id     uuid references public.positions(id)   on delete set null,
  department_id   uuid references public.departments(id) on delete set null,
  nationality     text,
  phone           text,
  iban            text,
  salary          numeric(12,2) not null default 0,
  allowance       numeric(12,2) not null default 0,
  iqama_expiry    date,
  passport_expiry date,
  active          boolean not null default true,
  created_at      timestamptz not null default now()
);
create unique index ux_employees_national_id
  on public.employees (national_id) where national_id is not null;
create index ix_emp_position on public.employees(position_id);
create index ix_emp_dept     on public.employees(department_id);

-- حسابات الدخول، مربوطة بسجلات الموظفين
create table public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  full_name   text,
  role        text not null default 'employee'
              check (role in ('admin','hr','accountant','employee')),
  employee_id uuid references public.employees(id) on delete set null,
  created_at  timestamptz not null default now()
);

-- المركبات
create table public.vehicles (
  id               uuid primary key default gen_random_uuid(),
  plate            text not null,
  model            text not null,
  year             int,
  type             text,
  driver_id        uuid references public.employees(id) on delete set null,
  km               bigint not null default 0,
  istimara_expiry  date,
  insurance_expiry date,
  status           text not null default 'نشطة',
  created_at       timestamptz not null default now()
);
create index ix_veh_driver on public.vehicles(driver_id);

-- الإجازات
create table public.leaves (
  id          uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  type        text not null default 'سنوية',
  from_date   date not null,
  to_date     date not null,
  status      text not null default 'معلقة' check (status in ('معلقة','معتمدة','مرفوضة')),
  note        text,
  decided_by  uuid references auth.users(id) on delete set null,
  decided_at  timestamptz,
  created_by  uuid references auth.users(id) on delete set null default auth.uid(),
  created_at  timestamptz not null default now(),
  check (to_date >= from_date)
);
create index ix_lv_emp on public.leaves(employee_id);

-- التقارير اليومية
create table public.daily_reports (
  id          uuid primary key default gen_random_uuid(),
  date        date not null,
  project_id  uuid references public.projects(id)  on delete set null,
  employee_id uuid not null references public.employees(id) on delete cascade,
  hours       numeric(5,2) not null default 0,
  task        text,
  created_by  uuid references auth.users(id) on delete set null default auth.uid(),
  created_at  timestamptz not null default now()
);
create index ix_dr_emp  on public.daily_reports(employee_id);
create index ix_dr_date on public.daily_reports(date);

-- العُهد
create table public.custody (
  id           uuid primary key default gen_random_uuid(),
  employee_id  uuid not null references public.employees(id) on delete cascade,
  amount       numeric(12,2) not null default 0,
  date         date not null default current_date,
  note         text,
  status       text not null default 'مفتوحة' check (status in ('مفتوحة','مسوّاة')),
  settled_date date,
  created_by   uuid references auth.users(id) on delete set null default auth.uid(),
  created_at   timestamptz not null default now()
);
create index ix_cu_emp on public.custody(employee_id);

-- مصروفات العُهد
create table public.custody_expenses (
  id           uuid primary key default gen_random_uuid(),
  custody_id   uuid not null references public.custody(id) on delete cascade,
  date         date not null default current_date,
  category     text not null default 'أخرى',
  cost         numeric(12,2) not null default 0,
  vehicle_id   uuid references public.vehicles(id) on delete set null,
  project_id   uuid references public.projects(id) on delete set null,
  note         text,
  receipt_path text,
  created_by   uuid references auth.users(id) on delete set null default auth.uid(),
  created_at   timestamptz not null default now()
);
create index ix_cx_cust on public.custody_expenses(custody_id);

-- سجل مصروفات الأسطول
create table public.fleet_log (
  id                uuid primary key default gen_random_uuid(),
  vehicle_id        uuid references public.vehicles(id) on delete cascade,
  kind              text not null default 'وقود' check (kind in ('وقود','صيانة','مخالفة')),
  date              date not null default current_date,
  cost              numeric(12,2) not null default 0,
  note              text,
  source_expense_id uuid references public.custody_expenses(id) on delete cascade,
  created_by        uuid references auth.users(id) on delete set null default auth.uid(),
  created_at        timestamptz not null default now()
);
create index ix_fl_veh on public.fleet_log(vehicle_id);

-- اعتماد مسير الرواتب
create table public.payroll_approvals (
  id          uuid primary key default gen_random_uuid(),
  month       text not null unique,          -- 'YYYY-MM'
  approved_by uuid references auth.users(id) on delete set null default auth.uid(),
  approved_at timestamptz not null default now()
);


-- ════════════════════════════════════════════════════════════
--  الجزء الثالث: الدوال
-- ════════════════════════════════════════════════════════════

-- ملف تعريف تلقائي لكل حساب جديد
create function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, role)
  values (new.id,
          coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email,'@',1)),
          'employee')
  on conflict (id) do nothing;
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- الصلاحية: من المنصب أولاً، ثم من الملف التعريفي كاحتياط
create function public.my_role() returns text
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select ps.role
       from public.profiles pr
       join public.employees e  on e.id  = pr.employee_id
       join public.positions ps on ps.id = e.position_id
      where pr.id = auth.uid()),
    (select role from public.profiles where id = auth.uid()),
    'employee')
$$;

create function public.my_employee_id() returns uuid
language sql stable security definer set search_path = public as $$
  select employee_id from public.profiles where id = auth.uid()
$$;

create function public.is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select public.my_role() in ('admin','hr','accountant')
$$;

create function public.is_manager() returns boolean
language sql stable security definer set search_path = public as $$
  select public.my_role() in ('admin','hr')
$$;

-- إنشاء المدير الأول من داخل البرنامج — يعمل مرة واحدة فقط
create function public.bootstrap_admin(p_name text, p_nid text)
returns text language plpgsql security definer set search_path = public as $$
declare v_pos uuid; v_emp uuid;
begin
  if exists (select 1 from public.profiles where role = 'admin') then
    return 'admin_exists';
  end if;
  if auth.uid() is null then
    return 'not_signed_in';
  end if;

  select id into v_pos from public.positions where role = 'admin' order by created_at limit 1;
  if v_pos is null then
    insert into public.positions (name, role) values ('مدير عام', 'admin') returning id into v_pos;
  end if;

  select id into v_emp from public.employees where national_id = p_nid;
  if v_emp is null then
    insert into public.employees (name, national_id, position_id)
    values (p_name, p_nid, v_pos) returning id into v_emp;
  else
    update public.employees set name = p_name, position_id = v_pos where id = v_emp;
  end if;

  update public.profiles
     set full_name = p_name, role = 'admin', employee_id = v_emp
   where id = auth.uid();

  return 'ok';
end $$;

grant execute on function public.my_role()                   to authenticated;
grant execute on function public.bootstrap_admin(text, text) to authenticated;


-- ════════════════════════════════════════════════════════════
--  الجزء الرابع: حماية الصفوف
-- ════════════════════════════════════════════════════════════

alter table public.org_settings      enable row level security;
alter table public.departments       enable row level security;
alter table public.projects          enable row level security;
alter table public.positions         enable row level security;
alter table public.employees         enable row level security;
alter table public.profiles          enable row level security;
alter table public.vehicles          enable row level security;
alter table public.leaves            enable row level security;
alter table public.daily_reports     enable row level security;
alter table public.custody           enable row level security;
alter table public.custody_expenses  enable row level security;
alter table public.fleet_log         enable row level security;
alter table public.payroll_approvals enable row level security;

-- اسم الشركة: الجميع يقرأ، الإدارة تعدّل
create policy org_read  on public.org_settings for select to authenticated using (true);
create policy org_write on public.org_settings for update to authenticated
  using (public.is_manager()) with check (public.is_manager());

-- الجداول المرجعية: الجميع يقرأ، الإدارة تكتب
create policy dep_read  on public.departments for select to authenticated using (true);
create policy dep_write on public.departments for all    to authenticated
  using (public.is_manager()) with check (public.is_manager());

create policy prj_read  on public.projects for select to authenticated using (true);
create policy prj_write on public.projects for all    to authenticated
  using (public.is_manager()) with check (public.is_manager());

create policy pos_read  on public.positions for select to authenticated using (true);
create policy pos_write on public.positions for all    to authenticated
  using (public.is_manager()) with check (public.is_manager());

-- الموظفون: الإدارة ترى الجميع، والموظف يرى نفسه فقط (بهذا تُحمى الرواتب)
create policy emp_read  on public.employees for select to authenticated
  using (public.is_staff() or id = public.my_employee_id());
create policy emp_write on public.employees for all to authenticated
  using (public.is_manager()) with check (public.is_manager());

-- حسابات الدخول: كل مستخدم يرى حسابه، والمدير يرى ويعدّل الجميع
create policy prof_read  on public.profiles for select to authenticated
  using (id = auth.uid() or public.my_role() = 'admin');
create policy prof_write on public.profiles for all to authenticated
  using (public.my_role() = 'admin') with check (public.my_role() = 'admin');

-- المركبات
create policy veh_read  on public.vehicles for select to authenticated using (true);
create policy veh_write on public.vehicles for all    to authenticated
  using (public.is_manager()) with check (public.is_manager());

-- الإجازات
create policy lv_read on public.leaves for select to authenticated
  using (public.is_staff() or employee_id = public.my_employee_id());
create policy lv_ins  on public.leaves for insert to authenticated
  with check (public.is_staff() or employee_id = public.my_employee_id());
create policy lv_upd  on public.leaves for update to authenticated
  using (public.is_manager() or (employee_id = public.my_employee_id() and status = 'معلقة'))
  with check (public.is_manager() or (employee_id = public.my_employee_id() and status = 'معلقة'));
create policy lv_del  on public.leaves for delete to authenticated
  using (public.is_manager() or (employee_id = public.my_employee_id() and status = 'معلقة'));

-- التقارير اليومية
create policy dr_read on public.daily_reports for select to authenticated
  using (public.is_staff() or employee_id = public.my_employee_id());
create policy dr_ins  on public.daily_reports for insert to authenticated
  with check (public.is_staff() or employee_id = public.my_employee_id());
create policy dr_upd  on public.daily_reports for update to authenticated
  using (public.is_manager() or created_by = auth.uid())
  with check (public.is_manager() or created_by = auth.uid());
create policy dr_del  on public.daily_reports for delete to authenticated
  using (public.is_manager() or created_by = auth.uid());

-- العُهد: الصرف والتسوية للإدارة والمحاسبة، والموظف يرى عهدته
create policy cu_read  on public.custody for select to authenticated
  using (public.is_staff() or employee_id = public.my_employee_id());
create policy cu_write on public.custody for all to authenticated
  using (public.is_staff()) with check (public.is_staff());

-- مصروفات العُهد: الموظف يسجّل على عهدته المفتوحة
create policy cx_read on public.custody_expenses for select to authenticated
  using (public.is_staff() or exists (
    select 1 from public.custody c
     where c.id = custody_id and c.employee_id = public.my_employee_id()));
create policy cx_ins  on public.custody_expenses for insert to authenticated
  with check (public.is_staff() or exists (
    select 1 from public.custody c
     where c.id = custody_id and c.employee_id = public.my_employee_id()
       and c.status = 'مفتوحة'));
create policy cx_upd  on public.custody_expenses for update to authenticated
  using (public.is_staff() or created_by = auth.uid())
  with check (public.is_staff() or created_by = auth.uid());
create policy cx_del  on public.custody_expenses for delete to authenticated
  using (public.is_staff() or created_by = auth.uid());

-- سجل الأسطول
create policy fl_read  on public.fleet_log for select to authenticated using (true);
create policy fl_write on public.fleet_log for all    to authenticated
  using (public.is_staff()) with check (public.is_staff());

-- اعتماد الرواتب
create policy pa_read on public.payroll_approvals for select to authenticated
  using (public.my_role() in ('admin','hr','accountant'));
create policy pa_ins  on public.payroll_approvals for insert to authenticated
  with check (public.my_role() = 'admin');
create policy pa_del  on public.payroll_approvals for delete to authenticated
  using (public.my_role() = 'admin');


-- ════════════════════════════════════════════════════════════
--  الجزء الخامس: مساحة صور الفواتير
-- ════════════════════════════════════════════════════════════

insert into storage.buckets (id, name, public)
values ('receipts', 'receipts', false)
on conflict (id) do nothing;

drop policy if exists receipts_read  on storage.objects;
drop policy if exists receipts_write on storage.objects;
drop policy if exists receipts_del   on storage.objects;

create policy receipts_read  on storage.objects for select to authenticated
  using (bucket_id = 'receipts');
create policy receipts_write on storage.objects for insert to authenticated
  with check (bucket_id = 'receipts');
create policy receipts_del   on storage.objects for delete to authenticated
  using (bucket_id = 'receipts' and (public.is_staff() or owner = auth.uid()));


-- ════════════════════════════════════════════════════════════
--  الجزء السادس: بيانات البداية
-- ════════════════════════════════════════════════════════════

insert into public.departments (name) values
  ('الإدارة'), ('المالية'), ('التشغيل'), ('الصيانة'), ('النقل'), ('المستودع');

-- المناصب وصلاحياتها — عدّلها لاحقاً من شاشة الإعدادات داخل البرنامج
insert into public.positions (name, role) values
  ('مدير عام',             'admin'),
  ('محاسب',                'admin'),      -- بناءً على طلبك: المحاسب مدير للنظام
  ('مدير الموارد البشرية', 'hr'),
  ('مشرف موقع',            'employee'),
  ('فني',                  'employee'),
  ('سائق',                 'employee'),
  ('أمين مستودع',          'employee');


-- ════════════════════════════════════════════════════════════
--  تحقق: يجب أن تظهر 13 جدولاً
-- ════════════════════════════════════════════════════════════

select count(*) as "عدد الجداول"
  from information_schema.tables
 where table_schema = 'public' and table_type = 'BASE TABLE';

-- ============================================================================
--  الخطوة التالية بعد تشغيل هذا الملف:
--
--  1) Authentication → Sign In / Providers → Email
--       • Confirm email             = مطفأ
--       • Allow new users to sign up = مفعّل
--  2) افتح البرنامج → زر "أول تشغيل — إنشاء حساب المدير"
--       اكتب اسمك ورقم هويتك، وستدخل مباشرة بصلاحية مدير النظام.
--  3) بعد إنشاء حسابات كل الموظفين، أطفئ Allow new users to sign up.
-- ============================================================================
