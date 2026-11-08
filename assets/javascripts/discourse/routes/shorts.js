import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";
import { getOwner } from "@ember/owner";
import PreloadStore from "discourse/lib/preload-store";


// 分类不再写死：读后台设置「套用视频卡片样式的分类」的第一个分类
function galleryCategoryId(ctx) {
  let raw = null;
  try {
    raw = getOwner(ctx).lookup("service:site-settings")?.kpann_gallery_categories;
  } catch (e) {}
  if (!raw) {
    try {
      raw = PreloadStore.get("siteSettings")?.kpann_gallery_categories;
    } catch (e) {}
  }
  const ids = String(raw || "")
    .split("|")
    .filter(Boolean);
  return ids[0] || null;
}

export default class ShortsRoute extends DiscourseRoute {
  // v = 从内页进来时要播第几集；必须声明成 query param，
  // 否则 topic -> shorts 的一次客户端跳转会把这个参数丢掉（Ember 只保留已声明的 query param）
  queryParams = { topic: { refreshModel: false }, v: { refreshModel: false } };

  async model() {
    const categoryId = galleryCategoryId(this);
    if (!categoryId) {
      return [];
    }
    const data = await ajax(`/c/${categoryId}.json`, { data: { page: 0 } });

    const topics = (data.topic_list?.topics || [])
      .filter((topic) => topic.kpann_embed_url)
      .map((topic) => ({
        id: topic.id,
        slug: topic.slug,
        title: topic.title,
        excerpt: topic.kpann_excerpt || topic.excerpt || "",
        // 正文 HTML 片段（跟视频页同一套排版）：优先用服务端处理好的，
        // 里面已经把视频 iframe 整块拿掉，只剩标题、段落、列表
        excerptHtml: topic.kpann_excerpt_html || "",
        cover: topic.kpann_cover_url || topic.image_url || null,
        embed:
          topic.kpann_embed_url || (topic.kpann_videos?.[0]?.embed ?? null),
        videos: Array.isArray(topic.kpann_videos) ? topic.kpann_videos : [],
        videoCount: Array.isArray(topic.kpann_videos) ? topic.kpann_videos.length : 0,
        hasCollection:
          Array.isArray(topic.kpann_videos) && topic.kpann_videos.length > 1,
        videosJson:
          Array.isArray(topic.kpann_videos) && topic.kpann_videos.length
            ? JSON.stringify(topic.kpann_videos)
            : "",
        views: topic.views || 0,
        // 点赞的三个值都来自核心列表序列化器（由插件里 register_modifier 打开）：
        // first_post_id 调官方 reactions 接口，op_liked 决定红心，op_can_like 决定点得动点不动
        postId: topic.first_post_id || null,
        likes:
          typeof topic.op_like_count === "number"
            ? topic.op_like_count
            : topic.like_count || 0,
        liked: !!topic.op_liked,
        likeAction: topic.op_liked
          ? topic.op_can_like
            ? "undo"
            : "liked"
          : topic.op_can_like
            ? "act"
            : "none",
        // 评论数要排除首楼，跟原生列表口径一致
        posts: Math.max(0, (topic.posts_count || 1) - 1),
        posterName: topic.kpann_poster_username || "",
        posterAvatar: (topic.kpann_poster_avatar || "").replace("{size}", "96"),
        posterId: topic.kpann_poster_id || null,
      }));

    // 补抓在后台跑，不 await：补抓要打外站，慢的时候要好几秒，不能卡首屏
    this.refreshMissingMeta(topics);

    return topics;
  }

  // 个别集次没抓到标题/封面（B 站偶发反爬、YouTube oembed 抽风）：
  // 让服务端按需补抓一次（服务端自己限频），补到了就换成新的，没补到就走客户端的兵底样式。
  async refreshMissingMeta(topics) {
    if (!Array.isArray(topics)) {
      return topics;
    }

    const needs = topics
      .filter((topic) =>
        topic.videos.some((video) => !video.title || !video.cover)
      )
      .slice(0, 5);

    await Promise.all(
      needs.map(async (topic) => {
        try {
          const result = await ajax(
            `/kpann-video-page/metadata/${topic.id}.json`
          );
          if (!Array.isArray(result?.videos) || !result.videos.length) {
            return;
          }
          topic.videos = result.videos;
          topic.videosJson = JSON.stringify(result.videos);
          topic.cover = topic.cover || result.cover || result.videos[0]?.cover || null;
          // 幻灯片已经渲染出来了：把合集数据替换掉，点开合集就是补好的标题/封面
          const slide = document.querySelector(
            `.kp-slide[data-topic-id="${topic.id}"]`
          );
          if (slide) {
            slide.dataset.videos = topic.videosJson;
          }
        } catch (e) {
          // 补抓失败不影响页面：继续用现有的数据
        }
      })
    );

    return topics;
  }

