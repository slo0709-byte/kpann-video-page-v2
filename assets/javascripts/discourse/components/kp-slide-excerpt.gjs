import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { on } from "@ember/modifier";
import { sanitizeAsync } from "discourse/lib/text";

// 沉浸页正文：跟视频页用同一套排版（<p> 段落、<br> 换行、列表），
// 服务端已经把视频 iframe 整块拿掉，所以这里不会出现播放器也不会留空行。
// HTML 先过 Discourse 官方的 sanitizeAsync 再插进 DOM，不直接塞原始 HTML。
export default class KpSlideExcerpt extends Component {
  @service siteSettings;

  @tracked expanded = false;
  @tracked safeHtml = null;

  constructor() {
    super(...arguments);
    this.prepare();
  }

  get limit() {
    const value = parseInt(this.siteSettings.kpann_immersive_excerpt_chars, 10);
    return Number.isFinite(value) && value > 0 ? value : 0;
  }

  get rawHtml() {
    return (this.args.html || "").trim();
  }

  get plainText() {
    return (this.args.text || "").trim();
  }

  // 有 HTML 就走 HTML（与视频页一致），没有就退回纯文本
  get useHtml() {
    return this.rawHtml.length > 0;
  }

  get contentHtml() {
    return this.safeHtml || "";
  }

  get needsToggle() {
    return this.limit > 0 && this.plainText.length > this.limit;
  }

  get collapsedText() {
    if (!this.needsToggle || this.expanded) {
      return this.plainText;
    }
    const cut = this.plainText.slice(0, this.limit);
    const lastSpace = Math.max(cut.lastIndexOf(" "), cut.lastIndexOf("\n"));
    const body = lastSpace > this.limit * 0.6 ? cut.slice(0, lastSpace) : cut;
    return body.replace(/\s+$/, "") + "…";
  }

  get containerClass() {
    return this.expanded ? "kp-slide__excerpt is-expanded" : "kp-slide__excerpt";
  }

  get toggleLabel() {
    return this.expanded ? "收起" : "…展开";
  }

  async prepare() {
    if (!this.useHtml) {
      return;
    }
    try {
      this.safeHtml = await sanitizeAsync(this.rawHtml, {});
    } catch (e) {
      this.safeHtml = null;
    }
  }

  @action
  toggle(event) {
    event.preventDefault();
    event.stopPropagation();
    this.expanded = !this.expanded;
  }

  <template>
    <div class={{this.containerClass}}>
      <div class="kp-slide__excerpt-body">
        {{#if this.useHtml}}
          {{#if this.contentHtml}}
            <div class="kp-slide__excerpt-text kp-slide__excerpt-html">{{{this.contentHtml}}}</div>
          {{/if}}
        {{else}}
          <span class="kp-slide__excerpt-text">{{this.collapsedText}}</span>
        {{/if}}
      </div>
      {{#if this.needsToggle}}
        <button type="button" class="kp-slide__excerpt-toggle" {{on "click" this.toggle}}>{{this.toggleLabel}}</button>
      {{/if}}
    </div>
  </template>
}
