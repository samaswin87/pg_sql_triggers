# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::TriggersController, type: :controller do
  routes { PgSqlTriggers::Engine.routes }

  let(:trigger) do
    PgSqlTriggers::TriggerRegistry.create!(
      trigger_name: "test_trigger",
      table_name: "test_table",
      version: 1,
      checksum: "abc123",
      source: "dsl",
      enabled: true
    )
  end

  before do
    allow(Rails.logger).to receive(:error)
    # Allow permissions by default
    allow(PgSqlTriggers::Permissions).to receive(:can?).and_return(true)
  end

  describe "POST #enable" do
    let(:disabled_trigger) do
      PgSqlTriggers::TriggerRegistry.create!(
        trigger_name: "disabled_trigger",
        table_name: "test_table",
        version: 1,
        checksum: "def456",
        source: "dsl",
        enabled: false
      )
    end

    context "when trigger is successfully enabled" do
      before do
        allow_any_instance_of(PgSqlTriggers::TriggerRegistry).to receive(:enable!).and_return(true)
      end

      it "enables the trigger" do
        expect_any_instance_of(PgSqlTriggers::TriggerRegistry).to receive(:enable!).with(confirmation: nil)
        post :enable, params: { id: disabled_trigger.id }
      end

      it "passes confirmation text to enable!" do
        expect_any_instance_of(PgSqlTriggers::TriggerRegistry)
          .to receive(:enable!)
          .with(confirmation: "EXECUTE TRIGGER_ENABLE")
        post :enable, params: { id: disabled_trigger.id, confirmation_text: "EXECUTE TRIGGER_ENABLE" }
      end

      it "sets success flash message" do
        post :enable, params: { id: disabled_trigger.id }
        expect(flash[:success]).to match(/enabled successfully/)
        expect(flash[:success]).to include(disabled_trigger.trigger_name)
      end

      it "redirects to root path by default" do
        post :enable, params: { id: disabled_trigger.id }
        expect(response).to redirect_to(root_path)
      end

      it "redirects to specified path when redirect_to param present" do
        post :enable, params: { id: disabled_trigger.id, redirect_to: "/custom/path" }
        expect(response).to redirect_to("/custom/path")
      end
    end

    context "when trigger is not found" do
      it "sets error flash and redirects" do
        post :enable, params: { id: 99_999 }
        expect(flash[:error]).to eq("Trigger not found.")
        expect(response).to redirect_to(root_path)
      end
    end

    context "when enable fails" do
      before do
        allow_any_instance_of(PgSqlTriggers::TriggerRegistry)
          .to receive(:enable!)
          .and_raise(StandardError.new("Database connection failed"))
      end

      it "sets error flash with failure message" do
        post :enable, params: { id: disabled_trigger.id }
        expect(flash[:error]).to match(/Failed to enable trigger/)
        expect(flash[:error]).to include("Database connection failed")
      end

      it "logs the error" do
        post :enable, params: { id: disabled_trigger.id }
        expect(Rails.logger).to have_received(:error).with(/Enable failed/)
      end

      it "redirects to root path" do
        post :enable, params: { id: disabled_trigger.id }
        expect(response).to redirect_to(root_path)
      end
    end

    context "when kill switch blocks operation" do
      before do
        allow_any_instance_of(PgSqlTriggers::TriggersController)
          .to receive(:check_kill_switch)
          .and_raise(PgSqlTriggers::KillSwitchError.new("Kill switch is active"))
      end

      it "sets error flash with kill switch message" do
        post :enable, params: { id: disabled_trigger.id }
        expect(flash[:error]).to eq("Kill switch is active")
      end

      it "redirects to root path" do
        post :enable, params: { id: disabled_trigger.id }
        expect(response).to redirect_to(root_path)
      end

      it "redirects to custom path if provided" do
        post :enable, params: { id: disabled_trigger.id, redirect_to: "/custom/path" }
        expect(response).to redirect_to("/custom/path")
      end
    end
  end

  describe "POST #disable" do
    context "when trigger is successfully disabled" do
      before do
        allow_any_instance_of(PgSqlTriggers::TriggerRegistry).to receive(:disable!).and_return(true)
      end

      it "disables the trigger" do
        expect_any_instance_of(PgSqlTriggers::TriggerRegistry).to receive(:disable!).with(confirmation: nil)
        post :disable, params: { id: trigger.id }
      end

      it "passes confirmation text to disable!" do
        expect_any_instance_of(PgSqlTriggers::TriggerRegistry)
          .to receive(:disable!)
          .with(confirmation: "EXECUTE TRIGGER_DISABLE")
        post :disable, params: { id: trigger.id, confirmation_text: "EXECUTE TRIGGER_DISABLE" }
      end

      it "sets success flash message" do
        post :disable, params: { id: trigger.id }
        expect(flash[:success]).to match(/disabled successfully/)
        expect(flash[:success]).to include(trigger.trigger_name)
      end

      it "redirects to root path by default" do
        post :disable, params: { id: trigger.id }
        expect(response).to redirect_to(root_path)
      end

      it "redirects to specified path when redirect_to param present" do
        post :disable, params: { id: trigger.id, redirect_to: "/custom/path" }
        expect(response).to redirect_to("/custom/path")
      end
    end

    context "when trigger is not found" do
      it "sets error flash and redirects" do
        post :disable, params: { id: 99_999 }
        expect(flash[:error]).to eq("Trigger not found.")
        expect(response).to redirect_to(root_path)
      end
    end

    context "when disable fails" do
      before do
        allow_any_instance_of(PgSqlTriggers::TriggerRegistry)
          .to receive(:disable!)
          .and_raise(StandardError.new("Permission denied"))
      end

      it "sets error flash with failure message" do
        post :disable, params: { id: trigger.id }
        expect(flash[:error]).to match(/Failed to disable trigger/)
        expect(flash[:error]).to include("Permission denied")
      end

      it "logs the error" do
        post :disable, params: { id: trigger.id }
        expect(Rails.logger).to have_received(:error).with(/Disable failed/)
      end

      it "redirects to root path" do
        post :disable, params: { id: trigger.id }
        expect(response).to redirect_to(root_path)
      end
    end

    context "when kill switch blocks operation" do
      before do
        allow_any_instance_of(PgSqlTriggers::TriggersController)
          .to receive(:check_kill_switch)
          .and_raise(PgSqlTriggers::KillSwitchError.new("Kill switch is active"))
      end

      it "sets error flash with kill switch message" do
        post :disable, params: { id: trigger.id }
        expect(flash[:error]).to eq("Kill switch is active")
      end

      it "redirects to root path" do
        post :disable, params: { id: trigger.id }
        expect(response).to redirect_to(root_path)
      end

      it "redirects to custom path if provided" do
        post :disable, params: { id: trigger.id, redirect_to: "/custom/path" }
        expect(response).to redirect_to("/custom/path")
      end
    end
  end

  describe "permission checks" do
    context "when user lacks permissions" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?).with(anything, :enable_trigger).and_return(false)
      end

      it "blocks enable action" do
        post :enable, params: { id: trigger.id }
        expect(flash[:alert]).to match(/Insufficient permissions/)
        expect(flash[:alert]).to include("Operator role required")
        expect(response).to redirect_to(root_path)
      end

      it "blocks disable action" do
        post :disable, params: { id: trigger.id }
        expect(flash[:alert]).to match(/Insufficient permissions/)
        expect(flash[:alert]).to include("Operator role required")
        expect(response).to redirect_to(root_path)
      end

      it "does not call enable! when permission is denied" do
        expect_any_instance_of(PgSqlTriggers::TriggerRegistry).not_to receive(:enable!)
        post :enable, params: { id: trigger.id }
      end

      it "does not call disable! when permission is denied" do
        expect_any_instance_of(PgSqlTriggers::TriggerRegistry).not_to receive(:disable!)
        post :disable, params: { id: trigger.id }
      end
    end

    context "when user has permissions" do
      before do
        allow(PgSqlTriggers::Permissions).to receive(:can?).with(anything, :enable_trigger).and_return(true)
        allow_any_instance_of(PgSqlTriggers::TriggerRegistry).to receive(:enable!).and_return(true)
        allow_any_instance_of(PgSqlTriggers::TriggerRegistry).to receive(:disable!).and_return(true)
      end

      it "allows enable action" do
        post :enable, params: { id: trigger.id }
        expect(flash[:alert]).to be_nil
        expect(flash[:success]).to be_present
      end

      it "allows disable action" do
        post :disable, params: { id: trigger.id }
        expect(flash[:alert]).to be_nil
        expect(flash[:success]).to be_present
      end
    end
  end

  describe "redirect behavior" do
    before do
      allow_any_instance_of(PgSqlTriggers::TriggerRegistry).to receive(:enable!).and_return(true)
    end

    it "uses redirect_to param if present" do
      post :enable, params: { id: trigger.id, redirect_to: "/tables/test_table" }
      expect(response).to redirect_to("/tables/test_table")
    end

    it "falls back to referer if no redirect_to" do
      request.env["HTTP_REFERER"] = "/tables/test_table"
      post :enable, params: { id: trigger.id }
      expect(response).to redirect_to("/tables/test_table")
    end

    it "falls back to root if no redirect_to or referer" do
      post :enable, params: { id: trigger.id }
      expect(response).to redirect_to(root_path)
    end
  end

  describe "error handling hierarchy" do
    it "handles KillSwitchError before StandardError" do
      allow_any_instance_of(PgSqlTriggers::TriggersController)
        .to receive(:check_kill_switch)
        .and_raise(PgSqlTriggers::KillSwitchError.new("Blocked"))

      post :enable, params: { id: trigger.id }
      expect(flash[:error]).to eq("Blocked")
      expect(Rails.logger).not_to have_received(:error)
    end

    it "handles StandardError when operation fails" do
      allow_any_instance_of(PgSqlTriggers::TriggerRegistry)
        .to receive(:enable!)
        .and_raise(StandardError.new("Generic error"))

      post :enable, params: { id: trigger.id }
      expect(flash[:error]).to match(/Failed to enable trigger/)
      expect(Rails.logger).to have_received(:error)
    end

    it "handles RecordNotFound before action execution" do
      post :enable, params: { id: 99_999 }
      expect(flash[:error]).to eq("Trigger not found.")
      expect(Rails.logger).not_to have_received(:error)
    end
  end
end
