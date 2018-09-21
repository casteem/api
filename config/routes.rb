Rails.application.routes.draw do
  resources :posts, only: [:index, :create] do
    collection do
      get 'exists'
      get 'search'
      get 'top'
      patch 'refresh/@:author/:permlink', to: 'posts#refresh', constraints: { author: /[^\/]+/ }
      patch 'set_moderator/@:author/:permlink', to: 'posts#set_moderator', constraints: { author: /[^\/]+/ }
      patch 'moderate/@:author/:permlink', to: 'posts#moderate', constraints: { author: /[^\/]+/ }
      get '@:author', to: 'posts#author', constraints: { author: /([^\/]+?)(?=\.json|$|\/)/ } # override, otherwise it cannot include dots
      get '@:author/:permlink', to: 'posts#show', constraints: { author: /[^\/]+/ }
      put '@:author/:permlink', to: 'posts#update', constraints: { author: /[^\/]+/ }
      delete '@:author/:permlink', to: 'posts#destroy', constraints: { author: /[^\/]+/ }
      get 'tag/:tag', to: 'posts#tag'
      post 'signed_url'
    end
  end


  resources :users, only: [:create] do
    collection do
      # post 'set_eth_address'
    end
  end

  resources :hunt_transactions, only: [:index] do
    collection do
      get 'stats'
      post 'daily_shuffle'
      post 'extensions'
    end
  end

  # resources :erc_transactions, only: [:create]

  resources :referral, only: [:create]

  get '*foo', to: lambda { |env| [404, {}, [ '{"error": "NOT_FOUND"}' ]] }
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
end
