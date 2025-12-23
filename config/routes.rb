# frozen_string_literal: true

PgTriggers::Engine.routes.draw do
  root to: "dashboard#index"

  resources :tables, only: [:index, :show]

  resources :generator, only: [:new, :create] do
    collection do
      post :preview
      post :validate_table
      get :tables
    end
  end

  resources :sql_capsules, only: [:new, :create, :show] do
    member do
      post :execute
    end
  end
end
