Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  root "songs#index"

  resources :songs, only: [ :index, :edit, :update, :destroy ] do
    scope module: :songs do
      # One editable cell in the song list. #show is the read-only cell, #edit
      # swaps in the input, #update saves it.
      resources :fields, only: [ :show, :edit, :update ], param: :name
    end
  end

  # Library scan. #create enqueues the job, #show reports current progress.
  resource :sync, only: [ :show, :create ]

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
