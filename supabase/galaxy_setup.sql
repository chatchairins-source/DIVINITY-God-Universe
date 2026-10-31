-- DIVINITY Galaxy v1: apply ONLY to a NEW dedicated DIVINITY Supabase project.
-- Never apply to QueueTech/QueueGo production.
-- Players come exclusively from auth.users. One account = one planet.
-- All credits, ore, energy, fleet, shields, trade and combat are server authoritative.
create table if not exists public.galaxy_planets (
  owner_id uuid primary key references auth.users(id) on delete cascade,
  planet_name text not null check (char_length(planet_name) between 2 and 32),
  x integer not null check (x between 0 and 1000),
  y integer not null check (y between 0 and 700),
  last_seen_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists galaxy_planets_presence_idx on public.galaxy_planets(last_seen_at desc);
create table if not exists public.galaxy_wallets (
  owner_id uuid primary key references public.galaxy_planets(owner_id) on delete cascade,
  credits bigint not null default 1000 check (credits >= 0),
  ore bigint not null default 150 check (ore >= 0),
  energy bigint not null default 150 check (energy >= 0),
  fleet_level integer not null default 1 check (fleet_level between 1 and 10),
  shield_level integer not null default 1 check (shield_level between 1 and 10)
);
create table if not exists public.galaxy_trades (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public.galaxy_planets(owner_id) on delete cascade,
  buyer_id uuid not null references public.galaxy_planets(owner_id) on delete cascade,
  ore_amount integer not null check (ore_amount between 1 and 100),
  credit_price integer not null check (credit_price between 1 and 10000),
  status text not null default 'pending' check (status in ('pending','accepted','declined','cancelled')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  check(seller_id <> buyer_id)
);
create index if not exists galaxy_trades_parties_idx on public.galaxy_trades(seller_id,buyer_id,created_at desc);
create table if not exists public.galaxy_wars (
  id uuid primary key default gen_random_uuid(),
  attacker_id uuid not null references public.galaxy_planets(owner_id) on delete cascade,
  defender_id uuid not null references public.galaxy_planets(owner_id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','attacker_won','defender_won','declined','cancelled')),
  attacker_power integer,
  defender_power integer,
  winner_id uuid references public.galaxy_planets(owner_id),
  credits_transferred integer not null default 0,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  check(attacker_id <> defender_id)
);
create index if not exists galaxy_wars_parties_idx on public.galaxy_wars(attacker_id,defender_id,created_at desc);

alter table public.galaxy_planets enable row level security;
alter table public.galaxy_wallets enable row level security;
alter table public.galaxy_trades enable row level security;
alter table public.galaxy_wars enable row level security;

drop policy if exists "galaxy authenticated planet directory" on public.galaxy_planets;
create policy "galaxy authenticated planet directory" on public.galaxy_planets for select to authenticated using (true);
drop policy if exists "galaxy own wallet" on public.galaxy_wallets;
create policy "galaxy own wallet" on public.galaxy_wallets for select to authenticated using (owner_id = (select auth.uid()));
drop policy if exists "galaxy trade parties" on public.galaxy_trades;
create policy "galaxy trade parties" on public.galaxy_trades for select to authenticated
 using (seller_id = (select auth.uid()) or buyer_id = (select auth.uid()));
drop policy if exists "galaxy war parties" on public.galaxy_wars;
create policy "galaxy war parties" on public.galaxy_wars for select to authenticated
 using (attacker_id = (select auth.uid()) or defender_id = (select auth.uid()));

revoke all on public.galaxy_planets,public.galaxy_wallets,public.galaxy_trades,public.galaxy_wars from anon,authenticated;
grant select on public.galaxy_planets,public.galaxy_wallets,public.galaxy_trades,public.galaxy_wars to authenticated;

create or replace function public.galaxy_register(p_name text)
returns public.galaxy_planets language plpgsql security definer set search_path = ''
as $$
declare u uuid := auth.uid(); result public.galaxy_planets;
begin
  if u is null then raise exception 'LOGIN_REQUIRED'; end if;
  if char_length(btrim(coalesce(p_name,''))) not between 2 and 32 then raise exception 'INVALID_PLANET_NAME'; end if;
  insert into public.galaxy_planets(owner_id,planet_name,x,y,last_seen_at)
    values(u,btrim(p_name),floor(random()*950+25)::int,floor(random()*620+40)::int,now())
    on conflict(owner_id) do nothing;
  insert into public.galaxy_wallets(owner_id) values(u) on conflict(owner_id) do nothing;
  select * into result from public.galaxy_planets where owner_id=u;
  return result;
end $$;

create or replace function public.galaxy_heartbeat()
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'LOGIN_REQUIRED'; end if;
  update public.galaxy_planets set last_seen_at=now() where owner_id=auth.uid();
  if not found then raise exception 'REGISTER_PLANET_FIRST'; end if;
end $$;

create or replace function public.galaxy_create_trade(p_buyer uuid,p_ore integer,p_credits integer)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare u uuid := auth.uid(); trade_id uuid;
begin
  if u is null then raise exception 'LOGIN_REQUIRED'; end if;
  if p_buyer is null or p_buyer=u or p_ore not between 1 and 100 or p_credits not between 1 and 10000
    then raise exception 'INVALID_TRADE'; end if;
  if not exists(select 1 from public.galaxy_planets where owner_id=p_buyer and last_seen_at>now()-interval '2 minutes')
    then raise exception 'BUYER_NOT_ONLINE'; end if;
  update public.galaxy_wallets set ore=ore-p_ore where owner_id=u and ore>=p_ore;
  if not found then raise exception 'INSUFFICIENT_ORE'; end if;
  insert into public.galaxy_trades(seller_id,buyer_id,ore_amount,credit_price)
    values(u,p_buyer,p_ore,p_credits) returning id into trade_id;
  return trade_id;
end $$;

create or replace function public.galaxy_respond_trade(p_id uuid,p_accept boolean)
returns text language plpgsql security definer set search_path = ''
as $$
declare u uuid:=auth.uid(); item public.galaxy_trades;
begin
  if u is null then raise exception 'LOGIN_REQUIRED'; end if;
  select * into item from public.galaxy_trades where id=p_id for update;
  if not found or item.status<>'pending' then raise exception 'TRADE_NOT_PENDING'; end if;
  if u<>item.buyer_id and u<>item.seller_id then raise exception 'NOT_YOUR_TRADE'; end if;
  if p_accept and u<>item.buyer_id then raise exception 'ONLY_BUYER_ACCEPTS'; end if;
  if p_accept then
    -- Lock both wallets in consistent order to avoid concurrent trade deadlocks.
    perform 1 from public.galaxy_wallets where owner_id in(item.seller_id,item.buyer_id) order by owner_id for update;
    update public.galaxy_wallets set credits=credits-item.credit_price
      where owner_id=item.buyer_id and credits>=item.credit_price;
    if not found then raise exception 'BUYER_INSUFFICIENT_CREDITS'; end if;
    update public.galaxy_wallets set credits=credits+item.credit_price where owner_id=item.seller_id;
    update public.galaxy_wallets set ore=ore+item.ore_amount where owner_id=item.buyer_id;
    update public.galaxy_trades set status='accepted',resolved_at=now() where id=p_id;
    return 'accepted';
  end if;
  update public.galaxy_wallets set ore=ore+item.ore_amount where owner_id=item.seller_id;
  update public.galaxy_trades set status=case when u=item.seller_id then 'cancelled' else 'declined' end,
    resolved_at=now() where id=p_id;
  return 'declined';
end $$;

create or replace function public.galaxy_upgrade(p_kind text)
returns text language plpgsql security definer set search_path = ''
as $$
declare u uuid:=auth.uid(); wallet public.galaxy_wallets; target_level integer; price integer; ore_cost integer;
begin
  if u is null then raise exception 'LOGIN_REQUIRED'; end if;
  if p_kind not in ('fleet','shield') then raise exception 'INVALID_UPGRADE'; end if;
  select * into wallet from public.galaxy_wallets where owner_id=u for update;
  if not found then raise exception 'REGISTER_PLANET_FIRST'; end if;
  target_level:=case when p_kind='fleet' then wallet.fleet_level else wallet.shield_level end;
  if target_level>=10 then raise exception 'MAX_LEVEL'; end if;
  price:=100*target_level;ore_cost:=20*target_level;
  if wallet.credits<price or wallet.ore<ore_cost then raise exception 'INSUFFICIENT_RESOURCES'; end if;
  if p_kind='fleet' then
    update public.galaxy_wallets set fleet_level=fleet_level+1,credits=credits-price,ore=ore-ore_cost where owner_id=u;
  else
    update public.galaxy_wallets set shield_level=shield_level+1,credits=credits-price,ore=ore-ore_cost where owner_id=u;
  end if;
  return p_kind;
end $$;

create or replace function public.galaxy_create_war(p_defender uuid)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare u uuid:=auth.uid(); war_id uuid;
begin
  if u is null then raise exception 'LOGIN_REQUIRED'; end if;
  if p_defender is null or p_defender=u then raise exception 'INVALID_TARGET'; end if;
  if not exists(select 1 from public.galaxy_planets where owner_id=p_defender
     and last_seen_at>now()-interval '2 minutes') then raise exception 'DEFENDER_NOT_ONLINE'; end if;
  if exists(select 1 from public.galaxy_wars where attacker_id=u
     and created_at>now()-interval '2 hours') then raise exception 'WAR_COOLDOWN_2_HOURS'; end if;
  update public.galaxy_wallets set energy=energy-30 where owner_id=u and energy>=30;
  if not found then raise exception 'NEED_30_ENERGY'; end if;
  insert into public.galaxy_wars(attacker_id,defender_id) values(u,p_defender)
    returning id into war_id;
  return war_id;
end $$;

create or replace function public.galaxy_respond_war(p_id uuid,p_accept boolean)
returns text language plpgsql security definer set search_path = ''
as $$
declare u uuid:=auth.uid(); item public.galaxy_wars; a integer; d integer; victor uuid; loser uuid;
  available bigint; prize integer;
begin
  if u is null then raise exception 'LOGIN_REQUIRED'; end if;
  select * into item from public.galaxy_wars where id=p_id for update;
  if not found or item.status<>'pending' then raise exception 'WAR_NOT_PENDING'; end if;
  if u<>item.defender_id and u<>item.attacker_id then raise exception 'NOT_YOUR_WAR'; end if;
  if p_accept and u<>item.defender_id then raise exception 'ONLY_DEFENDER_ACCEPTS'; end if;
  if not p_accept then
    update public.galaxy_wallets set energy=energy+30 where owner_id=item.attacker_id;
    update public.galaxy_wars set status=case when u=item.attacker_id then 'cancelled' else 'declined' end,
      resolved_at=now() where id=p_id;
    return 'declined';
  end if;
  perform 1 from public.galaxy_wallets where owner_id in(item.attacker_id,item.defender_id)
    order by owner_id for update;
  update public.galaxy_wallets set energy=energy-20
    where owner_id=item.defender_id and energy>=20;
  if not found then raise exception 'DEFENDER_NEEDS_20_ENERGY'; end if;
  select fleet_level*10+floor(random()*12)::int into a from public.galaxy_wallets
    where owner_id=item.attacker_id;
  select shield_level*10+floor(random()*12)::int into d from public.galaxy_wallets
    where owner_id=item.defender_id;
  victor:=case when a>d then item.attacker_id else item.defender_id end;
  loser:=case when victor=item.attacker_id then item.defender_id else item.attacker_id end;
  select credits into available from public.galaxy_wallets where owner_id=loser;
  prize:=least(available,20)::integer;
  update public.galaxy_wallets set credits=credits-prize where owner_id=loser;
  update public.galaxy_wallets set credits=credits+prize where owner_id=victor;
  update public.galaxy_wars set attacker_power=a,defender_power=d,winner_id=victor,
    credits_transferred=prize,
    status=case when victor=item.attacker_id then 'attacker_won' else 'defender_won' end,
    resolved_at=now() where id=p_id;
  return case when victor=item.attacker_id then 'attacker_won' else 'defender_won' end;
end $$;

revoke all on function public.galaxy_register(text), public.galaxy_heartbeat(),
 public.galaxy_create_trade(uuid,integer,integer), public.galaxy_respond_trade(uuid,boolean),
 public.galaxy_upgrade(text), public.galaxy_create_war(uuid), public.galaxy_respond_war(uuid,boolean)
 from public,anon;
grant execute on function public.galaxy_register(text), public.galaxy_heartbeat(),
 public.galaxy_create_trade(uuid,integer,integer), public.galaxy_respond_trade(uuid,boolean),
 public.galaxy_upgrade(text), public.galaxy_create_war(uuid), public.galaxy_respond_war(uuid,boolean)
 to authenticated;
