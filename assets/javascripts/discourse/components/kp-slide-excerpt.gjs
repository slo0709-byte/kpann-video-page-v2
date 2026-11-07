import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { on } from "@ember/modifier";

// 沉浸页简介：按后台设置的字数截断，点「展开」看全文。
export default class KpSlideExcerpt extends Component {
  @service siteSettings;

  @tracked expanded = false;

  get limit() {
    const value = parseInt(this.siteSettings.kpann_immersive_excerpt_chars, 10);
    return Number.isFinite(value) && value > 0 ? value : 0;
  }

  get text() {
    return (this.args.text || "").trim();
  }

  get needsToggle() {
    return this.limit > 0 && this.text.length > this.limit;
  }

  get displayText() {
    if (!this.needsToggle || this.expanded) {
      return this.text;
    }
    // 按字数截，尽量在空白处断开，避免切断半个词
    const cut = this.text.slice(0, this.limit);
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

  @action
  toggle(event) {
    event.preventDefault();
    event.stopPropagation();
    this.expanded = !this.expanded;
  }

  <template>
    <div class={{this.containerClass}}>
      <span class="kp-slide__excerpt-text">{{this.displayText}}</span>
      {{#if this.needsToggle}}
        <button type="button" class="kp-slide__excerpt-toggle" {{on "click" this.toggle}}>{{this.toggleLabel}}</button>
      {{/if}}
    </div>
  </template>
}
