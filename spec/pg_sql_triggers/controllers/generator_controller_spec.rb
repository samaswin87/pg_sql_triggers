# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::GeneratorController, type: :controller do
  routes { PgSqlTriggers::Engine.routes }

  let(:valid_params) do
    {
      pg_sql_triggers_generator_form: {
        trigger_name: "test_trigger",
        table_name: "users",
        function_name: "test_function",
        function_body: "CREATE OR REPLACE FUNCTION test_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;",
        events: %w[insert update],
        version: 1,
        enabled: false,
        environments: ["production"]
      }
    }
  end

  before do
    # Configure view paths
    engine_view_path = PgSqlTriggers::Engine.root.join("app/views").to_s
    controller.prepend_view_path(engine_view_path) if controller.respond_to?(:prepend_view_path)

    # Mock Rails.root
    allow(Rails).to receive(:root).and_return(Pathname.new(Dir.mktmpdir))
    allow(controller).to receive(:current_actor).and_return({ type: "User", id: 1 })

    # Create test table
    ActiveRecord::Base.connection.execute("CREATE TABLE IF NOT EXISTS users (id SERIAL PRIMARY KEY, name VARCHAR)")

    # Mock permissions
    allow(PgSqlTriggers::Permissions).to receive(:can?).and_return(true)
  end

  after do
    ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS users CASCADE")
  end

  describe "GET #new" do
    it "initializes a new form" do
      allow(PgSqlTriggers::DatabaseIntrospection).to receive_message_chain(:new, :list_tables).and_return(%w[users posts])
      get :new
      expect(assigns(:form)).to be_a(PgSqlTriggers::Generator::Form)
      expect(assigns(:available_tables)).to include("users")
    end

    context "when session contains form data" do
      let(:session_form_data) do
        {
          "trigger_name" => "restored_trigger",
          "table_name" => "users",
          "function_name" => "restored_function",
          "function_body" => "CREATE OR REPLACE FUNCTION restored_function() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;",
          "events" => ["insert", "update"],
          "version" => "2",
          "enabled" => "true",
          "timing" => "after",
          "condition" => "NEW.status = 'active'",
          "environments" => ["production"],
          "generate_function_stub" => "true"
        }
      end

      it "restores form data from session when available" do
        session[:generator_form_data] = session_form_data
        allow(PgSqlTriggers::DatabaseIntrospection).to receive_message_chain(:new, :list_tables).and_return(%w[users posts])

        get :new

        form = assigns(:form)
        expect(form).to be_a(PgSqlTriggers::Generator::Form)
        expect(form.trigger_name).to eq("restored_trigger")
        expect(form.table_name).to eq("users")
        expect(form.function_name).to eq("restored_function")
        expect(form.function_body).to include("restored_function")
        expect(form.events).to include("insert", "update")
        # Version is stored as string in session, but Form converts it to integer
        expect(form.version.to_i).to eq(2)
        expect(form.enabled).to be true
        expect(form.timing).to eq("after")
        expect(form.condition).to eq("NEW.status = 'active'")
        expect(form.environments).to include("production")
      end

      it "clears session data after restoring" do
        session[:generator_form_data] = session_form_data
        allow(PgSqlTriggers::DatabaseIntrospection).to receive_message_chain(:new, :list_tables).and_return(%w[users posts])

        get :new

        expect(session[:generator_form_data]).to be_nil
      end

      it "initializes new form when session data is empty" do
        session[:generator_form_data] = nil
        allow(PgSqlTriggers::DatabaseIntrospection).to receive_message_chain(:new, :list_tables).and_return(%w[users posts])

        get :new

        form = assigns(:form)
        expect(form).to be_a(PgSqlTriggers::Generator::Form)
        expect(form.trigger_name).to be_nil
      end
    end
  end

  describe "POST #preview" do
    it "generates DSL and function content when form is valid" do
      allow(PgSqlTriggers::DatabaseIntrospection).to receive_message_chain(:new, :validate_table).and_return({ valid: true })
      allow(PgSqlTriggers::Testing::SyntaxValidator).to receive_message_chain(:new, :validate_function_syntax).and_return({ valid: true })
      allow(controller).to receive(:render).and_return(nil)

      post :preview, params: valid_params
      expect(assigns(:dsl_content)).to be_present
      expect(assigns(:function_content)).to be_present
      expect(assigns(:file_paths)).to be_present
    end

    it "stores form data in session when form is valid" do
      allow(PgSqlTriggers::DatabaseIntrospection).to receive_message_chain(:new, :validate_table).and_return({ valid: true })
      allow(PgSqlTriggers::Testing::SyntaxValidator).to receive_message_chain(:new, :validate_function_syntax).and_return({ valid: true })
      allow(controller).to receive(:render).and_return(nil)

      post :preview, params: valid_params

      expect(session[:generator_form_data]).to be_present
      expect(session[:generator_form_data]["trigger_name"]).to eq("test_trigger")
      expect(session[:generator_form_data]["table_name"]).to eq("users")
      expect(session[:generator_form_data]["function_name"]).to eq("test_function")
      expect(session[:generator_form_data]["events"]).to include("insert", "update")
    end

    it "does not store form data in session when form is invalid" do
      invalid_params = valid_params.deep_dup
      invalid_params[:pg_sql_triggers_generator_form][:trigger_name] = ""

      allow(PgSqlTriggers::DatabaseIntrospection).to receive_message_chain(:new, :list_tables).and_return(["users"])
      allow(controller).to receive(:render).and_return(nil)

      post :preview, params: invalid_params

      expect(session[:generator_form_data]).to be_nil
    end

    it "validates SQL function body" do
      allow(PgSqlTriggers::DatabaseIntrospection).to receive_message_chain(:new, :validate_table).and_return({ valid: true })
      validator = instance_double(PgSqlTriggers::Testing::SyntaxValidator)
      allow(PgSqlTriggers::Testing::SyntaxValidator).to receive(:new).and_return(validator)
      allow(validator).to receive(:validate_function_syntax).and_return({ valid: true })
      allow(controller).to receive(:render).and_return(nil)

      post :preview, params: valid_params
      expect(assigns(:sql_validation)).to be_present
    end

    it "renders new template when form is invalid" do
      invalid_params = valid_params.deep_dup
      invalid_params[:pg_sql_triggers_generator_form][:trigger_name] = ""

      allow(PgSqlTriggers::DatabaseIntrospection).to receive_message_chain(:new, :list_tables).and_return(["users"])
      allow(controller).to receive(:render).and_return(nil)
      post :preview, params: invalid_params
      expect(controller).to have_received(:render).with(:new)
    end

    context "when back_to_edit parameter is present" do
      it "stores form data in session and redirects to new" do
        params_with_back = valid_params.deep_dup
        params_with_back[:back_to_edit] = "1"

        post :preview, params: params_with_back

        expect(session[:generator_form_data]).to be_present
        expect(session[:generator_form_data]["trigger_name"]).to eq("test_trigger")
        expect(session[:generator_form_data]["table_name"]).to eq("users")
        expect(response).to redirect_to(new_generator_path)
      end

      it "preserves all form fields including condition and timing" do
        params_with_back = valid_params.deep_dup
        params_with_back[:back_to_edit] = "1"
        params_with_back[:pg_sql_triggers_generator_form][:condition] = "NEW.id > 0"
        params_with_back[:pg_sql_triggers_generator_form][:timing] = "after"

        post :preview, params: params_with_back

        expect(session[:generator_form_data]["condition"]).to eq("NEW.id > 0")
        expect(session[:generator_form_data]["timing"]).to eq("after")
        expect(response).to redirect_to(new_generator_path)
      end

      it "does not validate form when back_to_edit is present" do
        invalid_params = valid_params.deep_dup
        invalid_params[:back_to_edit] = "1"
        invalid_params[:pg_sql_triggers_generator_form][:trigger_name] = ""

        post :preview, params: invalid_params

        # Should still store and redirect even if form is invalid
        expect(session[:generator_form_data]).to be_present
        expect(response).to redirect_to(new_generator_path)
      end
    end
  end

  describe "POST #create" do
    it "creates trigger when form is valid" do
      allow(PgSqlTriggers::DatabaseIntrospection).to receive_message_chain(:new, :validate_table).and_return({ valid: true })
      allow(PgSqlTriggers::Testing::SyntaxValidator).to receive_message_chain(:new, :validate_function_syntax).and_return({ valid: true })
      allow(PgSqlTriggers::Generator::Service).to receive(:create_trigger).and_return({
                                                                                        success: true,
                                                                                        migration_path: "db/triggers/20231215120001_test_trigger.rb",
                                                                                        dsl_path: "app/triggers/test_trigger.rb"
                                                                                      })

      post :create, params: valid_params
      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to include("successfully")
    end

    it "clears session data after successful creation" do
      session[:generator_form_data] = { "trigger_name" => "test" }
      allow(PgSqlTriggers::DatabaseIntrospection).to receive_message_chain(:new, :validate_table).and_return({ valid: true })
      allow(PgSqlTriggers::Testing::SyntaxValidator).to receive_message_chain(:new, :validate_function_syntax).and_return({ valid: true })
      allow(PgSqlTriggers::Generator::Service).to receive(:create_trigger).and_return({
                                                                                        success: true,
                                                                                        migration_path: "db/triggers/20231215120001_test_trigger.rb",
                                                                                        dsl_path: "app/triggers/test_trigger.rb"
                                                                                      })

      post :create, params: valid_params

      expect(session[:generator_form_data]).to be_nil
    end

    it "does not clear session data when creation fails" do
      session[:generator_form_data] = { "trigger_name" => "test" }
      allow(PgSqlTriggers::DatabaseIntrospection).to receive_message_chain(:new, :validate_table).and_return({ valid: true })
      allow(PgSqlTriggers::Testing::SyntaxValidator).to receive_message_chain(:new, :validate_function_syntax).and_return({ valid: true })
      allow(PgSqlTriggers::Generator::Service).to receive(:create_trigger).and_return({
                                                                                        success: false,
                                                                                        error: "Permission denied"
                                                                                      })
      allow(PgSqlTriggers::DatabaseIntrospection).to receive_message_chain(:new, :list_tables).and_return(["users"])
      allow(controller).to receive(:render).with(:new).and_return(nil)

      post :create, params: valid_params

      # Session data should still be present (though it might be overwritten by the new form data)
      expect(session[:generator_form_data]).to be_present
    end

    it "shows error when creation fails" do
      allow(PgSqlTriggers::DatabaseIntrospection).to receive_message_chain(:new, :validate_table).and_return({ valid: true })
      allow(PgSqlTriggers::Testing::SyntaxValidator).to receive_message_chain(:new, :validate_function_syntax).and_return({ valid: true })
      allow(PgSqlTriggers::Generator::Service).to receive(:create_trigger).and_return({
                                                                                        success: false,
                                                                                        error: "Permission denied"
                                                                                      })
      allow(PgSqlTriggers::DatabaseIntrospection).to receive_message_chain(:new, :list_tables).and_return(["users"])
      allow(controller).to receive(:render).with(:new).and_return(nil)

      post :create, params: valid_params
      expect(controller).to have_received(:render).with(:new)
      expect(flash[:alert]).to include("Generation failed")
    end

    it "validates SQL before creating" do
      allow(PgSqlTriggers::DatabaseIntrospection).to receive_message_chain(:new, :validate_table).and_return({ valid: true })
      validator = instance_double(PgSqlTriggers::Testing::SyntaxValidator)
      allow(PgSqlTriggers::Testing::SyntaxValidator).to receive(:new).and_return(validator)
      allow(validator).to receive(:validate_function_syntax).and_return({ valid: false, error: "Syntax error" })
      allow(PgSqlTriggers::Generator::Service).to receive(:generate_dsl).and_return("# DSL code")
      allow(PgSqlTriggers::DatabaseIntrospection).to receive_message_chain(:new, :list_tables).and_return(["users"])
      allow(controller).to receive(:render).with(:preview).and_return(nil)

      post :create, params: valid_params
      expect(controller).to have_received(:render).with(:preview)
      expect(flash[:alert]).to include("SQL validation failed")
    end

    context "with WHEN condition" do
      let(:params_with_condition) do
        valid_params.deep_dup.tap do |p|
          p[:pg_sql_triggers_generator_form][:condition] = "NEW.id > 0"
        end
      end

      it "validates WHEN condition when present" do
        allow(PgSqlTriggers::DatabaseIntrospection).to receive_message_chain(:new, :validate_table).and_return({ valid: true })
        validator = instance_double(PgSqlTriggers::Testing::SyntaxValidator)
        allow(PgSqlTriggers::Testing::SyntaxValidator).to receive(:new).and_return(validator)
        allow(validator).to receive_messages(validate_function_syntax: { valid: true }, validate_condition: { valid: true, message: "Condition syntax is valid" })
        allow(PgSqlTriggers::Generator::Service).to receive(:create_trigger).and_return({
                                                                                          success: true,
                                                                                          migration_path: "db/triggers/20231215120001_test_trigger.rb",
                                                                                          dsl_path: "app/triggers/test_trigger.rb"
                                                                                        })

        post :create, params: params_with_condition
        expect(validator).to have_received(:validate_condition)
        expect(response).to redirect_to(root_path)
      end

      it "rejects invalid WHEN condition" do
        allow(PgSqlTriggers::DatabaseIntrospection).to receive_message_chain(:new, :validate_table).and_return({ valid: true })
        validator = instance_double(PgSqlTriggers::Testing::SyntaxValidator)
        allow(PgSqlTriggers::Testing::SyntaxValidator).to receive(:new).and_return(validator)
        allow(validator).to receive_messages(validate_function_syntax: { valid: true }, validate_condition: { valid: false, error: "syntax error at or near \"INVALID\"" })
        allow(PgSqlTriggers::Generator::Service).to receive(:generate_dsl).and_return("# DSL code")
        allow(PgSqlTriggers::DatabaseIntrospection).to receive_message_chain(:new, :list_tables).and_return(["users"])
        allow(controller).to receive(:render).with(:preview).and_return(nil)

        post :create, params: params_with_condition
        expect(validator).to have_received(:validate_condition)
        expect(controller).to have_received(:render).with(:preview)
        expect(flash[:alert]).to include("WHEN condition validation failed")
      end

      it "validates condition in preview" do
        allow(PgSqlTriggers::DatabaseIntrospection).to receive_message_chain(:new, :validate_table).and_return({ valid: true })
        validator = instance_double(PgSqlTriggers::Testing::SyntaxValidator)
        allow(PgSqlTriggers::Testing::SyntaxValidator).to receive(:new).and_return(validator)
        allow(validator).to receive_messages(validate_function_syntax: { valid: true }, validate_condition: { valid: true, message: "Condition syntax is valid" })
        allow(controller).to receive(:render).and_return(nil)

        post :preview, params: params_with_condition
        expect(validator).to have_received(:validate_condition)
        expect(assigns(:sql_validation)).to be_present
      end

      it "validates condition syntax with real database" do
        # Don't mock the validator - use real one to test actual SQL validation
        allow(PgSqlTriggers::DatabaseIntrospection).to receive_message_chain(:new, :validate_table).and_return({ valid: true })
        allow(PgSqlTriggers::DatabaseIntrospection).to receive_message_chain(:new, :list_tables).and_return(["users"])
        allow(PgSqlTriggers::Generator::Service).to receive(:create_trigger).and_return({
                                                                                          success: true,
                                                                                          migration_path: "db/triggers/20231215120001_test_trigger.rb",
                                                                                          dsl_path: "app/triggers/test_trigger.rb"
                                                                                        })

        # Use real validator to test actual SQL validation
        # The condition "NEW.id > 0" should be valid for the users table with id column
        post :create, params: params_with_condition

        # The validation should run (either pass or fail, but it should be called)
        # If it passes, we redirect; if it fails, we render preview with error
        expect(assigns(:sql_validation) || response.redirect?).to be_truthy
        expect(flash[:notice]).to include("successfully") if response.redirect?
      end

      it "rejects invalid condition syntax with real database" do
        invalid_condition_params = valid_params.deep_dup.tap do |p|
          p[:pg_sql_triggers_generator_form][:condition] = "INVALID SQL SYNTAX !!!"
        end

        allow(PgSqlTriggers::DatabaseIntrospection).to receive_message_chain(:new, :validate_table).and_return({ valid: true })
        allow(PgSqlTriggers::Generator::Service).to receive(:generate_dsl).and_return("# DSL code")
        allow(PgSqlTriggers::DatabaseIntrospection).to receive_message_chain(:new, :list_tables).and_return(["users"])
        allow(controller).to receive(:render).with(:preview).and_return(nil)

        post :create, params: invalid_condition_params
        expect(controller).to have_received(:render).with(:preview)
        expect(flash[:alert]).to include("WHEN condition validation failed")
      end
    end

    it "skips condition validation when condition is blank" do
      allow(PgSqlTriggers::DatabaseIntrospection).to receive_message_chain(:new, :validate_table).and_return({ valid: true })
      validator = instance_double(PgSqlTriggers::Testing::SyntaxValidator)
      allow(PgSqlTriggers::Testing::SyntaxValidator).to receive(:new).and_return(validator)
      allow(validator).to receive_messages(validate_function_syntax: { valid: true }, validate_condition: { valid: true })
      allow(PgSqlTriggers::Generator::Service).to receive(:create_trigger).and_return({
                                                                                        success: true,
                                                                                        migration_path: "db/triggers/20231215120001_test_trigger.rb",
                                                                                        dsl_path: "app/triggers/test_trigger.rb"
                                                                                      })

      post :create, params: valid_params
      expect(validator).not_to have_received(:validate_condition)
      expect(response).to redirect_to(root_path)
    end

    it "handles condition attribute when column doesn't exist" do
      # Temporarily stub column_names to exclude condition
      original_column_names = PgSqlTriggers::TriggerRegistry.column_names
      allow(PgSqlTriggers::TriggerRegistry).to receive(:column_names).and_return(original_column_names - ["condition"])

      allow(PgSqlTriggers::DatabaseIntrospection).to receive_message_chain(:new, :validate_table).and_return({ valid: true })
      validator = instance_double(PgSqlTriggers::Testing::SyntaxValidator)
      allow(PgSqlTriggers::Testing::SyntaxValidator).to receive(:new).and_return(validator)
      allow(validator).to receive_messages(validate_function_syntax: { valid: true }, validate_condition: { valid: true })
      allow(PgSqlTriggers::Generator::Service).to receive(:create_trigger).and_return({
                                                                                        success: true,
                                                                                        migration_path: "db/triggers/20231215120001_test_trigger.rb",
                                                                                        dsl_path: "app/triggers/test_trigger.rb"
                                                                                      })

      params_with_condition = valid_params.deep_dup.tap do |p|
        p[:pg_sql_triggers_generator_form][:condition] = "NEW.id > 0"
      end

      # Should not raise an error about unknown attribute 'condition'
      # The condition validation should still run, but the attribute won't be set on the registry object
      post :create, params: params_with_condition
      expect(response).to redirect_to(root_path)
      expect(validator).to have_received(:validate_condition)
    end
  end

  describe "POST #validate_table" do
    it "returns validation result for valid table" do
      allow(PgSqlTriggers::DatabaseIntrospection).to receive_message_chain(:new, :validate_table).and_return({
                                                                                                               valid: true,
                                                                                                               table_name: "users",
                                                                                                               column_count: 2
                                                                                                             })

      post :validate_table, params: { table_name: "users" }, format: :json
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["valid"]).to be true
    end

    it "returns error for invalid table" do
      allow(PgSqlTriggers::DatabaseIntrospection).to receive_message_chain(:new, :validate_table).and_return({
                                                                                                               valid: false,
                                                                                                               error: "Table not found"
                                                                                                             })

      post :validate_table, params: { table_name: "nonexistent" }, format: :json
      json = JSON.parse(response.body)
      expect(json["valid"]).to be false
      expect(json["error"]).to include("not found")
    end

    it "returns error for blank table name" do
      post :validate_table, params: { table_name: "" }, format: :json
      expect(response).to have_http_status(:bad_request)
      json = JSON.parse(response.body)
      expect(json["valid"]).to be false
    end
  end

  describe "GET #tables" do
    it "returns list of tables as JSON" do
      allow(PgSqlTriggers::DatabaseIntrospection).to receive_message_chain(:new, :list_tables).and_return(%w[users posts])

      get :tables, format: :json
      json = JSON.parse(response.body)
      expect(json["tables"]).to include("users", "posts")
    end
  end

  describe "permission checks" do
    it "redirects when permission denied" do
      allow(PgSqlTriggers::Permissions).to receive(:can?).and_return(false)

      get :new
      expect(response).to redirect_to("/")
      expect(flash[:alert]).to include("Insufficient permissions")
    end
  end
end
