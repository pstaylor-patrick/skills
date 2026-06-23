---
name: stack:rails
description: Rails conventions for PST projects -- MVC structure, ActiveRecord, service objects.
---

# Rails Stack Module

Depends on: `ruby` (auto-activated).

## Structure

- Thin controllers. No business logic in controllers.
- Fat models only for persistence logic. No domain logic in models.
- Service objects in `app/services/`. One public method (`call` or a domain verb). Plain Ruby classes.
- No callbacks for side effects (`after_create` that sends email). Use service objects.

## ActiveRecord

- Scopes named for their intent, not their SQL: `.active` not `.where_status_is_1`.
- Add DB indexes for every foreign key and every column used in a `WHERE` clause.
- Eager-load associations in controllers: `includes(:association)` to prevent N+1.
- Never `find_by!` in controllers without rescuing `ActiveRecord::RecordNotFound`.

## API responses

- Use `render json:` with explicit status. Never rely on default 200.
- Serialize with a dedicated serializer class (ActiveModel::Serializers or equivalent), not `to_json` with `only:`.

## Testing

- RSpec + FactoryBot. Traits over multiple factories for the same model.
- No fixtures. No `create` in unit tests when `build` suffices.
- Request specs for API endpoints. No controller specs.
