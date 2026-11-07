# frozen_string_literal: true

# name: kpann-video-page
# about: Kpann 视频列表卡片、视频观看页与沉浸模式（Discourse 路由）
# version: 1.4.0
# authors: kpann
# url: https://kpoppann.com

enabled_site_setting :kpann_video_page_enabled

register_asset "stylesheets/common/kpann-video-list.scss"
register_asset "stylesheets/common/kpann-video-page.scss"
register_asset "stylesheets/common/kpann-shorts.scss"
register_asset "stylesheets/common/kpann-video-topic.scss"
register_asset "stylesheets/common/kpann-video-classic.scss"


# ============================================================================
# 视频元数据（封面 / 播放地址 / 时长 / 一帖多视频）
# 原先是独立插件 kpann-video-covers，2026-11-01 并入本插件：视频页只需要装这一个插件。
# 作用：解析首楼里的 YouTube / B 站地址，把结果写进话题自定义字段，列表和观看页直接读。
# ============================================================================
module ::KpannVideoCovers
  FIELD = "kpann_cover_url"
  EMBED_FIELD = "kpann_embed_url"
  DURATION_FIELD = "kpann_duration"
  CACHE_FIELD = "kpann_cover_checked"
  # 一帖多视频：按出现顺序存整组（供沉浸页做合集）
  VIDEOS_FIELD = "kpann_videos"
  BACKFILL_KEY = "kpann_video_covers_backfill_v3"

  YOUTUBE_ID = /data-video-id="([A-Za-z0-9_\-]{6,})"/
  YOUTUBE_URL = %r{youtube\.com/(?:watch\?v=|embed/|shorts/)([A-Za-z0-9_\-]{6,})}
  YOUTU_BE = %r{youtu\.be/([A-Za-z0-9_\-]{6,})}
  # 帖子里可能还是原始链接（onebox 展开前），也可能是展开后的 iframe，两种都要认
  BILIBILI_BV = %r{(?:bvid=|/video/)(BV[0-9A-Za-z]{10})}i
  BILIBILI_AV = %r{bilibili\.com/video/av(\d+)}i
  B23_SHORT = %r{https?://b23\.tv/([A-Za-z0-9]+)}i
  VIDEO_ISH = %r{bilibili\.com|b23\.tv|youtu\.be|youtube\.com}i

  # 抓每个视频的标题 / 时长 / 封面（api.bilibili.com 从机房 IP 被挡，改用手机版页面）
  MOBILE_UA =
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
  META_STORE = "kpann_video_meta"

  class << self
    def youtube_id(cooked)
      return nil if cooked.blank?
      cooked[YOUTUBE_ID, 1] || cooked[YOUTUBE_URL, 1] || cooked[YOUTU_BE, 1]
    end

    def bilibili_bvid(cooked)
      return nil if cooked.blank?
      bv = cooked[BILIBILI_BV, 1]
      return bv if bv.present?
      av = cooked[BILIBILI_AV, 1]
      return "av#{av}" if av.present?
      short = cooked[B23_SHORT, 1]
      short.present? ? resolve_b23(short) : nil
    end

    # b23.tv 短链：跟一次 302 拿到真实地址里的 BV 号
    def resolve_b23(code)
      uri = URI("https://b23.tv/#{code}")
      http = Net::HTTP.new(uri.host, 443)
      http.use_ssl = true
      http.open_timeout = 3
      http.read_timeout = 5
      response = http.request(Net::HTTP::Get.new(uri))
      location = response["location"].to_s
      location[BILIBILI_BV, 1]
    rescue StandardError
      nil
    end

    def youtube_cover(video_id)
      "https://i.ytimg.com/vi/#{video_id}/hqdefault.jpg"
    end

    def http_get(url, headers = {})
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 3
      http.read_timeout = 5
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = headers.delete(:ua) || "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
      headers.each { |k, v| request[k] = v if k.is_a?(String) }
      response = http.request(request)
      response.code == "200" ? response.body.to_s : nil
    rescue StandardError
      nil
    end

    # B 站：封面和时长一次拿到。机房 IP 被反爬时返回 nil
    def bilibili_meta(bvid)
      # B 站 WAF：带浏览器 UA 或 Referer 会返回 HTML 挑战页，只认 curl 这类朴素 UA
      query = bvid.start_with?("av") ? "aid=#{bvid.delete_prefix("av")}" : "bvid=#{bvid}"
      body = http_get("https://api.bilibili.com/x/web-interface/view?#{query}", { ua: "curl/8.5.0" })
      return {} if body.blank? || !body.lstrip.start_with?("{")
      json = JSON.parse(body) rescue nil
      return {} unless json && json["code"] == 0
      data = json["data"] || {}
      pic = data["pic"]
      {
        title: data["title"].to_s.strip.presence,
        cover: pic.present? ? pic.sub(%r{\Ahttp://}, "https://") : nil,
        duration: data["duration"].to_i > 0 ? data["duration"].to_i : nil,
      }
    rescue StandardError
      {}
    end

    # 会跟跳转的 GET（m.bilibili.com 会 302 到带 site/lang 的地址）
    def http_get_follow(url, headers = {}, limit = 3)
      return nil if limit < 0
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 3
      http.read_timeout = 5
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = headers[:ua] || "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
      headers.each { |k, v| request[k] = v if k.is_a?(String) }
      response = http.request(request)
      if response.is_a?(Net::HTTPRedirection) && response["location"].present?
        return http_get_follow(URI.join(url, response["location"]).to_s, headers, limit - 1)
      end
      response.code == "200" ? response.body.to_s : nil
    rescue StandardError
      nil
    end

    # B 站手机版页面一次拿全标题 / 时长 / 封面
    def bilibili_page_meta(bvid)
      return {} unless bvid.to_s.start_with?("BV")
      html = http_get_follow("https://m.bilibili.com/video/#{bvid}", ua: MOBILE_UA)
      return {} if html.blank?
      html = html.dup.force_encoding(Encoding::UTF_8)
      html = html.scrub("") unless html.valid_encoding?

      title =
        html[/property="og:title"\s+content="([^"]*)"/m, 1] ||
          html[%r{<title>\s*([^<]*?)\s*</title>}, 1]
      title =
        ERB::Util.html_unescape(title.to_s)
          .sub(%r{_哔哩哔哩_bilibili\s*\z}, "")
          .strip
          .presence

      seconds = html[/property="video:duration"\s+content="(\d+)"/, 1].to_i
      if seconds <= 0 && (iso = html[/"duration"\s*:\s*"PT([^"]*)"/, 1])
        total =
          iso[/(\d+)H/, 1].to_i * 3600 + iso[/(\d+)M/, 1].to_i * 60 + iso[/(\d+)S/, 1].to_i
        seconds = total
      end

      cover = html[/property="og:image"\s+content="([^"]*)"/m, 1]
      cover = cover.to_s.sub(%r{\Ahttp://}, "https://").presence

      { title: title, duration: (seconds > 0 ? seconds : nil), cover: cover }
    rescue StandardError
      {}
    end

    def youtube_meta(video_id)
      body =
        http_get(
          "https://www.youtube.com/oembed?url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3D#{video_id}&format=json",
        )
      json = (JSON.parse(body.to_s) rescue nil)
      return {} unless json.is_a?(Hash)
      {
        title: json["title"].to_s.strip.presence,
        duration: youtube_duration(video_id),
        cover: json["thumbnail_url"],
      }
    rescue StandardError
      {}
    end

    # 单个视频的元数据：先查缓存，再抓一次页面
    def entry_meta(entry)
      key = "v2_#{entry["id"]}"
      cached = PluginStore.get(META_STORE, key)
      if cached.present?
        parsed = (JSON.parse(cached) rescue nil)
        return parsed if parsed.is_a?(Hash) && parsed["title"].present?
      end

      raw =
        begin
          if entry["provider"] == "bilibili"
            meta = bilibili_page_meta(entry["id"])
            meta = bilibili_meta(entry["id"]) if meta.values.compact.empty?
            meta
          else
            youtube_meta(entry["id"])
          end
        rescue StandardError
          {}
        end

      meta =
        (raw || {}).each_with_object({}) do |(k, v), hash|
          hash[k.to_s] = v if v.present?
        end
      PluginStore.set(META_STORE, key, meta.to_json) if meta.present?
      meta
    end

    def enrich_entry(entry)
      meta = entry_meta(entry)
      entry["title"] = meta["title"] if meta["title"].present?
      duration = meta["duration"].to_i
      entry["duration"] = duration if duration > 0
      cover = meta["cover"]
      if entry["cover"].blank? && cover.present?
        entry["cover"] =
          if entry["provider"] == "bilibili"
            cover_upload_for(entry["id"], cover) || cover
          else
            cover
          end
      end
      entry
    end

    def youtube_duration(video_id)
      body = http_get("https://www.youtube.com/watch?v=#{video_id}", { "Accept-Language" => "en" })
      return nil if body.blank?
      seconds = body[/"lengthSeconds":"(\d+)"/, 1]
      seconds && seconds.to_i > 0 ? seconds.to_i : nil
    end

    # 二进制下载：B 站图有 Referer 防盗链，浏览器直连会 403，只能服务端取回转存
    def http_get_binary(url)
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = 10
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "curl/8.5.0"
      request["Referer"] = "https://www.bilibili.com/" if uri.host.to_s.end_with?("hdslb.com")
      response = http.request(request)
      response.code == "200" ? response.body : nil
    rescue StandardError
      nil
    end

    def cover_upload_for(bvid, pic_url)
      return nil if pic_url.blank?
      key = "cover_upload_#{bvid}"
      stored_id = PluginStore.get("kpann_video_covers", key)
      if stored_id.present?
        upload = Upload.find_by(id: stored_id)
        return upload.url if upload
      end

      body = http_get_binary(pic_url)
      return nil if body.blank?

      tmp = Tempfile.new(["kpann-cover", ".jpg"])
      tmp.binmode
      tmp.write(body)
      tmp.close
      file = File.open(tmp.path)
      upload =
        UploadCreator.new(file, "kpann-#{bvid}.jpg", skip_validations: true).create_for(
          Discourse.system_user.id,
        )
      file.close
      tmp.unlink
      return nil if upload.nil?

      PluginStore.set("kpann_video_covers", key, upload.id)
      upload.url
    rescue StandardError => e
      Rails.logger.warn("[kpann-video-covers] cover upload failed: #{e.message}")
      nil
    end

    # 首楼里所有视频，按出现顺序，去重。返回 [{provider, id, embed, cover}]
    def video_entries(cooked)
      pattern = /
        data-video-id="(?<yt_a>[\w-]{6,})"
        | youtube\.com\/(?:watch\?v=|embed\/|shorts\/)(?<yt_b>[\w-]{6,})
        | youtu\.be\/(?<yt_c>[\w-]{6,})
        | (?:bvid=|\/video\/)(?<bv>BV[0-9A-Za-z]{10})
        | bilibili\.com\/video\/av(?<av>\d+)
      /xi
      entries = []
      seen = {}
      cooked.to_s.scan(pattern) do
        m = Regexp.last_match
        youtube = m[:yt_a].presence || m[:yt_b].presence || m[:yt_c].presence
        if youtube
          key = "yt:#{youtube}"
          next if seen[key]
          seen[key] = true
          entries << {
            "provider" => "youtube",
            "id" => youtube,
            "embed" => "https://www.youtube.com/embed/#{youtube}?rel=0&modestbranding=1",
            "cover" => youtube_cover(youtube),
          }
        else
          bvid = m[:bv].presence
          bvid = "av#{m[:av]}" if bvid.nil? && m[:av].present?
          next if bvid.nil?
          key = "bi:#{bvid}"
          next if seen[key]
          seen[key] = true
          param = bvid.start_with?("av") ? "aid=#{bvid.delete_prefix("av")}" : "bvid=#{bvid}"
          entries << {
            "provider" => "bilibili",
            "id" => bvid,
            "embed" => "https://player.bilibili.com/player.html?#{param}&page=1&high_quality=1&autoplay=0",
            "cover" => nil,
          }
        end
      end
      entries
    end

    def store_for_topic(topic)
      return if topic.nil?
      post = topic.first_post
      return if post.nil?

      cooked = post.cooked.to_s
      video_id = youtube_id(cooked)
      bvid = video_id ? nil : bilibili_bvid(cooked)

      if video_id
        topic.custom_fields[FIELD] = youtube_cover(video_id)
        topic.custom_fields[EMBED_FIELD] =
          "https://www.youtube.com/embed/#{video_id}?rel=0&modestbranding=1"
      elsif bvid
        meta = bilibili_meta(bvid)
        meta = bilibili_page_meta(bvid) if meta[:cover].blank? && meta[:duration].blank?
        if meta[:cover].present?
          topic.custom_fields[FIELD] = cover_upload_for(bvid, meta[:cover]) || meta[:cover]
        end
        topic.custom_fields[DURATION_FIELD] = meta[:duration] if meta[:duration].present?
        page = cooked[/[?&]page=(\d+)/, 1] || "1"
        key = bvid.start_with?("av") ? "aid=#{bvid.delete_prefix("av")}" : "bvid=#{bvid}"
        topic.custom_fields[EMBED_FIELD] =
          "https://player.bilibili.com/player.html?#{key}&page=#{page}&high_quality=1&autoplay=0"
      end

      entries = video_entries(cooked).map { |entry| enrich_entry(entry) }
      if entries.any?
        topic.custom_fields[VIDEOS_FIELD] = entries.to_json
      elsif topic.custom_fields[VIDEOS_FIELD].present?
        topic.custom_fields[VIDEOS_FIELD] = nil
      end

      # 只对「看起来就不是视频帖」的打标记，避免 onebox 还没展开时把帖子永久跳过
      if video_id.nil? && bvid.nil? && cooked !~ VIDEO_ISH
        topic.custom_fields[CACHE_FIELD] = "1"
      end

      topic.save_custom_fields(true)

      if video_id && topic.custom_fields[DURATION_FIELD].blank?
        Jobs.enqueue(:kpann_video_duration, topic_id: topic.id)
      end
    end
  end
end

after_initialize do
  require_relative "app/controllers/kpann_video_page/shorts_controller"
  require_relative "app/controllers/kpann_video_page/metadata_controller"

  Discourse::Application.routes.append do
    get "/shorts" => "kpann_video_page/shorts#show"
    # 前台发现某一条视频没抓到标题/封面时，来这里让它重试一次
    get "/kpann-video-page/metadata/:topic_id" => "kpann_video_page/metadata#show"
  end

  # 作者取 1 楼作者（first_post.user），不是帖子创建者：
  # 改过归属的帖子两者不同，用创建者会显示成别人
  add_to_serializer(:topic_list_item, :kpann_poster_username) do
    (object.first_post&.user || object.user)&.username
  end
  add_to_serializer(:topic_list_item, :kpann_poster_avatar) do
    (object.first_post&.user || object.user)&.avatar_template
  end
  add_to_serializer(:topic_list_item, :kpann_poster_id) do
    (object.first_post&.user || object.user)&.id
  end

  # 沉浸页点赞要用首楼 id + 「我能不能赞 / 撤不撤销得了」。
  # 这几个值核心序列化器本来就有（first_post_id / op_liked / op_can_like），
  # 默认不输出，靠官方这个 modifier 开关打开，不自己算一遍权限。
  register_modifier(:serialize_topic_op_likes_data) { true }

  # 沉浸页简介：拿首楼纯文本，保留段落换行（不要把换行压成空格）
  # <p> / <br> / </div> 转成换行，其余标签去掉；连续空行压到一个
  add_to_serializer(:topic_list_item, :kpann_excerpt) do
    post = object.first_post
    html = post&.cooked.to_s
    html = html.gsub(%r{<br\s*/?>}i, "\n")
    html = html.gsub(%r{</p>}i, "\n\n")
    html = html.gsub(%r{</div>}i, "\n")
    html = html.gsub(%r{</li>}i, "\n")
    text = html.gsub(/<[^>]+>/, "")
    text = CGI.unescapeHTML(text.to_s)
    text = text.gsub(/[ \t]+/, " ")           # 行内空白归一
    text = text.gsub(/\n{3,}/, "\n\n")         # 最多空一行
    text.strip.truncate(400)
  end
end

after_initialize do
  register_topic_custom_field_type(::KpannVideoCovers::FIELD, :string)
  register_topic_custom_field_type(::KpannVideoCovers::EMBED_FIELD, :string)
  register_topic_custom_field_type(::KpannVideoCovers::DURATION_FIELD, :integer)
  register_topic_custom_field_type(::KpannVideoCovers::CACHE_FIELD, :string)
  register_topic_custom_field_type(::KpannVideoCovers::VIDEOS_FIELD, :string)

  [::KpannVideoCovers::FIELD, ::KpannVideoCovers::EMBED_FIELD, ::KpannVideoCovers::DURATION_FIELD, ::KpannVideoCovers::VIDEOS_FIELD].each do |name|
    add_preloaded_topic_list_custom_field(name)
  end

  add_to_serializer(:topic_list_item, :kpann_cover_url) { object.custom_fields[::KpannVideoCovers::FIELD] }
  add_to_serializer(:topic_list_item, :kpann_embed_url) { object.custom_fields[::KpannVideoCovers::EMBED_FIELD] }
  add_to_serializer(:topic_list_item, :kpann_duration) { object.custom_fields[::KpannVideoCovers::DURATION_FIELD] }
  # 沉浸页合集：一帖多视频的完整列表
  add_to_serializer(:topic_list_item, :kpann_videos) do
    raw = object.custom_fields[::KpannVideoCovers::VIDEOS_FIELD]
    begin
      raw.present? ? JSON.parse(raw) : []
    rescue JSON::ParserError
      []
    end
  end

  # 列表卡片要显示"频道"（作者），列表负载里没有这个字段，这里补上
  add_to_serializer(:topic_list_item, :kpann_author_username) do
    object.first_post&.user&.username
  end
  add_to_serializer(:topic_list_item, :kpann_author_avatar) do
    user = object.first_post&.user
    user && user.avatar_template_url.gsub("{size}", "48")
  end

  add_to_serializer(:topic_view, :kpann_cover_url) { object.topic.custom_fields[::KpannVideoCovers::FIELD] }
  add_to_serializer(:topic_view, :kpann_embed_url) { object.topic.custom_fields[::KpannVideoCovers::EMBED_FIELD] }
  add_to_serializer(:topic_view, :kpann_duration) { object.topic.custom_fields[::KpannVideoCovers::DURATION_FIELD] }
  add_to_serializer(:topic_view, :kpann_videos) do
    raw = object.topic.custom_fields[::KpannVideoCovers::VIDEOS_FIELD]
    begin
      raw.present? ? JSON.parse(raw) : []
    rescue JSON::ParserError
      []
    end
  end

  on(:post_created) do |post|
    ::KpannVideoCovers.store_for_topic(post.topic) if post.post_number == 1
  end

  on(:post_edited) do |post|
    ::KpannVideoCovers.store_for_topic(post.topic) if post.post_number == 1
  end

  class ::Jobs::KpannVideoDuration < ::Jobs::Base
    def execute(args)
      topic = Topic.find_by(id: args[:topic_id])
      return if topic.nil?
      post = topic.first_post
      return if post.nil?
      video_id = ::KpannVideoCovers.youtube_id(post.cooked.to_s)
      return if video_id.nil?
      seconds = ::KpannVideoCovers.youtube_duration(video_id)
      return if seconds.nil?
      topic.custom_fields[::KpannVideoCovers::DURATION_FIELD] = seconds
      topic.save_custom_fields(true)
    end
  end

  class ::Jobs::KpannVideoCoversBackfill < ::Jobs::Base
    def execute(_args)
      filled = 0
      Topic.where(deleted_at: nil).in_batches(of: 200) do |batch|
        batch.each do |topic|
          next if topic.custom_fields[::KpannVideoCovers::EMBED_FIELD].present? &&
                  topic.custom_fields[::KpannVideoCovers::DURATION_FIELD].present?
          next if topic.custom_fields[::KpannVideoCovers::CACHE_FIELD].present?
          ::KpannVideoCovers.store_for_topic(topic)
          filled += 1
        end
      end
      Rails.logger.warn("[kpann-video-covers] backfill filled=#{filled}")
    end
  end

  if Discourse.redis.set(::KpannVideoCovers::BACKFILL_KEY, "1", nx: true)
    Jobs.enqueue(:kpann_video_covers_backfill)
  end
end


