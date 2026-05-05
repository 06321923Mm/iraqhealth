-- طلبات استحواذ الأطباء على عياداتهم — تنتظر موافقة الأدمن قبل الربط.

-- ─── الجدول ────────────────────────────────────────────────────────────────
create table if not exists public.clinic_claim_requests (
  id           uuid        primary key default gen_random_uuid(),
  doctor_id    integer     not null references public.doctors(id) on delete cascade,
  user_id      uuid        not null references auth.users(id) on delete cascade,
  clinic_name  text        not null default '',
  status       text        not null default 'pending'
                           check (status in ('pending', 'approved', 'rejected')),
  created_at   timestamptz not null default now(),
  reviewed_at  timestamptz
);

-- طلب معلّق واحد فقط لكل عيادة (يمنع تعارض الطلبات)
create unique index if not exists clinic_claim_requests_doctor_pending_idx
  on public.clinic_claim_requests (doctor_id)
  where status = 'pending';

-- طلب معلّق واحد فقط لكل مستخدم
create unique index if not exists clinic_claim_requests_user_pending_idx
  on public.clinic_claim_requests (user_id)
  where status = 'pending';

-- ─── RLS ───────────────────────────────────────────────────────────────────
alter table public.clinic_claim_requests enable row level security;

-- المستخدم المصادق يرى طلباته فقط
create policy "auth user sees own requests"
  on public.clinic_claim_requests for select
  to authenticated
  using (user_id = auth.uid());

-- المستخدم يرسل طلباً باسمه
create policy "auth user inserts own request"
  on public.clinic_claim_requests for insert
  to authenticated
  with check (user_id = auth.uid());

-- المستخدم يلغي طلبه المعلّق فقط
create policy "auth user cancels own pending"
  on public.clinic_claim_requests for delete
  to authenticated
  using (user_id = auth.uid() and status = 'pending');

-- الأدمن (anon) يرى جميع الطلبات ويحدّث حالتها
create policy "anon admin sees all"
  on public.clinic_claim_requests for select
  to anon using (true);

create policy "anon admin updates status"
  on public.clinic_claim_requests for update
  to anon
  using (true)
  with check (status in ('pending', 'approved', 'rejected'));

-- ─── الصلاحيات ─────────────────────────────────────────────────────────────
grant select, insert, delete
  on public.clinic_claim_requests to authenticated;

grant select, update (status, reviewed_at)
  on public.clinic_claim_requests to anon;

-- ─── Trigger: الموافقة تربط العيادة تلقائياً ──────────────────────────────
create or replace function public.approve_clinic_claim()
returns trigger language plpgsql security definer as $$
begin
  if new.status = 'approved' and old.status = 'pending' then
    update public.doctors
      set owner_user_id = new.user_id
      where id = new.doctor_id
        and (owner_user_id is null or owner_user_id = new.user_id);
    new.reviewed_at = now();
  elsif new.status = 'rejected' and old.status = 'pending' then
    new.reviewed_at = now();
  end if;
  return new;
end $$;

create trigger trg_approve_clinic_claim
  before update of status on public.clinic_claim_requests
  for each row execute function public.approve_clinic_claim();
