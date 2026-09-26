-- ============================================================================
--  ١) حذف الرواتب والبدلات من قاعدة البيانات
--  ٢) سجل الوقت الإضافي والخصم — بالساعة أو باليوم
--
--  من يرى ومن يسجّل:
--    مدير النظام والموارد البشرية والمحاسب — كل الموظفين
--    مدير القسم                            — موظفو قسمه وحدهم
--    الموظف                                 — سجلّه هو فقط، قراءة بلا تعديل
--
--  الصقه في:  Supabase → SQL Editor → New query → Run
--  آمن لإعادة التشغيل أكثر من مرة.
-- ============================================================================


-- ── ١) حذف عمودَي الراتب والبدلات ────────────────────────────────────
--  تحذير: هذا يمحو القيم المخزَّنة فيهما نهائياً.

alter table public.employees drop column if exists salary;
alter table public.employees drop column if exists allowance;

-- إعادة بناء منفذ مدير القسم بعد تغيير جدول الموظفين
drop view if exists public.team_members;

create view public.team_members
with (security_invoker = off) as
  select e.id, e.name, e.national_id, e.position_id, e.department_id,
         e.nationality, e.phone, e.iqama_expiry, e.passport_expiry, e.active
    from public.employees e
   where public.is_supervisor()
     and public.my_department_id() is not null
     and e.department_id = public.my_department_id();

grant select on public.team_members to authenticated;


-- ── ٢) جدول الإضافي والخصم ──────────────────────────────────────────
--  qty = المقدار، و unit يحدد أهو ساعات أم أيام.

create table if not exists public.time_adjustments (
  id          uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  kind        text not null check (kind in ('إضافي','خصم')),
  unit        text not null check (unit in ('ساعة','يوم')),
  qty         numeric(8,2) not null check (qty > 0),
  date        date not null default current_date,
  note        text,
  created_by  uuid default auth.uid() references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);

create index if not exists ix_ta_emp   on public.time_adjustments(employee_id);
create index if not exists ix_ta_date  on public.time_adjustments(date);

alter table public.time_adjustments enable row level security;

drop policy if exists ta_read  on public.time_adjustments;
drop policy if exists ta_write on public.time_adjustments;

-- القراءة: الإدارة كلها، ومدير القسم لقسمه، والموظف لنفسه
create policy ta_read on public.time_adjustments for select to authenticated
  using (public.is_staff()
      or employee_id = public.my_employee_id()
      or (public.is_supervisor() and public.in_my_dept(employee_id)));

-- التسجيل والتعديل والحذف: الإدارة، ومدير القسم داخل قسمه فقط
create policy ta_write on public.time_adjustments for all to authenticated
  using (public.is_staff()
      or (public.is_supervisor() and public.in_my_dept(employee_id)))
  with check (public.is_staff()
      or (public.is_supervisor() and public.in_my_dept(employee_id)));


-- ============================================================================
--  للتحقق
-- ============================================================================
select column_name as "العمود"
  from information_schema.columns
 where table_schema = 'public' and table_name = 'employees'
 order by ordinal_position;
