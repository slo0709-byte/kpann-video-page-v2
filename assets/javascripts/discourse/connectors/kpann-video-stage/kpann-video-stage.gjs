import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import willDestroy from "@ember/render-modifiers/modifiers/will-destroy";
import { service } from "@ember/service";
import getURL from "discourse/lib/get-url";
import dIcon from "discourse/ui-kit/helpers/d-icon";

// 视频帖顶部播放器：16:9 的一格。
// 地址来自服务端序列化的 topic.kpann_videos / kpann_embed_url；
// 只在后台设置 kpann_gallery_categories 里的分类生效，别的分类不受影响。
// 这里只做渲染，不搬任何原生节点，也不在渲染后改 DOM。
export default class KpannVideoStage extends Component {
  @service siteSettings;

  // 播放器自己那个「全屏」按钮的状态。
  // B 站 etc 自带的全屏只能在它自己的 iframe 里放大（网页全屏），落在 16:9 里等于没反应，
  // 所以这里对整个播放器容器做系统全屏：容器是本页面的节点，同源，不用跨域授权。
  @tracked isFullscreen = false;
  @service kpvPlayer;

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

  get index() {
    return this.kpvPlayer.indexFor(this.topic?.id);
  }

  get currentVideo() {
    return this.videos[this.index] || null;
  }

  get src() {
    if (!this.isVideoTopic) {
      return null;
    }
    return this.currentVideo?.embed || this.topic?.kpann_embed_url || null;
  }

  get provider() {
    return this.currentVideo?.provider || null;
  }

  get title() {
    return this.currentVideo?.title || this.topic?.title || "视频";
  }

  // B 站播放器在手机上要能全屏，得给 iframe 补 webkitallowfullscreen 和 encrypted-media
  get frameAllow() {
    return "autoplay; fullscreen; webkitallowfullscreen; picture-in-picture; encrypted-media";
  }

  // 只有一项：换集时这一项的值变了，keyed each 会重建 iframe 元素
  get frames() {
    return this.src ? [this.src] : [];
  }

  // PC 播放器下面那排分集胶囊（Gemini 方案 B）：P1 + 这一集自己的真标题。
  // 没抓到元数据时给「第 N 集」，不拿平台名当标题。
  get pills() {
    return this.videos.map((video, index) => ({
      index,
      label: `P${index + 1}`,
      title:
        (typeof video.title === "string" && video.title.trim()) ||
        this.pillDuration(video.duration) ||
        `第 ${index + 1} 集`,
      active: index === this.index,
    }));
  }

  pillDuration(seconds) {
    const total = Math.round(Number(seconds) || 0);
    if (!total) {
      return null;
    }
    return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`;
  }

  // 有合集就出胶囊排（单视频帖不出）
  get showPills() {
    return this.pills.length > 1;
  }

  get immersiveHref() {
    return getURL(`/shorts?topic=${this.topic?.id}&v=${this.index}`);
  }

  // 平铺页的动作排（post-menu-buttons DAG）靠这个拿到当前这条视频
  @action
  selectPill(index) {
    if (this.topic?.id != null) {
      this.kpvPlayer.select(this.topic.id, index);
    }
  }


  // 给 body 挂一个标记类：样式一律以它为作用域，桌面/手机、平铺/嵌套都通用
  @action
  markPage() {
    document.body.classList.add("kpv-on");
    this.kpvPlayer.setTopic(this.topic);

    // 从沉浸页退回来时带 ?kpv=N，直接选中那一集
    const raw = new URLSearchParams(window.location.search).get("kpv");
    const index = Number.parseInt(raw, 10);
    if (!Number.isNaN(index) && this.topic?.id != null) {
      this.kpvPlayer.select(this.topic.id, index);
    }

    // 用系统返回键 / Esc 退出全屏时，把按钮状态一起复位
    this.onFullscreenChange = () => {
      this.isFullscreen = !!(
        document.fullscreenElement || document.webkitFullscreenElement
      );
    };
    document.addEventListener("fullscreenchange", this.onFullscreenChange);
    document.addEventListener("webkitfullscreenchange", this.onFullscreenChange);
  }

  // 全屏：先试系统 API（对整个播放器容器），失败就退回 CSS 铺满整个视口
  @action
  async toggleFullscreen(event) {
    event?.preventDefault?.();
    event?.stopPropagation?.();

    const stage =
      event?.currentTarget?.closest?.(".kpv") ||
      document.querySelector("body.kpv-on .kpv");

    if (this.isFullscreen) {
      try {
        if (document.exitFullscreen) {
          await document.exitFullscreen();
        } else if (document.webkitExitFullscreen) {
          document.webkitExitFullscreen();
        }
      } catch (e) {
        // 退出失败就走下面的 CSS 状态
      }
      this.isFullscreen = false;
      return;
    }

    if (stage) {
      try {
        const request =
          stage.requestFullscreen ||
          stage.webkitRequestFullscreen ||
          stage.mozRequestFullScreen ||
          stage.msRequestFullscreen;
        if (request) {
          await request.call(stage);
          this.isFullscreen = true;
          return;
        }
      } catch (e) {
        // 系统全屏被拒（iOS Safari 等）：落到下面的 CSS 铺满
      }
    }

    this.isFullscreen = true;
  }

  @action
  unmarkPage() {
    document.body.classList.remove("kpv-on");
    this.kpvPlayer.setTopic(null);
    if (this.onFullscreenChange) {
      document.removeEventListener("fullscreenchange", this.onFullscreenChange);
      document.removeEventListener(
        "webkitfullscreenchange",
        this.onFullscreenChange
      );
      this.onFullscreenChange = null;
    }
  }

  <template>
    {{#if this.src}}
      <div
        class="kpv {{if this.isFullscreen 'is-fullscreen'}}"
        {{didInsert this.markPage}}
        {{willDestroy this.unmarkPage}}
      >
        <div class="kpv__stage">
          {{! 换集时重建 iframe（不要改同一个元素的 src）：改 src 会往浏览器历史里插一条，
              后退就会一集一集往回走。新建元素不产生历史条目。 }}
          {{#each this.frames key="@identity" as |src|}}
            <iframe
              class="kpv__frame"
              src={{src}}
              title={{this.title}}
              allow={{this.frameAllow}}
              allowfullscreen
              webkitallowfullscreen
              mozallowfullscreen
              frameborder="no"
              scrolling="no"
            ></iframe>
          {{/each}}

          {{! 全屏按钮：B 站自带的是「网页全屏」，关在 16:9 里等于没反应，
              这里给一个真系统全屏（对 .kpv 容器，同源）。只在手机显示。 }}
          <button
            type="button"
            class="kpv__fs"
            title={{if this.isFullscreen "退出全屏" "全屏"}}
            aria-label={{if this.isFullscreen "退出全屏" "全屏"}}
            {{on "click" this.toggleFullscreen}}
          >
            {{dIcon (if this.isFullscreen "compress" "expand")}}
          </button>
        </div>

        {{#if this.showPills}}
          <div class="kpv-pills">
            {{#each this.pills as |pill|}}
              <button
                type="button"
                class="kpv-pill {{if pill.active 'is-active'}}"
                title={{pill.title}}
                {{on "click" (fn this.selectPill pill.index)}}
              >
                <span class="kpv-pill__n">{{pill.label}}</span>
                <span class="kpv-pill__t">{{pill.title}}</span>
              </button>
            {{/each}}
          </div>
        {{/if}}
      </div>
    {{/if}}
  </template>
}