  waitForTrack() {
    const started = Date.now();
    const tick = () => {
      const track = document.querySelector(".kp-shorts__track");
      if (track) {
        if (!track.dataset.kpBound) {
          track.dataset.kpBound = "1";
          track.addEventListener("scroll", () => this.syncSlides(), { passive: true });
        }
        if (this.pendingFocus) {
          this.jumpToEntryTopic();
          this.pendingFocus = false;
          requestAnimationFrame(() => track.classList.add("is-ready"));
        }
        return;
      }
      if (Date.now() - started < 5000) {
        requestAnimationFrame(tick);
      }
    };
    requestAnimationFrame(tick);
  }

  jumpToEntryTopic() {
    const topicId = new URLSearchParams(window.location.search).get("topic");
    if (!topicId) {
      return;
    }
    const track = document.querySelector(".kp-shorts__track");
    if (!track) {
      return;
    }
    const slides = Array.from(track.querySelectorAll(".kp-slide"));
    const index = slides.findIndex(
      (slide) => String(slide.dataset.topicId) === String(topicId)
    );
    if (index < 0) {
      return;
    }
    if (Math.abs(track.scrollTop - index * track.clientHeight) > 4) {
      track.scrollTop = index * track.clientHeight;
    }

    // 从内页带 ?v=N 进来：直接播那一集
    const wanted = Number.parseInt(
      new URLSearchParams(window.location.search).get("v"),
      10
    );
    if (!Number.isNaN(wanted) && wanted > 0) {
      let videos = [];
      try {
        videos = JSON.parse(slides[index].dataset.videos || "[]");
      } catch (e) {
        videos = [];
      }
      const embed = videos[wanted]?.embed;
      if (embed) {
        this.switchVideo(slides[index], embed);
      }
    }
  }

  syncSlides() {
    const track = document.querySelector(".kp-shorts__track");
    if (!track) {
      return;
    }

    const height = track.clientHeight || 1;
    const index = Math.round(track.scrollTop / height);

    track.querySelectorAll(".kp-slide__holder").forEach((holder, i) => {
      // 只给当前这一条挂播放器；滑走立即卸载，播放随之停止
      const near = i === index;
      const frame = holder.querySelector("iframe");

      if (near && !frame && holder.dataset.embed) {
        holder.appendChild(this.buildFrame(holder.dataset.embed));
      } else if (!near && frame) {
        frame.remove();
      }
    });
  }

  // 播放器 iframe：加载完（或 1.2 秒兜底）才淡入，底下有封面顶着，切换不闪
  buildFrame(embed) {
    const iframe = document.createElement("iframe");
    iframe.className = "kp-slide__frame";
    iframe.src = embed;
    iframe.setAttribute("frameborder", "0");
    iframe.setAttribute(
      "allow",
      "autoplay; encrypted-media; picture-in-picture; fullscreen"
    );
    iframe.setAttribute("allowfullscreen", "");
    // B 站播放器在手机上要能全屏，光有 allowfullscreen 不够
    iframe.setAttribute("webkitallowfullscreen", "");
    iframe.setAttribute("mozallowfullscreen", "");
    const reveal = () => iframe.classList.add("kp-frame-ready");
    iframe.addEventListener("load", () =>
      requestAnimationFrame(() => requestAnimationFrame(reveal))
    );
    setTimeout(reveal, 1200);
    return iframe;
  }

  formatDuration(seconds) {
    const total = Math.round(Number(seconds) || 0);
    if (!total) {
      return "";
    }
    const m = Math.floor(total / 60);
    const s = total % 60;
    return `${m}:${String(s).padStart(2, "0")}`;
  }

  // 一帖多视频：底部弹出合集列表
  // 合集里一条的标题：没抓到元数据时给「第 N 集」，不拿平台名当标题
  collectionTitle(video, index, slide) {
    const own = typeof video.title === "string" ? video.title.trim() : "";
    if (own) {
      return own;
    }
    const topicTitle = slide
      ?.querySelector(".kp-slide__title")
      ?.textContent?.trim();
    return topicTitle ? `${topicTitle} · 第 ${index + 1} 集` : `第 ${index + 1} 集`;
  }

