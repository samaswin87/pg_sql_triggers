# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Kill Switch Integration', type: :integration do
  let(:logger) { instance_double(Logger) }

  before do
    # Setup default configuration
    allow(PgSqlTriggers).to receive(:kill_switch_enabled).and_return(true)
    allow(PgSqlTriggers).to receive(:kill_switch_environments).and_return([:production, :staging])
    allow(PgSqlTriggers).to receive(:kill_switch_confirmation_required).and_return(true)
    allow(PgSqlTriggers).to receive(:kill_switch_logger).and_return(logger)
    allow(PgSqlTriggers).to receive(:kill_switch_confirmation_pattern).and_return(
      ->(op) { "EXECUTE #{op.to_s.upcase}" }
    )

    # Stub logger methods
    allow(logger).to receive(:debug)
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:error)

    # Clear ENV overrides
    ENV.delete('KILL_SWITCH_OVERRIDE')
    ENV.delete('CONFIRMATION_TEXT')

    # Reset thread-local state
    Thread.current[PgSqlTriggers::SQL::KillSwitch::OVERRIDE_KEY] = nil
  end

  describe 'Console Integration' do
    describe 'TriggerRegistry' do
      let(:trigger) do
        PgSqlTriggers::TriggerRegistry.new(
          trigger_name: 'test_trigger',
          table_name: 'users',
          version: 1,
          enabled: false,
          source: 'dsl',
          checksum: 'test_checksum',
          environment: 'production'
        )
      end

      before do
        allow(trigger).to receive(:update!)
        allow(PgSqlTriggers::DatabaseIntrospection).to receive(:new).and_return(
          instance_double(PgSqlTriggers::DatabaseIntrospection, trigger_exists?: false)
        )
      end

      context 'in production environment' do
        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
        end

        it 'blocks enable! without confirmation' do
          expect {
            trigger.enable!
          }.to raise_error(PgSqlTriggers::KillSwitchError, /Kill switch is active/)
        end

        it 'blocks disable! without confirmation' do
          expect {
            trigger.disable!
          }.to raise_error(PgSqlTriggers::KillSwitchError, /Kill switch is active/)
        end

        it 'allows enable! with correct confirmation' do
          expect {
            trigger.enable!(confirmation: "EXECUTE TRIGGER_ENABLE")
          }.not_to raise_error
        end

        it 'allows disable! with correct confirmation' do
          expect {
            trigger.disable!(confirmation: "EXECUTE TRIGGER_DISABLE")
          }.not_to raise_error
        end

        it 'logs override when confirmation provided' do
          expect(logger).to receive(:warn).with(/OVERRIDDEN.*trigger_enable/)
          trigger.enable!(confirmation: "EXECUTE TRIGGER_ENABLE")
        end
      end

      context 'in development environment' do
        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
        end

        it 'allows enable! without confirmation' do
          expect {
            trigger.enable!
          }.not_to raise_error
        end

        it 'allows disable! without confirmation' do
          expect {
            trigger.disable!
          }.not_to raise_error
        end
      end

      context 'with override block' do
        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
        end

        it 'allows operations within override block' do
          expect {
            PgSqlTriggers::SQL::KillSwitch.override(confirmation: "EXECUTE TRIGGER_ENABLE") do
              trigger.enable!
            end
          }.not_to raise_error
        end

        it 'maintains thread-local override state' do
          PgSqlTriggers::SQL::KillSwitch.override do
            expect(Thread.current[PgSqlTriggers::SQL::KillSwitch::OVERRIDE_KEY]).to be true
          end
          expect(Thread.current[PgSqlTriggers::SQL::KillSwitch::OVERRIDE_KEY]).to be_nil
        end
      end
    end

    describe 'Migrator' do
      before do
        allow(PgSqlTriggers::Migrator).to receive(:ensure_migrations_table!)
        allow(PgSqlTriggers::Migrator).to receive(:current_version).and_return(0)
        allow(PgSqlTriggers::Migrator).to receive(:pending_migrations).and_return([])
        allow(PgSqlTriggers::Migrator).to receive(:migrations).and_return([])
      end

      context 'in production environment' do
        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
        end

        it 'blocks run_up without confirmation' do
          expect {
            PgSqlTriggers::Migrator.run_up
          }.to raise_error(PgSqlTriggers::KillSwitchError, /Kill switch is active/)
        end

        it 'blocks run_down without confirmation' do
          allow(PgSqlTriggers::Migrator).to receive(:current_version).and_return(1)
          expect {
            PgSqlTriggers::Migrator.run_down
          }.to raise_error(PgSqlTriggers::KillSwitchError, /Kill switch is active/)
        end

        it 'allows run_up with correct confirmation' do
          expect {
            PgSqlTriggers::Migrator.run_up(nil, confirmation: "EXECUTE MIGRATOR_RUN_UP")
          }.not_to raise_error
        end

        it 'allows run_down with correct confirmation' do
          allow(PgSqlTriggers::Migrator).to receive(:current_version).and_return(1)
          expect {
            PgSqlTriggers::Migrator.run_down(nil, confirmation: "EXECUTE MIGRATOR_RUN_DOWN")
          }.not_to raise_error
        end
      end

      context 'in development environment' do
        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
        end

        it 'allows run_up without confirmation' do
          expect {
            PgSqlTriggers::Migrator.run_up
          }.not_to raise_error
        end

        it 'allows run_down without confirmation' do
          allow(PgSqlTriggers::Migrator).to receive(:current_version).and_return(1)
          expect {
            PgSqlTriggers::Migrator.run_down
          }.not_to raise_error
        end
      end

      context 'with ENV override' do
        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
          ENV['KILL_SWITCH_OVERRIDE'] = 'true'
        end

        it 'allows run_up with confirmation via ENV' do
          expect {
            # Simulate what happens in rake task - confirmation comes from ENV
            PgSqlTriggers::SQL::KillSwitch.check!(
              operation: :migrator_run_up,
              environment: 'production',
              confirmation: 'EXECUTE MIGRATOR_RUN_UP',
              actor: { type: 'CLI', id: 'test' }
            )
          }.not_to raise_error
        end
      end
    end
  end

  describe 'End-to-End Scenarios' do
    context 'production deployment workflow' do
      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
      end

      it 'blocks all dangerous operations by default' do
        # Try to enable a trigger
        trigger = PgSqlTriggers::TriggerRegistry.new(
          trigger_name: 'test',
          table_name: 'users',
          version: 1,
          enabled: false,
          source: 'dsl',
          checksum: 'test',
          environment: 'production'
        )
        allow(trigger).to receive(:update!)
        allow(PgSqlTriggers::DatabaseIntrospection).to receive(:new).and_return(
          instance_double(PgSqlTriggers::DatabaseIntrospection, trigger_exists?: false)
        )

        expect { trigger.enable! }.to raise_error(PgSqlTriggers::KillSwitchError)

        # Try to run migrations
        allow(PgSqlTriggers::Migrator).to receive(:ensure_migrations_table!)
        allow(PgSqlTriggers::Migrator).to receive(:pending_migrations).and_return([])

        expect {
          PgSqlTriggers::Migrator.run_up
        }.to raise_error(PgSqlTriggers::KillSwitchError)
      end

      it 'allows operations with proper confirmation workflow' do
        trigger = PgSqlTriggers::TriggerRegistry.new(
          trigger_name: 'test',
          table_name: 'users',
          version: 1,
          enabled: false,
          source: 'dsl',
          checksum: 'test',
          environment: 'production'
        )
        allow(trigger).to receive(:update!)
        allow(PgSqlTriggers::DatabaseIntrospection).to receive(:new).and_return(
          instance_double(PgSqlTriggers::DatabaseIntrospection, trigger_exists?: false)
        )

        # Enable trigger with confirmation
        expect {
          trigger.enable!(confirmation: "EXECUTE TRIGGER_ENABLE")
        }.not_to raise_error

        # Run migration with override block
        allow(PgSqlTriggers::Migrator).to receive(:ensure_migrations_table!)
        allow(PgSqlTriggers::Migrator).to receive(:pending_migrations).and_return([])

        expect {
          PgSqlTriggers::SQL::KillSwitch.override(confirmation: "EXECUTE MIGRATOR_RUN_UP") do
            PgSqlTriggers::Migrator.run_up
          end
        }.not_to raise_error
      end
    end

    context 'logging and audit trail' do
      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
      end

      it 'logs all kill switch events' do
        trigger = PgSqlTriggers::TriggerRegistry.new(
          trigger_name: 'test',
          table_name: 'users',
          version: 1,
          enabled: false,
          source: 'dsl',
          checksum: 'test',
          environment: 'production'
        )
        allow(trigger).to receive(:update!)
        allow(PgSqlTriggers::DatabaseIntrospection).to receive(:new).and_return(
          instance_double(PgSqlTriggers::DatabaseIntrospection, trigger_exists?: false)
        )

        # Blocked operation
        expect(logger).to receive(:error).with(/BLOCKED.*trigger_enable/)
        begin
          trigger.enable!
        rescue PgSqlTriggers::KillSwitchError
          # Expected
        end

        # Overridden operation
        expect(logger).to receive(:warn).with(/OVERRIDDEN.*trigger_enable.*explicit_confirmation/)
        trigger.enable!(confirmation: "EXECUTE TRIGGER_ENABLE")
      end
    end

    context 'custom confirmation patterns' do
      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
        allow(PgSqlTriggers).to receive(:kill_switch_confirmation_pattern).and_return(
          ->(op) { "CONFIRM-#{op.to_s.upcase}-NOW" }
        )
      end

      it 'uses custom confirmation pattern' do
        trigger = PgSqlTriggers::TriggerRegistry.new(
          trigger_name: 'test',
          table_name: 'users',
          version: 1,
          enabled: false,
          source: 'dsl',
          checksum: 'test',
          environment: 'production'
        )
        allow(trigger).to receive(:update!)
        allow(PgSqlTriggers::DatabaseIntrospection).to receive(:new).and_return(
          instance_double(PgSqlTriggers::DatabaseIntrospection, trigger_exists?: false)
        )

        expect {
          trigger.enable!(confirmation: "CONFIRM-TRIGGER_ENABLE-NOW")
        }.not_to raise_error

        expect {
          trigger.enable!(confirmation: "EXECUTE TRIGGER_ENABLE")
        }.to raise_error(PgSqlTriggers::KillSwitchError, /Invalid confirmation text/)
      end
    end
  end

  describe 'Thread Safety' do
    it 'maintains separate override state per thread' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))

      thread1_result = nil
      thread2_result = nil

      thread1 = Thread.new do
        PgSqlTriggers::SQL::KillSwitch.override do
          sleep 0.05
          thread1_result = Thread.current[PgSqlTriggers::SQL::KillSwitch::OVERRIDE_KEY]
        end
      end

      thread2 = Thread.new do
        sleep 0.02
        thread2_result = Thread.current[PgSqlTriggers::SQL::KillSwitch::OVERRIDE_KEY]
      end

      thread1.join
      thread2.join

      expect(thread1_result).to be true
      expect(thread2_result).to be_nil
    end
  end

  describe 'Configuration Flexibility' do
    context 'with kill switch disabled globally' do
      before do
        allow(PgSqlTriggers).to receive(:kill_switch_enabled).and_return(false)
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
      end

      it 'allows all operations without confirmation' do
        trigger = PgSqlTriggers::TriggerRegistry.new(
          trigger_name: 'test',
          table_name: 'users',
          version: 1,
          enabled: false,
          source: 'dsl',
          checksum: 'test',
          environment: 'production'
        )
        allow(trigger).to receive(:update!)
        allow(PgSqlTriggers::DatabaseIntrospection).to receive(:new).and_return(
          instance_double(PgSqlTriggers::DatabaseIntrospection, trigger_exists?: false)
        )

        expect { trigger.enable! }.not_to raise_error
        expect { trigger.disable! }.not_to raise_error
      end
    end

    context 'with custom protected environments' do
      before do
        allow(PgSqlTriggers).to receive(:kill_switch_environments).and_return([:production, :qa])
      end

      it 'protects custom environments' do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('qa'))

        trigger = PgSqlTriggers::TriggerRegistry.new(
          trigger_name: 'test',
          table_name: 'users',
          version: 1,
          enabled: false,
          source: 'dsl',
          checksum: 'test',
          environment: 'qa'
        )
        allow(trigger).to receive(:update!)
        allow(PgSqlTriggers::DatabaseIntrospection).to receive(:new).and_return(
          instance_double(PgSqlTriggers::DatabaseIntrospection, trigger_exists?: false)
        )

        expect { trigger.enable! }.to raise_error(PgSqlTriggers::KillSwitchError)
      end

      it 'does not protect staging if not in list' do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('staging'))

        trigger = PgSqlTriggers::TriggerRegistry.new(
          trigger_name: 'test',
          table_name: 'users',
          version: 1,
          enabled: false,
          source: 'dsl',
          checksum: 'test',
          environment: 'staging'
        )
        allow(trigger).to receive(:update!)
        allow(PgSqlTriggers::DatabaseIntrospection).to receive(:new).and_return(
          instance_double(PgSqlTriggers::DatabaseIntrospection, trigger_exists?: false)
        )

        expect { trigger.enable! }.not_to raise_error
      end
    end
  end
end
