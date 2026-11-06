import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { service } from "@ember/service";

// 长正文折叠：走核心自带 outlet `post-content-cooked-html` 的 __after 子口，
// 只加一个按钮，不动核心组件。折叠本身由 CSS :has() 完成，判断依据是按钮上的 is-open 类。
export default class KpannVideoCollapse extends Component {
  @service siteSettings;
  @service kpvPlayer;

  @tracked open = false;

  get topic() {
    return this.kpvPlayer?.topic;
  }

  get post() {
    return this.args.outletArgs?.post;
  }

  get limit() {
    const value = parseInt(this.siteSettings.kpann_watch_excerpt_chars, 10);
    return Number.isNaN(value) ? 0 : value;
  }

  get text() {
    return (this.post?.cooked || "")
      .replace(/<[^>]+>/g, " ")
      .replace(/\s+/g, " ")
      .trim();
  }

  get isVideoTopic() {
    const topic = this.topic;
    if (!topic) {
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

  get long() {
    // 只在首楼折叠；回复里不加按钮
    const number = this.post?.post_number;
    if (number && number !== 1) {
      return false;
    }
    return this.isVideoTopic && this.limit > 0 && this.text.length > this.limit;
  }

  @action
  toggle() {
    this.open = !this.open;
  }

  <template>
    {{#if this.long}}
      <button
        type="button"
        class="kpv-body__toggle {{if this.open 'is-open'}}"
        {{on "click" this.toggle}}
      >{{if this.open "收起" "展开全文"}}</button>
    {{/if}}
  </template>
}
