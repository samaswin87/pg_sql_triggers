# frozen_string_literal: true

module PgTriggers
  module Testing
    autoload :SyntaxValidator, "pg_triggers/testing/syntax_validator"
    autoload :DryRun, "pg_triggers/testing/dry_run"
    autoload :SafeExecutor, "pg_triggers/testing/safe_executor"
    autoload :FunctionTester, "pg_triggers/testing/function_tester"
  end
end
