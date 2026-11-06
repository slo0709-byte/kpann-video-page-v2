import Component from "@glimmer/component";
import { applyValueTransformer } from "discourse/lib/transformer";

// 沉浸页作者行：头像框和名牌的类名交给官方的两个值变换去加，插件改规则这里不用跟着改。
// 变换出问题就退回空类名，页面照常显示。
export default class KpSlideAuthor extends Component {
  get frameClasses() {
    return this.#transformerClasses("post-avatar-class");
  }

  get nameClasses() {
    return this.#transformerClasses("poster-name-class");
  }

  get avatarWrapClass() {
    return `kp-slide__avatarwrap topic-avatar ${this.frameClasses}`.trim();
  }

  get usernameClass() {
    return `username kp-slide__username ${this.nameClasses}`.trim();
  }

  #transformerClasses(name) {
    try {
      const value = applyValueTransformer(name, [], {
        post: { user_id: this.args.posterId },
        user: { id: this.args.posterId },
        userWasDeleted: false,
      });
      return Array.isArray(value) ? value.join(" ") : value || "";
    } catch (e) {
      return "";
    }
  }

  <template>
    <a
      class="kp-slide__authorlink trigger-user-card"
      data-user-card={{@username}}
      href="/u/{{@username}}"
    >
      {{#if @avatarUrl}}
        <span class={{this.avatarWrapClass}}>
          <span class="post-avatar">
            <img class="avatar" src={{@avatarUrl}} alt={{@username}} width="40" height="40" />
          </span>
        </span>
      {{/if}}
      <span class={{this.usernameClass}}>{{@username}}</span>
    </a>
  </template>
}
