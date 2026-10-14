-- shirim3 database schema (Supabase / Postgres)
-- All objects are prefixed with shirim3_ so they don't clash with other apps in the same project.
-- Run once in: Supabase Dashboard -> SQL Editor -> New query -> Run

-- ============ Shirt orders ============
create table if not exists public.shirim3_shirt_orders (
  id             bigint generated always as identity primary key,
  created_at     timestamptz not null default now(),
  full_name      text not null check (char_length(trim(full_name)) between 2 and 100),
  size           text not null check (size in ('XXXL','XXL','XL','L','M','S','18','16','14','12','10','8','6','4')),
  fabric         text not null check (fabric in ('דרייפיט','טריקו')),
  paid_claimed   boolean not null default false,  -- what the customer ticked on the form
  paid_verified  boolean not null default false,  -- admin sets this after checking PayBox
  notes          text
);

-- ============ Cake / cookie bakers ============
create table if not exists public.shirim3_cake_bakers (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  name        text not null check (char_length(trim(name)) between 2 and 100)
);

-- Enforce the 20-baker limit on the server (works across all visitors)
create or replace function public.shirim3_enforce_cake_limit()
returns trigger language plpgsql as $$
begin
  perform pg_advisory_xact_lock(42);  -- prevents two simultaneous inserts from both passing
  if (select count(*) from public.shirim3_cake_bakers) >= 20 then
    raise exception 'cake list is full (20/20)' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists shirim3_cake_limit_trigger on public.shirim3_cake_bakers;
create trigger shirim3_cake_limit_trigger
  before insert on public.shirim3_cake_bakers
  for each row execute function public.shirim3_enforce_cake_limit();

-- ============ Admin allow-list ============
-- Other apps in this project may have logged-in users too, so "authenticated" is NOT enough.
-- Only emails listed here can read/manage shirim3 data.
create table if not exists public.shirim3_admins (
  email text primary key
);
alter table public.shirim3_admins enable row level security;  -- no policies: not readable via the API

create or replace function public.shirim3_is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.shirim3_admins
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;
revoke all on function public.shirim3_is_admin() from public;
grant execute on function public.shirim3_is_admin() to anon, authenticated;

-- To add an admin (after creating that user in Authentication -> Users):
--   insert into public.shirim3_admins (email) values ('you@example.com');

-- ============ Row Level Security ============
alter table public.shirim3_shirt_orders enable row level security;
alter table public.shirim3_cake_bakers  enable row level security;

-- Visitors may ONLY add a shirt order. They cannot read other people's orders.
drop policy if exists "anon can insert shirt orders" on public.shirim3_shirt_orders;
create policy "anon can insert shirt orders"
  on public.shirim3_shirt_orders for insert to anon, authenticated
  with check (paid_verified = false);

drop policy if exists "admin can read shirt orders" on public.shirim3_shirt_orders;
create policy "admin can read shirt orders"
  on public.shirim3_shirt_orders for select to authenticated using (public.shirim3_is_admin());

drop policy if exists "admin can update shirt orders" on public.shirim3_shirt_orders;
create policy "admin can update shirt orders"
  on public.shirim3_shirt_orders for update to authenticated
  using (public.shirim3_is_admin()) with check (public.shirim3_is_admin());

drop policy if exists "admin can delete shirt orders" on public.shirim3_shirt_orders;
create policy "admin can delete shirt orders"
  on public.shirim3_shirt_orders for delete to authenticated using (public.shirim3_is_admin());

-- Cake list is public: anyone can see names and add themselves.
drop policy if exists "anyone can read bakers" on public.shirim3_cake_bakers;
create policy "anyone can read bakers"
  on public.shirim3_cake_bakers for select to anon, authenticated using (true);

drop policy if exists "anyone can add a baker" on public.shirim3_cake_bakers;
create policy "anyone can add a baker"
  on public.shirim3_cake_bakers for insert to anon, authenticated with check (true);

drop policy if exists "admin can update bakers" on public.shirim3_cake_bakers;
create policy "admin can update bakers"
  on public.shirim3_cake_bakers for update to authenticated
  using (public.shirim3_is_admin()) with check (public.shirim3_is_admin());

drop policy if exists "admin can delete bakers" on public.shirim3_cake_bakers;
create policy "admin can delete bakers"
  on public.shirim3_cake_bakers for delete to authenticated using (public.shirim3_is_admin());
