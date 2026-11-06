import Component from "@glimmer/component";
import { service } from "@ember/service";

// 作者行后面的「观看 N」。
// 走核心自带 outlet `post-metadata` 的 __after 子口，不改核心文件。
// 只在视频分类里出现，其它分类不受影响。
export default class KpannVideoViews extends Component {
  @service siteSettings;
  @service kpvPlayer;

  get topic() {
    return this.kpvPlayer?.topic;
  }

  get show() {
    // 这个 outlet 每条回复都会渲染一次，只给首楼用
    const post = this.args.outletArgs?.post;
    if (post && post.post_number && post.post_number !== 1) {
      return false;
    }
    const topic = this.topic;
    if (!topic || !topic.views) {
      return false;
    }
    const id = Number(topic.category?.id || topic.category_id);
    if (!id) {
      return false;
    }
    return String(this.siteSettings.kpann_gallery_categories || "")
      .split("|")
      .filter(Boolean)
      .map(Number)
      .includes(id);
  }

  <template>
    {{#if this.show}}
      <span class="kpv-views">观看 {{this.topic.views}}</span>
    {{/if}}
  </template>
}
