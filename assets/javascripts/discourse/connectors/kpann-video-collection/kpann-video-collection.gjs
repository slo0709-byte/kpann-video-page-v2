import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { service } from "@ember/service";
import { modifier } from "ember-modifier";
import dIcon from "discourse/ui-kit/helpers/d-icon";

// 一帖多视频时的合集。
// 桌面：右侧 340px 栏（CSS 把 #topic 变成 1fr + 340 两列，这里只是列表内容）
// 手机：一条「视频合集 N / 第几集」的条，点开从底部升起的抽屉
// 数据来自 topic.kpann_videos（服务端序列化），选中第几个交给 kpvPlayer。
export default class KpannVideoCollection extends Component {
  @service siteSettings;
  @service kpvPlayer;

  @tracked open = false;
  @tracked dragY = 0;

  // 组件销毁（换页/换帖）时把滚动锁解开，别把整站锁死
  willDestroy() {
    document.documentElement.classList.remove("kpv-sheet-open");
    super.willDestroy(...arguments);
  }

  get topic() {
    return this.args.model || this.args.outletArgs?.model;
  }

  get enabledCategories() {
    return String(this.siteSettings.kpann_gallery_categories || "")
      .split("|")
      .filter(Boolean)
      .map(Number);
  }

  get isVideoTopic() {
    const id = Number(this.topic?.category?.id || this.topic?.category_id);
    return !!id && this.enabledCategories.includes(id);
  }

  get videos() {
    const list = this.topic?.kpann_videos;
    return this.isVideoTopic && Array.isArray(list) ? list : [];
  }

  get show() {
    return this.videos.length > 1;
  }

  get currentIndex() {
    return this.kpvPlayer.indexFor(this.topic?.id);
  }

  get current() {
    return this.items[this.currentIndex] || this.items[0] || null;
  }

  get currentNumber() {
    return this.currentIndex + 1;
  }

  get items() {
    const topicTitle = (this.topic?.title || "视频").trim();
    const topicCover = this.topic?.kpann_cover_url || null;

    return this.videos.map((video, index) => {
      const own = typeof video?.title === "string" ? video.title.trim() : "";
      const duration = this.#duration(video?.duration);
      const provider =
        video?.provider === "bilibili"
          ? "B站"
          : video?.provider === "youtube"
            ? "YouTube"
            : "视频";

      return {
        index,
        cover: video?.cover || (index === 0 ? topicCover : null),
        duration,
        name: own || `${topicTitle} · 第 ${index + 1} 集`,
        sub: [provider, duration].filter(Boolean).join(" · "),
        current: index === this.currentIndex,
      };
    });
  }