  openCollection(slide) {
    if (!slide) {
      return;
    }
    // 上一次没关干净的先摘掉，避免连点两次打不开
    document.querySelector(".kp-collection")?.remove();
    let videos = [];
    try {
      videos = JSON.parse(slide.dataset.videos || "[]");
    } catch (e) {
      videos = [];
    }
    if (videos.length < 2) {
      return;
    }
    const current = slide.querySelector(".kp-slide__holder")?.dataset.embed || "";

    const sheet = document.createElement("div");
    sheet.className = "kp-collection";

    const panel = document.createElement("div");
    panel.className = "kp-collection__panel";

    const title = document.createElement("div");
    title.className = "kp-collection__title";
    title.textContent = `合集 ${videos.length}`;
    panel.appendChild(title);

    videos.forEach((video, index) => {
      const item = document.createElement("button");
      item.type = "button";
      item.className = "kp-collection__item";
      if (video.embed === current) {
        item.classList.add("is-current");
      }
      const thumb = document.createElement("span");
      thumb.className = "kp-collection__thumb";
      if (video.cover) {
        const img = document.createElement("img");
        img.src = video.cover;
        img.alt = "";
        img.loading = "lazy";
        thumb.appendChild(img);
      } else {
        const idx = document.createElement("span");
        idx.className = "kp-collection__index";
        idx.textContent = String(index + 1);
        thumb.appendChild(idx);
      }
      const meta = document.createElement("span");
      meta.className = "kp-collection__meta";
      const name = document.createElement("span");
      name.className = "kp-collection__name";
      name.textContent = this.collectionTitle(video, index, slide);
      const sub = document.createElement("span");
      sub.className = "kp-collection__sub";
      const provider = video.provider === "youtube" ? "YouTube" : "B站";
      const duration = video.duration ? this.formatDuration(video.duration) : "";
      sub.textContent = duration ? `${provider} · ${duration}` : provider;
      meta.appendChild(name);
      meta.appendChild(sub);
      item.appendChild(thumb);
      item.appendChild(meta);
      item.addEventListener("click", () => {
        this.switchVideo(slide, video.embed);
        this.closeCollection();
      });
      panel.appendChild(item);
    });

    const close = document.createElement("button");
    close.type = "button";
    close.className = "kp-collection__close";
    close.textContent = "关闭";
    close.addEventListener("click", () => this.closeCollection());
    panel.appendChild(close);

    sheet.appendChild(panel);
    sheet.addEventListener("click", (event) => {
      if (event.target === sheet) {
        this.closeCollection();
      }
    });
    document.body.appendChild(sheet);
    requestAnimationFrame(() => sheet.classList.add("is-open"));
  }

  closeCollection() {
    const sheet = document.querySelector(".kp-collection");
    if (!sheet) {
      return;
    }
    sheet.classList.remove("is-open");
    setTimeout(() => sheet.remove(), 220);
  }

  switchVideo(slide, embed) {
    const holder = slide?.querySelector(".kp-slide__holder");
    if (!holder || !embed || holder.dataset.embed === embed) {
      return;
    }
    holder.dataset.embed = embed;
    holder.querySelector("iframe")?.remove();
    holder.appendChild(this.buildFrame(embed));
  }

  async openComments(topicId, slug) {
    try {
      const mod = await import(
        "discourse/plugins/kpann-video-page/discourse/components/kp-comments-modal"
      );
      const modal = getOwner(this).lookup("service:modal");
      modal.show(mod.default, { model: { topicId, slug } });
    } catch (e) {
      // 保底：打不开就跳原生帖子页
      window.location.assign(`/t/${topicId}`);
    }
  }

  onClick = (event) => {
    const collectionBtn = event.target.closest(".kp-act--collection");
    if (collectionBtn) {
      event.preventDefault();
      this.openCollection(collectionBtn.closest(".kp-slide"));
      return;
    }
    const btn = event.target.closest(".kp-act--comment");
    if (!btn) {
      return;
    }
    event.preventDefault();
    this.openComments(btn.dataset.topic, btn.dataset.slug);
  };

  activate() {
    document.body.classList.add("kpann-shorts-route");
    this.onScroll = () => this.syncSlides();
    window.addEventListener("scroll", this.onScroll, true);
    document.addEventListener("click", this.onClick);
    this.pendingFocus = true;
    this.waitForTrack();
    setTimeout(() => this.syncSlides(), 600);
    setTimeout(() => this.syncSlides(), 1800);
  }

  deactivate() {
    document.body.classList.remove("kpann-shorts-route");
    if (this.onScroll) {
      window.removeEventListener("scroll", this.onScroll, true);
    }
    document.removeEventListener("click", this.onClick);
  }
}









