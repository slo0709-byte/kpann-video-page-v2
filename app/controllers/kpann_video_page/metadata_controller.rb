# frozen_string_literal: true

module ::KpannVideoPage
  # 按需补抓视频元数据（标题 / 封面 / 时长）。
  # 帖子发布或编辑时插件已经抓过一次；这里给「当时没抓到」的条目一次重试机会，
  # 由前台发现某一条没标题或没封面时调用，同一个帖子 10 分钟最多抓一次。
  class MetadataController < ::ApplicationController
    requires_plugin "kpann-video-page"

    REFETCH_KEY = "kpann_video_meta_refetch"
    REFETCH_TTL = 600

    def show
      topic = Topic.find_by(id: params[:topic_id])
      raise Discourse::NotFound if topic.nil?

      guardian.ensure_can_see!(topic)

      refetch(topic) if needs_refetch?(topic)

      render json: {
               videos: stored_videos(topic),
               cover: topic.custom_fields[::KpannVideoCovers::FIELD],
               embed: topic.custom_fields[::KpannVideoCovers::EMBED_FIELD],
               duration: topic.custom_fields[::KpannVideoCovers::DURATION_FIELD],
             }
    end

    private

    def stored_videos(topic)
      raw = topic.custom_fields[::KpannVideoCovers::VIDEOS_FIELD]
      return [] if raw.blank?

      parsed = JSON.parse(raw)
      parsed.is_a?(Array) ? parsed : []
    rescue JSON::ParserError
      []
    end

    def needs_refetch?(topic)
      videos = stored_videos(topic)
      return true if videos.empty?

      videos.any? { |video| video["title"].blank? || video["cover"].blank? }
    end

    def refetch(topic)
      key = "#{REFETCH_KEY}:#{topic.id}"
      return if Discourse.redis.get(key)

      Discourse.redis.setex(key, REFETCH_TTL, "1")
      ::KpannVideoCovers.store_for_topic(topic)
    rescue StandardError => e
      Rails.logger.warn("[kpann-video-page] metadata refetch failed: #{e.message}")
    end
  end
end
