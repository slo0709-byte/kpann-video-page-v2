import Component from "@glimmer/component";
import { service } from "@ember/service";

// 首楼作者行里的「N 浏览」。
// 核心 components/post/meta-data.gjs 里写着「这里不要放 PluginOutlet，用 DAG API」，
// 所以这一项通过官方 post-meta-data-infos 这个 mutable value transformer 加进元信息排，
// 位置钉在「时间」后面；不在视频分类首楼时什么都不渲染。
export default class KpannPostViews extends Component {
  @service siteSettings;

  get post() {
    return this.args.post;
  }

  get topic() {
    return this.post?.topic;
  }

  get views() {
    return Number(this.topic?.views) || 0;
  }

  get show() {
    if (this.post?.post_number !== 1 || !this.topic) {
      return false;
    }

    const id = Number(this.topic.category?.id ?? this.topic.category_id);
    if (!id) {
      return false;
    }

    const ids = String(this.siteSettings.kpann_gallery_categories || "")
      .split("|")
      .filter(Boolean)
      .map(Number);

    return ids.includes(id) && this.views > 0;
  }

  <template>
    {{#if this.show}}
      <div class="post-info kpann-post-views">
        <span>{{this.views}} 浏览</span>
      </div>
    {{/if}}
  </template>
}
