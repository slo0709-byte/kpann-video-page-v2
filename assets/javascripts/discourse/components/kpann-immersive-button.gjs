import Component from "@glimmer/component";
import { service } from "@ember/service";
import getURL from "discourse/lib/get-url";
import dIcon from "discourse/ui-kit/helpers/d-icon";

// 动作排里的「沉浸」入口。
// 走官方 post-menu-buttons DAG 注册（见 initializers/kpann-video-page.js），
// 不插 DOM、不拆核心结构，平铺页和嵌套页共用同一处。
export default class KpannImmersiveButton extends Component {
  @service siteSettings;
  @service kpvPlayer;

  get topic() {
    // 帖子自己的 topic 优先：换到别的帖子时 kpvPlayer 里可能还留着上一个视频帖
    return this.args.post?.topic || this.kpvPlayer?.topic;
  }

  get show() {
    // 这个按钮每条回复都会渲染一次，只给首楼
    const number = this.args.post?.post_number;
    if (number && number !== 1) {
      return false;
    }
    const topic = this.topic;
    if (!topic) {
      return false;
    }
    const id = Number(topic.category?.id || topic.category_id);
    if (!id) {
      return false;
    }
    const enabled = String(this.siteSettings.kpann_gallery_categories || "")
      .split("|")
      .filter(Boolean)
      .map(Number);
    if (!enabled.includes(id)) {
      return false;
    }
    const videos = topic.kpann_videos;
    return (Array.isArray(videos) && videos.length > 0) || !!topic.kpann_embed_url;
  }

  get href() {
    const index = this.kpvPlayer?.indexFor(this.topic?.id) || 0;
    return getURL(`/shorts?topic=${this.topic?.id}&v=${index}`);
  }

  <template>
    {{#if this.show}}
      <a class="btn btn-flat kpann-immersive" href={{this.href}} title="沉浸模式">
        {{dIcon "play"}}
        <span class="d-button-label">沉浸</span>
      </a>
    {{/if}}
  </template>
}
