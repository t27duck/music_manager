Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  root "songs#index"

  resources :songs, only: [ :index, :edit, :update, :destroy ] do
    scope module: :songs do
      # One editable cell in the song list. #show is the read-only cell, #edit
      # swaps in the input, #update saves it.
      resources :fields, only: [ :show, :edit, :update ], param: :name

      # Embedded cover art. #show serves the image bytes themselves.
      resource :album_art, only: [ :show, :edit, :update, :destroy ]
    end
  end

  # Albums and artists are GROUP BYs over songs, not tables -- see app/models/album.rb.
  # The :id is the grouping key itself, encoded; see app/models/library_key.rb.
  resources :albums, only: [ :index, :show ]

  # Applying one set of changes to a checkbox selection. #new is the modal.
  resources :bulk_updates, only: [ :new, :create ]

  # Re-filing songs under a path template. #new *is* the preview: it re-renders
  # as the template is edited. #create performs the moves.
  resources :file_organizations, only: [ :new, :create ]

  # Library scan. Progress is reported by the shared #progress resource below,
  # not here -- the bar shows whichever operation is running, not just this one.
  resource :sync, only: :create

  # The progress of whatever long-running operation is current. Polled by
  # progress_controller.js as a fallback for a broadcast that went missing.
  resource :progress, only: :show

  # The audit trail of past syncs. Live progress is the #progress resource
  # above; this is what happened, not what is happening.
  resources :sync_runs, only: :index

  # Drag-and-drop upload page, and one POST per file.
  resource :upload, only: [ :show, :create ]

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
