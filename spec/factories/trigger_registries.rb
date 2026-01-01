# frozen_string_literal: true

FactoryBot.define do
  factory :trigger_registry, class: "PgSqlTriggers::TriggerRegistry" do
    sequence(:trigger_name) { |n| "test_trigger_#{n}" }
    table_name { "users" }
    version { 1 }
    enabled { false }
    source { "dsl" }
    sequence(:checksum) { |n| "checksum_#{n}" }
    environment { "test" }
    timing { "before" }

    trait :enabled do
      enabled { true }
    end

    trait :disabled do
      enabled { false }
    end

    trait :production do
      environment { "production" }
    end

    trait :staging do
      environment { "staging" }
    end

    trait :development do
      environment { "development" }
    end

    trait :with_definition do
      definition { "CREATE TRIGGER test_trigger BEFORE INSERT ON users FOR EACH ROW EXECUTE FUNCTION test_function()" }
    end

    trait :with_function_body do
      function_body { "BEGIN\n  -- Trigger logic here\n  RETURN NEW;\nEND;" }
    end

    trait :with_condition do
      condition { "NEW.status = 'active'" }
    end

    trait :after_insert do
      timing { "after" }
    end

    trait :before_insert do
      timing { "before" }
    end

    # Convenience factory for production triggers
    factory :production_trigger, traits: [:production]

    # Convenience factory for enabled triggers
    factory :enabled_trigger, traits: [:enabled]

    # Convenience factory for disabled triggers
    factory :disabled_trigger, traits: [:disabled]
  end
end
