defmodule InvaderWeb.SignInLive do
  @moduledoc """
  Custom sign-in page with Space Invaders arcade theme.
  Shows a setup token form for the first user (admin setup).
  """
  use InvaderWeb, :live_view

  alias Invader.Accounts.User

  @impl true
  def mount(_params, session, socket) do
    user_count = Ash.count!(User, authorize?: false)
    needs_setup = user_count == 0
    setup_token_validated = session["admin_setup_validated"] == true

    {:ok,
     assign(socket,
       page_title: "Sign In",
       needs_setup: needs_setup,
       setup_token_validated: setup_token_validated,
       token_error: nil
     )}
  end

  @impl true
  def handle_event("validate_setup_token", %{"token" => token}, socket) do
    expected_token = Application.get_env(:invader, :admin_setup_token)

    if expected_token && token == expected_token do
      # Token is valid - redirect to a controller that sets the session and redirects back
      {:noreply, redirect(socket, to: "/auth/setup/validate?token=#{URI.encode_www_form(token)}")}
    else
      {:noreply, assign(socket, token_error: "Invalid setup token")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main
      class="arcade-container min-h-screen bg-black flex flex-col items-center justify-center relative z-10"
      role="main"
    >
      <!-- CRT Scanlines Overlay -->
      <div class="crt-overlay pointer-events-none fixed inset-0 z-40" aria-hidden="true"></div>
      
    <!-- Animated Aliens Header Decoration -->
      <div class="flex justify-center gap-4 mb-6 text-2xl">
        <span class="alien-sprite text-cyan-400"></span>
        <span class="alien-sprite text-magenta-400" style="animation-delay: 0.2s;"></span>
        <span class="alien-sprite text-green-400" style="animation-delay: 0.4s;"></span>
        <span class="alien-sprite text-cyan-400" style="animation-delay: 0.6s;"></span>
        <span class="alien-sprite text-magenta-400" style="animation-delay: 0.8s;"></span>
      </div>
      
    <!-- Title -->
      <h1 class="text-3xl md:text-4xl font-bold tracking-widest arcade-glow mb-2">
        INVADER
      </h1>
      <p class="text-cyan-500 text-[10px] tracking-wider mb-12">[ RALPH LOOP COMMAND CENTER ]</p>
      
    <!-- Sign In Panel -->
      <div class="arcade-panel p-6 sm:p-8 max-w-md w-full mx-4">
        <%= if @needs_setup && !@setup_token_validated do %>
          <!-- Admin Setup Token Form -->
          <div class="text-center mb-8">
            <h2 class="text-sm text-yellow-400 mb-2">ADMIN SETUP</h2>
            <p class="text-[8px] text-cyan-700">ENTER SETUP TOKEN TO INITIALIZE</p>
          </div>

          <.form for={%{}} phx-submit="validate_setup_token" class="space-y-4">
            <div>
              <input
                type="password"
                name="token"
                placeholder="Setup Token"
                autocomplete="off"
                class="w-full bg-black border border-cyan-600 text-cyan-400 px-4 py-3 text-[10px] tracking-wider focus:border-cyan-400 focus:outline-none focus:ring-1 focus:ring-cyan-400"
              />
            </div>

            <%= if @token_error do %>
              <p class="text-red-500 text-[10px] text-center">{@token_error}</p>
            <% end %>

            <button
              type="submit"
              class="arcade-btn w-full border-yellow-400 text-yellow-400 hover:bg-yellow-400 hover:text-black py-3"
            >
              <span class="text-[10px]">VERIFY TOKEN</span>
            </button>
          </.form>

          <div class="mt-6 text-center">
            <p class="text-[8px] text-cyan-700">
              The setup token was displayed when you ran the install script.
            </p>
          </div>
        <% else %>
          <!-- Normal Sign In -->
          <div class="text-center mb-8">
            <h2 class="text-sm text-cyan-400 mb-2">PLAYER LOGIN</h2>
            <p class="text-[8px] text-cyan-700">AUTHENTICATE TO ACCESS COMMAND CENTER</p>
          </div>
          
    <!-- GitHub Sign In Button -->
          <a
            href="/auth/user/github"
            class="arcade-btn w-full flex items-center justify-center gap-3 border-white text-white hover:border-cyan-400 hover:text-cyan-400 py-4"
          >
            <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
              <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z" />
            </svg>
            <span class="text-[10px]">SIGN IN WITH GITHUB</span>
          </a>
        <% end %>
        
    <!-- Insert Coin Animation -->
        <div class="mt-8 text-center">
          <p class="text-[8px] text-cyan-600 blink">
            <%= if @needs_setup && !@setup_token_validated do %>
              FIRST PLAYER SETUP REQUIRED
            <% else %>
              INSERT CREDENTIALS TO CONTINUE
            <% end %>
          </p>
        </div>
      </div>
      
    <!-- Bottom Decoration -->
      <div class="mt-12 flex justify-center">
        <div class="flex items-center gap-4 text-[10px] text-cyan-600">
          <span>▂▂▂</span>
          <span class="text-green-500">SHIELDS</span>
          <span>▂▂▂</span>
          <span>▂▂▂</span>
          <span class="text-green-500">READY</span>
          <span>▂▂▂</span>
        </div>
      </div>
      
    <!-- Credit Insert -->
      <div class="text-center mt-6 text-[8px] text-cyan-700" aria-hidden="true">
        CREDIT 00
      </div>
    </main>
    """
  end
end
