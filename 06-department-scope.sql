-- ============================================================================
--  صلاحية "مدير قسم" — يرى قسمه وحده
--
--  الموارد البشرية والمالية: كل الموظفين بما فيهم مدراء الأقسام.
--  مدير القسم: كل من في قسمه — بياناتهم ووثائقهم وإجازاتهم وعهدهم وتقاريرهم،
--              بلا رواتب ولا بدلات ولا آيبان.
--  الموظف: نفسه فقط.
--
--  الصقه في:  Supabase → SQL Editor → New query → Run
--  آمن لإعادة التشغيل أكثر من مرة.
-- ============================================================================

-- ── 1) إضافة الصلاحية الجديدة لقائمة الصلاحيات المسموحة ──────────────

alter table public.positions drop constraint if exists positions_role_check;
alter table public.positions add  constraint positions_role_check
  check (role in ('admin','hr','accountant','supervisor','employee'));

alter table public.profiles  drop constraint if exists profiles_role_check;
alter table public.profiles  add  constraint profiles_role_check
  check (role in ('admin','hr','accountant','supervisor','employee'));


-- ── 2) دوال القسم ───────────────────────────────────────────────────

-- قسم المستخدم الحالي
create or replace function public.my_department_id() returns uuid
language sql stable security definer set search_path = public as $$
  select e.department_id
    from public.profiles p
    join public.employees e on e.id = p.employee_id
   where p.id = auth.uid()
$$;

-- هل المستخدم الحالي مدير قسم؟
create or replace function public.is_supervisor() returns boolean
language sql stable security definer set search_path = public as $$
  select public.my_role() = 'supervisor'
$$;

-- هل هذا الموظف في قسمي؟
create or replace function public.in_my_dept(p_emp uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.my_department_id() is not null
     and exists (select 1 from public.employees e
                  where e.id = p_emp
                    and e.department_id = public.my_department_id())
$$;

grant execute on function public.my_department_id() to authenticated;
grant execute on function public.is_supervisor()    to authenticated;
grant execute on function public.in_my_dept(uuid)   to authenticated;


-- ── 3) فريق مدير القسم: بلا أعمدة الرواتب ───────────────────────────
--  هذا المنفذ الوحيد الذي يرى منه مدير القسم فريقه، وهو لا يحمل
--  salary ولا allowance ولا iban أصلاً، فلا سبيل لقراءتها.

drop view if exists public.team_members;

create view public.team_members
with (security_invoker = off) as
  select e.id,
         e.name,
         e.national_id,
         e.position_id,
         e.department_id,
         e.nationality,
         e.phone,
         e.iqama_expiry,
         e.passport_expiry,
         e.active
    from public.employees e
   where public.is_supervisor()
     and public.my_department_id() is not null
     and e.department_id = public.my_department_id();

grant select on public.team_members to authenticated;


-- ── 4) الإجازات: مدير القسم يرى ويعتمد إجازات قسمه ──────────────────

drop policy if exists lv_read on public.leaves;
drop policy if exists lv_upd  on public.leaves;
drop policy if exists lv_del  on public.leaves;

create policy lv_read on public.leaves for select to authenticated
  using (public.is_staff()
      or employee_id = public.my_employee_id()
      or (public.is_supervisor() and public.in_my_dept(employee_id)));

create policy lv_upd on public.leaves for update to authenticated
  using (public.is_manager()
      or (public.is_supervisor() and public.in_my_dept(employee_id))
      or (employee_id = public.my_employee_id() and status = 'معلقة'))
  with check (public.is_manager()
      or (public.is_supervisor() and public.in_my_dept(employee_id))
      or (employee_id = public.my_employee_id() and status = 'معلقة'));

create policy lv_del on public.leaves for delete to authenticated
  using (public.is_manager()
      or (employee_id = public.my_employee_id() and status = 'معلقة'));


-- ── 5) التقارير اليومية: يرى تقارير قسمه ────────────────────────────

drop policy if exists dr_read on public.daily_reports;

create policy dr_read on public.daily_reports for select to authenticated
  using (public.is_staff()
      or employee_id = public.my_employee_id()
      or (public.is_supervisor() and public.in_my_dept(employee_id)));


-- ── 6) العُهد ومصروفاتها: يرى عهد قسمه ولا يصرف ولا يسوّي ───────────

drop policy if exists cu_read on public.custody;

create policy cu_read on public.custody for select to authenticated
  using (public.is_staff()
      or employee_id = public.my_employee_id()
      or (public.is_supervisor() and public.in_my_dept(employee_id)));

drop policy if exists cx_read on public.custody_expenses;

create policy cx_read on public.custody_expenses for select to authenticated
  using (public.is_staff()
      or exists (select 1 from public.custody c
                  where c.id = custody_id
                    and (c.employee_id = public.my_employee_id()
                     or (public.is_supervisor() and public.in_my_dept(c.employee_id)))));


-- ── 7) مناصب مدراء الأقسام ──────────────────────────────────────────
--  عدّلها أو أضف عليها من شاشة الإعدادات داخل البرنامج.

insert into public.positions (name, role) values
  ('مدير الصيانة', 'supervisor'),
  ('مدير التركيب', 'supervisor'),
  ('مدير التشغيل', 'supervisor')
on conflict (name) do update set role = 'supervisor';


-- ============================================================================
--  للتحقق — كل منصب وصلاحيته
-- ============================================================================
select name as "المنصب",
       case role when 'admin'      then 'مدير النظام'
                 when 'hr'         then 'موارد بشرية'
                 when 'accountant' then 'محاسب'
                 when 'supervisor' then 'مدير قسم'
                 else 'موظف' end as "الصلاحية"
  from public.positions
 order by role, name;

-- ============================================================================
--  كيف تجعل موظفاً مديراً لقسم:
--    1) في دليل الموظفين اختر له قسمه (الصيانة مثلاً)
--    2) واختر له منصباً صلاحيته "مدير قسم" (مدير الصيانة مثلاً)
--  القسم يحدد من يرى، والمنصب يحدد ماذا يستطيع.
-- ============================================================================
