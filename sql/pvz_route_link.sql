-- Маршруты для этикеток берём из СУЩЕСТВУЮЩЕЙ таблицы public.pvz_locations:
-- в ней уже есть колонка route_number, заполненная для нужных ПВЗ
-- (например ТАШ-46 → 6, АКК-1 → 165). Отдельная таблица не нужна.
--
-- Здесь только: (1) доступ приложения на чтение справочника — обязательно для
-- подстановки маршрута на этикетку; (2)–(3) опционально — перенос маршрута в
-- customer_orders, чтобы дашборд/поиск/RPC тоже его показывали.
-- Запускать в Supabase SQL Editor. Идемпотентно.

-- 1. Доступ на чтение pvz_locations из приложения.
--    Политику создаём всегда; RLS НЕ переключаем, чтобы не задеть запись
--    (импорт ПВЗ). Если RLS на таблице выключен — политика просто неактивна.
grant select on public.pvz_locations to anon, authenticated;
drop policy if exists pvz_locations_read on public.pvz_locations;
create policy pvz_locations_read on public.pvz_locations for select using (true);

-- 2. (опционально) Бэкфилл маршрута в уже существующие заказы по коду ПВЗ.
--    Только там, где маршрут ещё не проставлен — ничего не перезатираем.
update public.customer_orders co
set route_number = pl.route_number
from public.pvz_locations pl
where upper(btrim(co.pvz_code)) = upper(btrim(pl.code))
  and pl.route_number is not null
  and co.route_number is null;

-- 3. (опционально) Автозаполнение маршрута для новых/изменённых заказов.
create or replace function public.set_order_route_from_pvz()
returns trigger
language plpgsql
as $$
begin
  if new.pvz_code is not null and new.route_number is null then
    select pl.route_number into new.route_number
    from public.pvz_locations pl
    where upper(btrim(pl.code)) = upper(btrim(new.pvz_code))
      and pl.route_number is not null
    limit 1;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_set_order_route_from_pvz on public.customer_orders;
create trigger trg_set_order_route_from_pvz
  before insert or update of pvz_code on public.customer_orders
  for each row execute function public.set_order_route_from_pvz();
