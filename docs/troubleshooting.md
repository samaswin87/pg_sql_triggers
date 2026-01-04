# Troubleshooting Guide

Common issues and solutions for PgSqlTriggers.

## Table of Contents

- [Installation Issues](#installation-issues)
- [Permission Errors](#permission-errors)
- [Kill Switch Errors](#kill-switch-errors)
- [Drift Detection Issues](#drift-detection-issues)
- [Migration Problems](#migration-problems)
- [UI Issues](#ui-issues)
- [Performance Issues](#performance-issues)
- [Error Codes Reference](#error-codes-reference)

## Installation Issues

### Migration Errors

**Problem**: Migrations fail during installation.

**Solutions**:
1. Ensure PostgreSQL is running and accessible
2. Check database connection in `config/database.yml`
3. Verify you have sufficient database permissions
4. Check migration logs for specific errors

```bash
# Check database connection
rails db:version

# Run migrations with verbose output
rails db:migrate VERBOSE=true
```

### Initializer Not Loading

**Problem**: Configuration not being applied.

**Solutions**:
1. Restart Rails server after changing initializer
2. Check for syntax errors in `config/initializers/pg_sql_triggers.rb`
3. Verify the file is being loaded (check Rails logs)

```ruby
# Test configuration
rails console
> PgSqlTriggers.kill_switch_enabled
```

### Web UI Not Accessible

**Problem**: Cannot access web UI at `/pg_sql_triggers`.

**Solutions**:
1. Verify engine is mounted in `config/routes.rb`:
   ```ruby
   mount PgSqlTriggers::Engine, at: "/pg_sql_triggers"
   ```
2. Restart Rails server
3. Check for route conflicts
4. Verify database tables exist

## Permission Errors

### Permission Denied Errors

**Problem**: `PermissionError` with code `PERMISSION_DENIED`.

**Error Message**: "Permission denied: [action] requires [role] level access"

**Solutions**:
1. **Check permission configuration**:
   ```ruby
   # Verify permission checker is configured
   PgSqlTriggers.permission_checker # Should not be nil
   ```

2. **Verify actor format**:
   ```ruby
   # In your controller
   def current_actor
     {
       type: current_user.class.name,
       id: current_user.id.to_s,
       role: current_user.role  # Ensure role is included
     }
   end
   ```

3. **Check required role for action**:
   - Viewer: `view_triggers`, `view_diffs`
   - Operator: `enable_trigger`, `disable_trigger`, `apply_trigger`
   - Admin: `drop_trigger`, `execute_sql`, `override_drift`

4. **Review permission checker logic**:
   ```ruby
   config.permission_checker = ->(actor, action, environment) {
     # Debug: add logging
     Rails.logger.debug "Checking permission: #{action} for #{actor}"
     # Your permission logic
   }
   ```

### All Users Have Full Access

**Problem**: Permissions are not being enforced.

**Solutions**:
1. **Configure permission checker** (default is permissive):
   ```ruby
   PgSqlTriggers.configure do |config|
     config.permission_checker = ->(actor, action, environment) {
       # Your permission logic
     }
   end
   ```

2. **Verify in production**: Default allows all permissions for development convenience

### UI Buttons Hidden

**Problem**: Action buttons are not visible in UI.

**Solutions**:
1. Check your permission level (Viewer/Operator/Admin)
2. Verify `current_actor` method returns correct role
3. Check browser console for JavaScript errors
4. Review permission helper methods in views

## Kill Switch Errors

### Operation Blocked by Kill Switch

**Problem**: `KillSwitchError` with code `KILL_SWITCH_ACTIVE`.

**Error Message**: "Kill switch is active for [environment] environment"

**Solutions**:
1. **Provide confirmation text**:
   ```bash
   # CLI/rake tasks
   KILL_SWITCH_OVERRIDE=true CONFIRMATION_TEXT="EXECUTE OPERATION_NAME" rake your:task
   
   # Console
   PgSqlTriggers::SQL::KillSwitch.override(confirmation: "EXECUTE OPERATION_NAME") do
     # your operation
   end
   ```

2. **UI operations**: Enter confirmation text in the modal

3. **Check expected confirmation format**:
   ```ruby
   # Default pattern
   "EXECUTE #{operation.to_s.upcase}"
   
   # Check your configuration
   PgSqlTriggers.kill_switch_confirmation_pattern.call(:trigger_enable)
   ```

### Invalid Confirmation Text

**Problem**: `KillSwitchError` with code `KILL_SWITCH_CONFIRMATION_INVALID`.

**Error Message**: "Invalid confirmation text. Expected: '[expected]', got: '[provided]'"

**Solutions**:
1. Use exact confirmation text (case-sensitive)
2. Check confirmation pattern configuration
3. Verify no extra whitespace
4. Use the exact format shown in error message

### Kill Switch Not Working

**Problem**: Operations execute even with kill switch enabled.

**Solutions**:
1. **Verify kill switch is enabled**:
   ```ruby
   PgSqlTriggers.kill_switch_enabled # Should be true
   ```

2. **Check protected environments**:
   ```ruby
   PgSqlTriggers.kill_switch_environments # Should include current environment
   ```

3. **Verify environment detection**:
   ```ruby
   PgSqlTriggers.default_environment.call # Should match your environment
   ```

## Drift Detection Issues

### False Drift Detections

**Problem**: Triggers show as drifted when they are not.

**Solutions**:
1. **Re-run drift detection**:
   ```ruby
   PgSqlTriggers::Drift.detect("trigger_name")
   ```

2. **Check function body formatting**: Whitespace differences can cause drift

3. **Verify trigger definition**: Ensure DSL matches database state

4. **Use re-execute**: If drift is expected, use re-execute to sync

### Drift Not Detected

**Problem**: Manual changes not detected as drift.

**Solutions**:
1. Run drift detection manually:
   ```ruby
   PgSqlTriggers::Drift.detect("trigger_name")
   ```

2. Check drift state:
   ```ruby
   trigger = PgSqlTriggers::TriggerRegistry.find_by(trigger_name: "trigger_name")
   trigger.drift_state
   ```

3. Verify database trigger exists and matches definition

### Unknown Drift State

**Problem**: Drift state shows as "unknown".

**Solutions**:
1. **Check database connection**: Verify PostgreSQL is accessible
2. **Verify trigger exists in database**: Check `pg_trigger` system catalog
3. **Check function exists**: Verify function is in `pg_proc`
4. **Review error logs**: Check Rails logs for drift detection errors

## Migration Problems

### Migration Fails to Apply

**Problem**: Migration fails with SQL errors.

**Solutions**:
1. **Check SQL syntax**: Validate function and trigger SQL
2. **Verify table exists**: Ensure target table exists
3. **Check dependencies**: Ensure required functions exist
4. **Review error message**: Check Rails logs for specific SQL error

```bash
# Run migration with verbose output
rake trigger:migrate VERBOSE=true
```

### Unsafe Migration Error

**Problem**: `UnsafeMigrationError` with code `UNSAFE_MIGRATION`.

**Error Message**: "Migration contains unsafe DROP + CREATE operations"

**Solutions**:
1. **Use CREATE OR REPLACE** (for functions):
   ```sql
   -- Instead of:
   DROP FUNCTION my_function();
   CREATE FUNCTION my_function() ...
   
   -- Use:
   CREATE OR REPLACE FUNCTION my_function() ...
   ```

2. **Allow unsafe migrations** (if intentional):
   ```ruby
   PgSqlTriggers.configure do |config|
     config.allow_unsafe_migrations = true
   end
   ```

3. **Use kill switch override** for specific migrations

### Migration Version Conflicts

**Problem**: Migration version already exists or not found.

**Solutions**:
1. **Check migration status**:
   ```ruby
   PgSqlTriggers::Migrator.status
   ```

2. **Verify migration files**: Check `db/triggers/` directory

3. **Check registry table**: Verify migration versions in database

## UI Issues

### Buttons Not Working

**Problem**: Action buttons don't respond to clicks.

**Solutions**:
1. Check browser console for JavaScript errors
2. Verify CSRF token is present
3. Check network tab for failed requests
4. Ensure JavaScript is enabled
5. Clear browser cache

### Error Messages Not Displaying

**Problem**: Errors occur but not shown in UI.

**Solutions**:
1. Check flash messages are being set
2. Verify error handling in controllers
3. Check browser console for JavaScript errors
4. Review Rails logs for actual errors

### Slow UI Performance

**Problem**: Dashboard or pages load slowly.

**Solutions**:
1. **Check database performance**: Add indexes if needed
2. **Limit result sets**: Use pagination
3. **Review drift detection**: Drift detection can be slow for many triggers
4. **Check audit log size**: Large audit logs can slow queries

### Audit Log Not Loading

**Problem**: Audit log page fails to load or is empty.

**Solutions**:
1. Verify audit log table exists:
   ```bash
   rails db:migrate
   ```

2. Check for audit log entries:
   ```ruby
   PgSqlTriggers::AuditLog.count
   ```

3. Review controller logs for errors
4. Check database connection

## Performance Issues

### Slow Drift Detection

**Problem**: Drift detection takes too long.

**Solutions**:
1. **Batch detection**: Don't detect drift for all triggers at once
2. **Cache results**: Store drift state in registry
3. **Optimize queries**: Review database query performance
4. **Limit triggers checked**: Only check triggers that changed

### Large Audit Log Table

**Problem**: Audit log queries are slow.

**Solutions**:
1. **Add indexes**:
   ```ruby
   # Migration
   add_index :pg_sql_triggers_audit_log, :trigger_name
   add_index :pg_sql_triggers_audit_log, :operation
   add_index :pg_sql_triggers_audit_log, :created_at
   add_index :pg_sql_triggers_audit_log, :status
   ```

2. **Archive old logs**: Implement retention policy
3. **Use pagination**: Limit results per page
4. **Filter aggressively**: Use filters to reduce result set

### Registry Table Performance

**Problem**: Registry queries are slow.

**Solutions**:
1. **Add indexes**: Ensure indexes on frequently queried columns
2. **Limit triggers**: Consider partitioning if you have many triggers
3. **Optimize queries**: Review query plans
4. **Cache frequently accessed data**: Store in memory cache

## Error Codes Reference

### Kill Switch Errors

- **`KILL_SWITCH_ACTIVE`**: Kill switch is blocking operation
  - Solution: Provide confirmation text to override

- **`KILL_SWITCH_CONFIRMATION_REQUIRED`**: Confirmation text is required
  - Solution: Provide confirmation text

- **`KILL_SWITCH_CONFIRMATION_INVALID`**: Confirmation text doesn't match
  - Solution: Use exact confirmation text format

### Permission Errors

- **`PERMISSION_DENIED`**: User doesn't have required permission
  - Solution: Request appropriate role or configure permissions

### Validation Errors

- **`VALIDATION_FAILED`**: Input validation failed
  - Solution: Review error message for specific field issues

### Execution Errors

- **`EXECUTION_FAILED`**: SQL execution failed
  - Solution: Check SQL syntax and database state

### Migration Errors

- **`UNSAFE_MIGRATION`**: Migration contains unsafe operations
  - Solution: Use CREATE OR REPLACE or allow unsafe migrations

- **`TRIGGER_NOT_FOUND`**: Trigger not found in registry
  - Solution: Verify trigger name or create trigger first

### Drift Errors

- **`DRIFT_DETECTED`**: Trigger has drifted from definition
  - Solution: Run migration or re-execute trigger

## Getting Help

### Debug Mode

Enable verbose logging:

```ruby
# In initializer or console
Rails.logger.level = Logger::DEBUG
```

### Check Logs

Review Rails logs for detailed error information:

```bash
# Development
tail -f log/development.log

# Production
tail -f log/production.log
```

### Common Debugging Steps

1. **Verify configuration**:
   ```ruby
   rails console
   > PgSqlTriggers.kill_switch_enabled
   > PgSqlTriggers.permission_checker
   ```

2. **Check database state**:
   ```ruby
   > PgSqlTriggers::TriggerRegistry.count
   > PgSqlTriggers::AuditLog.count
   ```

3. **Test permissions**:
   ```ruby
   > actor = { type: "User", id: "1", role: "admin" }
   > PgSqlTriggers::Permissions.can?(actor, :drop_trigger)
   ```

4. **Verify trigger state**:
   ```ruby
   > trigger = PgSqlTriggers::TriggerRegistry.first
   > trigger.drift_state
   > trigger.enabled?
   ```

## Related Documentation

- [Configuration Reference](configuration.md) - Configuration options
- [Permissions Guide](permissions.md) - Permission system details
- [Kill Switch Guide](kill-switch.md) - Kill switch configuration
- [API Reference](api-reference.md) - Console API methods

