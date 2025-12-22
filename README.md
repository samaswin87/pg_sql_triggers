# PgTriggers

> **A PostgreSQL Trigger Control Plane for Rails**

Production-grade PostgreSQL trigger management for Rails with lifecycle management, safe deploys, versioning, drift detection, and a mountable UI.

## Why PgTriggers?

Rails teams use PostgreSQL triggers for data integrity, performance, billing logic, and audit enforcement. But triggers today are:

- Managed manually
- Invisible to Rails
- Unsafe to deploy
- Hard to audit
- Easy to drift

**PgTriggers** brings triggers into the Rails ecosystem with:

- Lifecycle management
- Safe deploys
- Versioning
- UI control
- Auditability
- Emergency SQL escape hatches

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'pg_triggers'
```

And then execute:

```bash
$ bundle install
```

Run the installer:

```bash
$ rails generate pg_triggers:install
$ rails db:migrate
```

This will:
1. Create an initializer at `config/initializers/pg_triggers.rb`
2. Create migrations for registry and audit tables
3. Mount the engine at `/pg_triggers`

## Usage

### 1. Declaring Triggers

Create trigger definitions using the Ruby DSL:

```ruby
# app/triggers/device_readings_guard.rb
PgTriggers::DSL.pg_trigger "rpm_device_readings_guard" do
  table :device_readings
  on :insert, :update
  function :validate_rpm_rules

  version 1
  enabled false

  when_env :production
end
```

### 2. Console Introspection

Access trigger information from the Rails console:

```ruby
# List all triggers
PgTriggers::Registry.list

# List enabled triggers
PgTriggers::Registry.enabled

# List disabled triggers
PgTriggers::Registry.disabled

# Get triggers for a specific table
PgTriggers::Registry.for_table(:device_readings)

# Check for drift
PgTriggers::Registry.diff

# Validate all triggers
PgTriggers::Registry.validate!
```

### 3. Web UI

Access the web UI at `http://localhost:3000/pg_triggers` to:

- View all triggers and their status
- Enable/disable triggers
- View drift states
- Execute SQL capsules
- Review audit logs
- Manage trigger lifecycle

### 4. Permissions

PgTriggers supports three permission levels:

- **Viewer**: Read-only access (view triggers, diffs, audit logs)
- **Operator**: Can enable/disable triggers, apply generated triggers
- **Admin**: Full access including dropping triggers and executing SQL

Configure custom permission checking:

```ruby
# config/initializers/pg_triggers.rb
PgTriggers.configure do |config|
  config.permission_checker = ->(actor, action, environment) {
    # Your custom permission logic
    user = User.find(actor[:id])
    user.has_permission?(action)
  }
end
```

### 5. Drift Detection

PgTriggers automatically detects drift between your DSL definitions and the actual database state:

- **Managed & In Sync**: Trigger matches DSL definition
- **Managed & Drifted**: Trigger exists but doesn't match DSL
- **Manual Override**: Trigger was modified outside of PgTriggers
- **Disabled**: Trigger is disabled
- **Dropped**: Trigger was dropped but still in registry
- **Unknown**: Trigger exists in DB but not in registry

### 6. Audit Logging

All trigger mutations are automatically logged:

```ruby
# View audit logs
PgTriggers::AuditLog.recent

# View logs for a specific trigger
PgTriggers::AuditLog.for_target("rpm_device_readings_guard")

# View failed operations
PgTriggers::AuditLog.failed
```

### 7. Production Kill Switch

By default, PgTriggers blocks destructive operations in production:

```ruby
# config/initializers/pg_triggers.rb
PgTriggers.configure do |config|
  # Enable production kill switch (default: true)
  config.kill_switch_enabled = true
end
```

Override for specific operations:

```ruby
PgTriggers::SQL.override_kill_switch do
  # Dangerous operation here
end
```

## Configuration

```ruby
# config/initializers/pg_triggers.rb
PgTriggers.configure do |config|
  # Kill switch for production (default: true)
  config.kill_switch_enabled = true

  # Environment detection (default: -> { Rails.env })
  config.default_environment = -> { Rails.env }

  # Custom permission checker
  config.permission_checker = ->(actor, action, environment) {
    # Return true/false based on your authorization logic
    true
  }
end
```

## Core Principles

- **Rails-native**: Works seamlessly with Rails conventions
- **Explicit over magic**: No automatic execution
- **Safe by default**: Requires explicit confirmation for destructive actions
- **Auditable always**: Every mutation is logged
- **Power with guardrails**: Emergency SQL escape hatches with safety checks

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/samaswin87/pg_triggers.
