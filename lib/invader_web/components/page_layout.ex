defmodule InvaderWeb.PageLayout do
  @moduledoc """
  Provides a consistent arcade-themed page layout for all pages.
  """
  use Phoenix.Component

  import InvaderWeb.CoreComponents, only: [flash: 1]

  attr :page_title, :string, default: "Invader"
  attr :show_back_button, :boolean, default: true
  attr :back_link, :string, default: "/"
  attr :flash, :map, default: %{}
  slot :inner_block, required: true
  slot :header_actions

  def arcade_page(assigns) do
    ~H"""
    <.flash kind={:info} flash={@flash} />
    <.flash kind={:error} flash={@flash} />
    <main
      class="arcade-container min-h-screen bg-black p-2 sm:p-4 relative z-10"
      role="main"
    >
      <!-- CRT Scanlines Overlay -->
      <div class="crt-overlay pointer-events-none fixed inset-0 z-40" aria-hidden="true"></div>
      
    <!-- Header -->
      <header class="text-center mb-4 sm:mb-6 relative">
        <div :if={@show_back_button} class="absolute left-0 top-0">
          <.link
            navigate={@back_link}
            class="arcade-btn border-cyan-700 text-cyan-500 p-1.5 hover:border-cyan-400 hover:text-cyan-400 inline-flex items-center gap-1"
          >
            <svg viewBox="0 0 16 16" class="w-4 h-4 fill-current" style="image-rendering: pixelated;">
              <rect x="0" y="7" width="12" height="2" />
              <rect x="0" y="5" width="2" height="2" />
              <rect x="0" y="9" width="2" height="2" />
              <rect x="2" y="3" width="2" height="2" />
              <rect x="2" y="11" width="2" height="2" />
              <rect x="4" y="1" width="2" height="2" />
              <rect x="4" y="13" width="2" height="2" />
            </svg>
            <span class="text-[10px]">BACK</span>
          </.link>
        </div>

        <div :if={@header_actions != []} class="absolute right-0 top-0 flex gap-1">
          {render_slot(@header_actions)}
        </div>

        <h1 class="text-2xl md:text-3xl font-bold tracking-widest arcade-glow">
          {@page_title}
        </h1>
      </header>
      
    <!-- Content -->
      <div class="arcade-panel p-3 sm:p-4">
        {render_slot(@inner_block)}
      </div>
      
    <!-- Bottom Decoration -->
      <div class="mt-4 sm:mt-6 flex justify-center">
        <div class="flex items-center gap-2 sm:gap-4 text-[8px] sm:text-[10px] text-cyan-600">
          <span>---</span>
          <span class="text-green-500">INVADER</span>
          <span>---</span>
        </div>
      </div>
    </main>
    """
  end
end
