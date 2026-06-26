with group_companies(name, code) as (
  values
    ('Cakes Haven Incorporation', 'CAKES_HAVEN'),
    ('Cakes and Occasions Corporation', 'CAKES_OCCASIONS'),
    ('Chatime', 'CHATIME'),
    ('Chawnah Foods INC.', 'CHAWNAH_FOODS'),
    ('DU99 7-Eleven', 'DU99_7_ELEVEN'),
    ('Fresh Berry Foods Corporation', 'FRESH_BERRY_FOODS'),
    ('Icebergs', 'ICEBERGS'),
    ('Taters', 'TATERS')
)
insert into public.companies (name, code, is_active)
select name, code, true
from group_companies
on conflict (code) do update
set
  name = excluded.name,
  is_active = true;

notify pgrst, 'reload schema';