  #duration(seconds) {
    const total = Math.round(Number(seconds) || 0);
    if (!total) {
      return "";
    }
    return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`;
  }

  @action
  toggleDrawer() {
    this.open = !this.open;
    this.#syncBodyLock();
  }



  @action
  closeDrawer() {
    this.open = false;
    this.dragY = 0;
    this.#syncBodyLock();
  }

  // 跟沉浸式评论抽屉一样：打开时锁住页面滚动，只有抽屉里能滚
  #syncBodyLock() {
    document.documentElement.classList.toggle("kpv-sheet-open", this.open);
  }

  // 下拉关闭
  // 用 ember-modifier 注册原生监听：Ember 的 {{on}} 修饰符给 touchmove
  // 挂的是 passive 监听，passive 下 preventDefault() 无效，
  // 真机下拉会被浏览器当成滚动抢走，抽屉就"拖不动"。
  #startY = null;
  #pulling = false;

  #atListTop() {
    const list = this.#sheetElement?.querySelector(".kpv-coll__list");
    return !list || list.scrollTop <= 0;
  }

  #sheetElement = null;

  sheetGestures = modifier((element) => {
    this.#sheetElement = element;

    const onStart = (event) => {
      const inList = !!event.target?.closest?.(".kpv-coll__list");
      // 列表没滚到顶时，下拉是滚列表
      if (inList && !this.#atListTop()) {
        this.#startY = null;
        this.#pulling = false;
        return;
      }
      this.#startY = event.touches?.[0]?.clientY ?? null;
      this.#pulling = false;
    };

    const onMove = (event) => {
      if (this.#startY == null) {
        return;
      }
      const y = event.touches?.[0]?.clientY ?? this.#startY;
      const dy = y - this.#startY;
      if (dy <= 0) {
        // 往上推：交还给列表滚动
        this.dragY = 0;
        this.#pulling = false;
        return;
      }
      this.#pulling = true;
      this.dragY = dy;
      if (event.cancelable) {
        event.preventDefault();
      }
    };

    const onEnd = () => {
      const shouldClose = this.#pulling && this.dragY > 80;
      this.#startY = null;
      this.#pulling = false;
      this.dragY = 0;
      if (shouldClose) {
        this.closeDrawer();
      }
    };

    element.addEventListener("touchstart", onStart, { passive: true });
    element.addEventListener("touchmove", onMove, { passive: false });
    element.addEventListener("touchend", onEnd, { passive: true });
    element.addEventListener("touchcancel", onEnd, { passive: true });

    return () => {
      element.removeEventListener("touchstart", onStart);
      element.removeEventListener("touchmove", onMove);
      element.removeEventListener("touchend", onEnd);
      element.removeEventListener("touchcancel", onEnd);
      if (this.#sheetElement === element) {
        this.#sheetElement = null;
      }
    };
  });

  // 抽屉的初始位置用内联样式写死：插件 CSS 是运行时注入的，
  // 等它到位之前抽屉会先按原位渲染一遍（手机上一进页面就闪一下合集列表）。
  get sheetStyle() {
    if (this.dragY > 0) {
      return `transform: translateY(${this.dragY}px); transition: none;`;
    }
    if (!this.open) {
      // 主题有更强的 transform 规则，这里必须带 !important 才能真的藏在屏幕外
      return "transform: translateY(100%) !important;";
    }
    return null;
  }

  @action
  play(item) {
    this.kpvPlayer.select(this.topic?.id, item.index);
    this.open = false;
    this.dragY = 0;
    this.#syncBodyLock();
    // 选完这一集：播放器露出来不足三成时才滚回顶部，露得多就别动页面
    const stage = document.querySelector(".kpv__stage");
    if (stage) {
      const rect = stage.getBoundingClientRect();
      const visible = Math.min(rect.bottom, window.innerHeight) - Math.max(rect.top, 0);
      const ratio = rect.height > 0 ? Math.max(0, visible) / rect.height : 0;
      if (ratio < 0.3) {
        stage.scrollIntoView({ behavior: "smooth", block: "start" });
      }
    }
  }

  <template>
    {{#if this.show}}
      <section class="kpv-coll {{if this.open 'is-open'}}">
        <button
          type="button"
          class="kpv-coll__bar"
          {{on "click" this.toggleDrawer}}
        >
          <span class="kpv-coll__bar-thumb {{unless this.current.cover 'is-empty'}}">
            {{#if this.current.cover}}
              <img src={{this.current.cover}} alt="" loading="lazy">
            {{else}}
              {{dIcon "play"}}
            {{/if}}
          </span>
          <span class="kpv-coll__bar-text">
            <span class="kpv-coll__bar-title">
              视频合集 · {{this.videos.length}} 个
            </span>
            <span class="kpv-coll__bar-sub">
              第 {{this.currentNumber}} 集 · {{this.current.name}}
            </span>
          </span>
          {{dIcon "chevron-up"}}
        </button>

        <div class="kpv-coll__backdrop" {{on "click" this.toggleDrawer}}></div>

        <div
          class="kpv-coll__sheet"
          style={{this.sheetStyle}}
          {{this.sheetGestures}}
        >
          <div class="kpv-coll__handle"></div>
          <header class="kpv-coll__head">
            <span class="kpv-coll__title">视频合集</span>
            <span class="kpv-coll__count">{{this.videos.length}} 个</span>
            <button
              type="button"
              class="kpv-coll__close"
              title="收起"
              {{on "click" this.toggleDrawer}}
            >
              {{dIcon "xmark"}}
            </button>
          </header>
          <div class="kpv-coll__list">
            {{#each this.items key="index" as |item|}}
              <button
                type="button"
                class="kpv-coll__item {{if item.current 'is-current'}}"
                {{on "click" (fn this.play item)}}
              >
                <span class="kpv-coll__thumb {{unless item.cover 'is-empty'}}">
                  {{#if item.cover}}
                    <img src={{item.cover}} alt="" loading="lazy">
                  {{else}}
                    {{dIcon "play"}}
                  {{/if}}
                  {{#if item.duration}}
                    <span class="kpv-coll__dur">{{item.duration}}</span>
                  {{/if}}
                </span>
                <span class="kpv-coll__meta">
                  <span class="kpv-coll__name">{{item.name}}</span>
                  <span class="kpv-coll__sub">{{item.sub}}</span>
                </span>
              </button>
            {{/each}}
          </div>
        </div>
      </section>
    {{/if}}
  </template>
}
