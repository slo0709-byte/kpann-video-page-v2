import Component from "@glimmer/component";
import { trustHTML } from "@ember/template";
import dFormatDate from "discourse/ui-kit/helpers/d-format-date";
import dAvatar from "discourse/ui-kit/helpers/d-avatar";
import dIcon from "discourse/ui-kit/helpers/d-icon";

// 视频分类列表里的一个格子（桌面和手机共用）。
// 走官方 topic-list-columns 转换器把「标题」列换成这个组件，
// 行本身还是核心的，所以悬停、批量选择、悬停预览、整行点击都不受影响。
export default class KpannVideoCard extends Component {
  get topic() {
    return this.args.topic;
  }

  get cover() {
    return this.topic?.kpann_cover_url || null;
  }

  get creator() {
    return this.topic?.creator || null;
  }

  get username() {
    return this.topic?.creator?.username || this.topic?.kpann_poster_username || null;
  }

  get likes() {
    return this.topic?.like_count || 0;
  }

  get replies() {
    return Math.max((this.topic?.posts_count || 1) - 1, 0);
  }

  get views() {
    return this.topic?.views || 0;
  }

  get bumpedTitle() {
    return this.topic?.bumpedAtTitle || null;
  }

  get lastUrl() {
    return this.topic?.lastPostUrl || this.topic?.url;
  }

  <template>
    <td class="kpv-card-cell">
      <a class="kpv-card" href={{this.topic.url}}>
        <span class="kpv-card__cover {{unless this.cover 'is-empty'}}">
          {{#if this.cover}}
            <img src={{this.cover}} alt="" loading="lazy">
          {{else}}
            {{dIcon "play"}}
          {{/if}}
        </span>

        <span class="kpv-card__body">
          <span class="kpv-card__title">{{this.topic.title}}</span>

          <span class="kpv-card__meta">
            {{#if this.creator}}
              <span class="kpv-card__avatar">{{dAvatar this.creator imageSize="small"}}</span>
              <span class="kpv-card__user">{{this.username}}</span>
            {{/if}}
            <span class="kpv-card__stat" title="点赞">
              {{dIcon "heart"}}<span>{{this.likes}}</span>
            </span>
            <span class="kpv-card__stat" title="回复">
              {{dIcon "comment"}}<span>{{this.replies}}</span>
            </span>
            <span class="kpv-card__stat" title="观看">
              {{dIcon "eye"}}<span>{{this.views}}</span>
            </span>
            <a
              class="kpv-card__time"
              href={{this.lastUrl}}
              title={{trustHTML this.bumpedTitle}}
            >{{dFormatDate this.topic.bumpedAt format="tiny" noTitle="true"}}</a>
          </span>
        </span>
      </a>
    </td>
  </template>
}

