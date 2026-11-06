# frozen_string_literal: true

module ::KpannVideoPage
  class ShortsController < ::ApplicationController
    requires_plugin "kpann-video-page"

    def show
      render html: "", layout: true
    end
  end
end
